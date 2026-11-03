import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/features/proxy/data/proxy_failure_log.dart';
import 'package:flutter_test/flutter_test.dart';

const _subUrl = 'https://sub.example.com/a1b2c3';
const _nodeAddr = 'node1.example.com:8443';

class _ThrowingStack implements StackTrace {
  @override
  String toString() => throw StateError('stack toString failed');
}

class _ThrowingError {
  @override
  String toString() => throw StateError('error toString failed');
}

void main() {
  late List<AppFailureRecord> records;

  setUp(() {
    records = [];
    debugAppFailureSink = records.add;
  });
  tearDown(() => debugAppFailureSink = null);

  test('logProxyFailure：只写定位标签与类型名，不写异常原文', () {
    logProxyFailure(
      'proxy.test',
      StateError('bad $_subUrl via $_nodeAddr'),
      StackTrace.empty,
    );
    final line = records.single.line;
    for (final secret in [_subUrl, 'a1b2c3', _nodeAddr, 'example.com']) {
      expect(line, isNot(contains(secret)), reason: line);
    }
    expect(line, contains('[ERROR] proxy.test: StateError'));
  });

  test('文件系统异常的路径也不落盘', () {
    logProxyFailure(
      'proxy.fs',
      FileSystemException('read failed', '/Users/someone/$_nodeAddr/x'),
    );
    expect(records.single.line, isNot(contains('someone')));
    expect(records.single.line, isNot(contains(_nodeAddr)));
    expect(records.single.line, contains('proxy.fs: FileSystemException'));
  });

  test('堆栈文本化抛错：logProxyFailure 不向外抛', () {
    expect(
      () => logProxyFailure('proxy.test', StateError('x'), _ThrowingStack()),
      returnsNormally,
    );
  });

  test('异常的 toString 抛错：logProxyFailure 不向外抛', () {
    expect(
      () => logProxyFailure('proxy.test', _ThrowingError(), StackTrace.empty),
      returnsNormally,
    );
  });

  test('日志接缝本身抛错：logProxyFailure 不向外抛', () {
    debugAppFailureSink = (_) => throw StateError('sink failed');
    expect(
      () => logProxyFailure('proxy.test', StateError('x')),
      returnsNormally,
    );
  });

  group('logProxySelectionFailure：节点 / 分组名不进日志', () {
    const bareDomain = 'node.example.com'; // 节点名常是没有端口的裸域名

    test('只写固定标签与失败码', () {
      logProxySelectionFailure('exception');
      final line = records.single.line;
      expect(
        line,
        contains('[ERROR] proxies.select: SelectionFailed(code=exception)'),
      );
      expect(line, isNot(contains(bareDomain)));
    });

    test('像节点名的短串当作 code 传入：一律 other', () {
      for (final code in ['node.example.com', 'a.b', 'hk-01', 'hk01', '']) {
        records.clear();
        logProxySelectionFailure(code);
        final line = records.single.line;
        expect(line, contains('SelectionFailed(code=other)'), reason: code);
        expect(line, isNot(contains(code.isEmpty ? '\u0000' : 'code=$code')));
      }
    });

    test('白名单内的失败码原样保留', () {
      for (final code in kSelectionFailureCodes) {
        records.clear();
        logProxySelectionFailure(code);
        expect(records.single.line, contains('SelectionFailed(code=$code)'));
      }
    });

    test('失败码不是稳定短码（可能夹带名字）：记成 other', () {
      logProxySelectionFailure('outbound $bareDomain not found');
      final line = records.single.line;
      expect(line, contains('code=other'));
      expect(line, isNot(contains(bareDomain)));
      expect(line, isNot(contains('example')));
    });

    test('真正写进 app.log 的文本里没有裸域名节点名', () async {
      final dir = await Directory.systemTemp.createTemp('proxy_sel_log_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.log');
      debugAppFailureSink = null;
      AppLogger.configureForTesting(resolveLogFile: () async => file);
      addTearDown(AppLogger.resetForTesting);

      logProxySelectionFailure('unavailable');
      await AppLogger.instance.flush();

      final content = await file.readAsString();
      expect(content, contains('proxies.select'));
      expect(content, contains('code=unavailable'));
      expect(content, isNot(contains(bareDomain)));
    });

    test('不向外抛', () {
      debugAppFailureSink = (_) => throw StateError('sink failed');
      expect(() => logProxySelectionFailure('x'), returnsNormally);
    });
  });
}
