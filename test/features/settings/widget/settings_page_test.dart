import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/settings/widget/per_app_proxy_page.dart';
import 'package:clashmiao/features/settings/widget/settings_page.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<Widget> _host({
  bool? debugIsAndroid,
  bool? debugIsIOS,
  String locale = 'zhCn',
  BoxService? boxService,
}) async {
  SharedPreferences.setMockInitialValues({'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(boxService ?? StubBoxService()),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          // 本机 flutter test host engine 的 shaders/ink_sparkle.frag 产物版本
          // 与 tester 引擎不匹配（预置环境问题，与本文件测试内容无关，已用隔离
          // 对照实测确认：`per_app_proxy_page_test.dart` 在完全不涉及本文件任何
          // 改动的情况下同样会触发），默认 Material 3 splash 工厂在真实 tap
          // 触发水波纹时会尝试加载该 shader 并抛出无法在 pumpAndSettle 之后用
          // takeException 挽回的异步异常。测试不关心水波纹视觉效果，这里禁用
          // splash 从根上避免触发这条加载路径，而不是逐个测试事后补救。
          splashFactory: NoSplash.splashFactory,
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: SettingsPage(
          debugIsAndroid: debugIsAndroid,
          debugIsIOS: debugIsIOS,
        ),
      ),
    ),
  );
}

/// resetTunnel 调用次数 + 可选异常注入的 spy，其余方法直接复用 [StubBoxService]
/// 的空实现——这条测试只关心 Reset Tunnel 入口是否真的调到了
/// `boxService.resetTunnel()`。
class _ResetTunnelSpyBoxService extends StubBoxService {
  int resetTunnelCalls = 0;
  Object? resetTunnelError;

  @override
  Future<void> resetTunnel() async {
    resetTunnelCalls++;
    final error = resetTunnelError;
    if (error != null) throw error;
  }
}

