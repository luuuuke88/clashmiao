import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/build_config.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:clashmiao/features/about/widget/about_page.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

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
  testWidgets('AboutPage renders app overview', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    expect(find.text('About ClashMiao'), findsOneWidget);
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
    expect(
      find.text('© 2024 ClashMiao Studio. All Rights Reserved.'),
      findsOneWidget,
    );
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
            updateAvailableProvider.overrideWith((_) async => null),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('检查更新'));
      await tester.pump(const Duration(milliseconds: 300));

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
            updateAvailableProvider.overrideWith((_) async => 'v9.9.9'),
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
  });
}
