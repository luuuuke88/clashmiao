import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:clashmiao/features/about/application/update_check_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/about/presentation/about_page.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/toast_pump.dart';

Future<Widget> _host({List<Override> extraOverrides = const []}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      ...extraOverrides,
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const AboutPage(),
      ),
    ),
  );
}

void main() {
  // AppToast 对同文案做 800 ms（真实时钟）去重，状态是进程级静态的；每个用例前
  // 清掉，避免上一例弹过的提示让下一例的提示被吞——否则用例顺序一换就红。
  setUp(AppToast.resetForTest);

  testWidgets('AboutPage renders app overview', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    // 标题走 i18n。此前这里硬编码 'About ClashMiao'，在简中环境下顶着一个
    // 英文标题，而「线路」「设置」这些页的标题都是中文——这条断言当时把这个
    // bug 一起锁住了。品牌名在下方的大字标里已经有，标题不必再带一次。
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('About ClashMiao'), findsNothing);
    expect(find.text('ClashMiao'), findsOneWidget);
    expect(find.text('VERSION 1.2.3 (BUILD 45)'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    // 源代码有兜底默认 URL（见 build_config.dart 的 githubRepoUrl），永远可用
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('MADE WITH LOVE FOR CATS'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.only(top: 48),
      ),
      findsOneWidget,
    );
    // 版权行：不写年份与 All Rights Reserved（许可证未定），12 sp、字距 0、可换行。
    expect(
      find.text('© 2024 ClashMiao Studio. All Rights Reserved.'),
      findsNothing,
    );
    final copyright = tester.widget<Text>(find.text('© ClashMiao'));
    expect(copyright.style?.fontSize, 12);
    expect(copyright.style?.letterSpacing, 0);
    expect(copyright.softWrap, isNot(false));
    expect(copyright.maxLines, isNull);
    expect(find.byType(SliverFillRemaining), findsOneWidget);
    expect(find.byType(BrandMark), findsOneWidget);
    expect(find.byIcon(FluentIcons.animal_paw_print_20_filled), findsNothing);
  });

  // 这些外链靠编译期 --dart-define 注入。以前没配置时行为是"入口还在、点了
  // 什么都不发生"——用户会认为这个 App 有坏按钮，而不是"这个功能没提供"。
  // 现在改成没配置就不显示入口。
  //
  // 这条测试是**双向**的：断言跟着 `hasXxx` 走，而不是写死某一边。
  // - 默认（CI）跑：dart-define 为空 → 验证"未配置就不显示"
  // - 注入后跑：`flutter test test/features/about/ \
  //     --dart-define=PRIVACY_POLICY_URL=https://example.com/privacy \
  //     --dart-define=TELEGRAM_CHANNEL_URL=https://t.me/example`
  //   → 验证"配置了就显示"，同时证明 dart-define 名字跟 build_config.dart
  //   真的对得上（写错名字这一侧就会红）
  //
  // 两个方向都实跑验证过。只锁一边的话，"名字打错导致永远走未配置分支"
  // 这种错误会完全测不出来——而那正是这套机制最容易出的错。
  testWidgets('外链入口跟随 dart-define 配置状态显示/隐藏', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    expect(
      find.text('Telegram 频道'),
      hasTelegramChannel ? findsOneWidget : findsNothing,
    );
    expect(find.text('隐私政策'), hasPrivacyPolicy ? findsOneWidget : findsNothing);
  });

  // 「检查更新」的点击交互此前零测试覆盖（parity 追踪表里记为 Important
  // backlog）。两条分支都要锁：没有新版本时给一条"已是最新"轻提示，
  // 有新版本时弹更新对话框——后者是这个功能存在的意义，不能只测到
  // "点了不崩溃"。
  group('检查更新的点击交互', () {
    testWidgets('没有新版本时提示"已是最新"，不弹对话框', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await _host(
          extraOverrides: [
            updateCheckProvider.overrideWith(
              (_) async => const UpdateCheckResult.upToDate(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.text('现在更新'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('有新版本时弹出更新对话框（带版本号对比）', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await _host(
          extraOverrides: [
            updateCheckProvider.overrideWith(
              (_) async => const UpdateCheckResult.available('v9.9.9'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('现在更新'), findsOneWidget);
      // 当前版本来自 _host 里 mock 的 PackageInfo(1.2.3)，新版本去掉 v 前缀
      expect(find.textContaining('9.9.9'), findsWidgets);

      // 关掉对话框，别把它留给后面的用例
      await tester.tap(find.text('以后再说'));
      await tester.pumpAndSettle();
    });

    testWidgets('检查失败时提示失败，不能说成"已是最新"，也不弹对话框', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await _host(
          extraOverrides: [
            updateCheckProvider.overrideWith(
              (_) async => const UpdateCheckResult.failed(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
      expect(find.text('已是最新版本'), findsNothing);
      expect(find.text('现在更新'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('provider 自己抛异常也按失败处理，加载态会恢复', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await _host(
          extraOverrides: [
            updateCheckProvider.overrideWith(
              (_) => Future<UpdateCheckResult>.error(
                StateError('prefs unavailable'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(find.text('检查更新失败，请检查网络后重试'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  testWidgets('关于页可滚动：小屏上能把底部内容滚进视野', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(scrollView.physics, isNot(isA<NeverScrollableScrollPhysics>()));

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, greaterThan(0), reason: '小屏内容应超出一屏');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: '手势应当真的滚动页面');
    await tester.scrollUntilVisible(find.text('© ClashMiao'), 100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文字放大 2.0 倍时关于页不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('开源许可', () {
    testWidgets('有「开源许可」入口，点击打开 LicensePage', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _host());
      await tester.pumpAndSettle();

      expect(find.text('开源许可'), findsOneWidget);
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();

      final page = tester.widget<LicensePage>(find.byType(LicensePage));
      expect(page.applicationName, 'ClashMiao');
      expect(page.applicationVersion, '1.2.3');
      expect(page.applicationIcon, isNotNull);
    });
  });
}
