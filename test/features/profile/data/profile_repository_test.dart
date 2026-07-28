import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/temp_dirs.dart';

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

class _ValidatingBoxService implements BoxService {
  const _ValidatingBoxService({this.normalize});

  final String Function(String raw)? normalize;

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async {
    final raw = await File(tempPath).readAsString();
    if (raw.contains('invalid-subscription')) return 'invalid config';
    await File(path).writeAsString(normalize?.call(raw) ?? raw);
    return null;
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> setup(AppDirectories directories, {bool debug = false}) async {}
  @override
  Future<void> changeConfigOptions(String jsonOptions) async {}
  @override
  Future<void> start(String configPath, {String name = ''}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> restart(String configPath, {String name = ''}) async {}
  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {}
  @override
  Future<void> urlTest(String groupTag) async {}
  @override
  Stream<BoxStatus> watchStatus() => const Stream.empty();
  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String path) async => null;
  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String path) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => const Stream.empty();
  @override
  Future<void> resetTunnel() async {}
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
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
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

    test('sing-box JSON 多级 selector 也会补出 flat proxy', () async {
      final body = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': '节点选择',
            'outbounds': ['手动选择', '自动选择'],
            'default': '手动选择',
          },
          {
            'type': 'selector',
            'tag': '手动选择',
            'outbounds': ['HK-1', 'JP-1'],
            'default': 'HK-1',
          },
          {
            'type': 'urltest',
            'tag': '自动选择',
            'outbounds': ['HK-1', 'JP-1'],
            'default': 'JP-1',
          },
          {'type': 'vless', 'tag': 'HK-1'},
          {'type': 'vless', 'tag': 'JP-1'},
        ],
        'inbounds': [
          {
            'type': 'tun',
            'address': ['172.19.0.1/30', '2001:0470:f9da:fdfa::1/64'],
          },
        ],
        'dns': {
          'servers': [
            {
              'tag': 'remote',
              'address': 'https://1.1.1.1/dns-query',
              'detour': '节点选择',
            },
          ],
        },
        'route': {
          'final': '节点选择',
          'rules': [
            {'clash_mode': 'global', 'outbound': '节点选择'},
            {'clash_mode': 'direct', 'outbound': 'direct'},
          ],
          'rule_set': [
            {
              'tag': 'geosite-cn',
              'type': 'remote',
              'format': 'binary',
              'url': 'https://example.test/geosite-cn.srs',
              'download_detour': '自动选择',
            },
          ],
        },
      });
      final server = await _serveOnce(body, headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      final file = File(repo.configFilePath(profile.id));
      final out = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final outbounds = (out['outbounds'] as List).cast<Map<String, dynamic>>();
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');

      expect(proxy['outbounds'], ['HK-1', 'JP-1']);
      expect(proxy['default'], 'HK-1');
      expect(outbounds.any((o) => o['type'] == 'urltest'), isFalse);
      expect((out['route'] as Map<String, dynamic>)['final'], 'proxy');
      expect(
        (((out['route'] as Map<String, dynamic>)['rules'] as List).first
            as Map<String, dynamic>)['outbound'],
        'proxy',
      );
      expect(
        (((out['route'] as Map<String, dynamic>)['rule_set'] as List).first
            as Map<String, dynamic>)['download_detour'],
        'proxy',
      );
      expect(
        (((out['dns'] as Map<String, dynamic>)['servers'] as List).first
            as Map<String, dynamic>)['detour'],
        'proxy',
      );
      final inbounds = (out['inbounds'] as List).cast<Map<String, dynamic>>();
      expect(inbounds.first.containsKey('address'), isFalse);
      expect(inbounds.first['inet4_address'], ['172.19.0.1/28']);
    });

    test('默认订阅请求不强制透传 User-Agent', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // ignore: unawaited_futures
      server.listen((req) async {
        final ua = req.headers.value(HttpHeaders.userAgentHeader);
        expect(ua == 'sing-box', isFalse);
        req.response.write(
          jsonEncode({
            'outbounds': [
              {'type': 'vless', 'tag': 'HK-1'},
            ],
          }),
        );
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      final file = File(repo.configFilePath(profile.id));
      final out = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final outbounds = (out['outbounds'] as List).cast<Map<String, dynamic>>();
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');

      expect(proxy['outbounds'], ['HK-1']);
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
      // 这里必须给一个真实节点：零节点的响应现在会被 UA 回退逻辑判定为
      // "订阅没有发节点"并抛错（见 subscription_fetch.dart），而本用例
      // 要验证的是名称覆盖，不该依赖"空配置也能建订阅"这个旧行为。
      final body = jsonEncode({
        'outbounds': [
          {'tag': 'node-1', 'type': 'vless'},
        ],
      });
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
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
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
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
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

  group('ProfileRepository.addByUrl 去重', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('dedupe_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    test('重复添加同一 URL 更新已有记录而不是新增一条', () async {
      var callCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // ignore: unawaited_futures
      server.listen((req) async {
        callCount++;
        req.response.write(
          jsonEncode({
            'outbounds': [
              {'type': 'vless', 'tag': 'node-$callCount'},
            ],
          }),
        );
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final url = 'http://localhost:${server.port}/sub';
      final first = await repo.addByUrl(url, customName: 'A');
      final second = await repo.addByUrl(url, customName: 'A2');

      // 同一条记录，不是新增一条
      expect(second.id, first.id);
      expect(repo.getAll().length, 1);
      // 第二次调用确实带来了新内容（触发了真实的重新拉取，不是原地空转）
      expect(callCount, 2);
      expect(repo.getAll().first.name, 'A2');

      final out =
          jsonDecode(await File(repo.configFilePath(first.id)).readAsString())
              as Map<String, dynamic>;
      final outbounds = (out['outbounds'] as List).cast<Map<String, dynamic>>();
      final leaf = outbounds.firstWhere((o) => o['type'] == 'vless');
      expect(leaf['tag'], 'node-2');
    });

    test('URL 前后空格不影响去重判断', () async {
      var callCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // ignore: unawaited_futures
      server.listen((req) async {
        callCount++;
        req.response.write(
          jsonEncode({
            'outbounds': [
              {'type': 'vless', 'tag': 'node'},
            ],
          }),
        );
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final url = 'http://localhost:${server.port}/sub';
      final first = await repo.addByUrl(url);
      final second = await repo.addByUrl('  $url  ');

      expect(second.id, first.id);
      expect(repo.getAll().length, 1);
      expect(callCount, 2);
    });
  });

  group('ProfileRepository validation', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('repo_validate_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const _ValidatingBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    test('update rejects invalid config and preserves previous file', () async {
      final validBody = jsonEncode({
        'outbounds': [
          {'type': 'selector', 'tag': 'old', 'outbounds': <String>[]},
        ],
      });
      final validServer = await _serveOnce(validBody, headers: {});
      addTearDown(() => validServer.close(force: true));
      final profile = await repo.addByUrl(
        'http://localhost:${validServer.port}/',
      );
      final configFile = File(repo.configFilePath(profile.id));
      final before = await configFile.readAsString();

      final invalidServer = await _serveOnce(
        'invalid-subscription',
        headers: {},
      );
      addTearDown(() => invalidServer.close(force: true));
      await repo.editProfile(
        profile.id,
        newUrl: 'http://localhost:${invalidServer.port}/',
      );

      await expectLater(
        repo.update(profile.id),
        throwsA(isA<ProfileValidationException>()),
      );
      expect(await configFile.readAsString(), before);
    });

    test(
      'addByUrl repairs native parsed node lists into selectable groups',
      () async {
        final repoWithNativeOutput = ProfileRepository(
          dio: Dio(),
          configDir: tmpDir,
          prefs: await SharedPreferences.getInstance(),
          boxService: _ValidatingBoxService(
            normalize: (_) => jsonEncode({
              'outbounds': [
                {'type': 'urltest', 'tag': '测速', 'outbounds': <String>[]},
                {'type': 'vless', 'tag': 'HK-1'},
                {'type': 'vless', 'tag': 'JP-1'},
              ],
            }),
          ),
        );
        final server = await _serveOnce('native-subscription', headers: {});
        addTearDown(() => server.close(force: true));

        final profile = await repoWithNativeOutput.addByUrl(
          'http://localhost:${server.port}/',
        );
        final out =
            jsonDecode(
                  await File(
                    repoWithNativeOutput.configFilePath(profile.id),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final outbounds = (out['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        final selector = outbounds.firstWhere((o) => o['tag'] == 'proxy');

        expect(selector['outbounds'], ['HK-1', 'JP-1']);
        expect(selector['default'], 'HK-1');
        expect(outbounds.any((o) => o['type'] == 'urltest'), isFalse);
        expect((out['route'] as Map<String, dynamic>)['final'], 'proxy');
      },
    );

    test(
      'informational proxy tags are not selected as the default outbound',
      () async {
        final repoWithNativeOutput = ProfileRepository(
          dio: Dio(),
          configDir: tmpDir,
          prefs: await SharedPreferences.getInstance(),
          boxService: _ValidatingBoxService(
            normalize: (_) => jsonEncode({
              'outbounds': [
                {'type': 'vless', 'tag': '🌐 官网地址：ncink.cc'},
                {'type': 'vless', 'tag': '🇭🇰 香港01-BGP|IEPL中继'},
                {'type': 'vless', 'tag': '🇯🇵 日本01-BGP|IEPL中继'},
              ],
            }),
          ),
        );
        final server = await _serveOnce('native-subscription', headers: {});
        addTearDown(() => server.close(force: true));

        final profile = await repoWithNativeOutput.addByUrl(
          'http://localhost:${server.port}/',
        );
        final out =
            jsonDecode(
                  await File(
                    repoWithNativeOutput.configFilePath(profile.id),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final outbounds = (out['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        final selector = outbounds.firstWhere((o) => o['tag'] == 'proxy');

        expect(selector['outbounds'], [
          '🌐 官网地址：ncink.cc',
          '🇭🇰 香港01-BGP|IEPL中继',
          '🇯🇵 日本01-BGP|IEPL中继',
        ]);
        expect(selector['default'], '🇭🇰 香港01-BGP|IEPL中继');
      },
    );

    test(
      'native auto/urltest group is not used as the default route',
      () async {
        final repoWithNativeOutput = ProfileRepository(
          dio: Dio(),
          configDir: tmpDir,
          prefs: await SharedPreferences.getInstance(),
          boxService: _ValidatingBoxService(
            normalize: (_) => jsonEncode({
              'outbounds': [
                {
                  'type': 'selector',
                  'tag': 'proxy',
                  'outbounds': ['auto', 'HK-1'],
                  'default': 'auto',
                },
                {
                  'type': 'urltest',
                  'tag': 'auto',
                  'outbounds': ['HK-1', 'JP-1'],
                  'default': 'JP-1',
                },
                {'type': 'vless', 'tag': 'HK-1'},
                {'type': 'vless', 'tag': 'JP-1'},
              ],
              'route': {'final': 'auto'},
            }),
          ),
        );
        final server = await _serveOnce('native-subscription', headers: {});
        addTearDown(() => server.close(force: true));

        final profile = await repoWithNativeOutput.addByUrl(
          'http://localhost:${server.port}/',
        );
        final out =
            jsonDecode(
                  await File(
                    repoWithNativeOutput.configFilePath(profile.id),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final outbounds = (out['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        final selector = outbounds.firstWhere((o) => o['tag'] == 'proxy');

        expect(selector['outbounds'], ['HK-1', 'JP-1']);
        expect(selector['default'], 'HK-1');
        expect(outbounds.any((o) => o['type'] == 'urltest'), isFalse);
        expect((out['route'] as Map<String, dynamic>)['final'], 'proxy');
      },
    );

    test(
      'native nested selectors still create a flat proxy selector',
      () async {
        final repoWithNativeOutput = ProfileRepository(
          dio: Dio(),
          configDir: tmpDir,
          prefs: await SharedPreferences.getInstance(),
          boxService: _ValidatingBoxService(
            normalize: (_) => jsonEncode({
              'outbounds': [
                {
                  'type': 'selector',
                  'tag': '节点选择',
                  'outbounds': ['手动选择', '自动选择'],
                  'default': '手动选择',
                },
                {
                  'type': 'selector',
                  'tag': '手动选择',
                  'outbounds': ['HK-1', 'JP-1'],
                  'default': 'HK-1',
                },
                {
                  'type': 'urltest',
                  'tag': '自动选择',
                  'outbounds': ['HK-1', 'JP-1'],
                  'default': 'JP-1',
                },
                {'type': 'vless', 'tag': 'HK-1'},
                {'type': 'vless', 'tag': 'JP-1'},
              ],
              'route': {'final': '节点选择'},
            }),
          ),
        );
        final server = await _serveOnce('native-subscription', headers: {});
        addTearDown(() => server.close(force: true));

        final profile = await repoWithNativeOutput.addByUrl(
          'http://localhost:${server.port}/',
        );
        final out =
            jsonDecode(
                  await File(
                    repoWithNativeOutput.configFilePath(profile.id),
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        final outbounds = (out['outbounds'] as List)
            .cast<Map<String, dynamic>>();
        final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
        final manual = outbounds.firstWhere((o) => o['tag'] == '手动选择');

        expect(proxy['outbounds'], ['HK-1', 'JP-1']);
        expect(proxy['default'], 'HK-1');
        expect(manual['outbounds'], ['HK-1', 'JP-1']);
        expect(outbounds.any((o) => o['type'] == 'urltest'), isFalse);
        expect((out['route'] as Map<String, dynamic>)['final'], 'proxy');
      },
    );

    test('update repairs native parsed subscriptions too', () async {
      final repoWithNativeOutput = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: await SharedPreferences.getInstance(),
        boxService: _ValidatingBoxService(
          normalize: (_) => jsonEncode({
            'outbounds': [
              {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
              {'type': 'trojan', 'tag': 'SG-1'},
            ],
          }),
        ),
      );
      final server = await _serveOnce('native-subscription', headers: {});
      addTearDown(() => server.close(force: true));
      final profile = await repoWithNativeOutput.addByUrl(
        'http://localhost:${server.port}/',
      );

      await repoWithNativeOutput.update(profile.id);

      final out =
          jsonDecode(
                await File(
                  repoWithNativeOutput.configFilePath(profile.id),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final outbounds = (out['outbounds'] as List).cast<Map<String, dynamic>>();
      final selector = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(selector['outbounds'], ['SG-1']);
      expect(selector['default'], 'SG-1');
    });
  });

  group('ProfileRepository.addByUrl User-Agent 回退', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('repo_ua_test_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    test('面板只认 sing-box UA 时，自动回退并拿到有节点的配置', () async {
      // 假面板，完整复现线上那家的行为：认得的 UA 发完整配置，认不得的发一份
      // 结构合法但节点为空的骨架（HTTP 200，不是错误码）。
      final seenUserAgents = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      // ignore: unawaited_futures
      server.listen((req) async {
        final ua = req.headers.value('user-agent') ?? '';
        seenUserAgents.add(ua);
        final knowsClient = ua.toLowerCase().contains('sing-box');
        req.response.write(
          knowsClient
              ? jsonEncode({
                  'outbounds': [
                    {'tag': 'HK-01', 'type': 'vless'},
                    {'tag': 'JP-01', 'type': 'vless'},
                  ],
                })
              : 'mixed-port: 7890\nproxies: []\n',
        );
        await req.response.close();
      });

      final profile = await repo.addByUrl('http://localhost:${server.port}/');

      final out =
          jsonDecode(await File(repo.configFilePath(profile.id)).readAsString())
              as Map<String, dynamic>;
      // 注意：写盘时 _ensureMinimalProfileStructure 还会补上 selector / direct
      // 这些内置出站，所以这里断言"真实节点都在"，而不是写死总数。
      final tags = (out['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag'])
          .toList();
      expect(tags, containsAll(<String>['HK-01', 'JP-01']));
      expect(
        seenUserAgents.any((ua) => ua.toLowerCase().contains('sing-box')),
        isTrue,
        reason: '应当在首次拿到空配置后改用 sing-box UA 重试',
      );
    });

    test('回退命中的 UA 被记在订阅上，刷新时不会再退回空配置', () async {
      // 不记住的话：导入靠回退成功，但下一次自动刷新又用回自身 UA，
      // 面板再发一份空配置，节点列表当场被清空——比原来的导入失败更糟。
      final seenUserAgents = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      // ignore: unawaited_futures
      server.listen((req) async {
        final ua = req.headers.value('user-agent') ?? '';
        seenUserAgents.add(ua);
        req.response.write(
          ua.toLowerCase().contains('sing-box')
              ? jsonEncode({
                  'outbounds': [
                    {'tag': 'HK-01', 'type': 'vless'},
                  ],
                })
              : 'mixed-port: 7890\nproxies: []\n',
        );
        await req.response.close();
      });

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      expect(
        profile.customUserAgent,
        contains('sing-box'),
        reason: '成功的 UA 应当写回订阅，供后续刷新复用',
      );

      seenUserAgents.clear();
      await repo.update(profile.id);

      expect(
        seenUserAgents.first.toLowerCase(),
        contains('sing-box'),
        reason: '刷新的第一次请求就该用记住的 UA，而不是先撞一次空配置',
      );
      final out =
          jsonDecode(await File(repo.configFilePath(profile.id)).readAsString())
              as Map<String, dynamic>;
      final tags = (out['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag'])
          .toList();
      expect(tags, contains('HK-01'));
    });
  });
}
