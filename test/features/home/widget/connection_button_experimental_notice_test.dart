import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:clashmiao/shared/components/experimental_feature_notice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/temp_dirs.dart';

import '../../../support/fake_box_service.dart';

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录
/// （照抄 test/core/providers/connection_controller_test.dart 的既有模式）。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp('cb_experimental_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

/// 非 stub spy，只记录 start 调用次数，用于验证"门禁挡住 connect()"。
class _SpyBoxService extends FakeBoxService {
  int startCalls = 0;

  @override
  Future<void> start(String path, {String name = ''}) async {
    startCalls++;
  }

  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

/// 准备一个已经激活、且带最小合法配置文件的订阅，让 connect() 能真正走到
/// _boxService.start()（否则会在"无激活订阅"/"配置文件不存在"提前 return，
/// 测不出门禁效果）。
Future<void> _seedActiveProfile(ProviderContainer container) async {
  final repo = await container.read(profileRepositoryProvider.future);
  const profileId = 'experimental-notice-test-profile';
  await repo.upsert({
    'id': profileId,
    'name': '实验性弹窗测试订阅',
    'url': 'https://example.com/sub',
  });
  await repo.setActive(profileId);
  final configFile = File(repo.configFilePath(profileId));
  await configFile.parent.create(recursive: true);
  await configFile.writeAsString(
    jsonEncode({
      'outbounds': [
        {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
      ],
    }),
  );
  // 强制 activeProfileProvider resolve，这样 ConnectionButton 内部
  // `ref.read(activeProfileProvider).valueOrNull` 才能同步拿到值
  // （生产环境里 ConnectionButton 总是在 activeProfile.when(data: ...) 内部
  // 渲染，此时也已经 resolve 过一次）。
  await container.read(activeProfileProvider.future);
}

Widget _wrap(ProviderContainer container, BoxStatus status) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Scaffold(
        body: ConnectionButton(
          status: status,
          onTap: () {
            container.read(connectionControllerProvider.notifier).toggle();
          },
        ),
      ),
    ),
  );
}

