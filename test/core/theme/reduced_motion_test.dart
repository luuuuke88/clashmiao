import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 「减少动画」（`MediaQuery.disableAnimations`）在真实组件上的行为：入场动画
/// 直接停在终态、加载转圈改成静态弧；并且运行**途中**打开开关也立刻生效。

Future<(Widget, ValueNotifier<bool>)> _host(
  Widget Function(BuildContext) home, {
  required bool reduced,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  final disabled = ValueNotifier<bool>(reduced);
  addTearDown(disabled.dispose);
  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: ValueListenableBuilder<bool>(
          valueListenable: disabled,
          builder: (context, value, _) => MaterialApp(
            theme: ThemeData.light().copyWith(
              splashFactory: NoSplash.splashFactory,
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
            home: Builder(builder: home),
          ),
        ),
      ),
    ),
    disabled,
  );
}

Future<void> _openProfileDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  // 只等路由自己的转场走完；入场动画（延迟 200 ms + 时长 300 ms）另行断言。
  await tester.pump();
}

Widget _opener(BuildContext _) => Consumer(
  builder: (context, ref, _) => Center(
    child: ElevatedButton(
      onPressed: () => showProfileFormDialog(context, ref),
      child: const Text('open'),
    ),
  ),
);

/// 标题（「新的配置文件」）最近的 FadeTransition / SlideTransition：就是
/// `.fadeIn().slideX()` 这一层，不是路由的转场。
double _titleOpacity(WidgetTester tester) {
  final fade = find
      .ancestor(
        of: find.text('新的配置文件').first,
        matching: find.byType(FadeTransition),
      )
      .first;
  return tester.widget<FadeTransition>(fade).opacity.value;
}

Offset _titleSlide(WidgetTester tester) {
  final slide = find
      .ancestor(
        of: find.text('新的配置文件').first,
        matching: find.byType(SlideTransition),
      )
      .first;
  return tester.widget<SlideTransition>(slide).position.value;
}

void main() {
  group('入场动画（profile_form_dialog 的 fadeIn / slideX，带 delay）', () {
    testWidgets('对照：正常模式下延迟期内还没显示', (tester) async {
      final (widget, _) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await _openProfileDialog(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_titleOpacity(tester), lessThan(1), reason: '延迟 200 ms 内应仍是透明');
      await tester.pump(const Duration(milliseconds: 600));
      expect(_titleOpacity(tester), 1.0);
      expect(_titleSlide(tester), Offset.zero);
    });

    testWidgets('减少动画：打开后第一帧就是终态（不透明、无位移）', (tester) async {
      final (widget, _) = await _host(_opener, reduced: true);
      await tester.pumpWidget(widget);
      await _openProfileDialog(tester);
      expect(_titleOpacity(tester), 1.0);
      expect(_titleSlide(tester), Offset.zero);
      // 让 flutter_animate 内部的零延迟定时器跑完，免得留下 pending timer。
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('运行途中打开减少动画：立刻跳到终态并停止', (tester) async {
      final (widget, disabled) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await _openProfileDialog(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_titleOpacity(tester), lessThan(1));

      disabled.value = true;
      await tester.pump();
      expect(_titleOpacity(tester), 1.0);
      expect(_titleSlide(tester), Offset.zero);
      // 控制器已停止：再走时间也不会回退。
      await tester.pump(const Duration(milliseconds: 500));
      expect(_titleOpacity(tester), 1.0);
    });
  });

  group('GlassIconButton.loading', () {
    Widget loadingButton(BuildContext _) => Center(
      child: GlassIconButton(
        icon: FluentIcons.flash_24_regular,
        tooltip: '测速',
        loading: true,
        onTap: () {},
      ),
    );

    CircularProgressIndicator indicator(WidgetTester tester) =>
        tester.widget<CircularProgressIndicator>(
          find.descendant(
            of: find.byType(GlassIconButton),
            matching: find.byType(CircularProgressIndicator),
          ),
        );

    testWidgets('对照：正常模式是不确定进度的转圈（持续有动画帧）', (tester) async {
      final (widget, _) = await _host(loadingButton, reduced: false);
      await tester.pumpWidget(widget);
      expect(indicator(tester).value, isNull);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('减少动画：静态弧，没有任何在跑的动画', (tester) async {
      final (widget, _) = await _host(loadingButton, reduced: true);
      await tester.pumpWidget(widget);
      expect(indicator(tester).value, isNotNull);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('运行途中打开减少动画：转圈变静态弧；关掉后恢复转圈', (tester) async {
      final (widget, disabled) = await _host(loadingButton, reduced: false);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(indicator(tester).value, isNull);

      disabled.value = true;
      await tester.pump();
      expect(indicator(tester).value, isNotNull);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      disabled.value = false;
      await tester.pump();
      expect(indicator(tester).value, isNull);
    });
  });
}
