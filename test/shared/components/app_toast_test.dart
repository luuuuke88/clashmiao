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
}