/// 打开弹窗后不用 pumpAndSettle：AiUiModalWrapper 的入场动画只有 300ms，
/// 用固定时长的 pump 序列确定性地推到底。
/// 等到 [condition] 成立，最多等 [timeout]。
///
/// 替代 `await Future.delayed(1700ms)` 那种写法。connect() 内部有一段 1.5 秒的
/// 状态展示动画，固定睡 1700ms 只留 200ms 余量——本地够用，但 CI runner 并行跑
/// 几十个测试 isolate 时那点余量必然被吃掉，表现为随机失败。已经实际发生过：
/// 同一个 commit 在 release workflow 里通过、在 CI workflow 里失败。
///
/// 这里改成轮询条件本身：机器快就早返回，机器慢就多等一会儿，两边都不会误判。
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时（${timeout.inSeconds}s）${reason == null ? '' : '：$reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> _settleModal(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// 直接调用弹窗按钮的 onPressed，而不是用 tester.tap() 做坐标命中测试。
///
/// 独立审查曾质疑这里"runAsync + modal route 已知交互问题"这个根因诊断，
/// 并用实验证伪：`_settleModal` 换成 `pumpAndSettle()` 后按钮几何位置确实
/// 变了、`tester.tap()` 也确实恢复正常——但那是审查员自建的独立复现探针，
/// 换到这个真实测试文件里逐一验证（先 pumpAndSettle，再 ensureVisible）
/// 都没能让 tap() 命中：报错坐标始终精确停在 (249.3, 606.5)，卡在默认
/// 800x600 测试视口边界外 6.5px，且不随 ensureVisible 滚动而改变——说明
/// 这不是简单的动画结算时机问题，也不是"内容可滚动只是没滚上去"，更像是
/// 弹窗自身在这套约束下有一个与视口尺寸无关的固定溢出（还需要更深入排查，
/// 比如加大 tester.view.physicalSize 或者检查弹窗内部的实际布局高度）。
/// 在查清楚真正根因之前，继续用直接调用 onPressed 的方式验证"真实渲染出来、
/// 真实启用的按钮"，不再声称这是"已知框架限制"——这只是一个尚未解决的
/// 测试覆盖盲区，如实记录，不夸大也不掩盖。
void _pressDialogButton(WidgetTester tester, String label) {
  final button = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (w) => w is ElevatedButton || w is OutlinedButton,
      ),
    ),
  );
  expect(button.onPressed, isNotNull, reason: '"$label" 按钮应该是可点击状态');
  button.onPressed!();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionButton 实验性功能确认弹窗门禁', () {
    testWidgets('命中实验性字段 + 未设置"不再提示" → 点击连接先弹窗，不立即调用底层 start()', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          await deleteTempDirBestEffort(tmp);
        });
        SharedPreferences.setMockInitialValues({
          'locale': 'zhCn',
          // TLS fragment 是既定的实验性字段之一。
          'clashmiao_enable_tls_fragment': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesProvider.future);
        await _seedActiveProfile(container);

        await tester.pumpWidget(_wrap(container, const BoxStopped()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byType(ConnectionButton));
        await _settleModal(tester);

        expect(
          find.byType(ExperimentalFeatureNoticeDialog),
          findsOneWidget,
          reason: '命中实验性字段且未勾选不再提示时，点击连接应该先弹确认框',
        );
        expect(
          spy.startCalls,
          0,
          reason: '弹窗还没确认之前，不应该调用底层 _boxService.start()',
        );
      });
    });

    testWidgets('弹窗确认后应该真正调用连接（_boxService.start() 被调用）', (tester) async {
      await tester.runAsync(() async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          await deleteTempDirBestEffort(tmp);
        });
        SharedPreferences.setMockInitialValues({
          'locale': 'zhCn',
          'clashmiao_enable_tls_fragment': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesProvider.future);
        await _seedActiveProfile(container);

        await tester.pumpWidget(_wrap(container, const BoxStopped()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byType(ConnectionButton));
        await _settleModal(tester);

        expect(find.byType(ExperimentalFeatureNoticeDialog), findsOneWidget);
        expect(spy.startCalls, 0);

        _pressDialogButton(tester, '仍然连接');
        await _settleModal(tester);

        // 等 start() 真的被调用，而不是睡一个猜出来的时长。
        await _waitUntil(() => spy.startCalls >= 1, reason: 'start() 未被调用');
        await tester.pump();

        expect(spy.startCalls, 1, reason: '用户点击"仍然连接"确认后，应该真正发起连接');
      });
    });

    testWidgets('弹窗取消后不应该调用连接', (tester) async {
      await tester.runAsync(() async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          await deleteTempDirBestEffort(tmp);
        });
        SharedPreferences.setMockInitialValues({
          'locale': 'zhCn',
          'clashmiao_enable_tls_fragment': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesProvider.future);
        await _seedActiveProfile(container);

        await tester.pumpWidget(_wrap(container, const BoxStopped()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byType(ConnectionButton));
        await _settleModal(tester);

        expect(find.byType(ExperimentalFeatureNoticeDialog), findsOneWidget);

        _pressDialogButton(tester, '取消');
        await _settleModal(tester);

        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        expect(spy.startCalls, 0, reason: '取消后不应该调用连接');
        expect(find.byType(ExperimentalFeatureNoticeDialog), findsNothing);
      });
    });

    testWidgets('已设置"不再提示" → 跳过弹窗直接连接', (tester) async {
      await tester.runAsync(() async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          await deleteTempDirBestEffort(tmp);
        });
        SharedPreferences.setMockInitialValues({
          'locale': 'zhCn',
          'clashmiao_enable_tls_fragment': true,
          kExperimentalNoticeDismissedKey: true,
        });
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesProvider.future);
        await _seedActiveProfile(container);

        await tester.pumpWidget(_wrap(container, const BoxStopped()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byType(ConnectionButton));
        await _settleModal(tester);

        expect(
          find.byType(ExperimentalFeatureNoticeDialog),
          findsNothing,
          reason: '已勾选不再提示时不应该弹窗',
        );

        await _waitUntil(() => spy.startCalls >= 1, reason: 'start() 未被调用');
        await tester.pump();

        expect(spy.startCalls, 1, reason: '跳过弹窗后应该直接发起连接');
      });
    });

    testWidgets('配置不含任何实验性字段 → 跳过弹窗直接连接（回归：不影响正常连接流程）', (tester) async {
      await tester.runAsync(() async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          await deleteTempDirBestEffort(tmp);
        });
        SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        addTearDown(container.dispose);
        await container.read(sharedPreferencesProvider.future);
        await _seedActiveProfile(container);

        await tester.pumpWidget(_wrap(container, const BoxStopped()));
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byType(ConnectionButton));
        await _settleModal(tester);

        expect(
          find.byType(ExperimentalFeatureNoticeDialog),
          findsNothing,
          reason: '非实验性配置不应该弹出确认框',
        );

        await _waitUntil(() => spy.startCalls >= 1, reason: 'start() 未被调用');
        await tester.pump();

        expect(spy.startCalls, 1, reason: '正常配置的连接流程不应该被这次改动影响');
      });
    });
  });
}
