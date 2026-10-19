import 'dart:io';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<(Widget, ProviderContainer)> _host({
  Map<String, Object> initialPrefs = const {},
  bool viaRoute = false,
  bool disableAnimations = false,
  ThemeData? theme,
  String locale = 'zhCn',
  double textScale = 1.0,
  bool rtl = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': locale,
    'clashmiao_set_system_proxy': true,
    'clashmiao_enable_tun': false,
    ...initialPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);

  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme:
              theme ??
              ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
          builder: (context, child) => Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: disableAnimations,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
          ),
          home: viaRoute
              ? Scaffold(
                  body: Builder(
                    builder: (context) => Center(
                      child: ElevatedButton(
                        onPressed: () => QuickSettingsModal.show(context),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                )
              : const Scaffold(body: QuickSettingsModal()),
        ),
      ),
    ),
    container,
  );
}

void main() {
  group('QuickSettingsModal smoke', () {
    testWidgets('渲染快速设置面板', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('快速设置'), findsOneWidget);
      expect(find.text('仅线路'), findsOneWidget);
      // 服务模式档位按平台分：移动端是 仅线路/VPN，桌面端是 仅线路/系统线路
      // （桌面没有 TUN 驱动和权限，不提供 VPN 档，见 _quickServiceModeChoices）。
      if (Platform.isAndroid || Platform.isIOS) {
        expect(find.text('VPN'), findsOneWidget);
      } else {
        expect(find.text('系统线路'), findsOneWidget);
        expect(find.text('VPN'), findsNothing);
      }
      // 默认未授权 WARP：入口行是「设置 WARP」，不是开关。
      expect(find.text('设置 WARP'), findsOneWidget);
      expect(find.text('启用 TLS 数据分段'), findsOneWidget);
      expect(find.text('所有进阶选项'), findsOneWidget);
      expect(find.text('全局代理'), findsNothing);
      expect(find.text('智能分流'), findsNothing);
      expect(find.text('启用 DNS 路由'), findsNothing);
    });

    // 三个档位对应的是 setSystemProxy / enableTun 两个 bool 的组合，任意时刻
    // 只能有一个为 true。可选档位按平台不同（桌面没有 VPN 档），所以互斥性
    // 分两条路径验证，验的是同一条不变量。
    testWidgets('服务模式切换会保持系统线路和 VPN 互斥（移动端）', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('VPN'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isTrue);

      await tester.tap(find.text('仅线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);
    }, skip: !Platform.isAndroid && !Platform.isIOS);

    testWidgets('服务模式切换会保持仅线路和系统线路互斥（桌面端）', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('仅线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('系统线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(
        container.read(networkSettingsProvider).enableTun,
        isFalse,
        reason: '桌面端任何档位都不该把 enableTun 打开——没有驱动和权限支撑它',
      );
    }, skip: Platform.isAndroid || Platform.isIOS);

    testWidgets('TLS Fragment 开关写入网络设置', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(networkSettingsProvider).enableTlsFragment,
        isFalse,
      );

      await tester.tap(find.text('启用 TLS 数据分段'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
    });

    testWidgets('已有 WARP 授权时 WARP 开关写入网络设置', (tester) async {
      final (widget, container) = await _host(
        initialPrefs: {
          'clashmiao_warp_consent_given': true,
          'clashmiao_enable_warp': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).enableWarp, isFalse);

      await tester.tap(find.text('启用 WARP'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).enableWarp, isTrue);
    });

    testWidgets('WARP 未授权：显示「设置 WARP」与「未配置」，不出现开关', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('设置 WARP'), findsOneWidget);
      expect(find.text('未配置'), findsOneWidget);
      expect(find.text('启用 WARP'), findsNothing, reason: '未授权时不能假装有一个能开的开关');
      expect(find.byType(Switch), findsOneWidget, reason: '只有 TLS 分段那一个开关');
    });

    testWidgets('WARP 已授权：保持「启用 WARP」开关，没有「未配置」', (tester) async {
      final (widget, _) = await _host(
        initialPrefs: {'clashmiao_warp_consent_given': true},
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('启用 WARP'), findsOneWidget);
      expect(find.text('设置 WARP'), findsNothing);
      expect(find.text('未配置'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(2));
    });

    // 真机验收 BUG-4：升级后（两个开关都没动过，系统线路开关默认 true）移动端
    // 分段控件两段都不亮——当前值落在移动端没有的「系统线路」档上。
    testWidgets('移动端默认设置：VPN 档带选中底色与 selected 语义（升级后首次打开）', (tester) async {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      addTearDown(() => debugServiceModePlatformOverride = null);
      final handle = tester.ensureSemantics();
      final (widget, _) =
          await _host(); // set_system_proxy=true, enable_tun=false
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.getSemantics(find.text('VPN')),
        isSemantics(isSelected: true, isButton: true),
      );
      expect(
        tester.getSemantics(find.text('仅线路')),
        isSemantics(isSelected: false, hasSelectedState: true, isButton: true),
      );
      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('VPN'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, scheme.primaryContainer);
      handle.dispose();
    });

    // 不给假入口：iOS 的 Packet Tunnel 恒为 TUN，「仅线路」在 iOS 上什么也不
    // 改变，所以不出现；只展示 VPN 并说明边界。
    testWidgets('iOS：只有 VPN 一档、不是可点的按钮，并说明「iOS 仅支持 VPN 模式」', (tester) async {
      debugServiceModePlatformOverride = ServiceModePlatform.ios;
      addTearDown(() => debugServiceModePlatformOverride = null);
      final handle = tester.ensureSemantics();
      // 旧版本在 iOS 上点过「仅线路」留下的组合。
      final (widget, container) = await _host(
        initialPrefs: {
          'clashmiao_set_system_proxy': false,
          'clashmiao_enable_tun': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('仅线路'), findsNothing);
      expect(find.text('系统线路'), findsNothing);
      expect(find.text('iOS 仅支持 VPN 模式'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('VPN')),
        isSemantics(isSelected: true, hasSelectedState: true, isButton: false),
      );

      await tester.tap(find.text('VPN'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(networkSettingsProvider).enableTun,
        isFalse,
        reason: '只有一档时点击没有动作，不写设置',
      );
      handle.dispose();
    });

    testWidgets('Android：两档可选，没有 iOS 的边界说明', (tester) async {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      addTearDown(() => debugServiceModePlatformOverride = null);
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('仅线路'), findsOneWidget);
      expect(find.text('VPN'), findsOneWidget);
      expect(find.text('iOS 仅支持 VPN 模式'), findsNothing);
    });

    testWidgets('服务模式分段控件：选中项带 selected 语义并用 primaryContainer', (tester) async {
      final handle = tester.ensureSemantics();
      final (widget, _) = await _host(
        initialPrefs: {
          'clashmiao_set_system_proxy': false,
          'clashmiao_enable_tun': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      const selectedLabel = '仅线路';
      final unselectedLabel = (Platform.isAndroid || Platform.isIOS)
          ? 'VPN'
          : '系统线路';

      final selected = tester.getSemantics(find.text(selectedLabel));
      expect(selected, isSemantics(isSelected: true, isButton: true));
      final other = tester.getSemantics(find.text(unselectedLabel));
      expect(
        other,
        isSemantics(isSelected: false, hasSelectedState: true, isButton: true),
      );

      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      final selectedText = tester.widget<Text>(find.text(selectedLabel));
      expect(selectedText.style?.color, scheme.onPrimaryContainer);
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(selectedLabel),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).color, scheme.primaryContainer);
      handle.dispose();
    });

    testWidgets('减少动画：切换模式的下一帧就已是终态（选中语义与颜色）', (tester) async {
      final (widget, _) = await _host(
        disableAnimations: true,
        initialPrefs: {
          'clashmiao_set_system_proxy': false,
          'clashmiao_enable_tun': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));

      final other = (Platform.isAndroid || Platform.isIOS) ? 'VPN' : '系统线路';
      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;
      Color? fillOf(String label) {
        final box = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        return (box.decoration! as BoxDecoration).color;
      }

      expect(fillOf('仅线路'), scheme.primaryContainer);
      await tester.tap(find.text(other));
      await tester.pump(); // 只给一帧，不 settle
      await tester.pump();

      // 实际渲染出来的色块（不是 widget 上的目标值）：没有 200ms 插值。
      Color renderedFill(String label) {
        final decorated = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(AnimatedContainer),
                    )
                    .first,
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (decorated.decoration as BoxDecoration).color ??
            Colors.transparent;
      }

      expect(renderedFill(other), scheme.primaryContainer);
      expect(renderedFill('仅线路'), Colors.transparent);
      expect(
        tester.getSemantics(find.text(other)),
        isSemantics(isSelected: true, isButton: true),
      );
    });

    testWidgets('开启动画时同一操作的下一帧还在插值（对照，证明上面的断言有区分力）', (tester) async {
      final (widget, _) = await _host(
        initialPrefs: {
          'clashmiao_set_system_proxy': false,
          'clashmiao_enable_tun': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));
      final other = (Platform.isAndroid || Platform.isIOS) ? 'VPN' : '系统线路';
      final scheme = Theme.of(
        tester.element(find.byType(Scaffold)),
      ).colorScheme;

      await tester.tap(find.text(other));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find
                  .ancestor(
                    of: find.text(other),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (decorated.decoration as BoxDecoration).color,
        isNot(scheme.primaryContainer),
        reason: '200ms 过渡刚走一帧，不应已到终点',
      );
    });

    group('作为底部弹层路由', () {
      final darkTheme = ThemeData.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.dark],
      );

      testWidgets('实色表面、遮罩 black@0.40、24dp 顶角、系统拖拽柄，且没有模糊和内部入场动画', (
        tester,
      ) async {
        final (widget, _) = await _host(viaRoute: true, theme: darkTheme);
        await tester.pumpWidget(widget);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('快速设置'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_DragHandle',
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(QuickSettingsModal),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason: '半透明 + 模糊会让背景节点透进内容区',
        );
        expect(
          find.descendant(
            of: find.byType(QuickSettingsModal),
            matching: find.byType(Animate),
          ),
          findsNothing,
          reason: '路由动画之外不允许再有位移/淡入',
        );

        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor, const Color(0xFF1C1C22));
        final shape = sheet.shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(24)),
        );
        final barrier = tester.widget<ModalBarrier>(
          find.byType(ModalBarrier).last,
        );
        expect(barrier.color!.a, closeTo(0.40, 0.01));
        expect(barrier.color!.r, 0);
      });

      testWidgets('浅色主题使用 surfaceContainerLow', (tester) async {
        final (widget, _) = await _host(viaRoute: true);
        await tester.pumpWidget(widget);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final scheme = Theme.of(
          tester.element(find.byType(BottomSheet)),
        ).colorScheme;
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(sheet.backgroundColor, scheme.surfaceContainerLow);
      });

      testWidgets('只有路由这一次入场动画：250ms 到位，退出 200ms', (tester) async {
        final (widget, _) = await _host(viaRoute: true, theme: darkTheme);
        await tester.pumpWidget(widget);
        await tester.tap(find.text('open'));
        await tester.pump();
        // 路由动画结束时刻：位置已经是终点。旧版内容区还有最长 600ms 的横移。
        await tester.pump(const Duration(milliseconds: 250));
        final top250 = tester.getTopLeft(find.byType(BottomSheet)).dy;
        final left250 = tester.getTopLeft(find.text('快速设置')).dx;
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(BottomSheet)).dy, top250);
        expect(
          tester.getTopLeft(find.text('快速设置')).dx,
          left250,
          reason: '内容区不能在路由到位之后还在横移',
        );

        Navigator.of(tester.element(find.byType(QuickSettingsModal))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byType(QuickSettingsModal),
          findsNothing,
          reason: '退出 200ms 内完成',
        );
      });

      testWidgets('减少动画：弹出与关闭各只需一帧', (tester) async {
        final (widget, _) = await _host(
          viaRoute: true,
          theme: darkTheme,
          disableAnimations: true,
        );
        await tester.pumpWidget(widget);
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump();
        expect(find.text('快速设置'), findsOneWidget);
        final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(BottomSheet)).dy,
          top,
          reason: '没有位移动画：第二帧就已在终点',
        );

        Navigator.of(tester.element(find.byType(QuickSettingsModal))).pop();
        await tester.pump();
        await tester.pump();
        expect(find.byType(QuickSettingsModal), findsNothing);
      });
    });

    group('WARP 未授权行在窄屏/大字号/RTL 下换行而不溢出', () {
      const cases = <(String, String, String, bool)>[
        ('id', 'Siapkan WARP', 'Belum dikonfigurasi', false),
        ('ru', 'Настроить WARP', 'Не настроено', false),
        ('zhCn', '设置 WARP', '未配置', false),
        ('ar', 'إعداد WARP', 'غير مهيأ', true),
        ('id', 'Siapkan WARP', 'Belum dikonfigurasi', true),
      ];
      for (final scale in [1.3, 2.0]) {
        for (final (locale, title, status, rtl) in cases) {
          testWidgets('320dp / $scale× / $locale / ${rtl ? "RTL" : "LTR"}', (
            tester,
          ) async {
            tester.view.physicalSize = const Size(320, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            final (widget, _) = await _host(
              locale: locale,
              textScale: scale,
              rtl: rtl,
            );
            await tester.pumpWidget(widget);
            await tester.pump(const Duration(milliseconds: 50));

            expect(
              tester.takeException(),
              isNull,
              reason: '不能有 RenderFlex overflow',
            );
            // 完整文字都在，没有被省略号截断（用 Text 的 overflow 与渲染高度共同判断）。
            for (final label in [title, status]) {
              expect(find.text(label), findsOneWidget);
              final text = tester.widget<Text>(find.text(label));
              expect(text.overflow, isNot(TextOverflow.ellipsis));
            }
            final titleRect = tester.getRect(find.text(title));
            final statusRect = tester.getRect(find.text(status));
            // 行没有超出屏幕。
            for (final r in [titleRect, statusRect]) {
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(320));
            }
            // 标题与状态不重叠。
            expect(
              titleRect.overlaps(statusRect),
              isFalse,
              reason: '状态文字不能压在标题上',
            );
            // 行高不再固定 56：大字号下随内容增长，且整行包住两段文字。
            final tile = tester.getRect(
              find
                  .ancestor(
                    of: find.text(title),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            expect(tile.height, greaterThanOrEqualTo(56));
            expect(tile.top, lessThanOrEqualTo(titleRect.top));
            expect(tile.bottom, greaterThanOrEqualTo(statusRect.bottom));
          });
        }
      }

      testWidgets('宽屏 1.0× 时状态仍与标题同行（不无谓折行）', (tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final (widget, _) = await _host();
        await tester.pumpWidget(widget);
        await tester.pump(const Duration(milliseconds: 50));
        final t = tester.getRect(find.text('设置 WARP'));
        final s = tester.getRect(find.text('未配置'));
        expect((t.center.dy - s.center.dy).abs(), lessThan(4));
      });
    });

    // 桌面端仓库里不带 wintun 驱动，macOS 也没有网络扩展权限/特权 helper，
    // 选了 TUN 只会让内核起 tun 设备失败。给用户一个必定失败的选项，比不给
    // 这个选项糟糕得多。测试跑在 macOS 宿主上，正好覆盖桌面分支。
    testWidgets('桌面端不提供 TUN 服务模式（选了必定失败的选项不该出现）', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('仅线路'), findsWidgets, reason: '前置条件：服务模式选择器要真的渲染出来了');
      expect(find.text('系统线路'), findsWidgets, reason: '桌面端唯一真正能用的接管方式');
      expect(find.text('VPN'), findsNothing, reason: '桌面端没有 TUN 驱动/权限，不能给这个档位');
    }, skip: Platform.isAndroid || Platform.isIOS);
  });

  group('整行语义', () {
    testWidgets('开关行合并为一个节点：标题 + 开关状态 + 点击，不拆成多个焦点', (tester) async {
      final handle = tester.ensureSemantics();
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      final node = tester.getSemantics(find.text('启用 TLS 数据分段'));
      expect(
        node,
        isSemantics(
          label: '启用 TLS 数据分段',
          hasToggledState: true,
          isToggled: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      // 整行只有这一个焦点：同一行里没有另一个独立的开关节点。
      expect(find.byType(Switch), findsOneWidget);
      final switchNode = tester.getSemantics(find.byType(Switch));
      expect(switchNode.id, node.id, reason: '开关与标题是同一个语义节点');

      await tester.tap(find.text('启用 TLS 数据分段'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
      handle.dispose();
    });

    testWidgets('入口行读作按钮', (tester) async {
      final handle = tester.ensureSemantics();
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester.getSemantics(find.text('所有进阶选项')),
        isSemantics(label: '所有进阶选项', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });
}
