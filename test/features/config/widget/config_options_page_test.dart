import 'dart:convert';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/config/widget/config_options_page.dart';
import 'package:clashmiao/shared/components/tip_card.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 可控行为的假 BoxService，只重写 generateWarpConfig（其余沿用
/// StubBoxService 的安全空实现），用于验证"生成 WARP 配置"按钮真的调用了
/// service 层而不是弹一个假 toast。
class _FakeWarpBoxService extends StubBoxService {
  _FakeWarpBoxService({this.response, this.error});

  final String? response;
  final Object? error;

  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async {
    if (error != null) throw error!;
    return response;
  }
}

Future<Widget> _host({Widget home = const ConfigOptionsPage()}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
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
        home: home,
      ),
    ),
  );
}

Future<void> _pumpPage(WidgetTester tester, {Widget? home}) async {
  await tester.pumpWidget(await _host(home: home ?? const ConfigOptionsPage()));
  await tester.pumpAndSettle();
}

/// 跟 `_host` 一样，但暴露 [ProviderContainer] 供测试读取/断言 provider 状态
/// （生成 WARP 配置的用例需要验证 networkSettingsProvider 是否真的被写入）。
Future<ProviderContainer> _containerWith(
  SharedPreferences prefs, {
  List<Override> extraOverrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      ...extraOverrides,
    ],
  );
  // networkSettingsProvider 依赖 sharedPreferencesProvider.requireValue，
  // 必须先等 FutureProvider resolve，不然 pump 页面时读取会抛异常
  // （跟 _host() 里的 await 是同一个理由）。
  await container.read(sharedPreferencesProvider.future);
  return container;
}

/// toastification 的 toast 自带一个真实 Timer 做自动关闭，`pumpAndSettle`
/// 不一定能把它排干——测试结束时框架会断言"没有 pending timer"。跟
/// `test/app/app_toast_test.dart` 的 `_drainToasts` 用法一致：往前推够长
/// 时间再强制关掉剩余 toast。
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

/// 打开 WARP 开关（先走同意弹窗），让 canChangeOptions 变 true，
/// 这样"生成 WARP 配置文件"那一项才是可点的。
Future<void> _enableWarp(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('启用 WARP'), 600);
  await tester.pumpAndSettle();
  await tester.tap(find.text('启用 WARP'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('同意'));
  await tester.pumpAndSettle();
}

