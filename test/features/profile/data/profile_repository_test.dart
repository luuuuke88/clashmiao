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

  group('ProfileRepository 增删改活', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('repo_crud_');
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

    Future<String> addNamed(String name) async {
      final body = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': name, 'outbounds': <String>[]},
        ],
      });
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));
      final p = await repo.addByUrl(
        'http://localhost:${server.port}/',
        customName: name,
      );
      return p.id;
    }

    test('delete 移除 profile + 删配置文件', () async {
      final id = await addNamed('A');
      final cfgPath = repo.configFilePath(id);
      expect(await File(cfgPath).exists(), isTrue);

      await repo.delete(id);
      expect(repo.getAll().any((p) => p.id == id), isFalse);
      expect(await File(cfgPath).exists(), isFalse);
    });

    test('删掉激活订阅后自动切到第一个剩下的', () async {
      final aId = await addNamed('A');
      final bId = await addNamed('B');
      await repo.setActive(aId);

      await repo.delete(aId);
      expect(repo.getActive()?.id, bId);
    });

    test('删唯一订阅后 getActive 返回 null', () async {
      final id = await addNamed('OnlyOne');
      await repo.delete(id);
      expect(repo.getAll(), isEmpty);
      expect(repo.getActive(), isNull);
    });

    test('setActive 切换 + 更新 active 标记', () async {
      final aId = await addNamed('A');
      final bId = await addNamed('B');

      await repo.setActive(bId);
      expect(repo.getActive()?.id, bId);
      // 所有 profile 的 active 标记应该和 setActive 对齐
      expect(repo.getAll().firstWhere((p) => p.id == bId).active, isTrue);
      expect(repo.getAll().firstWhere((p) => p.id == aId).active, isFalse);
    });

    test('editProfile 改名 + 改 URL（trim、空值跳过）', () async {
      final id = await addNamed('Original');

      await repo.editProfile(id, newName: '  Renamed  ');
      expect(repo.getAll().firstWhere((p) => p.id == id).name, 'Renamed');

      // 空字符串 / 仅空格不应该覆盖
      await repo.editProfile(id, newName: '   ');
      expect(repo.getAll().firstWhere((p) => p.id == id).name, 'Renamed');

      await repo.editProfile(id, newUrl: 'https://newurl.example/sub');
      expect(
        repo.getAll().firstWhere((p) => p.id == id).url,
        'https://newurl.example/sub',
      );
    });

    test('getActive 在 activeId 找不到时 fallback 到第一个', () async {
      final aId = await addNamed('A');
      await addNamed('B');
      // 删 A 的 prefs key 模拟脏数据，但 A profile 还在
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('clashmiao_active_profile', 'no-such-id');
      // 因为 activeId 找不到，会返回 profiles.first
      expect(repo.getActive()?.id, aId);
    });

    test('getActive 在 prefs 没设过时返回 null', () async {
      // 无任何 profile
      expect(repo.getActive(), isNull);
    });
  });

  group('ProfileRepository.addByContent', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('content_');
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

    test('ss:// URI 内容写到 profile 文件（stub 路径下原文写出）', () async {
      const ssUri = 'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@host:443#node';
      final profile = await repo.addByContent(ssUri, name: 'My SS');

      expect(profile.name, 'My SS');
      expect(profile.active, isTrue); // 首条自动 active
      // URL 字段做了截断 + 前缀，避免存敏感凭据
      expect(profile.url.startsWith('content://'), isTrue);
      expect(profile.url.length, lessThan(60));

      final file = File(repo.configFilePath(profile.id));
      expect(await file.readAsString(), ssUri);
    });

    test('空 name 使用默认 "本地导入"', () async {
      final profile = await repo.addByContent('ss://abc@h:1#x', name: '');
      expect(profile.name, '本地导入');
    });

    test('第二次 addByContent 不自动 active（保留首条）', () async {
      final p1 = await repo.addByContent('ss://abc@h:1#x', name: 'A');
      final p2 = await repo.addByContent('ss://xyz@h:2#y', name: 'B');
      expect(p1.active, isTrue);
      expect(p2.active, isFalse);
      expect(repo.getActive()?.id, p1.id);
    });
  });
}
