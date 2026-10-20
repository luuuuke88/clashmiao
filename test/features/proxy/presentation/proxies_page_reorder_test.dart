import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/fake_box_service.dart';
import '../../../support/fake_connection_controller.dart';

// 按延迟排序的线路页在测速结果陆续回来时会重排。真机实测：手指按下时指着
// 香港01，抬起前列表重排，选中的却是挪到同一位置的德国。这里锁住两件事：
// - 手指按着、或测速进行中时行顺序冻结，结束后才重排；
// - 一次点击作用于按下时手指下的那个节点，绝不是之后挪过来的节点。

const _profile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

class _Box extends FakeBoxService {
  final List<String> urlTests = [];

  /// 测速调用的内核结果；默认立即成功。测试可以换成会失败 / 不返回的。
  Future<void> Function() onUrlTest = () async {};

  @override
  Future<void> urlTest(String groupTag) {
    urlTests.add(groupTag);
    return onUrlTest();
  }

  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

class _Port extends FakeKernelPort {
  final List<String> selected = [];

  @override
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    selected.add(outboundTag);
    return const SelectOk();
  }
}

OutboundGroup _group(Map<String, int> delays) => OutboundGroup(
  tag: 'select',
  type: 'selector',
  selected: 'auto',
  items: [
    const OutboundProxy(tag: 'auto', type: 'urltest'),
    for (final e in delays.entries)
      OutboundProxy(tag: e.key, type: 'vless', delay: e.value),
  ],
);

class _Rig {
  _Rig(this.widget, this.container, this.port, this.box, this.groups);

  final Widget widget;
  final ProviderContainer container;
  final _Port port;
  final _Box box;
  final StreamController<List<OutboundGroup>> groups;

  void setConnected(bool value) =>
      container.read(_connected.notifier).state = value;

  void switchProfile(ProfileEntity profile) =>
      container.read(_activeProfile.notifier).state = profile;
}

final _connected = StateProvider<bool>((_) => true);
final _activeProfile = StateProvider<ProfileEntity>((_) => _profile);

Future<_Rig> _rig(Map<String, int> delays) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final port = _Port();
  final box = _Box();
  // 由 [_teardown] 关闭。
  // ignore: close_sinks
  final groups = StreamController<List<OutboundGroup>>.broadcast();
  final initial = [_group(delays)];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith(
        (ref) async => ref.watch(_activeProfile),
      ),
      boxServiceProvider.overrideWithValue(box),
      kernelPortProvider.overrideWithValue(port),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      // 离线分组解析自订阅配置，不带延迟。
      offlineProxyGroupsProvider.overrideWith(
        (_) async => [
          _group({for (final tag in delays.keys) tag: 0}),
        ],
      ),
      outboundGroupsProvider.overrideWith((ref) async* {
        yield initial;
        yield* groups.stream;
      }),
      isConnectedProvider.overrideWith((ref) => ref.watch(_connected)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  await container
      .read(proxiesSortProvider.notifier)
      .updateSort(ProxiesSort.delay);
  return _Rig(
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const ProxiesPage(),
        ),
      ),
    ),
    container,
    port,
    box,
    groups,
  );
}

/// 节点行从上到下的顺序（按名称文字的纵坐标）。
List<String> _order(WidgetTester tester, List<String> tags) {
  final ys = {for (final t in tags) t: tester.getCenter(find.text(t)).dy};
  return [...tags]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

/// 逐帧推进 600 ms：数据送达、重排、动画启动与走完各要占帧，只推一两帧时
/// 动画可能刚启动就停在起点。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _teardown(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(const SizedBox());
  rig.container.dispose();
  await rig.groups.close();
  await tester.pump(const Duration(seconds: 15));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
}

/// 节点行的位移盒在列表里的布局位置。同时确认它是列表（sliver）的直接子节点：
/// 列表逐个询问直接子节点的命中测试，位移盒能按绘制位置回答，点击才落得到
/// 看到的那一行上。
double _layoutTop(WidgetTester tester, String tag) {
  final box = tester.renderObject(
    find.byKey(ValueKey('node:$tag'), skipOffstage: false).last,
  );
  final data = box.parentData;
  expect(
    data,
    isA<SliverMultiBoxAdaptorParentData>(),
    reason: '位移盒必须是列表的直接子节点',
  );
  return (data! as SliverMultiBoxAdaptorParentData).layoutOffset!;
}

