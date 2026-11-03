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
}
