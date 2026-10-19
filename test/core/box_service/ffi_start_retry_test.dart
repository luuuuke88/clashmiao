import 'package:clashmiao/core/box_service/ffi_box_service.dart';
import 'package:clashmiao/core/box_service/model/box_service_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('startWithStopRetry（原先在连接控制器里靠字符串匹配做的重试，现归 FFI 层）', () {
    test('首次启动成功：不 stop、不重试', () async {
      final calls = <String>[];
      final err = await startWithStopRetry(
        start: () {
          calls.add('start');
          return '';
        },
        stop: () {
          calls.add('stop');
          return '';
        },
        delay: (_) async => calls.add('delay'),
      );
      expect(err, '');
      expect(calls, ['start']);
    });

    test('其它启动错误原样返回，不 stop、不重试', () async {
      final calls = <String>[];
      final err = await startWithStopRetry(
        start: () {
          calls.add('start');
          return 'bind: address already in use';
        },
        stop: () {
          calls.add('stop');
          return '';
        },
      );
      expect(err, 'bind: address already in use');
      expect(calls, ['start']);
    });

    test('instance not stopped → stop → 等待 → 再启动一次', () async {
      final calls = <String>[];
      var n = 0;
      final err = await startWithStopRetry(
        start: () {
          calls.add('start');
          return n++ == 0 ? 'start service: instance not stopped' : '';
        },
        stop: () {
          calls.add('stop');
          return '';
        },
        delay: (d) async => calls.add('delay:${d.inMilliseconds}'),
      );
      expect(err, '');
      expect(calls, ['start', 'stop', 'delay:500', 'start']);
    });

    test('重试后仍失败：只重试这一次，返回第二次的错误', () async {
      var n = 0;
      final err = await startWithStopRetry(
        start: () => 'instance not stopped #${n++}',
        stop: () => '',
        delay: (_) async {},
      );
      expect(n, 2);
      expect(err, 'instance not stopped #1');
    });

    test('stop 本身失败：不盲目重试，返回原始启动错误', () async {
      var starts = 0;
      final err = await startWithStopRetry(
        start: () {
          starts++;
          return 'instance not stopped';
        },
        stop: () => 'stop failed',
        delay: (_) async {},
      );
      expect(starts, 1);
      expect(err, 'instance not stopped');
    });
  });

  test('BoxServiceException 携带调用名与原始文本', () {
    const e = BoxServiceException('start', 'x');
    expect(e.code, 'start');
    expect(e.message, 'x');
    expect(e.toString(), 'BoxServiceException(start: x)');
  });
}
