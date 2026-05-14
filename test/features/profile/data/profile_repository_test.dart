import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 起一个一次性 HTTP server，用来 mock 订阅响应。
Future<HttpServer> _serveOnce(
  String body, {
  required Map<String, String> headers,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen((req) async {
    headers.forEach((k, v) => req.response.headers.set(k, v));
    req.response.write(body);
    await req.response.close();
  });
  return server;
}

void main() {
  group('ProfileRepository normalize (StubBoxService 路径)', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('repo_test_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: StubBoxService(),
      );
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    test('sing-box JSON 原文带 outbounds → 直通保留 inbounds/route', () async {
      final body = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'p', 'outbounds': <String>[]},
        ],
        'inbounds': [
          {'type': 'mixed', 'listen_port': 2080},
        ],
        'route': {'rules': <Map<String, dynamic>>[]},
      });
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl(
        'http://localhost:${server.port}/test#X',
      );
      final file = File(repo.configFilePath(profile.id));
      final out = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      // 直通：inbounds / route 字段保留
      expect(out.containsKey('inbounds'), isTrue);
      expect(out.containsKey('route'), isTrue);
      expect(out['outbounds'] as List, isNotEmpty);
    });

    test('非 JSON body → StubBoxService 路径直接写原文', () async {
      const body = 'proxies:\n  - name: hello\n';
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      final file = File(repo.configFilePath(profile.id));
      expect(await file.readAsString(), body);
    });

    test('JSON 但缺 outbounds → StubBoxService 回退到原文', () async {
      final body = jsonEncode({'inbounds': <Map<String, dynamic>>[]});
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      final file = File(repo.configFilePath(profile.id));
      expect(await file.readAsString(), body);
    });

    test('addByUrl 首条订阅自动 active', () async {
      final body = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'p', 'outbounds': <String>[]},
        ],
      });
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      expect(profile.active, isTrue);
      expect(repo.getActive()?.id, profile.id);
    });

    test('customName 覆盖 header 解析的名称', () async {
      final body = jsonEncode({'outbounds': <Map<String, dynamic>>[]});
      final server = await _serveOnce(
        body,
        headers: {'profile-title': 'FromHeader'},
      );
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl(
        'http://localhost:${server.port}/',
        customName: 'MyCustom',
      );
      expect(profile.name, 'MyCustom');
    });
  });
}
