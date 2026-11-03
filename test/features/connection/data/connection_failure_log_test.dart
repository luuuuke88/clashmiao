import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/features/connection/data/connection_failure_log.dart';
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

  test('logConnectionFailure：只写定位标签与类型名，不写异常原文', () {
    logConnectionFailure(
      'connection.test',
      StateError('bad $_subUrl via $_nodeAddr'),
      StackTrace.empty,
    );
    final line = records.single.line;
    for (final secret in [_subUrl, 'a1b2c3', _nodeAddr, 'example.com']) {
      expect(line, isNot(contains(secret)), reason: line);
    }
    expect(line, contains('[ERROR] connection.test: StateError'));
  });

  test('文件系统异常的路径也不落盘', () {
    logConnectionFailure(
      'connection.fs',
      FileSystemException('read failed', '/Users/someone/$_nodeAddr/x'),
    );
    expect(records.single.line, isNot(contains('someone')));
    expect(records.single.line, isNot(contains(_nodeAddr)));
    expect(records.single.line, contains('connection.fs: FileSystemException'));
  });

  test('堆栈文本化抛错：logConnectionFailure 不向外抛', () {
    expect(
      () => logConnectionFailure(
        'connection.test',
        StateError('x'),
        _ThrowingStack(),
      ),
      returnsNormally,
    );
  });

  test('异常的 toString 抛错：logConnectionFailure 不向外抛', () {
    expect(
      () => logConnectionFailure(
        'connection.test',
        _ThrowingError(),
        StackTrace.empty,
      ),
      returnsNormally,
    );
  });

  test('日志接缝本身抛错：logConnectionFailure 不向外抛', () {
    debugAppFailureSink = (_) => throw StateError('sink failed');
    expect(
      () => logConnectionFailure('connection.test', StateError('x')),
      returnsNormally,
    );
  });
}