/// 行内容（位移盒里面的重绘边界）此刻的绘制范围（含位移）。
Rect _visualRect(WidgetTester tester, String tag) => tester.getRect(
  find
      .descendant(
        of: find.byKey(ValueKey('node:$tag'), skipOffstage: false).last,
        matching: find.byType(RepaintBoundary, skipOffstage: false),
        skipOffstage: false,
      )
      .first,
);

/// 节点行可点击的卡片此刻的范围（含位移）。
Rect _tapRect(WidgetTester tester, String tag) => tester.getRect(
  find.descendant(
    of: find.byKey(ValueKey('node:$tag'), skipOffstage: false).last,
    matching: find.byType(InkWell, skipOffstage: false),
    skipOffstage: false,
  ),
);

/// 位移盒的布局范围（不含位移）。
Rect _layoutRect(WidgetTester tester, String tag) =>
    tester.getRect(find.byKey(ValueKey('node:$tag'), skipOffstage: false).last);

bool _built(String tag) => find
    .byKey(ValueKey('node:$tag'), skipOffstage: false)
    .evaluate()
    .isNotEmpty;

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

const _many = [
  'Alpha',
  'Bravo',
  'Charlie',
  'Delta',
  'Echo',
  'Foxtrot',
  'Golf',
  'Hotel',
  'India',
  'Juliet',
  'Kilo',
  'Lima',
];

bool _testing(_Rig rig) =>
    rig.container.read(latencyTestCoordinatorProvider).isGroupTesting('select');

/// 先跑完一轮测速（所有节点都出新结果）：之后 30 s 冷却期内预热不会再自动
/// 开测，测试里的冻结只来自测试自己发起的那一轮。
Future<void> _completeRound(
  WidgetTester tester,
  _Rig rig,
  Map<String, int> delays,
) async {
  unawaited(
    rig.container
        .read(latencyTestCoordinatorProvider.notifier)
        .manualTest('select'),
  );
  await tester.pump();
  rig.groups.add([_group(delays)]);
  await tester.pump();
  await _settle(tester);
  expect(_testing(rig), isFalse);
}

