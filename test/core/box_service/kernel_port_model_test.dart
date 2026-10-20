import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:flutter_test/flutter_test.dart';

Map<Object?, Object?> _json({Map<Object?, Object?>? override}) => {
  'epoch': 'e1',
  'version': 12,
  'status': 'started',
  'attempt': 3,
  'desired': 'on',
  'source': 'tile',
  'appliedSeq': 7,
  'activeConfigRevision': 5,
  'selectionsReplayNeeded': true,
  'lastFailure': {
    'code': 'startTimeout',
    'message': 'm',
    'attempt': 2,
    'seq': 6,
  },
  ...?override,
};

void main() {
  group('KernelSnapshot.fromJson', () {
    test('完整载荷逐字段解析，toJson 往返相等', () {
      final s = KernelSnapshot.fromJson(_json());
      expect(s.epoch, 'e1');
      expect(s.version, 12);
      expect(s.status, KernelStatus.started);
      expect(s.attempt, 3);
      expect(s.desired, Desired.on);
      expect(s.source, DesiredSource.tile);
      expect(s.appliedSeq, 7);
      expect(s.activeConfigRevision, 5);
      expect(s.selectionsReplayNeeded, isTrue);
      expect(
        s.lastFailure,
        const KernelFailure(
          code: KernelFailureCode.startTimeout,
          message: 'm',
          attempt: 2,
          seq: 6,
        ),
      );
      expect(KernelSnapshot.fromJson(s.toJson()), s);
    });

    test('可空字段缺省/为 null 都解析为 null；status 大小写不敏感', () {
      final s = KernelSnapshot.fromJson(
        _json(
          override: {
            'activeConfigRevision': null,
            'lastFailure': null,
            'status': 'Stopping',
            'desired': 'OFF',
          },
        ),
      );
      expect(s.activeConfigRevision, isNull);
      expect(s.lastFailure, isNull);
      expect(s.status, KernelStatus.stopping);
      expect(s.desired, Desired.off);
    });

    test('retainedConfigPaths：列表解析、参与相等性、toJson 往返', () {
      final s = KernelSnapshot.fromJson(
        _json(
          override: {
            'retainedConfigPaths': ['/w/runtime-1.json', '/w/runtime-2.json'],
          },
        ),
      );
      expect(s.retainedConfigPaths, ['/w/runtime-1.json', '/w/runtime-2.json']);
      expect(KernelSnapshot.fromJson(s.toJson()), s);
      expect(
        s.copyWith(retainedConfigPaths: ['/w/runtime-1.json']) == s,
        isFalse,
      );
      expect(
        s.copyWith(clearRetainedConfigPaths: true).retainedConfigPaths,
        isNull,
      );
      final empty = KernelSnapshot.fromJson(
        _json(override: {'retainedConfigPaths': <Object?>[]}),
      );
      expect(empty.retainedConfigPaths, isEmpty, reason: '空列表 = 已知没有引用');
    });

    test('retainedConfigPaths 缺省 / null / 含非字符串：一律为未知（null），快照不丢', () {
      expect(KernelSnapshot.fromJson(_json()).retainedConfigPaths, isNull);
      for (final raw in [
        null,
        'not-a-list',
        ['/w/a.json', 3],
      ]) {
        final s = KernelSnapshot.fromJson(
          _json(override: {'retainedConfigPaths': raw}),
        );
        expect(s.retainedConfigPaths, isNull, reason: '$raw');
        expect(s.version, 12);
      }
    });

    test('未知来源按 system，未知失败码按 unknown，快照不丢', () {
      final s = KernelSnapshot.fromJson(
        _json(
          override: {
            'source': 'martian',
            'lastFailure': {'code': 'zzz', 'message': '', 'attempt': 1},
          },
        ),
      );
      expect(s.source, DesiredSource.system);
      expect(s.lastFailure?.code, KernelFailureCode.unknown);
      expect(s.lastFailure?.seq, isNull);
    });

    test('通知栏来源可识别', () {
      expect(
        KernelSnapshot.fromJson(_json(override: {'source': 'notification'}))
            .source,
        DesiredSource.notification,
      );
    });

    for (final bad in <String, Map<Object?, Object?>>{
      '缺 epoch': {'epoch': null},
      '空 epoch': {'epoch': ''},
      '未知 status': {'status': 'weird'},
      '未知 desired': {'desired': 'maybe'},
      'version 不是数字': {'version': 'x'},
      '缺 appliedSeq': {'appliedSeq': null},
      '缺 selectionsReplayNeeded': {'selectionsReplayNeeded': null},
      'selectionsReplayNeeded 类型错误': {'selectionsReplayNeeded': 'true'},
    }.entries) {
      test('非法载荷抛 FormatException：${bad.key}', () {
        expect(
          () => KernelSnapshot.fromJson(_json(override: bad.value)),
          throwsFormatException,
        );
      });
    }
  });

  test('KernelFailureCode 覆盖约定的全部失败码', () {
    expect(
      KernelFailureCode.values.map((c) => c.name),
      containsAll([
        'startTimeout',
        'permissionDenied',
        'emptyConfiguration',
        'createService',
        'startService',
        'startCommandServer',
        'kernelUnresponsive',
        'kernelExited',
        'unknown',
      ]),
    );
  });
}
