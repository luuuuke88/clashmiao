import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:clashmiao/shared/components/motion_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 整页加载占位（首页、订阅页整页与弹层）遵守系统「减少动画」：
///
/// - 数据 provider 一直 pending，页面停在加载占位上；
/// - 减少动画开着进入：占位是静态弧，**没有任何在跑的 ticker**；
/// - 运行途中打开减少动画：转圈立刻变静态弧，随后不再有动画帧；
/// - 两种情况下语义都是「进度未知的加载中」（恰好一个 loadingSpinner，没有
///   progressBar，没有 75% 之类的数值或 0–100 范围）。
///
/// 连接区（`_ConnectionInfo`、出口 IP 卡）不在本期范围，这里只看整页占位。

/// 永远不完成的 future：provider 停在 loading。
Future<T> _pending<T>() => Completer<T>().future;

typedef _Page = ({String name, Widget Function() build, List<Override> extra});

final _pages = <_Page>[
  (
    name: '首页（当前订阅加载中）',
    build: () => const HomePage(),
    extra: [
      activeProfileProvider.overrideWith((_) => _pending<ProfileEntity?>()),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  ),
  (
    name: '订阅页（列表加载中）',
    build: () => const ProfilesPage(),
    extra: [
      profileListProvider.overrideWith((_) => _pending<List<ProfileEntity>>()),
    ],
  ),
  (
    name: '订阅弹层（列表加载中）',
    build: () => const Scaffold(body: ProfilesPage(embedInSheet: true)),
    extra: [
      profileListProvider.overrideWith((_) => _pending<List<ProfileEntity>>()),
    ],
  ),
];

Future<(Widget, ValueNotifier<bool>)> _host(
  _Page page, {
  required bool reduced,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      ...page.extra,
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
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: child!,
            ),
            home: page.build(),
          ),
        ),
      ),
    ),
    disabled,
  );
}

CircularProgressIndicator _indicator(WidgetTester tester) =>
    tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(MotionProgress),
        matching: find.byType(CircularProgressIndicator),
      ),
    );

List<SemanticsData> _wholeTree(WidgetTester tester) {
  final all = <SemanticsData>[];
  void visit(SemanticsNode node) {
    all.add(node.getSemanticsData());
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return all;
}

void _expectUnknownProgressOnly(WidgetTester tester) {
  final all = _wholeTree(tester);
  expect(
    all.where((d) => d.role == SemanticsRole.progressBar),
    isEmpty,
    reason: '整页加载不能出现确定进度（progressBar）节点',
  );
  final spinners = all
      .where((d) => d.role == SemanticsRole.loadingSpinner)
      .toList();
  expect(spinners, hasLength(1), reason: '应当恰好一个「进度未知」的加载节点');
  final s = spinners.single;
  expect(s.value, anyOf(isNull, isEmpty), reason: '不能报出 75% 之类的数值');
  expect(s.minValue, anyOf(isNull, isEmpty));
  expect(s.maxValue, anyOf(isNull, isEmpty));
}

/// 弹层自己有 300 ms 入场淡入；ticker 从下一帧才开始计时，所以分两帧推进，
/// 让入场走完（转圈本身是无限循环，不能 pumpAndSettle）。
Future<void> _settleEntrance(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _drain(WidgetTester tester) async {
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  for (final page in _pages) {
    group(page.name, () {
      testWidgets('对照：正常模式下整页占位是不确定进度的转圈（持续有动画帧）', (tester) async {
        final (widget, _) = await _host(page, reduced: false);
        await tester.pumpWidget(widget);
        await _settleEntrance(tester);
        expect(find.byType(MotionProgress), findsOneWidget);
        expect(_indicator(tester).value, isNull);
        expect(tester.hasRunningAnimations, isTrue);
      });

      testWidgets('减少动画开着进入：静态弧、没有在跑的 ticker，语义是未知进度', (tester) async {
        final handle = tester.ensureSemantics();
        final (widget, _) = await _host(page, reduced: true);
        await tester.pumpWidget(widget);
        await _settleEntrance(tester);

        expect(find.byType(MotionProgress), findsOneWidget);
        expect(_indicator(tester).value, MotionProgress.staticArc);
        expect(tester.hasRunningAnimations, isFalse, reason: '不应再有动画帧');
        _expectUnknownProgressOnly(tester);

        await tester.pump(const Duration(seconds: 2));
        expect(tester.hasRunningAnimations, isFalse);
        handle.dispose();
        await _drain(tester);
      });

      testWidgets('运行途中打开减少动画：转圈立刻变静态弧并停下，语义始终是未知进度', (tester) async {
        final handle = tester.ensureSemantics();
        final (widget, disabled) = await _host(page, reduced: false);
        await tester.pumpWidget(widget);
        await _settleEntrance(tester);
        expect(_indicator(tester).value, isNull);
        expect(tester.hasRunningAnimations, isTrue);
        _expectUnknownProgressOnly(tester);

        disabled.value = true;
        await tester.pump();
        expect(_indicator(tester).value, MotionProgress.staticArc);
        _expectUnknownProgressOnly(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.hasRunningAnimations, isFalse, reason: '打开后不应再有动画帧');

        // 关掉后恢复转圈（不是卡死在静态弧）。
        disabled.value = false;
        await tester.pump();
        expect(_indicator(tester).value, isNull);
        _expectUnknownProgressOnly(tester);
        handle.dispose();
        await _drain(tester);
      });
    });
  }
}
