import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 起一个记录请求次数的 HTTP server，用来验证"保存时是否真的发起了网络请求"
/// ——不关心内容本身，只关心「被打到几次」。
Future<HttpServer> _countingServer(void Function() onRequest) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // ignore: unawaited_futures
  server.listen((req) async {
    onRequest();
    req.response.write(
      jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'node'},
        ],
      }),
    );
    await req.response.close();
  });
  return server;
}

/// 这几个测试需要真的走一遍网络（本地 HttpServer + dio 请求）来验证
/// "保存是否真的触发了重新拉取"，而不是只看 UI 状态。
///
/// `tester.runAsync`：widget test 默认跑在 fake-time zone 里（`tester.pump`
/// 靠它才能快进动画），真实 Socket / Timer（HttpServer 内部的 idle 超时）在
/// 这个 zone 里会跟 fake clock 打架（"Timer 到测试结束还没触发"的报错）。
///
/// 另外 `TestWidgetsFlutterBinding` 会全局装一个 `_MockHttpOverrides`——任何
/// `HttpClient()`（包括 dio 的 IOHttpClientAdapter 内部创建的）不打真实网络、
/// 一律返回 400。这里用 [_disableHttpMock] 在本文件级别关掉它（见其文档）。
Future<T?> _withRealNetwork<T>(
  WidgetTester tester,
  Future<T> Function() body,
) {
  return tester.runAsync(body);
}

/// 关掉 `TestWidgetsFlutterBinding` 装的全局 HTTP mock（一律返回 400、不打真实
/// 网络）。
///
/// 只能设 `HttpOverrides.global = null`，不能用 `HttpOverrides.runZoned` 包一层
/// "真的建一个 HttpClient" 的 createHttpClient 回调——那个回调本身运行在它自己
/// 建的 zone 里，回调内调用的 `HttpClient()` 工厂构造器会看到
/// `HttpOverrides.current` 还是它自己，再次递归调用同一个回调，直接栈溢出。
/// `setupHttpOverrides()`只在 `TestWidgetsFlutterBinding.initInstances()` 调用
/// 一次（每个测试文件独立进程），所以这里清一次全局值，对本文件内其余测试
/// 都有效，不会被自动重新装回。
void _disableHttpMock() {
  HttpOverrides.global = null;
}

/// 反复小步 pump，直到 [condition] 成立或者到达 [timeout]——用来等待一个
/// 真实网络请求落地后触发的 UI 变化，比固定 `Future.delayed` 更抗系统负载抖动。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('_pumpUntil 超时（$timeout）仍未满足条件');
    }
    await Future.delayed(step);
    await tester.pump(step);
  }
}

Future<Widget> _host({
  required ProfileRepository repo,
  required ProfileEntity profile,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(StubBoxService()),
      profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
      profileListProvider.overrideWith((_) => Future.value(repo.getAll())),
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileListProvider.future);
  await container.read(activeProfileProvider.future);

  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          splashFactory: NoSplash.splashFactory,
        ),
        home: ProfileDetailsPage(profile.id),
      ),
    ),
  );
}

void main() {
  group('ProfileDetailsPage._save 保存时的重新拉取行为', () {
    late Directory tmpDir;
    late ProfileRepository repo;

    setUp(() async {
      _disableHttpMock();
      tmpDir = await Directory.systemTemp.createTemp('details_save_');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = ProfileRepository(
        dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 3))),
        configDir: tmpDir,
        prefs: prefs,
        boxService: StubBoxService(),
      );
    });

    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    testWidgets('URL 变化时保存会触发一次真实的重新拉取', (tester) async {
      await _withRealNetwork(tester, () async {
        var requestCount = 0;
        final server = await _countingServer(() => requestCount++);
        addTearDown(() => server.close(force: true));

        final profile = ProfileEntity(
          id: 'p1',
          name: '旧订阅',
          url: 'https://old.example.invalid/sub',
          active: true,
          lastUpdate: DateTime.now(),
        );
        await repo.upsert(profile.toJson());

        await tester.pumpWidget(await _host(repo: repo, profile: profile));
        await tester.pump(const Duration(milliseconds: 250));

        final urlField = find.byWidgetPredicate(
          (w) => w is TextField && w.keyboardType == TextInputType.url,
        );
        expect(urlField, findsOneWidget);
        await tester.enterText(
          urlField,
          'http://localhost:${server.port}/new',
        );
        await tester.tap(find.text('保存'));
        await tester.pump();
        await _pumpUntil(tester, () => requestCount > 0);
        await tester.pumpAndSettle();

        expect(requestCount, 1);
        expect(
          repo.getAll().firstWhere((p) => p.id == 'p1').url,
          'http://localhost:${server.port}/new',
        );
      });
    });

    testWidgets('URL 未变化时保存不应该发起多余的网络请求', (tester) async {
      await _withRealNetwork(tester, () async {
        var requestCount = 0;
        final server = await _countingServer(() => requestCount++);
        addTearDown(() => server.close(force: true));

        final profile = ProfileEntity(
          id: 'p2',
          name: '旧订阅',
          url: 'http://localhost:${server.port}/unchanged',
          active: true,
          lastUpdate: DateTime.now(),
        );
        await repo.upsert(profile.toJson());

        await tester.pumpWidget(await _host(repo: repo, profile: profile));
        await tester.pump(const Duration(milliseconds: 250));

        // 只改名称，不改网址
        await tester.enterText(find.byType(TextField).first, '新名称');
        await tester.tap(find.text('保存'));
        await tester.pump();
        await _pumpUntil(
          tester,
          () => repo.getAll().firstWhere((p) => p.id == 'p2').name == '新名称',
        );
        await tester.pumpAndSettle();

        expect(requestCount, 0);
        expect(repo.getAll().firstWhere((p) => p.id == 'p2').name, '新名称');
      });
    });
  });
}
