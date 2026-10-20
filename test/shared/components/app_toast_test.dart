import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

/// 让 AppToast 显示时，屏幕底部控件应继续可点。
Widget _host() {
  int selectedIndex = 0;

  return ToastificationWrapper(
    config: ToastificationConfig(
      itemWidth: 288, // 测试中只验证点击可达性，不关心视觉尺寸。
      marginBuilder: (context, alignment) {
        if (alignment.resolve(Directionality.of(context)).y >= 0.5) {
          final safeBottom = MediaQuery.of(context).padding.bottom;
          return EdgeInsets.only(left: 16, right: 16, bottom: safeBottom + 88);
        }
        if (alignment.resolve(Directionality.of(context)).y <= -0.5) {
          return const EdgeInsets.only(top: 12);
        }
        return EdgeInsets.zero;
      },
      applyMediaQueryViewInsets: true,
    ),
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            body: Stack(
              children: [
                Center(child: Text('selected=$selectedIndex')),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      key: const ValueKey('bottom-nav'),
                      children: List.generate(4, (index) {
                        return Expanded(
                          child: GestureDetector(
                            key: ValueKey('bottom_nav_$index'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() => selectedIndex = index);
                            },
                            child: Center(child: Text('Tab$index')),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 160,
                  child: Center(
                    child: TextButton(
                      key: const ValueKey('show-toast'),
                      onPressed: () {
                        AppToast.info(context, '测速中，请稍候...');
                      },
                      child: const Text('toast'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('toast 出现时底部按钮仍可点击', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('show-toast')));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getCenter(find.text('测速中，请稍候...')).dy,
      greaterThan(screenHeight - 220),
    );

    await tester.tap(find.byKey(const ValueKey('bottom_nav_3')));
    await tester.pumpAndSettle();

    expect(find.text('selected=3'), findsOneWidget);
    await _drainToasts(tester);
  });

  group('toast 外观', () {
    Future<void> showToast(
      WidgetTester tester, {
      required ThemeData theme,
      required void Function(BuildContext) show,
    }) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('show'),
                    onPressed: () => show(context),
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('show')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }

    BoxDecoration toastDecoration(WidgetTester tester, String message) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(message), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    for (final brightness in Brightness.values) {
      testWidgets('底色不透明，卡片上的字不会透出来（$brightness）', (tester) async {
        AppToast.resetForTest();
        final theme =
            (brightness == Brightness.light
                    ? ThemeData.light()
                    : ThemeData.dark())
                .copyWith(
                  extensions: <ThemeExtension<dynamic>>[
                    brightness == Brightness.light
                        ? AiUiTheme.light
                        : AiUiTheme.dark,
                  ],
                );
        await showToast(
          tester,
          theme: theme,
          show: (context) => AppToast.success(context, '配置文件更新成功'),
        );

        final color = toastDecoration(tester, '配置文件更新成功').color!;
        expect(color.a, 1.0, reason: '半透明底会让下面卡片的文字透出来');
        expect(color, AppToast.surfaceColor(theme));
        await _drainToasts(tester);
      });
    }

    testWidgets('状态图标走 StatusColors，不再是不分明暗的原色', (tester) async {
      AppToast.resetForTest();
      final theme = ThemeData.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.dark],
      );
      await showToast(
        tester,
        theme: theme,
        show: (context) => AppToast.error(context, '失败了'),
      );
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(
            of: find.text('失败了'),
            matching: find.byType(Container),
          ),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, StatusColors.latencyTimeout(Brightness.dark));
      await _drainToasts(tester);
    });
  });

  group('toast 入退场走 Motion', () {
    // 实际起作用的是 AppToast.show 每次传给 showCustom 的 animationDuration /
    // animationBuilder：toastification 的 manager 是进程级单例、按对齐方式缓存，
    // 只认第一次见到的全局配置，之后「减少动画」开关变了它也不会更新。全局配置
    // （appToastConfig）只是兜底，下面单独断言它的取值。
    Future<void> host(
      WidgetTester tester, {
      required bool reduced,
      required bool viaGlobalConfig,
      required void Function(BuildContext) show,
    }) async {
      AppToast.resetForTest();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Builder(
            builder: (outer) => ToastificationWrapper(
              config: viaGlobalConfig ? appToastConfig(outer) : null,
              child: MaterialApp(
                theme: ThemeData.light().copyWith(
                  extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      key: const ValueKey('show'),
                      onPressed: () => show(context),
                      child: const Text('go'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('show')));
    }

    /// toast 文本以上所有 FadeTransition 的不透明度之积。
    double opacityOf(WidgetTester tester, String text) {
      var o = 1.0;
      for (final e
          in find
              .ancestor(
                of: find.text(text),
                matching: find.byType(FadeTransition),
              )
              .evaluate()) {
        o *= (e.widget as FadeTransition).opacity.value;
      }
      return o;
    }

    void showViaAppToast(BuildContext context) =>
        AppToast.info(context, '转场测试');
    final paths = <String, (void Function(BuildContext), bool)>{
      'AppToast.show': (showViaAppToast, false),
    };

    for (final entry in paths.entries) {
      testWidgets('${entry.key}：入场用 Motion.medium，不是库默认的 600 ms', (
        tester,
      ) async {
        await host(
          tester,
          reduced: false,
          viaGlobalConfig: entry.value.$2,
          show: entry.value.$1,
        );
        await tester.pump(); // 插入
        // 库在插入后要隔几帧才真正开始走动画：一帧一帧等到不再是 0。
        var frames = 0;
        while ((find.text('转场测试').evaluate().isEmpty ||
                opacityOf(tester, '转场测试') == 0) &&
            frames++ < 60) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final started = opacityOf(tester, '转场测试');
        expect(started, greaterThan(0));
        expect(started, lessThan(1), reason: '入场中途应是半透明');

        await tester.pump(Motion.medium);
        expect(opacityOf(tester, '转场测试'), 1, reason: '库默认 600 ms 在这里还没走完');
        await _drainToasts(tester);
      });

      testWidgets('${entry.key}：退场用 Motion.medium 内收尾', (tester) async {
        await host(
          tester,
          reduced: false,
          viaGlobalConfig: entry.value.$2,
          show: entry.value.$1,
        );
        await tester.pump();
        await tester.pump(Motion.medium);
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump();
        await tester.pump(Motion.medium + const Duration(milliseconds: 20));
        expect(find.text('转场测试'), findsNothing);
        await _drainToasts(tester);
      });

      testWidgets('${entry.key}：减少动画时入场当帧就是终态、退场立即消失', (tester) async {
        await host(
          tester,
          reduced: true,
          viaGlobalConfig: entry.value.$2,
          show: entry.value.$1,
        );
        await tester.pump(); // 插入这一帧
        await tester.pump(const Duration(milliseconds: 1));
        expect(opacityOf(tester, '转场测试'), 1);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 10));
        expect(find.text('转场测试'), findsNothing);
        await _drainToasts(tester);
      });
    }

    testWidgets('全局配置兜底：时长走 Motion，动画用 AppToast 的转场', (tester) async {
      late ToastificationConfig normal;
      late ToastificationConfig reducedCfg;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              normal = appToastConfig(context);
              return MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Builder(
                  builder: (context) {
                    reducedCfg = appToastConfig(context);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(normal.animationDuration, Motion.medium);
      expect(reducedCfg.animationDuration, Duration.zero);
      expect(normal.animationBuilder, AppToast.animationBuilder);
      expect(reducedCfg.animationBuilder, AppToast.animationBuilder);
    });
  });
}
