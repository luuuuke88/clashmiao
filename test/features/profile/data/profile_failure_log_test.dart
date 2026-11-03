import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/features/profile/data/profile_failure_log.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_box_service.dart';
import '../../../support/temp_dirs.dart';

// 解析器 / 网络层会把输入原文拼进异常消息：订阅地址（含短路径 token）与
// 节点地址（host:port）都不允许进 app.log。
const _subUrl = 'https://sub.example.com/a1b2c3';
const _nodeAddr = 'node1.example.com:8443';

class _LeakyBox extends FakeBoxService {
  _LeakyBox(this._reply);

  final Future<String?> Function() _reply;

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) => _reply();
}

class _ThrowingStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('stack toString broke');
}

class _ThrowingError {
  @override
  String toString() => throw StateError('error toString broke');
}

void main() {
  late List<AppFailureRecord> records;

  setUp(() {
    records = [];
    debugAppFailureSink = records.add;
  });
  tearDown(() => debugAppFailureSink = null);

  void expectNoLeak() {
    expect(records, isNotEmpty);
    for (final r in records) {
      for (final secret in [_subUrl, 'a1b2c3', _nodeAddr, 'example.com']) {
        expect(r.line, isNot(contains(secret)), reason: r.line);
      }
    }
  }

  test('logProfileFailure：只写类型名与稳定码，不写异常原文', () {
    logProfileFailure(
      'profile.store.test',
      ProfileValidationException('bad $_subUrl via $_nodeAddr'),
      StackTrace.empty,
      'uri-invalid',
    );
    expectNoLeak();
    expect(
      records.single.line,
      contains(
        '[ERROR] profile.store.test: '
        'ProfileValidationException(code=uri-invalid)',
      ),
    );
  });

  group('ProfileValidationException.toString', () {
    test('只含类型名与稳定码，不含 message 原文；message 仍可供界面读取', () {
      const e = ProfileValidationException(
        'uri-invalid: bad $_subUrl via $_nodeAddr',
        code: 'uri-invalid',
      );
      expect('$e', 'ProfileValidationException(code=uri-invalid)');
      expect(e.message, contains(_subUrl));
      const noCode = ProfileValidationException('x $_subUrl $_nodeAddr');
      expect('$noCode', 'ProfileValidationException');
      expect(
        '${ProfileValidationException.fromParseError('weird: $_subUrl')}',
        'ProfileValidationException',
      );
    });

    test('被当作字符串拼进别的文本（连接失败文案、日志）时也不泄露', () {
      final text = 'failed: ${ProfileValidationException(_subUrl)}';
      expect(text, isNot(contains('a1b2c3')));
    });
  });

  test('logProfileFailure：校验异常缺省取自带的稳定码', () {
    logProfileFailure(
      'profile.ui.test',
      ProfileValidationException('x $_subUrl', code: 'no-outbounds'),
    );
    expectNoLeak();
    expect(
      records.single.line,
      contains('ProfileValidationException(code=no-outbounds)'),
    );
  });

  test('logProfileFailureOnce：同一摘要只记一次，内容不含原文', () {
    addTearDown(resetAppFailureDedupForTesting);
    for (var i = 0; i < 3; i++) {
      logProfileFailureOnce(
        'profile.ui.once',
        StateError('dial $_nodeAddr for $_subUrl #$i'),
      );
    }
    expect(records, hasLength(1));
    expectNoLeak();
    expect(records.single.line, contains('profile.ui.once: StateError'));
  });

  group('日志函数是全函数：自身失败不会从 catch 块里抛出', () {
    test('堆栈的 toString 抛异常', () {
      expect(
        () => logProfileFailure(
          'profile.ui.test',
          StateError('x $_subUrl'),
          _ThrowingStackTrace(),
        ),
        returnsNormally,
      );
      expect(
        () => logProfileFailureOnce(
          'profile.ui.testOnce',
          StateError('x $_subUrl'),
          _ThrowingStackTrace(),
        ),
        returnsNormally,
      );
    });

    test('异常对象的 toString 抛异常', () {
      expect(
        () => logProfileFailure('profile.ui.test', _ThrowingError()),
        returnsNormally,
      );
    });

    test('日志落点本身抛异常', () {
      debugAppFailureSink = (_) => throw StateError('sink broke');
      expect(
        () => logProfileFailure('profile.ui.test', StateError('x')),
        returnsNormally,
      );
    });
  });

  test('文件系统异常的路径也不落盘', () {
    logProfileFailure(
      'profile.store.deleteFile',
      FileSystemException('rm failed', '/Users/someone/$_nodeAddr/x'),
    );
    expect(records.single.line, isNot(contains('someone')));
    expect(records.single.line, isNot(contains(_nodeAddr)));
    expect(
      records.single.line,
      contains('profile.store.deleteFile: FileSystemException'),
    );
  });

  group('仓库端到端：native 解析错误带订阅地址 / 节点地址', () {
    late Directory tmpDir;
    late HttpServer server;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('profile_fail_log_');
      SharedPreferences.setMockInitialValues({});
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.write('not-json-body');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await deleteTempDirBestEffort(tmpDir);
    });

    Future<void> addWith(Future<String?> Function() reply) async {
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: await SharedPreferences.getInstance(),
        boxService: _LeakyBox(reply),
      );
      await expectLater(
        repo.addByUrl('http://localhost:${server.port}/'),
        throwsA(isA<ProfileValidationException>()),
      );
    }

    test('带稳定码的解析错误：日志只有码', () async {
      await addWith(
        () async => 'uri-invalid: bad link $_subUrl (server $_nodeAddr)',
      );
      expectNoLeak();
      expect(
        records.map((r) => r.line).join('\n'),
        contains('ProfileValidationException(code=uri-invalid)'),
      );
    });

    test('无码的解析错误：日志只有类型名', () async {
      await addWith(
        () async => 'unexpected token near $_nodeAddr from $_subUrl',
      );
      expectNoLeak();
    });

    test('native 层直接抛异常（消息含地址）：同样不落盘', () async {
      await addWith(
        () async => throw StateError('dial $_nodeAddr for $_subUrl'),
      );
      expectNoLeak();
    });
  });

  group('失败码白名单', () {
    test('像节点名的短串当作 code 传入：记成 other', () {
      final records = <AppFailureRecord>[];
      debugAppFailureSink = records.add;
      addTearDown(() => debugAppFailureSink = null);
      for (final code in ['node.example.com', 'a.b', 'hk-01']) {
        records.clear();
        logProfileFailure('t', StateError('x'), StackTrace.empty, code);
        final line = records.single.line;
        expect(line, contains('StateError(code=other)'), reason: code);
        expect(line, isNot(contains(code)), reason: code);
      }
    });

    test('解析器固定码表内的码原样保留', () {
      final records = <AppFailureRecord>[];
      debugAppFailureSink = records.add;
      addTearDown(() => debugAppFailureSink = null);
      for (final code in kParseErrorCodes) {
        records.clear();
        logProfileFailure('t', StateError('x'), StackTrace.empty, code);
        expect(records.single.line, contains('StateError(code=$code)'));
      }
    });
  });
}
