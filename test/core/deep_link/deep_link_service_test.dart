import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端到端覆盖"解析 → 调用 addByUrl/addByContent → 写入
/// deepLinkImportResultProvider"整条链路，不经过真实 AppLinks 平台通道
/// （那部分只能靠真机验证，见 p3-deeplink-report.md）。
///
/// 用真实 [ProfileRepository]（配合一个本地 loopback HTTP server 服务假订阅
/// 响应）而不是 mock，与 profile_repository_test.dart 的 `_serveOnce` 写法
/// 保持一致，这样 addByUrl 真正的网络抓取 + 归一化 + 持久化都会被实际跑到。

Future<HttpServer> _serveOnce(String body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen((req) async {
    req.response.write(body);
    await req.response.close();
  });
  return server;
}

/// "透传 Ref"的 throwaway provider：拿到跟测试用 ProviderContainer 绑定的、
/// 货真价实的 [Ref]——和 DeepLinkService 自己拿到 Ref 的方式完全一致，不需要
/// 经过真实 AppLinks 平台通道就能直接驱动 [handleDeepLink]。
final _refProvider = Provider<Ref>((ref) => ref);

const _validSingBoxJsonBody = '''
{
  "outbounds": [
    {"type": "selector", "tag": "p", "outbounds": []}
  ],
  "inbounds": [
    {"type": "mixed", "listen_port": 2080}
  ],
  "route": {"rules": []}
}
''';

void main() {
  late Directory tmpDir;
  late ProviderContainer container;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('deep_link_service_test_');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(
      dio: Dio(),
      configDir: tmpDir,
      prefs: prefs,
      boxService: StubBoxService(),
    );
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('install-sub 深链：解析 → 真实 HTTP 抓取 → 落地为订阅 → 成功反馈 '
      '（?name= 覆盖 URL fragment 派生的名称）', () async {
    final server = await _serveOnce(_validSingBoxJsonBody);
    addTearDown(() => server.close(force: true));

    final ref = container.read(_refProvider);
    final subUrl = 'http://localhost:${server.port}/sub#来自URL的名字';
    final uri = Uri.parse(
      'clashmiao://install-sub'
      '?url=${Uri.encodeComponent(subUrl)}'
      '&name=${Uri.encodeComponent('自定义名称')}',
    );

    await handleDeepLink(uri, ref);

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportSuccess>());
    expect((result as DeepLinkImportSuccess).profileName, '自定义名称');

    final profiles = await container.read(profileListProvider.future);
    expect(profiles, hasLength(1));
    expect(profiles.single.name, '自定义名称');
    expect(profiles.single.url, subUrl);
  });

  test('clash://install-config 深链：与 install-sub 走相同的 addByUrl 路径', () async {
    final server = await _serveOnce(_validSingBoxJsonBody);
    addTearDown(() => server.close(force: true));

    final ref = container.read(_refProvider);
    final uri = Uri.parse(
      'clash://install-config'
      '?url=${Uri.encodeComponent('http://localhost:${server.port}/cfg')}',
    );

    await handleDeepLink(uri, ref);

    expect(
      container.read(deepLinkImportResultProvider),
      isA<DeepLinkImportSuccess>(),
    );
    final profiles = await container.read(profileListProvider.future);
    expect(profiles, hasLength(1));
  });

  test('缺 url 参数：不调用 repo，直接写失败反馈，profile 列表保持为空', () async {
    final ref = container.read(_refProvider);
    await handleDeepLink(Uri.parse('clashmiao://install-sub'), ref);

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportFailure>());

    final profiles = await container.read(profileListProvider.future);
    expect(profiles, isEmpty);
  });

  test('订阅抓取失败（连不上）：捕获异常写失败反馈，不崩溃、不抛出', () async {
    final ref = container.read(_refProvider);
    // 127.0.0.1:1 本地不可能有服务在监听，几乎立刻 connection refused。
    final uri = Uri.parse(
      'clashmiao://install-sub'
      '?url=${Uri.encodeComponent('http://127.0.0.1:1/not-listening')}',
    );

    await handleDeepLink(uri, ref);

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportFailure>());
    final profiles = await container.read(profileListProvider.future);
    expect(profiles, isEmpty);
  });

  test('clashmiao://import 携带单节点代理 URI → addByContent 落地，'
      '全程不发起网络请求', () async {
    final ref = container.read(_refProvider);
    // host:port 用明显不可达的地址：如果实现误走了 addByUrl 网络请求分支，
    // 这条 test 会因为连接失败/超时而不是"成功"收场，从而暴露问题。
    const proxyUri =
        'vless://11111111-2222-3333-4444-555555555555'
        '@127.0.0.1:1?encryption=none#测试节点';
    final uri = Uri.parse(
      'clashmiao://import?url=${Uri.encodeComponent(proxyUri)}',
    );

    await handleDeepLink(uri, ref);

    final result = container.read(deepLinkImportResultProvider);
    expect(result, isA<DeepLinkImportSuccess>());

    final profiles = await container.read(profileListProvider.future);
    expect(profiles, hasLength(1));
    expect(profiles.single.url, startsWith('content://'));
  });

  test('clashmiao://import 携带 http(s) URL → 当订阅处理，走真实 HTTP 抓取', () async {
    final server = await _serveOnce(_validSingBoxJsonBody);
    addTearDown(() => server.close(force: true));

    final ref = container.read(_refProvider);
    final uri = Uri.parse(
      'clashmiao://import'
      '?url=${Uri.encodeComponent('http://localhost:${server.port}/sub')}',
    );

    await handleDeepLink(uri, ref);

    expect(
      container.read(deepLinkImportResultProvider),
      isA<DeepLinkImportSuccess>(),
    );
    final profiles = await container.read(profileListProvider.future);
    expect(profiles.single.url, isNot(startsWith('content://')));
  });

  test('未注册的 host（防御性兜底）：不调用 repo、也不写反馈状态', () async {
    final ref = container.read(_refProvider);
    await handleDeepLink(
      Uri.parse(
        'clashmiao://not-a-real-host'
        '?url=${Uri.encodeComponent('https://example.com')}',
      ),
      ref,
    );

    expect(container.read(deepLinkImportResultProvider), isNull);
    final profiles = await container.read(profileListProvider.future);
    expect(profiles, isEmpty);
  });
}
