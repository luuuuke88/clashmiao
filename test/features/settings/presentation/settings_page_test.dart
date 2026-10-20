import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/settings/presentation/per_app_proxy_page.dart';
import 'package:clashmiao/features/settings/presentation/settings_page.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/toast_pump.dart';

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
      boxServiceProvider.overrideWithValue(
        boxService ?? const StubBoxService(),
      ),
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

/// 设置页分了三组、多了组标题，Android 上整页比默认 800x600 的测试视口高；
/// 需要点到下面几行的用例先把视口拉高，免得目标行被懒加载在视口外。
void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

  group('SettingsPage 分组与结构', () {
    testWidgets('渲染 通用 / 连接 / 隐私 三组标题，且按此顺序自上而下', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      final general = find.text('通用');
      final connection = find.text('连接');
      final privacy = find.text('隐私');
      expect(general, findsOneWidget);
      expect(connection, findsOneWidget);
      expect(privacy, findsOneWidget);

      final generalY = tester.getTopLeft(general).dy;
      final connectionY = tester.getTopLeft(connection).dy;
      final privacyY = tester.getTopLeft(privacy).dy;
      expect(generalY, lessThan(connectionY));
      expect(connectionY, lessThan(privacyY));

      // 组标题是 header 语义，读屏可以按标题跳组。
      for (final title in ['通用', '连接', '隐私']) {
        expect(
          tester.getSemantics(find.text(title)),
          matchesSemantics(label: title, isHeader: true),
        );
      }
    });

    testWidgets('各行落在规定的组里', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      final connection = y('连接');
      final privacy = y('隐私');

      // 通用：语言、主题、触觉反馈
      for (final label in ['语言', '主题模式', '触觉反馈']) {
        expect(y(label), lessThan(connection), reason: '$label 应在「通用」组');
      }
      // 连接：自动检查 IP、通知栏网速、电池优化、分应用代理
      for (final label in ['自动检查连接的 IP', '在通知中显示网络速度', '禁用电池优化', '分应用线路']) {
        expect(y(label), greaterThan(connection), reason: '$label 应在「连接」组');
        expect(y(label), lessThan(privacy), reason: '$label 应在「连接」组');
      }
      // 隐私：启用分析
      expect(y('启用分析'), greaterThan(privacy));
    });

    testWidgets('标题到卡片 8 dp，组与组之间 24 dp', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      final cards = find.byType(GlassCard);
      expect(cards, findsNWidgets(3));
      final firstCardTop = tester.getTopLeft(cards.at(0)).dy;
      final firstCardBottom = tester.getBottomLeft(cards.at(0)).dy;
      final secondCardTop = tester.getTopLeft(cards.at(1)).dy;

      // 标题文字底到卡片顶：标题行高度随字体而定，这里只断言间距由 8 dp 的
      // SizedBox 贡献——标题 Text 的下边缘与卡片顶边相差 8。
      final titleBottom = tester.getBottomLeft(find.text('通用')).dy;
      expect(firstCardTop - titleBottom, 8);

      // 第一张卡片底到第二组标题顶：24 dp。
      final connectionTop = tester.getTopLeft(find.text('连接')).dy;
      expect(connectionTop - firstCardBottom, 24);
      expect(secondCardTop, greaterThan(connectionTop));
    });

    testWidgets('页头没有问号按钮（它从来没有 onTap，是假入口）', (tester) async {
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(FluentIcons.question_circle_24_regular), findsNothing);
      expect(find.byType(GlassIconButton), findsNothing);
    });

    testWidgets('每一行高度不低于 56，长文案换行后会长高而不是溢出', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true, locale: 'en'));
      await tester.pumpAndSettle();

      for (final inkWell in tester.widgetList<InkWell>(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byType(InkWell),
        ),
      )) {
        expect(inkWell.onTap, isNotNull);
      }
      for (final element
          in find
              .descendant(
                of: find.byType(GlassCard),
                matching: find.byType(InkWell),
              )
              .evaluate()) {
        final height = (element.renderObject! as RenderBox).size.height;
        expect(height, greaterThanOrEqualTo(56));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('图标不再是彩虹色：全部使用同一个中性色', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      final colors = tester
          .widgetList<Icon>(
            find.descendant(
              of: find.byType(GlassCard),
              matching: find.byType(Icon),
            ),
          )
          .map((i) => i.color)
          .toSet();
      expect(colors, hasLength(1), reason: '设置页图标颜色应收敛为一个中性色');
    });

    // 开关行：整行一个语义节点（标题 + 开关状态 + 单一操作），开关自身仍
    // 保持 48 dp 点击目标。曾经 shrinkWrap 把开关缩到 40 dp，且 InkWell 与
    // Switch 各自带一个可点节点。
    testWidgets('开关行合并成单一语义节点，开关点击目标不小于 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      // 数「带点击操作的语义节点」。被合并进父节点的子节点只是父节点数据的
      // 一部分（mergedIntoParent），不另计——读屏看到的是合并后的那一个。
      int tapNodes(SemanticsNode node) {
        if (node.isMergedIntoParent) return 0;
        var count = node.getSemanticsData().hasAction(SemanticsAction.tap)
            ? 1
            : 0;
        node.visitChildren((child) {
          count += tapNodes(child);
          return true;
        });
        return count;
      }

      // 标题 + 开关状态 + 点击操作在同一个节点上
      final analytics = tester.getSemantics(find.byType(AnalyticsToggleTile));
      expect(
        analytics,
        isSemantics(
          label: '启用分析',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      expect(tapNodes(analytics), 1, reason: '整行只应有一个可点节点');

      // 设置页自己的开关行（触觉反馈）同理。
      final haptic = tester.getSemantics(
        find.ancestor(
          of: find.text('触觉反馈'),
          matching: find.byType(MergeSemantics),
        ),
      );
      expect(
        haptic,
        isSemantics(label: '触觉反馈', hasToggledState: true, hasTapAction: true),
      );
      expect(tapNodes(haptic), 1);

      // 开关控件本身没被缩小。
      for (final size
          in tester
              .widgetList(find.byType(Switch))
              .map((w) => tester.getSize(find.byWidget(w)))) {
        expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      }
      handle.dispose();
    });

    testWidgets('整页通过 Android 点按目标与标签无障碍规范', (tester) async {
      final handle = tester.ensureSemantics();
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('文字放大 $scale 倍、窄屏 320 dp 不溢出且可滚动到底', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          await _host(debugIsAndroid: true, locale: 'ptBr'),
        );
        await tester.pumpAndSettle();

        // 一路滚到最后一组，沿途每一行都会被布局一遍——溢出会在这里抛出。
        await tester.scrollUntilVisible(
          find.text('Privacidade'),
          300,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 200,
        );
        await tester.pumpAndSettle();

        expect(find.text('Privacidade'), findsOneWidget);
        expect(find.text('Habilitar Análise'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
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
      _useTallView(tester);
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
        platformCalls.where(
          (c) => c.method == 'is_ignoring_battery_optimizations',
        ),
        isNotEmpty,
      );
    });

    testWidgets('点击电池优化豁免入口触发系统请求并刷新为已豁免', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true));
      await tester.pumpAndSettle();

      expect(find.text('未豁免'), findsOneWidget);

      await tester.tap(find.text('禁用电池优化'));
      await tester.pumpAndSettle();

      expect(
        platformCalls.where(
          (c) => c.method == 'request_ignore_battery_optimizations',
        ),
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
    testWidgets('英文 locale 下电池优化豁免状态徽标走 i18n（初始未豁免）', (tester) async {
      await tester.pumpWidget(await _host(debugIsAndroid: true, locale: 'en'));
      await tester.pumpAndSettle();

      expect(find.text('Disable Battery Optimization'), findsOneWidget);
      expect(find.text('Not Exempted'), findsOneWidget);
      expect(find.text('未豁免'), findsNothing);
    });

    testWidgets('英文 locale 下点击豁免入口后徽标刷新为 Exempted', (tester) async {
      _useTallView(tester);
      await tester.pumpWidget(await _host(debugIsAndroid: true, locale: 'en'));
      await tester.pumpAndSettle();

      expect(find.text('Not Exempted'), findsOneWidget);

      await tester.tap(find.text('Disable Battery Optimization'));
      await tester.pumpAndSettle();

      expect(find.text('Exempted'), findsOneWidget);
      expect(find.text('Not Exempted'), findsNothing);
      expect(find.text('已豁免'), findsNothing);
    });

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

    testWidgets('点击重置 VPN 配置文件入口调用 boxService.resetTunnel() 并提示成功', (
      tester,
    ) async {
      final spy = _ResetTunnelSpyBoxService();
      await tester.pumpWidget(await _host(debugIsIOS: true, boxService: spy));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('重置 VPN 配置文件'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.resetTunnelCalls, 1);
      // 成功也必须给反馈：重置是瞬时的，页面上没有任何可见状态跟着变，
      // 只在失败时提示的话，用户点完看到的就是"什么都没发生"，无法区分
      // "成功了"和"这个按钮是坏的"。
      expect(find.text('VPN 配置文件已重置'), findsOneWidget);

      // 收尾：drain toast 的 auto-close timer，否则会污染后面的用例。
      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('重置 VPN 配置文件失败时展示错误提示，而不是静默吞掉', (tester) async {
      final spy = _ResetTunnelSpyBoxService()
        ..resetTunnelError = Exception('native reset failed');
      await tester.pumpWidget(await _host(debugIsIOS: true, boxService: spy));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('重置 VPN 配置文件'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.resetTunnelCalls, 1);
      // 提示是本地化文案，技术细节（异常原文）只进日志、不展示给用户。
      expect(find.text('意外错误'), findsOneWidget);
      expect(find.textContaining('native reset failed'), findsNothing);

      // 收尾：drain toast 的 auto-close timer。
      await tester.pump(const Duration(seconds: 6));
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 500));
    });

    // 分析开关通过共享 AnalyticsToggleTile 渲染，避免设置页重复维护开关 UI。
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
