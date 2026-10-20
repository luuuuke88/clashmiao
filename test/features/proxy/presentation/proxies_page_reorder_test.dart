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
import 'package:flutter/material.dart';
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

  @override
  Future<void> urlTest(String groupTag) async => urlTests.add(groupTag);

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
  _Rig(this.widget, this.container, this.port, this.groups);

  final Widget widget;
  final ProviderContainer container;
  final _Port port;
  final StreamController<List<OutboundGroup>> groups;
}

Future<_Rig> _rig(Map<String, int> delays) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final port = _Port();
  // 由 [_teardown] 关闭。
  // ignore: close_sinks
  final groups = StreamController<List<OutboundGroup>>.broadcast();
  final initial = [_group(delays)];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _profile),
      boxServiceProvider.overrideWithValue(_Box()),
      kernelPortProvider.overrideWithValue(port),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      offlineProxyGroupsProvider.overrideWith((_) async => initial),
      outboundGroupsProvider.overrideWith((ref) async* {
        yield initial;
        yield* groups.stream;
      }),
      isConnectedProvider.overrideWith((_) => true),
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
    groups,
  );
}

/// 节点行从上到下的顺序（按名称文字的纵坐标）。
List<String> _order(WidgetTester tester, List<String> tags) {
  final ys = {for (final t in tags) t: tester.getCenter(find.text(t)).dy};
  return [...tags]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _teardown(WidgetTester tester, _Rig rig) async {
  await tester.pumpWidget(const SizedBox());
  rig.container.dispose();
  await rig.groups.close();
  await tester.pump(const Duration(seconds: 15));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
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
}