void main() {
  const tags = ['Alpha', 'Bravo', 'Charlie'];

  testWidgets('手指按着时列表重排被推迟；抬起后选中的是按下时手指下的节点', (tester) async {
    final rig = await _rig({'Alpha': 100, 'Bravo': 200, 'Charlie': 300});
    await tester.pumpWidget(rig.widget);
    await _settle(tester);
    expect(_order(tester, tags), ['Alpha', 'Bravo', 'Charlie']);

    // 按住 Alpha 那一行。
    final alphaAt = tester.getCenter(find.text('Alpha'));
    final gesture = await tester.startGesture(alphaAt);
    await tester.pump(const Duration(milliseconds: 50));

    // 测速结果回来：Alpha 变成最慢，按排序它应该挪到最后。
    rig.groups.add([
      _group({'Alpha': 900, 'Bravo': 200, 'Charlie': 300}),
    ]);
    // 再按住 ~300 ms（总共短于长按的 500 ms），逐帧推进：要是重排了，位移动画
    // 早已走完。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(_order(tester, tags), [
      'Alpha',
      'Bravo',
      'Charlie',
    ], reason: '手指按着时不重排');
    expect(tester.getCenter(find.text('Alpha')), alphaAt, reason: 'Alpha 没被挪走');

    await gesture.up();
    await tester.pump();
    expect(rig.port.selected, ['Alpha'], reason: '选中的是按下时手指下的节点');

    // 抬起之后重排（带位移动画），动画结束后 Alpha 在最后。
    await _settle(tester);
    expect(_order(tester, tags), ['Bravo', 'Charlie', 'Alpha']);

    await _teardown(tester, rig);
  });

  testWidgets('按下之后上方的节点消失、这一行上移：点击仍作用于按下时的节点', (tester) async {
    // 冻结只管顺序，挡不住「上面少了一行」带来的位移（例如订阅刷新）：这时同一
    // 位置换成了下一个节点。行跟着节点走（key），点击才不会落到它身上。
    final rig = await _rig({
      'Zulu': 10,
      'Alpha': 100,
      'Bravo': 200,
      'Charlie': 300,
    });
    await tester.pumpWidget(rig.widget);
    await _settle(tester);

    final alphaAt = tester.getCenter(find.text('Alpha'));
    final gesture = await tester.startGesture(alphaAt);
    await tester.pump(const Duration(milliseconds: 50));
    rig.groups.add([
      _group({'Alpha': 100, 'Bravo': 200, 'Charlie': 300}),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(rig.port.selected, ['Alpha']);
    await _teardown(tester, rig);
  });

  testWidgets('测速进行中行顺序不变，测完才按延迟重排', (tester) async {
    final rig = await _rig({'Alpha': 100, 'Bravo': 200, 'Charlie': 300});
    await tester.pumpWidget(rig.widget);
    await _settle(tester);
    expect(_order(tester, tags), ['Alpha', 'Bravo', 'Charlie']);

    final coordinator = rig.container.read(
      latencyTestCoordinatorProvider.notifier,
    );
    unawaited(coordinator.manualTest('select'));
    await tester.pump();
    expect(
      rig.container
          .read(latencyTestCoordinatorProvider)
          .isGroupTesting('select'),
      isTrue,
    );

    // 结果陆续回来：Alpha 变慢、Bravo 变快，Charlie 还没出结果——仍在测速。
    rig.groups.add([
      _group({'Alpha': 900, 'Bravo': 50, 'Charlie': 300}),
    ]);
    await tester.pump();
    await _settle(tester);
    expect(
      rig.container
          .read(latencyTestCoordinatorProvider)
          .isGroupTesting('select'),
      isTrue,
    );
    expect(_order(tester, tags), [
      'Alpha',
      'Bravo',
      'Charlie',
    ], reason: '测速进行中不重排');

    // 最后一个结果回来：本轮测完，按延迟重排一次。
    rig.groups.add([
      _group({'Alpha': 900, 'Bravo': 50, 'Charlie': 400}),
    ]);
    await tester.pump();
    await _settle(tester);
    expect(
      rig.container
          .read(latencyTestCoordinatorProvider)
          .isGroupTesting('select'),
      isFalse,
    );
    expect(_order(tester, tags), ['Bravo', 'Charlie', 'Alpha']);

    await _teardown(tester, rig);
  });

  testWidgets('重排带位移动画：动画途中行处在新旧位置之间；系统减少动画时直接到位', (tester) async {
    Future<({double before, double mid, double after})> run({
      required bool reduceMotion,
    }) async {
      final rig = await _rig({'Alpha': 100, 'Bravo': 200, 'Charlie': 300});
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: rig.widget,
        ),
      );
      await _settle(tester);
      final before = tester.getRect(find.text('Alpha')).top;
      rig.groups.add([
        _group({'Alpha': 900, 'Bravo': 200, 'Charlie': 300}),
      ]);
      // 第 1 帧送达新分组，第 2 帧重排（画在原位置、动画随后启动），第 3 帧
      // 起动画推进。
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      final mid = tester.getRect(find.text('Alpha')).top;
      await _settle(tester);
      final after = tester.getRect(find.text('Alpha')).top;
      await _teardown(tester, rig);
      return (before: before, mid: mid, after: after);
    }

    final animated = await run(reduceMotion: false);
    expect(animated.after, greaterThan(animated.before));
    expect(animated.mid, greaterThan(animated.before), reason: '已经开始移动');
    expect(animated.mid, lessThan(animated.after), reason: '还没到终点：有动画');

    final reduced = await run(reduceMotion: true);
    expect(reduced.after, greaterThan(reduced.before));
    expect(reduced.mid, reduced.after, reason: '减少动画：直接出现在新位置');
  });
  group('动画途中按看到的位置点击，选中的就是看到的那一行', () {
    const five = {
      'Alpha': 100,
      'Bravo': 200,
      'Charlie': 300,
      'Delta': 400,
      'Echo': 500,
    };
    // Alpha 变成最慢：从第 1 行挪到第 5 行（跨 4 行）。
    const resorted = {
      'Alpha': 900,
      'Bravo': 200,
      'Charlie': 300,
      'Delta': 400,
      'Echo': 500,
    };

    Future<void> tapAlpha(WidgetTester tester, String phase) async {
      final rig = await _rig(five);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);
      final startTop = _layoutTop(tester, 'Alpha');
      final start = tester.getCenter(find.text('Alpha'));
      final rowHeight = tester
          .getSize(find.byKey(const ValueKey('node:Alpha')).last)
          .height;

      rig.groups.add([_group(resorted)]);
      // 推进到重排那一帧：布局已经在新位置，画面还在原位置（动画 0%）。
      for (var i = 0; i < 10 && _layoutTop(tester, 'Alpha') == startTop; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      final travel = _layoutTop(tester, 'Alpha') - startTop;
      expect(travel, greaterThan(3 * rowHeight), reason: '跨了好几行');
      final target = start.dy + travel;
      double visual() => tester.getCenter(find.text('Alpha')).dy;

      switch (phase) {
        case 'start':
          expect(visual(), start.dy, reason: '0%：还画在原位置');
        case 'halfTravel':
          for (var i = 0; i < 300 && visual() < start.dy + travel / 2; i++) {
            await tester.pump(const Duration(milliseconds: 1));
          }
          expect(visual(), greaterThanOrEqualTo(start.dy + travel / 2));
          expect(visual(), lessThan(target - rowHeight), reason: '还在半路');
        case 'halfTime':
          // 下一帧动画才启动，再走一半时长。
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(Motion.medium ~/ 2);
          expect(visual(), greaterThan(start.dy));
          expect(visual(), lessThan(target), reason: '动画进行到一半');
        case 'end':
          await _settle(tester);
          expect(visual(), target, reason: '100%：到了新位置');
      }
      if (phase == 'start' || phase == 'halfTravel') {
        expect(
          (visual() - target).abs(),
          greaterThan(rowHeight / 2),
          reason: '点的位置在 Alpha 的布局范围之外，只有按绘制位置命中才点得到',
        );
      }

      await tester.tapAt(Offset(start.dx, visual()));
      await tester.pump();
      expect(rig.port.selected, ['Alpha'], reason: '$phase：点到的是看到的 Alpha');
      await _teardown(tester, rig);
    }

    for (final phase in ['start', 'halfTravel', 'halfTime', 'end']) {
      testWidgets(phase, (tester) => tapAlpha(tester, phase));
    }
  });

  testWidgets('行内容在位移盒里面有自己的重绘边界：挪动只换图层偏移，不重绘行内容', (tester) async {
    final rig = await _rig({'Alpha': 100, 'Bravo': 200});
    await tester.pumpWidget(rig.widget);
    await _settle(tester);
    _layoutTop(tester, 'Alpha'); // 位移盒是列表的直接子节点
    final slide =
        tester.renderObject(find.byKey(const ValueKey('node:Alpha')).last)
            as RenderProxyBox;
    final semantics = slide.child! as RenderIndexedSemantics;
    expect(semantics.child!.isRepaintBoundary, isTrue);
    await _teardown(tester, rig);
  });

  group('命中与绘制一致：布局位置在缓存区、没画出来的行不截获点击', () {
    testWidgets('动画途中又一次重排把行挪进缓存区：它的位移不截获可见行的点击', (tester) async {
      final delays = {
        for (var i = 0; i < _many.length; i++) _many[i]: 100 * (i + 1),
      };
      final rig = await _rig(delays);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);

      // 第一个布局位置已在可视范围之外、但仍在缓存区（已构建）的行。
      final viewport = _scroll(tester).viewportDimension;
      final j = _many.indexWhere(
        (tag) => _built(tag) && _layoutTop(tester, tag) >= viewport,
      );
      expect(j, greaterThan(4), reason: '可视范围外还有缓存行');

      // 第一次重排：Alpha 从第 1 位挪到第 4 位（画着，开始位移动画）。
      var top = _layoutTop(tester, 'Alpha');
      rig.groups.add([
        _group({...delays, 'Alpha': 450}),
      ]);
      for (var i = 0; i < 10 && _layoutTop(tester, 'Alpha') == top; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));

      // 动画途中第二次重排：Alpha 挪到第 j 位，布局位置在可视范围之外，列表
      // 不再绘制它；它身上还挂着第一次动画的位移。
      top = _layoutTop(tester, 'Alpha');
      rig.groups.add([
        _group({...delays, 'Alpha': delays[_many[j]]! + 50}),
      ]);
      for (var i = 0; i < 10 && _layoutTop(tester, 'Alpha') == top; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(
        _layoutTop(tester, 'Alpha') - _scroll(tester).pixels,
        greaterThanOrEqualTo(viewport),
        reason: '列表不绘制 Alpha',
      );
      final ghost = _visualRect(tester, 'Alpha').center;
      final visible = [
        for (final tag in _many)
          if (tag != 'Alpha' &&
              _built(tag) &&
              _visualRect(tester, tag).contains(ghost))
            tag,
      ];
      expect(visible, hasLength(1), reason: 'Alpha 按位移算的位置上有一行看得见的');

      await tester.tapAt(ghost);
      await tester.pump();
      expect(rig.port.selected, visible, reason: '选中的是看得见的那一行');
      await _teardown(tester, rig);
    });

    testWidgets('动画途中滚动：位移立即走到终点，滚进缓存区的行不截获可见行的点击', (tester) async {
      // Alpha 原在第 3 位，变慢后挪到第 8 位（跨 5 行往下，排在途经各行之后，
      // 命中测试时先被询问）。
      final delays = {
        for (var i = 1; i < _many.length; i++) _many[i]: 100 * i,
        'Alpha': 250,
      };
      final rig = await _rig(delays);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);
      // 先往下滚一段，留出往回滚的余地。
      const scrolledAt = 200.0;
      _scroll(tester).jumpTo(scrolledAt);
      await _settle(tester);
      final viewport = _scroll(tester).viewportDimension;
      final startTop = _layoutTop(tester, 'Alpha');

      rig.groups.add([
        _group({...delays, 'Alpha': 750}),
      ]);
      for (var i = 0; i < 10 && _layoutTop(tester, 'Alpha') == startTop; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(
        _layoutTop(tester, 'Alpha') - scrolledAt,
        lessThan(viewport),
        reason: '新位置仍在可视范围内：列表绘制它，位移动画启动',
      );
      // 动画刚开始：Alpha 还画在原位置附近（新位置上方好几行）。
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 16));
      final rowHeight = _layoutRect(tester, 'Alpha').height;
      final alphaNow = _visualRect(tester, 'Alpha');
      expect(
        _layoutRect(tester, 'Alpha').center.dy - alphaNow.center.dy,
        greaterThan(3 * rowHeight),
        reason: '动画进行中，位移还很大',
      );

      // 往回滚：Alpha 的新布局位置滚出可视范围底端，进入缓存区。
      final scrollTo = _layoutTop(tester, 'Alpha') - viewport - 10;
      expect(scrollTo, inInclusiveRange(0, scrolledAt), reason: '往回滚');
      _scroll(tester).jumpTo(scrollTo);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_built('Alpha'), isTrue, reason: 'Alpha 仍在缓存区');
      expect(
        _layoutTop(tester, 'Alpha') - _scroll(tester).pixels,
        greaterThanOrEqualTo(viewport),
        reason: '列表不绘制 Alpha',
      );

      // 滚动开始时所有位移走到终点：看到的就是布局位置。
      for (final tag in _many.where(_built)) {
        expect(
          _visualRect(tester, tag).top,
          _layoutRect(tester, tag).top,
          reason: '$tag 的位移已收掉',
        );
      }

      // Alpha 滚动前按位移所在的范围，随滚动一起移动。不收掉位移、也不按绘制
      // 裁剪的话，Alpha 没画出来、按位移却仍覆盖这片区域，而且它排在途经各行
      // 之后、先被询问——点在这里看得见的行上，会落到看不见的 Alpha 身上。
      final ghost = alphaNow.shift(Offset(0, scrolledAt - scrollTo));
      // 与这片区域交叠最多的可见行（按它可点击的卡片范围算），点在交叠处。
      final overlaps = {
        for (final tag in _many)
          if (tag != 'Alpha' && _built(tag))
            tag: _tapRect(tester, tag).intersect(ghost),
      }..removeWhere((_, r) => r.height <= 0 || r.width <= 0);
      expect(overlaps, isNotEmpty, reason: '这片区域里有看得见的行');
      final target = overlaps.entries
          .reduce((a, b) => a.value.height >= b.value.height ? a : b)
          .key;
      final point = overlaps[target]!.center;
      await tester.tapAt(point);
      await tester.pump();
      expect(rig.port.selected, [target], reason: '选中的是看得见的那一行');
      await _teardown(tester, rig);
    });
  });

  group('冻结的各种退出路径：退出后补上推迟的重排，之后的重排照常生效', () {
    const base = {'Alpha': 100, 'Bravo': 200, 'Charlie': 300};
    // 测速途中回来的部分结果：Alpha 变慢、Bravo 变快，Charlie 还没出结果。
    const partial = {'Alpha': 900, 'Bravo': 50, 'Charlie': 300};
    const partialSorted = ['Bravo', 'Charlie', 'Alpha'];
    // 之后又一次变化：Charlie 最快。
    const later = {'Alpha': 900, 'Bravo': 50, 'Charlie': 10};
    const laterSorted = ['Charlie', 'Bravo', 'Alpha'];

    /// 发起一轮测速并推来部分结果：断言这时列表冻结着。
    Future<({Future<void> round})> startFrozenRound(
      WidgetTester tester,
      _Rig rig,
    ) async {
      final round = rig.container
          .read(latencyTestCoordinatorProvider.notifier)
          .manualTest('select');
      await tester.pump();
      rig.groups.add([_group(partial)]);
      await tester.pump();
      await _settle(tester);
      expect(_testing(rig), isTrue);
      expect(_order(tester, tags), tags, reason: '测速进行中不重排');
      return (round: round);
    }

    /// 已退出冻结：推迟的重排补上；再来一次结果变化，也照常重排。
    Future<void> expectUnfrozen(
      WidgetTester tester,
      _Rig rig, {
      required List<String> now,
      required void Function() laterChange,
      required List<String> afterLater,
    }) async {
      await _settle(tester);
      expect(_testing(rig), isFalse);
      expect(_order(tester, tags), now, reason: '退出冻结后补上推迟的重排');
      laterChange();
      await tester.pump();
      await _settle(tester);
      expect(_order(tester, tags), afterLater, reason: '之后的重排照常生效');
    }

    testWidgets('手势被取消（PointerCancel）', (tester) async {
      final rig = await _rig(base);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);
      await _completeRound(tester, rig, {
        'Alpha': 101,
        'Bravo': 201,
        'Charlie': 301,
      });

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Alpha')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      rig.groups.add([_group(partial)]);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(_order(tester, tags), tags, reason: '手指按着时不重排');

      await gesture.cancel();
      await expectUnfrozen(
        tester,
        rig,
        now: partialSorted,
        laterChange: () => rig.groups.add([_group(later)]),
        afterLater: laterSorted,
      );
      expect(rig.port.selected, isEmpty, reason: '取消的手势不选任何节点');
      await _teardown(tester, rig);
    });

    testWidgets('测速调用失败', (tester) async {
      final rig = await _rig(base);
      final kernel = Completer<void>();
      rig.box.onUrlTest = () => kernel.future;
      await tester.pumpWidget(rig.widget);
      await _settle(tester);

      final (:round) = await startFrozenRound(tester, rig);
      Object? thrown;
      unawaited(round.catchError((Object e) => thrown = e));
      kernel.completeError(StateError('urlTest failed'));
      await tester.pump();
      expect(thrown, isA<StateError>());

      await expectUnfrozen(
        tester,
        rig,
        now: partialSorted,
        laterChange: () => rig.groups.add([_group(later)]),
        afterLater: laterSorted,
      );
      await _teardown(tester, rig);
    });

    testWidgets('本轮超时（10 s 还有节点没出结果）', (tester) async {
      final rig = await _rig(base);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);

      final (:round) = await startFrozenRound(tester, rig);
      var done = false;
      unawaited(round.then((_) => done = true));
      await tester.pump(const Duration(seconds: 11));
      expect(done, isTrue, reason: '超时收尾');

      await expectUnfrozen(
        tester,
        rig,
        now: partialSorted,
        laterChange: () => rig.groups.add([_group(later)]),
        afterLater: laterSorted,
      );
      await _teardown(tester, rig);
    });

    testWidgets('测速途中断开连接', (tester) async {
      final rig = await _rig(base);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);

      await startFrozenRound(tester, rig);
      final cache = rig.container.read(proxyDelayCacheProvider.notifier);
      // 实时结果照常进了延迟缓存；断开后线路页按缓存展示。
      cache.recordMeasured(partial);
      rig.setConnected(false);
      await tester.pump();

      await expectUnfrozen(
        tester,
        rig,
        now: partialSorted,
        laterChange: () => cache.recordMeasured(later),
        afterLater: laterSorted,
      );
      await _teardown(tester, rig);
    });

    testWidgets('测速途中切换订阅', (tester) async {
      final rig = await _rig(base);
      await tester.pumpWidget(rig.widget);
      await _settle(tester);

      await startFrozenRound(tester, rig);
      rig.switchProfile(
        const ProfileEntity(
          id: 'profile-2',
          name: '另一个订阅',
          url: 'https://example.com/sub2',
          active: true,
        ),
      );
      await tester.pump();

      await expectUnfrozen(
        tester,
        rig,
        now: partialSorted,
        laterChange: () => rig.groups.add([_group(later)]),
        afterLater: laterSorted,
      );
      await _teardown(tester, rig);
    });
  });
}
