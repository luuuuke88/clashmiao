import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/core/box_service/model/box_stats.dart';
import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/box_service/model/directories.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/config/model/profile_nodes.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
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

/// 按新内核 `Parse` 的口径行事的假原生解析：叶子视图为空 → `no-outbounds:`，
/// 否则把输入原样写出。记录被调用的次数，用来断言「直通」没有进原生。
class _ParseLikeBoxService extends _ValidatingBoxService {
  _ParseLikeBoxService();

  int calls = 0;

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async {
    calls++;
    final raw = await File(tempPath).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map && profileNodeCount(decoded) == 0) {
      return 'no-outbounds: profile has no usable outbound';
    }
    await File(path).writeAsString(raw);
    return null;
  }
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

    test('sing-box JSON 原文带节点 → 直通保留 inbounds/route', () async {
      final body = jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'p'},
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

    test('sing-box JSON 多级 selector 直通后原样保存：只补 direct，不写 1.8 形态的死数据', () async {
      final input = <String, dynamic>{
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
        },
      };
      final server = await _serveOnce(jsonEncode(input), headers: {});
      addTearDown(() => server.close(force: true));

      final profile = await repo.addByUrl('http://localhost:${server.port}/');
      final out = jsonDecode(
        await File(repo.configFilePath(profile.id)).readAsString(),
      ) as Map<String, dynamic>;

      // 内核配置构建器对 selector / urltest / dns / route / inbounds 一律丢弃重建，
      // 落盘时不再改写它们：不补 proxy 选择组、不删 urltest、不改 route.final、
      // 不改 dns detour、不换 inbounds。
      expect(out['outbounds'], [
        ...(input['outbounds'] as List),
        {'type': 'direct', 'tag': 'direct'},
      ]);
      expect(out['route'], input['route']);
      expect(out['dns'], input['dns']);
      expect(out['inbounds'], input['inbounds']);
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
      final out = jsonDecode(
        await File(repo.configFilePath(profile.id)).readAsString(),
      ) as Map<String, dynamic>;
      final tags = [
        for (final o in out['outbounds'] as List) (o as Map)['tag'],
      ];
      expect(tags, ['HK-1', 'direct']);
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
          {'type': 'vless', 'tag': 'p'},
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
          {'type': 'vless', 'tag': name},
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

    test('空 name 使用注入的默认名（未注入时英文兜底）', () async {
      final profile = await repo.addByContent('ss://abc@h:1#x', name: '');
      expect(profile.name, 'Local import');

      // provider 注入的是当前语言的文案（惰性求值：按创建那一刻的语言）。
      final localized = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: repo.prefs,
        boxService: const StubBoxService(),
        store: repo.store,
        defaultNames: ProfileDefaultNames(local: () => '本地导入'),
      );
      final p2 = await localized.addByContent('ss://xyz@h:2#y', name: ' ');
      expect(p2.name, '本地导入');
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

      final out = jsonDecode(
        await File(repo.configFilePath(first.id)).readAsString(),
      ) as Map<String, dynamic>;
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
          {'type': 'vless', 'tag': 'old'},
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

    /// 用 [normalize] 当作 native Parse 的输出建仓库，导入后返回落盘配置。
    Future<Map<String, dynamic>> importNative(
      Map<String, dynamic> parsed,
    ) async {
      final repoWithNativeOutput = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: await SharedPreferences.getInstance(),
        boxService: _ValidatingBoxService(normalize: (_) => jsonEncode(parsed)),
      );
      final server = await _serveOnce('native-subscription', headers: {});
      addTearDown(() => server.close(force: true));
      final profile = await repoWithNativeOutput.addByUrl(
        'http://localhost:${server.port}/',
      );
      return jsonDecode(
        await File(repoWithNativeOutput.configFilePath(profile.id))
            .readAsString(),
      ) as Map<String, dynamic>;
    }

    test('native Parse 的输出原样落盘：只补 direct，不造 proxy 选择组 / route.final', () async {
      final parsed = <String, dynamic>{
        'outbounds': [
          {
            'type': 'urltest',
            'tag': '测速',
            'outbounds': ['HK-1', 'JP-1'],
          },
          {'type': 'vless', 'tag': 'HK-1'},
          {'type': 'vless', 'tag': 'JP-1'},
        ],
        'route': {'final': '测速'},
      };
      final out = await importNative(parsed);
      expect(out['outbounds'], [
        ...(parsed['outbounds'] as List),
        {'type': 'direct', 'tag': 'direct'},
      ]);
      expect(out['route'], {'final': '测速'});
      expect(out.containsKey('dns'), isFalse, reason: '不写 1.8 形态的 dns.servers');
      expect(
        out.containsKey('inbounds'),
        isFalse,
        reason: '不写带 inet4_address / sniff 的标准 inbounds',
      );
    });

    test('native Parse 输出已有 direct：一个字节都不改', () async {
      final parsed = <String, dynamic>{
        'outbounds': [
          {'type': 'trojan', 'tag': 'SG-1'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      };
      expect(await importNative(parsed), parsed);
    });

    test('只有端点的 Parse 输出合法：outbounds 为空数组也不失败，端点原样保留', () async {
      final parsed = <String, dynamic>{
        'outbounds': <Object>[],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg-hk'},
        ],
      };
      final out = await importNative(parsed);
      expect(out['endpoints'], parsed['endpoints']);
      expect(out['outbounds'], [
        {'type': 'direct', 'tag': 'direct'},
      ]);
    });

    test('update 同样原样保存 native Parse 的输出', () async {
      final parsed = <String, dynamic>{
        'outbounds': [
          {'type': 'trojan', 'tag': 'SG-1'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      };
      final repoWithNativeOutput = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: await SharedPreferences.getInstance(),
        boxService: _ValidatingBoxService(normalize: (_) => jsonEncode(parsed)),
      );
      final server = await _serveOnce('native-subscription', headers: {});
      addTearDown(() => server.close(force: true));
      final profile = await repoWithNativeOutput.addByUrl(
        'http://localhost:${server.port}/',
      );

      await repoWithNativeOutput.update(profile.id);

      final out = jsonDecode(
        await File(repoWithNativeOutput.configFilePath(profile.id))
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(out, parsed);
    });
  });

  group('JSON 直通判据 canPassThrough（所有入口共用的唯一口径）', () {
    late Directory tmpDir;
    late _ParseLikeBoxService box;
    late ProfileRepository repo;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('repo_passthrough_');
      SharedPreferences.setMockInitialValues({});
      box = _ParseLikeBoxService();
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: await SharedPreferences.getInstance(),
        boxService: box,
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmpDir);
    });

    List<File> profileFiles() => [
      for (final f in tmpDir.listSync(recursive: true))
        if (f is File && f.path.endsWith('.json')) f,
    ];

    test('direct-only JSON：不直通，Parse 报 no-outbounds，抛带码异常，不落盘', () async {
      const body = '{"outbounds":[{"type":"direct","tag":"direct"}]}';
      expect(canPassThrough(jsonDecode(body) as Map), isFalse);

      await expectLater(
        repo.addByContent(body, name: 'x'),
        throwsA(
          isA<ProfileValidationException>().having(
            (e) => e.code,
            'code',
            'no-outbounds',
          ),
        ),
      );
      expect(box.calls, 1, reason: '走了原生 Parse，没有直通');
      expect(repo.store.read(), isEmpty);
      expect(profileFiles(), isEmpty);
    });

    test('group-only JSON（只有 selector / urltest）：同上', () async {
      const body =
          '{"outbounds":[{"type":"selector","tag":"s","outbounds":["u"]},'
          '{"type":"urltest","tag":"u","outbounds":[]}]}';
      expect(canPassThrough(jsonDecode(body) as Map), isFalse);

      await expectLater(
        repo.addByContent(body, name: 'x'),
        throwsA(
          isA<ProfileValidationException>().having(
            (e) => e.code,
            'code',
            'no-outbounds',
          ),
        ),
      );
      expect(box.calls, 1);
      expect(repo.store.read(), isEmpty);
      expect(profileFiles(), isEmpty);
    });

    test('endpoint-only JSON：直通被接受并落盘（不进原生）', () async {
      const body =
          '{"outbounds":[],"endpoints":[{"type":"wireguard","tag":"wg-hk"}]}';
      expect(canPassThrough(jsonDecode(body) as Map), isTrue);

      final profile = await repo.addByContent(body, name: 'wg');

      expect(box.calls, 0, reason: '直通不调原生 Parse');
      final out = jsonDecode(
        await File(repo.configFilePath(profile.id)).readAsString(),
      ) as Map<String, dynamic>;
      expect(out['endpoints'], [
        {'type': 'wireguard', 'tag': 'wg-hk'},
      ]);
      expect(profileNodeCount(out), 1, reason: '落盘后不被判空');
    });

    test('含旧形态的 JSON 不直通：走 Parse', () async {
      const body =
          '{"outbounds":[{"type":"wireguard","tag":"w","server":"x"}]}';
      expect(canPassThrough(jsonDecode(body) as Map), isFalse);
      await repo.addByContent(body, name: 'old');
      expect(box.calls, 1);
    });

    test('canPassThrough 与共用夹具逐行一致：needsCleaning 的行不直通，其余直通', () {
      final shapes =
          (jsonDecode(
                File('kernel/testdata/shared/legacy-shapes.json')
                    .readAsStringSync(),
              ) as Map<String, dynamic>)['shapes']
              as List;
      expect(shapes, isNotEmpty);
      for (final row in shapes.cast<Map<String, dynamic>>()) {
        // 每行配一个干净的真实节点，让「叶子视图非空」恒成立，只测旧形态这一维。
        final profile = {
          'outbounds': [
            row['json'],
            {'type': 'shadowsocks', 'tag': 'clean-node'},
          ],
        };
        expect(
          canPassThrough(profile),
          !(row['needsCleaning'] as bool),
          reason: '${row['name']}',
        );
      }
    });

    test('旧形态清单覆盖的每个字段：单独出现就不直通', () {
      for (final field in [
        'tls_fragment',
        'domain_strategy',
        'sniff',
        'sniff_override_destination',
      ]) {
        expect(
          canPassThrough({
            'outbounds': [
              {'type': 'vless', 'tag': 'v', field: 1},
            ],
          }),
          isFalse,
          reason: field,
        );
      }
      expect(
        canPassThrough({
          'outbounds': [
            {
              'type': 'vless',
              'tag': 'v',
              'tls': {'tls_tricks': <String, dynamic>{}},
            },
          ],
        }),
        isFalse,
      );
    });

    test('订阅自带的 selector / urltest / direct 不阻止直通', () {
      expect(
        canPassThrough({
          'outbounds': [
            {
              'type': 'selector',
              'tag': 's',
              'outbounds': ['v'],
            },
            {
              'type': 'urltest',
              'tag': 'u',
              'outbounds': ['v'],
            },
            {'type': 'direct', 'tag': 'direct'},
            {'type': 'vless', 'tag': 'v'},
          ],
        }),
        isTrue,
      );
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

      final out = jsonDecode(
        await File(repo.configFilePath(profile.id)).readAsString(),
      ) as Map<String, dynamic>;
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
      final out = jsonDecode(
        await File(repo.configFilePath(profile.id)).readAsString(),
      ) as Map<String, dynamic>;
      final tags = (out['outbounds'] as List)
          .cast<Map<String, dynamic>>()
          .map((o) => o['tag'])
          .toList();
      expect(tags, contains('HK-01'));
    });
  });
}
