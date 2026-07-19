import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
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

// 独立成单独文件的原因：`AppToast`（lib/shared/components/app_toast.dart）
// 用静态字段做"800ms 内同文案去重"+ 调用 `toastification.dismissAll(...)`，
// 这个状态和 `toastification` 包自己的 Overlay 缓存都是进程级的、跨
// `testWidgets` 用例持续存在。放在同一个文件里跟其它 `_save` 测试连续跑时，
// 观察到这里的 toast 断言会稳定超时（前面用例已经触发过 toast，污染了这里
// 的状态）。`flutter test` 默认每个测试**文件**起一个独立进程，单独成文件
// 后不再有这个问题。

/// 永远判定配置无效的 [BoxService] fake——用来确定性地触发
/// `ProfileRepository.update()` 抛错（`ProfileValidationException`），不依赖
/// "连一个不存在的端口要多久才失败"这种受操作系统/环境影响的真实网络超时。
/// 真实的 HTTP 请求仍然会发生——只是响应内容永远通不过校验。
class _AlwaysInvalidBoxService implements BoxService {
  const _AlwaysInvalidBoxService();

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async => 'invalid config';

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

void main() {
  testWidgets('URL 变化但拉取失败时会明确提示错误，不能静默吞掉', (tester) async {
    HttpOverrides.global = null; // 关掉 TestWidgetsFlutterBinding 的全局 HTTP mock

    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp('details_save_fail_');
      addTearDown(() async {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();

      // 真的会发起 HTTP 请求，但响应体不是"看起来已经是合法 sing-box JSON"的
      // 内容（否则 `_normalizeAndWrite` 会走直通快路径，完全不调
      // boxService.validateConfig，下面"永远判定无效"就测不到了）。
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      // ignore: unawaited_futures
      server.listen((req) async {
        req.response.write('not-a-valid-config');
        await req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final repo = ProfileRepository(
        dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 3))),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const _AlwaysInvalidBoxService(),
      );

      final profile = ProfileEntity(
        id: 'p3',
        name: '旧订阅',
        url: 'https://old.example.invalid/sub',
        active: true,
        lastUpdate: DateTime.now(),
      );
      await repo.upsert(profile.toJson());

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

      await tester.pumpWidget(
        UncontrolledProviderScope(
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
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      final urlField = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.url,
      );
      await tester.enterText(urlField, 'http://localhost:${server.port}/new');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.textContaining('失败').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();

      // 明确的失败反馈：toast 文案里带着"失败"字样，不能静默吞掉
      expect(find.textContaining('失败'), findsWidgets);
    });
  });
}