void main() {
  // 电池优化豁免 tile 走裸 MethodChannel（未接 Pigeon），这里在 binary messenger
  // 层面直接 mock 原生桥接层（MethodBridge.kt CHANNEL_PLATFORM）的两个方法。
  const platformChannel = MethodChannel('com.clashmiao.app/platform');
  final platformCalls = <MethodCall>[];
  var batteryExempted = false;

  setUp(() {
    platformCalls.clear();
    batteryExempted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, (call) async {
          platformCalls.add(call);
          switch (call.method) {
            case 'is_ignoring_battery_optimizations':
              return batteryExempted;
            case 'request_ignore_battery_optimizations':
              batteryExempted = true;
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platformChannel, null);
  });

  group('SettingsPage smoke', () {
    testWidgets('页面整体渲染不崩 + 关键文字可见', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      // 顶部标题
      expect(find.text('设置'), findsOneWidget);
      // locale tile（zhCn）当前选择名
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.text('启用分析'), findsOneWidget);
      expect(find.text('自动检查连接的 IP'), findsOneWidget);
      // 设置首页不塞配置选项页入口，具体配置选项是独立页面。
      expect(find.text('全部配置选项'), findsNothing);
      expect(find.text('2080'), findsNothing);
      expect(find.text('https://1.1.1.1/dns-query'), findsNothing);
    });

    testWidgets('语言选择弹窗保持列表结构', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('语言'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('语言'), findsWidgets);
      expect(find.text('简体中文'), findsWidgets);
      expect(find.text('English'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints == const BoxConstraints(maxHeight: 720),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('主题选择弹窗显示图标选项', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('主题模式'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('主题模式'), findsWidgets);
      expect(find.byIcon(FluentIcons.settings_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.weather_sunny_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.weather_moon_24_regular), findsOneWidget);
      expect(
        find.byIcon(FluentIcons.checkmark_circle_24_filled),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Android 上显示每应用代理入口并可导航到该页面', (tester) async {
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('分应用线路'), findsOneWidget);

      await tester.tap(find.text('分应用线路'));
      await tester.pumpAndSettle();

      // PerAppProxyPage 的 _PinnedModesHeader 曾把 RadioListTile 包在带背景色的
      // DecoratedBox 里、缺一层 Material 包裹，构建时会触发框架的
      // "ListTile background color or ink splashes may be invisible" 断言。
      // 该缺陷已在 per_app_proxy_page.dart 中修复（改用 Material 承载背景色），
      // 这里断言零异常，防止回归。
      expect(tester.takeException(), isNull);

      expect(find.byType(PerAppProxyPage), findsOneWidget);
    });

    testWidgets('非 Android（默认）不显示每应用代理入口', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('分应用线路'), findsNothing);
    });

    testWidgets('Android 上显示电池优化豁免入口，初始查询未豁免状态', (tester) async {
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      expect(find.text('禁用电池优化'), findsOneWidget);
      expect(find.text('消除限制以获得最佳 VPN 性能'), findsOneWidget);
      expect(find.text('未豁免'), findsOneWidget);
      expect(
        platformCalls
            .where((c) => c.method == 'is_ignoring_battery_optimizations'),
        isNotEmpty,
      );
    });

    testWidgets('点击电池优化豁免入口触发系统请求并刷新为已豁免', (tester) async {
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      expect(find.text('未豁免'), findsOneWidget);

      await tester.tap(find.text('禁用电池优化'));
      await tester.pumpAndSettle();

      expect(
        platformCalls
            .where((c) => c.method == 'request_ignore_battery_optimizations'),
        hasLength(1),
      );
      expect(find.text('已豁免'), findsOneWidget);
      expect(find.text('未豁免'), findsNothing);
    });

    testWidgets('非 Android 不显示电池优化豁免入口', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('禁用电池优化'), findsNothing);
    });

    // 电池优化豁免状态徽标（已豁免/未豁免/…）曾经是硬编码中文字面量，跟
    // locale 无关——切到英文 locale 后其它文案都会跟着变、唯独这个徽标
    // 纹丝不动，还停在中文。这里钉住状态徽标必须跟随 locale 走 i18n。
    testWidgets(
      '英文 locale 下电池优化豁免状态徽标走 i18n（初始未豁免）',
      (tester) async {
        await tester.pumpWidget(
          await _host(debugIsAndroid: true, locale: 'en'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Disable Battery Optimization'), findsOneWidget);
        expect(find.text('Not Exempted'), findsOneWidget);
        expect(find.text('未豁免'), findsNothing);
      },
    );

    testWidgets(
      '英文 locale 下点击豁免入口后徽标刷新为 Exempted',
      (tester) async {
        await tester.pumpWidget(
          await _host(debugIsAndroid: true, locale: 'en'),
        );
        await tester.pumpAndSettle();

        expect(find.text('Not Exempted'), findsOneWidget);

        await tester.tap(find.text('Disable Battery Optimization'));
        await tester.pumpAndSettle();

        expect(find.text('Exempted'), findsOneWidget);
        expect(find.text('Not Exempted'), findsNothing);
        expect(find.text('已豁免'), findsNothing);
      },
    );

    testWidgets('iOS 上显示重置 VPN 配置文件入口', (tester) async {
      await tester.pumpWidget(await _host(debugIsIOS: true));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('重置 VPN 配置文件'), findsOneWidget);
    });

    testWidgets('非 iOS（默认）不显示重置 VPN 配置文件入口', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('重置 VPN 配置文件'), findsNothing);
    });

    testWidgets('点击重置 VPN 配置文件入口调用 boxService.resetTunnel()', (tester) async {
      final spy = _ResetTunnelSpyBoxService();
      await tester.pumpWidget(await _host(debugIsIOS: true, boxService: spy));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('重置 VPN 配置文件'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.resetTunnelCalls, 1);
    });

    testWidgets('重置 VPN 配置文件失败时展示错误提示，而不是静默吞掉', (tester) async {
      final spy = _ResetTunnelSpyBoxService()
        ..resetTunnelError = Exception('native reset failed');
      await tester.pumpWidget(await _host(debugIsIOS: true, boxService: spy));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('重置 VPN 配置文件'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.resetTunnelCalls, 1);
      expect(find.textContaining('native reset failed'), findsOneWidget);

      // 收尾：drain toast 的 auto-close timer。
      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });

    // 分析开关此前是私有的 _BoolPreferenceTile（强调色图标 + 单行样式），
    // onboarding_page.dart 是另一份私有的 _IntroSwitchTile（独立卡片样式）
    // ——两处控制同一个持久化偏好却各自维护一份 UI。现在两处都改用共享的
    // AnalyticsToggleTile（跟 onboarding_page_test.dart 的对应断言呼应，
    // 一起证明两个页面渲染的是同一个组件类型——同 TipCard 在
    // assets_page_test.dart / config_options_page_test.dart 里的验证方式）。
    testWidgets('分析开关用共享的 AnalyticsToggleTile 渲染', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AnalyticsToggleTile), findsOneWidget);
    });

    testWidgets('点击分析开关正确读写 clashmiao_analytics_enabled 偏好', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getBool('clashmiao_analytics_enabled'), isNull);

      await tester.tap(find.byType(AnalyticsToggleTile));
      await tester.pump();

      expect(prefs.getBool('clashmiao_analytics_enabled'), isTrue);

      await tester.tap(find.byType(AnalyticsToggleTile));
      await tester.pump();

      expect(prefs.getBool('clashmiao_analytics_enabled'), isFalse);
    });
  });
}