void main() {
  group('ConfigOptionsPage smoke', () {
    testWidgets('渲染分组的配置选项列表', (
      tester,
    ) async {
      await _pumpPage(tester);

      // 顶部的实验性功能提示应该用共享的 TipCard 组件（跟 assets_page 用
      // 的是同一个组件，风格统一——见 tip_card_test.dart）。
      expect(find.byType(TipCard), findsOneWidget);

      expect(find.text('配置选项'), findsOneWidget);
      expect(find.text('路由选项'), findsOneWidget);
      expect(find.text('DNS 选项'), findsOneWidget);
      expect(find.text('入站选项'), findsOneWidget);
      expect(find.text('TLS 特性 (实验性选项)'), findsOneWidget);
      expect(find.text('日志级别'), findsOneWidget);
      expect(find.text('地区'), findsOneWidget);
      expect(find.text('阻止广告 (实验性选项)'), findsOneWidget);
      expect(find.text('绕过局域网 (实验性选项)'), findsOneWidget);
      expect(find.text('解析目标地址'), findsOneWidget);
      expect(find.text('IPv6 路由'), findsOneWidget);
      expect(find.text('远程 DNS 域名策略'), findsOneWidget);
      expect(find.text('直连 DNS'), findsOneWidget);
      expect(find.text('直连 DNS 域名策略'), findsOneWidget);
      expect(find.text('严格路由'), findsOneWidget);
      expect(find.text('TUN 实现'), findsOneWidget);
      expect(find.text('启用 TLS 数据分段'), findsOneWidget);
      expect(find.text('混合端口'), findsOneWidget);
      expect(find.text('2080'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('启用 WARP'), 600);
      await tester.pumpAndSettle();

      expect(find.text('WARP 选项 (实验性选项)'), findsOneWidget);
      expect(find.text('启用 WARP'), findsOneWidget);
      expect(find.text('生成 WARP 配置文件'), findsOneWidget);
      expect(find.text('链式线路'), findsOneWidget);
      expect(find.text('许可证密钥'), findsOneWidget);
      expect(find.text('清理 IP'), findsOneWidget);
      expect(find.text('噪音计数'), findsOneWidget);
    });

    testWidgets('service mode opens selection modal', (tester) async {
      await _pumpPage(tester);

      await tester.scrollUntilVisible(find.text('服务模式'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('服务模式'));
      await tester.pumpAndSettle();

      expect(find.text('系统线路'), findsWidgets);
      expect(find.text('VPN'), findsOneWidget);
    });

    testWidgets('value tile opens input modal', (tester) async {
      await _pumpPage(
        tester,
        home: const ConfigOptionsPage(debugOpenMixedPortInput: true),
      );

      expect(find.text('混合端口'), findsWidgets);
      expect(find.text('2080'), findsWidgets);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('url test interval opens slider modal', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        home: const ConfigOptionsPage(debugOpenUrlTestIntervalSlider: true),
      );

      expect(find.text('网址测试间隔'), findsWidgets);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('10 min'), findsWidgets);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('WARP enable opens consent modal', (
      tester,
    ) async {
      await _pumpPage(tester);

      await tester.scrollUntilVisible(find.text('启用 WARP'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('启用 WARP'));
      await tester.pumpAndSettle();

      expect(find.text('Cloudflare WARP 许可条款'), findsOneWidget);
      expect(
        find.textContaining('Cloudflare WARP 是一个免费的 WireGuard VPN 提供商'),
        findsOneWidget,
      );
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('同意'), findsOneWidget);
    });

    testWidgets('more button opens actions modal', (
      tester,
    ) async {
      await _pumpPage(tester);

      // flutter test 默认把 defaultTargetPlatform 判定为 android（见
      // adaptive_icon_test.dart 的说明），所以"更多"按钮渲染的是纵向三点
      // （more_vertical），而不是之前硬编码的横向三点。
      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      expect(find.text('更多选项'), findsOneWidget);
      expect(find.text('将匿名选项导出到剪贴板'), findsOneWidget);
      expect(find.text('导出备份'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(find.text('重置选项'), findsOneWidget);
    });

    // ===============================================================
    // "更多"按钮图标的平台适配（AdaptiveIcon）代表性验证之二：这里的
    // _PillButton 拿的是裸 IconData（resolveAdaptiveIcon(...)），跟
    // per_app_proxy_page_test.dart 里 Icon Widget 场景（AdaptiveIcon(...)）
    // 是两条不同的接入方式，一起构成"至少覆盖 1-2 个调用点"的代表性验证。
    //
    // 注意：拆成两个独立的 testWidgets（而不是一个测试里连续切换平台两次
    // pumpWidget）——原因见 per_app_proxy_page_test.dart 同名注释：对同一棵
    // 活的 element 树连续 pump 带 `const` 子部件的相同 widget 时，Flutter
    // 会因为“identical 就跳过重建”而读不到新的平台值。每个 testWidgets 之间
    // 树会被整个卸载重来，不受影响。
    // ===============================================================
    testWidgets('mock 平台为 iOS 时，更多按钮渲染横向三点', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await _pumpPage(tester);

      expect(find.byIcon(FluentIcons.more_horizontal_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('mock 平台为 Android 时，更多按钮渲染纵向三点', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pumpPage(tester);

      expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.more_horizontal_24_regular), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('生成 WARP 配置文件（真调用，不再是假 toast）', () {
    testWidgets('成功时显示成功 toast，且账号信息真的写入 network settings', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final fake = _FakeWarpBoxService(
        response: jsonEncode({
          'account-id': 'acc-real',
          'access-token': 'token-real',
          'config': {'private_key': 'pk'},
        }),
      );
      final container = await _containerWith(
        prefs,
        extraOverrides: [boxServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ConfigOptionsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enableWarp(tester);
      await tester.scrollUntilVisible(find.text('生成 WARP 配置文件'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成 WARP 配置文件'));
      await tester.pumpAndSettle();

      expect(find.textContaining('WARP 配置生成成功'), findsOneWidget);
      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, 'acc-real');
      expect(settings.warpAccessToken, 'token-real');
      expect(jsonDecode(settings.warpWireguardConfig), {'private_key': 'pk'});

      await _drainToasts(tester);
    });

    testWidgets('native 抛异常时显示失败 toast，且不写入账号字段', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final fake = _FakeWarpBoxService(
        error: Exception('warp registration failed: rate limited'),
      );
      final container = await _containerWith(
        prefs,
        extraOverrides: [boxServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ConfigOptionsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _enableWarp(tester);
      await tester.scrollUntilVisible(find.text('生成 WARP 配置文件'), 600);
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成 WARP 配置文件'));
      await tester.pumpAndSettle();

      expect(find.textContaining('WARP 配置生成失败'), findsOneWidget);
      final settings = container.read(networkSettingsProvider);
      expect(settings.warpAccountId, '');
      expect(settings.warpAccessToken, '');

      await _drainToasts(tester);
    });

    testWidgets('未开启 WARP / 未同意条款时该项不可点', (tester) async {
      await _pumpPage(tester);

      await tester.scrollUntilVisible(find.text('生成 WARP 配置文件'), 600);
      await tester.pumpAndSettle();

      final tile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('生成 WARP 配置文件'),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    });
  });

  group('从剪贴板导入选项（wave3 新增入口）', () {
    /// 给 Clipboard.getData 打桩，返回固定文本；测试结束后清掉 handler，
    /// 避免污染同一文件里其它测试的剪贴板行为。
    void mockClipboardText(WidgetTester tester, String? text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return text == null ? null : {'text': text};
          }
          if (call.method == 'Clipboard.setData') return null;
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
    }

    Future<void> openImportEntry(WidgetTester tester) async {
      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从剪贴板导入选项'));
      await tester.pumpAndSettle();
    }

    testWidgets('菜单里可见"从剪贴板导入选项"入口', (tester) async {
      await _pumpPage(tester);

      await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
      await tester.pumpAndSettle();

      expect(find.text('从剪贴板导入选项'), findsOneWidget);
    });

    testWidgets('确认后：剪贴板里的合法 JSON 被解析并写入 network settings，显示成功 toast', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = await _containerWith(prefs);
      addTearDown(container.dispose);

      mockClipboardText(
        tester,
        jsonEncode({'mtu': 1300, 'muxPadding': true}),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ConfigOptionsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openImportEntry(tester);
      // 确认弹窗：标题/正文来自 t.settings.importOptions / importOptionsMsg。
      expect(find.text('这将使用提供的值重写所有配置选项。您确定吗？'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final settings = container.read(networkSettingsProvider);
      expect(settings.mtu, 1300);
      expect(settings.muxPadding, isTrue);
      expect(find.textContaining('已导入'), findsOneWidget);

      await _drainToasts(tester);
    });

    testWidgets('剪贴板内容不是合法 JSON 时显示错误 toast，不改动设置', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = await _containerWith(prefs);
      addTearDown(container.dispose);

      mockClipboardText(tester, 'not even json {{{');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ConfigOptionsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openImportEntry(tester);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final settings = container.read(networkSettingsProvider);
      expect(settings.mtu, 9000); // 默认值，没被改动
      expect(find.textContaining('JSON 解析失败'), findsOneWidget);

      await _drainToasts(tester);
    });

    testWidgets('取消确认弹窗时不读剪贴板、不改动设置', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = await _containerWith(prefs);
      addTearDown(container.dispose);

      // 特意不打桩 Clipboard.getData（默认 handler 会返回 null）——
      // 如果取消后代码还是去读了剪贴板，至少不应该崩溃；主要断言是设置不变。

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              home: const ConfigOptionsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openImportEntry(tester);
      // 确认框的按钮标签直接来自 MaterialLocalizations（非 SettingsInputDialog
      // 那种自定义硬编码 'CANCEL'/'OK'），实测是 'Cancel'/'OK'（非全大写）。
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final settings = container.read(networkSettingsProvider);
      expect(settings.mtu, 9000);
    });
  });
}
