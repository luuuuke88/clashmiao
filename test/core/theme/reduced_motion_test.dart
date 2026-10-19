import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:clashmiao/shared/components/motion_progress.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 「减少动画」（`MediaQuery.disableAnimations`）在真实组件上的行为：入场动画
/// 直接停在终态、加载转圈改成静态弧；并且运行**途中**打开开关也立刻生效。

/// 键盘高度（viewInsets.bottom），测试里按需改它来模拟键盘弹出 / 收起。
final _inset = ValueNotifier<double>(0);

/// 记录路由事件，用来确认「原弹窗确实被关闭 / 手动表单确实被打开」。
class _Routes extends NavigatorObserver {
  final events = <String>[];
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    events.add('push ${route.runtimeType}');
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('pop ${route.runtimeType}');
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('remove ${route.runtimeType}');
}

final _routes = _Routes();

Future<(Widget, ValueNotifier<bool>)> _host(
  Widget Function(BuildContext) home, {
  required bool reduced,
}) async {
  _inset.value = 0;
  _routes.events.clear();
  _routes.pushed.clear();
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
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: _inset,
              builder: (context, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: value,
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: child!,
              ),
            ),
            navigatorObservers: [_routes],
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

  group('关闭「减少动画」不重播已经显示完的入场', () {
    testWidgets('已完成的入场：开→关全程停在终态，不回到透明', (tester) async {
      final (widget, disabled) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await _openProfileDialog(tester);
      // 分两段走：先越过延迟，再走完时长（单次大步长时控制器还没起跑）。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_titleOpacity(tester), 1.0);

      disabled.value = true;
      await tester.pump();
      expect(_titleOpacity(tester), 1.0);

      disabled.value = false;
      await tester.pump();
      expect(_titleOpacity(tester), 1.0, reason: '关闭后不应回到透明重播');
      expect(_titleSlide(tester), Offset.zero);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_titleOpacity(tester), 1.0);
      await tester.pump(const Duration(seconds: 1));
      expect(_titleOpacity(tester), 1.0);
    });

    testWidgets('减少动画下挂载的内容：关掉后留在终态；只有之后新挂载的才播放入场', (tester) async {
      final showSecond = ValueNotifier<bool>(false);
      addTearDown(showSecond.dispose);
      final (widget, disabled) = await _host(
        (context) => ValueListenableBuilder<bool>(
          valueListenable: showSecond,
          builder: (context, second, _) => Column(
            children: [
              const Text('first')
                  .animateWithMotion(context)
                  .fadeIn(duration: 300.ms, delay: 200.ms),
              if (second)
                const Text('second')
                    .animateWithMotion(context)
                    .fadeIn(duration: 300.ms, delay: 200.ms),
            ],
          ),
        ),
        reduced: true,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 50));
      double opacityOf(String text) => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text(text),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacityOf('first'), 1.0);

      disabled.value = false;
      await tester.pump();
      expect(opacityOf('first'), 1.0, reason: '减少动画下已显示的内容不重播');
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf('first'), 1.0);

      // 关掉之后新挂载的：照常入场（延迟内仍透明，走完变不透明）。
      showSecond.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacityOf('second'), lessThan(1));
      expect(opacityOf('first'), 1.0);
      await tester.pump(const Duration(seconds: 1));
      expect(opacityOf('second'), 1.0);
    });
  });

  group('添加订阅 → 手动输入', () {
    List<ModalBottomSheetRoute<Object?>> sheets() =>
        _routes.pushed.whereType<ModalBottomSheetRoute<Object?>>().toList();

    Future<void> openManual(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手动输入'));
      await tester.pumpAndSettle();
    }

    testWidgets('原弹窗自然退出（不叠两层），手动表单由调用方页面打开', (tester) async {
      final (widget, _) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await openManual(tester);

      expect(sheets(), hasLength(2), reason: '一共推过两张弹窗：添加弹窗 + 手动表单');
      expect(sheets().first.isActive, isFalse, reason: '添加弹窗已正常退出，没有被叠在手动表单底下');
      expect(sheets().last.isActive, isTrue);
      expect(_routes.events, contains(startsWith('pop ModalBottomSheetRoute')));
      // 画面上只剩手动表单。
      expect(find.text('从剪贴板添加'), findsNothing);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭手动表单回到调用方页面，而不是添加弹窗', (tester) async {
      final (widget, _) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await openManual(tester);

      // 点遮罩关闭手动表单（弹层顶部的空白处）。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('从剪贴板添加'), findsNothing, reason: '不应退回添加弹窗');
      expect(find.text('open'), findsOneWidget, reason: '回到了调用方页面');
      expect(sheets().where((r) => r.isActive), isEmpty);
      expect(sheets(), hasLength(2), reason: '没有再多开任何弹窗');
    });

    testWidgets('添加弹窗销毁后：键盘高度变化 + 切换减少动画（含往返）不抛异常', (tester) async {
      final (widget, disabled) = await _host(_opener, reduced: false);
      await tester.pumpWidget(widget);
      await openManual(tester);
      expect(find.text('从剪贴板添加'), findsNothing, reason: '前置：添加弹窗已销毁');
      expect(find.byType(TextField), findsWidgets, reason: '手动表单已打开');

      // 键盘弹出 / 收起、减少动画开 / 关 / 再开：手动表单的重建都不能去读
      // 已销毁弹窗的 context。
      _inset.value = 300;
      await tester.pump();
      disabled.value = true;
      await tester.pump();
      _inset.value = 0;
      await tester.pump();
      disabled.value = false;
      await tester.pump();
      _inset.value = 280;
      disabled.value = true;
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('MotionProgress 语义始终是「进度未知的加载中」', () {
    Widget progress(BuildContext _) => const Center(
      child: SizedBox(width: 20, height: 20, child: MotionProgress()),
    );

    /// 整棵语义树（从根节点起）里所有节点的语义数据。
    List<SemanticsData> wholeTree(WidgetTester tester) {
      final all = <SemanticsData>[];
      void visit(SemanticsNode node) {
        all.add(node.getSemanticsData());
        node.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      return all;
    }

    /// 断言整棵树：没有任何 progressBar 节点；没有任何节点带数值或范围；恰有
    /// 一个 loadingSpinner（进度未知的加载中）。
    void expectUnknownProgressOnly(WidgetTester tester) {
      final all = wholeTree(tester);
      expect(
        all.where((d) => d.role == SemanticsRole.progressBar),
        isEmpty,
        reason: '不能出现确定进度（progressBar）节点',
      );
      for (final d in all) {
        expect(d.value, anyOf(isNull, isEmpty), reason: '不能报出 75% 之类的数值');
        expect(d.minValue, anyOf(isNull, isEmpty), reason: '不能有 0–100 范围');
        expect(d.maxValue, anyOf(isNull, isEmpty), reason: '不能有 0–100 范围');
      }
      expect(
        all.where((d) => d.role == SemanticsRole.loadingSpinner),
        hasLength(1),
        reason: '应当有且仅有一个「进度未知」的加载节点',
      );
    }

    for (final reduced in [false, true]) {
      testWidgets('${reduced ? "减少动画（静态弧）" : "正常（转圈）"}：整棵语义树只有未知进度的加载节点', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final (widget, _) = await _host(progress, reduced: reduced);
        await tester.pumpWidget(widget);
        expectUnknownProgressOnly(tester);
        handle.dispose();
      });
    }

    testWidgets('运行中来回切换减少动画：每一步整棵语义树都只有未知进度', (tester) async {
      final handle = tester.ensureSemantics();
      final (widget, disabled) = await _host(progress, reduced: false);
      await tester.pumpWidget(widget);
      expectUnknownProgressOnly(tester);
      disabled.value = true;
      await tester.pump();
      expectUnknownProgressOnly(tester);
      disabled.value = false;
      await tester.pump();
      expectUnknownProgressOnly(tester);
      handle.dispose();
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
