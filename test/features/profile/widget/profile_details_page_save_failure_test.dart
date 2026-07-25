import 'dart:io';
import 'dart:typed_data';

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

import '../../../support/temp_dirs.dart';

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

/// 返回一个固定响应体的假 [HttpClientAdapter]，不发出任何真实网络请求。
///
/// 这个文件原来起的是真实 `HttpServer` + 真实 socket。实测（连跑 6 轮全量
/// 测试）它跟 `profile_details_page_save_test.dart` **会一起偶发失败**，
/// 每轮失败的用例计数还不一样——典型的共享资源争用，争的就是这套真实网络
/// 栈（端口绑定 + socket + `connectTimeout: 3s`）在高负载下的表现。
///
/// 换成 adapter 层假实现后争用源消失，而断言强度不变：`ProfileRepository`
/// 走的是注入的这个 `dio`，Dio 完整请求管线仍被执行，只是不落到 socket。
/// 写法沿用仓库既有范式（`egress_ip_service_test.dart` 等的 `_FakeAdapter`）。
class _FixedBodyAdapter implements HttpClientAdapter {
  const _FixedBodyAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(body, HttpStatus.ok);

  @override
  void close({bool force = false}) {}
}

/// 反复小步 pump，直到 [condition] 成立或到达 [timeout]。
///
/// 这里的真实时间等待无法消除：`ProfileRepository` 写真实文件（fake-time 下
/// 完不成），且 `_save()` 期间的 `CircularProgressIndicator` 是无限动画
/// （`pumpAndSettle()` 在那个窗口内永远收敛不了）。但它现在等的只是本地
/// 文件 I/O + 微任务（毫秒级），deadline 给到 60 秒纯粹是让系统负载不可能
/// 成为判定因素。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 60),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('_pumpUntil 超时（$timeout）仍未满足条件');
    }
    await Future<void>.delayed(step);
    await tester.pump(step);
  }
}

void main() {
  testWidgets('URL 变化但拉取失败时会明确提示错误，不能静默吞掉', (tester) async {
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'details_save_fail_',
      );
      addTearDown(() async {
        await deleteTempDirBestEffort(tmpDir);
      });
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();

      // 真的会走一遍 Dio 请求管线，但响应体不是"看起来已经是合法 sing-box
      // JSON"的内容（否则 `_normalizeAndWrite` 会走直通快路径，完全不调
      // boxService.validateConfig，下面"永远判定无效"就测不到了）。
      final dio = Dio();
      dio.httpClientAdapter = const _FixedBodyAdapter('not-a-valid-config');

      final repo = ProfileRepository(
        dio: dio,
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
          boxServiceProvider.overrideWithValue(const StubBoxService()),
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
      await tester.enterText(urlField, 'https://new.example.invalid/new');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.textContaining('失败').evaluate().isNotEmpty,
      );

      // 明确的失败反馈：toast 文案里带着"失败"字样，不能静默吞掉
      expect(find.textContaining('失败'), findsWidgets);
    });
  });
}
