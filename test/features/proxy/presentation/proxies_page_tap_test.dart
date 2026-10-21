import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/proxy/application/optimistic_proxy_selections_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/fake_box_service.dart';
import '../../../support/fake_connection_controller.dart';
import '../../../support/profile_store_support.dart';
import '../../../support/toast_pump.dart';

/// Toastification 的 auto-close 走 Timer（info=3s / error=5s），widget dispose 后
/// timer 还活着会让 flutter_test 报 "A Timer is still pending"。
/// pump 一段足够长的假时钟把 timer 烧完，再 dismiss + 再 pump 一帧让动画收尾。
Future<void> _drainToasts(WidgetTester tester) async {
  // 已连接时协调器有 2 s 预热定时器与 17 s 测速超时定时器；容器由测试自己持有、
  // 要到 tearDown 才销毁，所以这里把假时钟推过去，让它们自然跑完。
  await tester.pump(const Duration(seconds: 21));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
}

/// 这条测试是为了守住用户报过的"Lines 页面点 ss-node 直接崩溃"那个回归。
/// 当时没抓到栈，但代码路径上 `_selectProxy` 的两个分支都不该崩。
/// 这里直接驱动两条 isConnected 路径，确认：
///   - 未连接：点 tile → 弹 info toast，不调 selectOutbound
///   - 已连接：点 tile → optimisticSelections 更新 + selectOutbound 被调
class _SpyBoxService extends FakeBoxService {
  int selectOutboundCalls = 0;
  String? lastGroupTag;
  int? lastExpectedAttempt;
  String? lastOutboundTag;
  final List<String> urlTestCalls = [];
  Future<void>? selectOutboundOverride;
  Future<void>? urlTestOverride;
  // 故意不用「预先构造好的 Future.error 塞进字段里、later await」这种写法：
  // 那样 Future 在赋值的那一刻就已经完成为 error 态，如果之后隔了几个微任务
  // 才被 await（比如经过 tester.tap 的手势识别),Dart 的 zone 会在 catchError
  // 真正接住之前就把它当"unhandled"报出来，导致 flutter_test 判定用例失败,
  // 即使产品代码里的 .catchError 完全接住了这个错误。
  // 改成这个字段：只在 selectOutbound 被调用的那个同步栈里 `throw`,让错误
  // 随着这次函数调用同步产生，调用方 `_selectProxy` 紧接着同步挂上的
  // `.then().catchError()` 能在同一轮里接住，不会被 zone 误判。
  Object? selectOutboundError;

  // 其余方法最小实现 —— 这条测试不会触发它们。
  /// 非空时 urlTest 抛它（模拟原生 PlatformException）。
  Object? urlTestError;

  @override
  Future<void> urlTest(String g) async {
    urlTestCalls.add(g);
    final err = urlTestError;
    if (err != null) throw err;
    final override = urlTestOverride;
    if (override != null) await override;
  }

  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

/// 手选现在走 [KernelPort.selectOutbound]（带 expectedAttempt）而不是 BoxService：
/// 这个替身把调用折回 [_SpyBoxService] 的计数 / 失败注入字段，保持各用例的断言不变。
class _SpyPort extends FakeKernelPort {
  _SpyPort(this.box);

  final _SpyBoxService box;

  @override
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    box.selectOutboundCalls++;
    box.lastExpectedAttempt = expectedAttempt;
    box.lastGroupTag = groupTag;
    box.lastOutboundTag = outboundTag;
    final error = box.selectOutboundError;
    if (error != null) return SelectFailed('exception', '$error');
    final override = box.selectOutboundOverride;
    if (override != null) await override;
    return const SelectOk();
  }
}

const _ssNode = OutboundProxy(tag: 'ss-node', type: 'shadowsocks');
const _activeProfile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

OutboundGroup _proxyGroup({String selected = 'ss-node'}) => OutboundGroup(
  tag: 'proxy',
  type: 'selector',
  selected: selected,
  items: const [_ssNode],
);

// 回滚场景需要至少两个真实节点：点击「另一个」节点失败后，回滚才有意义
// （单节点分组点自己没法区分"没切成功"和"本来就是它"）。
const _nodeA = OutboundProxy(tag: 'node-a', type: 'shadowsocks');
const _nodeB = OutboundProxy(tag: 'node-b', type: 'shadowsocks');

OutboundGroup _twoNodeGroup({String selected = 'node-a'}) => OutboundGroup(
  tag: 'proxy',
  type: 'selector',
  selected: selected,
  items: const [_nodeA, _nodeB],
);

Future<(Widget, ProviderContainer, _SpyBoxService)> _host({
  required bool connected,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final store = await seededProfileStore(prefs, [_activeProfile]);
  final spy = _SpyBoxService();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      profileStoreProvider.overrideWith((_) => Future.value(store)),
      activeProfileProvider.overrideWith((_) async => _activeProfile),
      boxServiceProvider.overrideWithValue(spy),
      kernelPortProvider.overrideWithValue(_SpyPort(spy)),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      // 离线 group 直接给一个：proxy / ss-node
      offlineProxyGroupsProvider.overrideWith((_) async => [_proxyGroup()]),
      // 已连接时内核推送同一份实时分组：选择 / 测速只对实时分组发起。
      if (connected)
        outboundGroupsProvider.overrideWith(
          (_) => Stream.value([_proxyGroup()]),
        ),
      // isConnected 用 Provider override
      isConnectedProvider.overrideWith((_) => connected),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileStoreProvider.future);
  await container.read(activeProfileProvider.future);
  return (
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
    spy,
  );
}

void main() {
  testWidgets('未连接时 tap ss-node tile → 不调 selectOutbound，不崩', (tester) async {
    final (widget, container, spy) = await _host(connected: false);
    await tester.pumpWidget(widget);
    // 等 offlineProxyGroupsProvider 解析
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // 找 ss-node tile（按 tag 显示的文本）
    final tile = find.text('ss-node');
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 0);
    // optimistic 选择也不该被写
    expect(container.read(optimisticProxySelectionsProvider), isEmpty);
    await _drainToasts(tester);
  });

  testWidgets('已连接时 tap ss-node tile → selectOutbound 触发 + optimistic 更新', (
    tester,
  ) async {
    final (widget, container, spy) = await _host(connected: true);
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final tile = find.text('ss-node');
    expect(tile, findsOneWidget);

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(spy.lastGroupTag, 'proxy');
    expect(spy.lastOutboundTag, 'ss-node');
    expect(container.read(optimisticProxySelectionsProvider), {
      'proxy': 'ss-node',
    });
    await _drainToasts(tester);
  });

  // 第 3 条 case（selectOutbound 失败 → catchError 兜住）：之前留了个注释说这个
  // 场景不好测（担心 Dart zone 把 catchError 已消费的 future error 又当 unhandled
  // 报出来）。绕开办法是别用「预先构造好的 Future.error 塞进字段、之后再 await」
  // 这种写法（那样错误在赋值那一刻就已完成，如果之后隔了几个微任务/事件循环轮次
  // 才被消费，Dart 会先判定为 unhandled）；改成 _SpyBoxService.selectOutboundError
  // 那样在方法调用的同步栈里直接 throw，紧跟着 `_selectProxy` 里同步挂上的
  // `.then().catchError()` 就能在同一条同步表达式内接住，不会被 zone 误判。
  testWidgets('已连接时 selectOutbound 失败 → 回滚乐观选择，不留在错误节点上', (tester) async {
    final (widget, container, spy) = await _hostWithGroups(
      connected: true,
      groups: [_twoNodeGroup(selected: 'node-a')],
    );
    spy.selectOutboundError = Exception('native switch failed');

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // 点击前没有任何乐观选择——UI 显示真实 selected：node-a。
    expect(container.read(optimisticProxySelectionsProvider), isEmpty);

    await tester.tap(find.text('node-b'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(spy.lastOutboundTag, 'node-b');
    // 乐观更新曾经短暂写入 node-b，失败后必须被撤销，而不是永久停在 node-b。
    expect(container.read(optimisticProxySelectionsProvider), isEmpty);
    await _drainToasts(tester);
  });

  testWidgets('已连接时 selectOutbound 失败 → 回滚到点击前的乐观值而不是清空', (tester) async {
    final (widget, container, spy) = await _hostWithGroups(
      connected: true,
      groups: [_twoNodeGroup(selected: 'node-a')],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    // 模拟"之前已经乐观切换成功过一次"：group 的乐观值已经是 node-b。
    container
        .read(optimisticProxySelectionsProvider.notifier)
        .update('proxy', 'node-b');
    await tester.pump();

    // 这次再点 node-a，但 native 调用失败。
    spy.selectOutboundError = Exception('native switch failed');
    await tester.tap(find.text('node-a'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(spy.lastOutboundTag, 'node-a');
    // 应该回滚回点击前的乐观值 node-b，而不是被清空、也不是停在失败的 node-a。
    expect(container.read(optimisticProxySelectionsProvider), {
      'proxy': 'node-b',
    });
    await _drainToasts(tester);
  });

  testWidgets('已连接时 tap ss-node tile 选中成功后，持久化选择供下次重连重放', (tester) async {
    final (widget, container, spy) = await _host(connected: true);
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('ss-node'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(
      container.read(proxySelectionStoreProvider),
      {'proxy': 'ss-node'},
      reason:
          'sing-box 的 selector 只在运行中实例内存里记住当前选中项，每次重连都会用'
          'runtime-config 的静态 default 重新起一个全新实例——手选结果必须持久化，'
          '否则下次重连会静默回退到默认值',
    );
    await _drainToasts(tester);
  });

  testWidgets('手选带上界面看到的当前 attempt（expectedAttempt），原生据此拒绝过期写入', (
    tester,
  ) async {
    final (widget, container, spy) = await _host(connected: true);
    // 把控制器状态换成「已连接，attempt = 4」。
    (container.read(
      connectionControllerProvider.notifier,
    ) as FakeConnectionController).set(
      const ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        epoch: 'e1',
        attempt: 4,
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('ss-node'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(spy.lastExpectedAttempt, 4);
    await _drainToasts(tester);
  });

  testWidgets('已连接时 selectOutbound 失败 → 不持久化这次失败的选择', (tester) async {
    final (widget, container, spy) = await _hostWithGroups(
      connected: true,
      groups: [_twoNodeGroup(selected: 'node-a')],
    );
    spy.selectOutboundError = Exception('native switch failed');

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('node-b'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(
      container.read(proxySelectionStoreProvider),
      isEmpty,
      reason: 'native 切换失败时，这次点击并不是"用户真正选中的节点"，不该被当成手选结果持久化',
    );
    await _drainToasts(tester);
  });

  // 真机验收 BUG-1 / BUG-5：已连接但实时分组还没到时，页面展示的是配置文件里
  // 解析出的分组，tag 不保证存在于运行时——绝不能拿它调内核；内核报错的原文
  // （PlatformException、selector not found）只进日志，界面是本地化文案。
  group('只对实时分组发起内核操作 / 错误文案类型化', () {
    // 同文案 800 ms 去重用的是真实时钟：用例之间清掉，免得上一条的提示把这条吞掉。
    setUp(AppToast.resetForTest);

    testWidgets('已连接但只有离线分组：点节点不调内核，提示线路加载中', (tester) async {
      final (widget, container, spy) = await _hostWithGroups(
        connected: true,
        groups: [_twoNodeGroup(selected: 'node-a')],
        liveGroups: false,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('node-b'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.selectOutboundCalls, 0, reason: '离线分组的 tag 不能用来调内核');
      expect(container.read(proxySelectionStoreProvider), isEmpty);
      expect(container.read(optimisticProxySelectionsProvider), isEmpty);
      expect(find.text('线路信息加载中，请稍候再试'), findsOneWidget);
      await _drainToasts(tester);
    });

    testWidgets('已连接但只有离线分组：测速按钮不调 urlTest，提示线路加载中', (tester) async {
      final (widget, _, spy) = await _hostWithGroups(
        connected: true,
        groups: [_twoNodeGroup(selected: 'node-a')],
        liveGroups: false,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.urlTestCalls, isEmpty);
      expect(find.text('线路信息加载中，请稍候再试'), findsOneWidget);
      await _drainToasts(tester);
    });

    testWidgets('切换失败：提示本地化文案，不展示内核错误原文', (tester) async {
      final (widget, _, spy) = await _hostWithGroups(
        connected: true,
        groups: [_twoNodeGroup(selected: 'node-a')],
      );
      spy.selectOutboundError = Exception('selector not found: proxy');
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('node-b'));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.selectOutboundCalls, 1);
      expect(find.text('切换线路失败，请稍后重试'), findsOneWidget);
      expect(find.textContaining('selector not found'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      await _drainToasts(tester);
    });

    testWidgets('测速失败：提示本地化文案，不展示 PlatformException 原文', (tester) async {
      final (widget, _, spy) = await _hostWithGroups(
        connected: true,
        groups: [_twoNodeGroup(selected: 'node-a')],
      );
      spy.urlTestError = PlatformException(
        code: 'urlTest',
        message: 'outbound group not found: proxy',
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
      await tester.pump(const Duration(milliseconds: 300));
      await pumpToast(tester);

      expect(spy.urlTestCalls, isNotEmpty);
      expect(find.text('测速失败，请稍后重试'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(find.textContaining('not found'), findsNothing);
      await _drainToasts(tester);
    });

    testWidgets('未连接时离线分组显示存储里的手选（下次重放的就是它），不是配置默认值', (tester) async {
      final (widget, _, _) = await _hostWithGroups(
        connected: false,
        groups: [_twoNodeGroup(selected: 'node-a')],
        initialPrefs: {
          'locale': 'zhCn',
          ProfileStore.selectionKey('profile-1'): '{"proxy":"node-b"}',
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final checked = find.descendant(
        of: find.ancestor(
          of: find.text('node-b'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(FluentIcons.checkmark_24_filled),
      );
      expect(checked, findsOneWidget);
    });
  });

  // empty state / reserved group filter / urlTest header 的覆盖在底下追加。
  _addProxiesPageExtraTests();
}

// =================================================================
//  追加：empty state / sort modal / urlTest header button 覆盖
// =================================================================

Future<(Widget, ProviderContainer, _SpyBoxService)> _hostWithGroups({
  required bool connected,
  required List<OutboundGroup> groups,
  Map<String, Object> initialPrefs = const {'locale': 'zhCn'},
  bool liveGroups = true,
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final spy = _SpyBoxService();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _activeProfile),
      boxServiceProvider.overrideWithValue(spy),
      kernelPortProvider.overrideWithValue(_SpyPort(spy)),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      offlineProxyGroupsProvider.overrideWith((_) async => groups),
      // 离线排除集：按这份分组拼成的配置（全部叶子节点）算，与生产同一函数。
      offlineInfoExclusionsProvider.overrideWith(
        (_) async => subscriptionInfoExclusionsForConfig({
          'outbounds': [
            for (final g in groups)
              for (final item in g.items) {'tag': item.tag, 'type': item.type},
          ],
        }),
      ),
      if (connected && liveGroups)
        outboundGroupsProvider.overrideWith((_) => Stream.value(groups)),
      isConnectedProvider.overrideWith((_) => connected),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  return (
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
    spy,
  );
}

void _addProxiesPageExtraTests() {
  testWidgets('空 groups 时显示 _EmptyProxy 文案（zhCn = 无可用的线路）', (tester) async {
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: const [],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('无可用的线路'), findsOneWidget);
  });

  testWidgets('GLOBAL / DIRECT / REJECT 内部 group 被过滤掉', (tester) async {
    // 给一组只包含 reserved tag 的 group —— 过滤后等于空，应该走 empty state
    final reserved = [
      const OutboundGroup(
        tag: 'GLOBAL',
        type: 'selector',
        selected: '',
        items: [],
      ),
      const OutboundGroup(
        tag: 'DIRECT',
        type: 'selector',
        selected: '',
        items: [],
      ),
      const OutboundGroup(
        tag: 'REJECT',
        type: 'selector',
        selected: '',
        items: [],
      ),
    ];
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: reserved,
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('无可用的线路'), findsOneWidget);
  });

  testWidgets('proxy 与订阅原始选择组节点相同时只展示一组线路', (tester) async {
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'ss-node',
          items: [OutboundProxy(tag: 'ss-node', type: 'shadowsocks')],
        ),
        OutboundGroup(
          tag: '原始选择组',
          type: 'selector',
          selected: 'ss-node',
          items: [OutboundProxy(tag: 'ss-node', type: 'shadowsocks')],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('proxy'), findsNothing);
    expect(find.text('原始选择组'), findsNothing);
    expect(find.text('ss-node'), findsOneWidget);
  });

  testWidgets('已连接但 live groups 只有空节点分组时回退离线分组', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final spy = _SpyBoxService();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        activeProfileProvider.overrideWith((_) async => _activeProfile),
        boxServiceProvider.overrideWithValue(spy),
        kernelPortProvider.overrideWithValue(_SpyPort(spy)),
        connectionControllerProvider.overrideWith(FakeConnectionController.new),
        isConnectedProvider.overrideWith((_) => true),
        outboundGroupsProvider.overrideWith(
          (_) => Stream.value([
            const OutboundGroup(
              tag: '测速',
              type: 'selector',
              selected: '',
              items: [],
            ),
          ]),
        ),
        offlineProxyGroupsProvider.overrideWith((_) async => [_proxyGroup()]),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
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
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('proxy'), findsNothing);
    expect(find.text('ss-node'), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('delay 为 0 的节点显示 — 占位而不是超时', (tester) async {
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: [_proxyGroup()],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ss-node'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('未测速'), findsNothing);
    expect(find.text('超时'), findsNothing);
  });

  testWidgets('离线线路会合并当前订阅缓存的测速结果', (tester) async {
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: [_proxyGroup()],
      initialPrefs: const {
        'locale': 'zhCn',
        'proxy_delays_profile-1': '{"ss-node":123}',
      },
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ss-node'), findsOneWidget);
    // 旧格式（裸 int）的缓存读出来是「历史值」：数字照常显示，不透明度降低。
    expect(find.text('123ms'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('已连接且拿到真实实时分组时（延迟未测出=0），不该用缓存的旧延迟顶替显示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      // 这个缓存值模拟"之前某次真实测速留下的旧数据"——已连接、拿到了真实
      // 的实时分组数据时，绝不应该被用来顶替显示，否则会冻结成一个永远不变
      // 的假数字（用户反馈过的"每次都是87"那个 bug 的根因）。
      'proxy_delays_profile-1': '{"ss-node":999}',
    });
    final prefs = await SharedPreferences.getInstance();
    final spy = _SpyBoxService();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        activeProfileProvider.overrideWith((_) async => _activeProfile),
        boxServiceProvider.overrideWithValue(spy),
        kernelPortProvider.overrideWithValue(_SpyPort(spy)),
        connectionControllerProvider.overrideWith(FakeConnectionController.new),
        isConnectedProvider.overrideWith((_) => true),
        // 真实的实时分组：ss-node 存在但还没测出延迟（默认 delay: 0）。
        outboundGroupsProvider.overrideWith(
          (_) => Stream.value([_proxyGroup()]),
        ),
        offlineProxyGroupsProvider.overrideWith((_) async => []),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
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
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ss-node'), findsOneWidget);
    expect(
      find.text('999ms'),
      findsNothing,
      reason: '已连接且实时分组数据非空时应该信任实时数据本身，不该拿离线缓存覆盖',
    );
    expect(find.text('—'), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('未连接时点 flash header button → 显示提示文案，不触发 urlTest', (tester) async {
    final (widget, _, spy) = await _hostWithGroups(
      connected: false,
      groups: [_proxyGroup()],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);

    expect(spy.urlTestCalls, isEmpty);
    expect(find.text('请连接后测速'), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('测速按钮只触发主分组的 group.urlTest', (tester) async {
    final (widget, _, spy) = await _hostWithGroups(
      connected: true,
      groups: [
        const OutboundGroup(
          tag: 'manual',
          type: 'selector',
          selected: 'ss-node',
          items: [OutboundProxy(tag: 'ss-node', type: 'shadowsocks')],
        ),
        const OutboundGroup(
          tag: 'auto',
          type: 'urltest',
          selected: 'auto-node',
          items: [OutboundProxy(tag: 'auto-node', type: 'urltest')],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.urlTestCalls, equals(['manual']));
    await _drainToasts(tester);
  });

  testWidgets('测全部按钮支持 url-test 格式 type 的分组', (tester) async {
    final (widget, _, spy) = await _hostWithGroups(
      connected: true,
      groups: [
        const OutboundGroup(
          tag: 'auto',
          type: 'url-test',
          selected: 'auto-node',
          items: [OutboundProxy(tag: 'auto-node', type: 'url-test')],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.urlTestCalls, equals(['auto']));
    await _drainToasts(tester);
  });

  testWidgets('测速进行中：顶部按钮变 18 dp 指示器，没有旧值的行保持占位；一轮结束后恢复', (tester) async {
    final (widget, _, spy) = await _hostWithGroups(
      connected: true,
      groups: [_proxyGroup()],
    );
    final completer = Completer<void>();
    spy.urlTestOverride = completer.future;

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('—'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.urlTestCalls, equals(['proxy']));
    final indicator = find.byType(CircularProgressIndicator);
    expect(indicator, findsOneWidget);
    expect(
      tester.getSize(
        find.ancestor(of: indicator, matching: find.byType(SizedBox)).first,
      ),
      const Size(18, 18),
    );
    expect(find.byIcon(FluentIcons.flash_24_regular), findsNothing);
    expect(find.text('—'), findsOneWidget, reason: '没有旧值的行保持占位，不闪烁');

    completer.complete();
    await tester.pump(const Duration(seconds: 18));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(FluentIcons.flash_24_regular), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('长按节点卡片弹出节点名称确认面板', (tester) async {
    final (widget, _, _) = await _hostWithGroups(
      connected: false,
      groups: [_proxyGroup()],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('ss-node'), findsOneWidget);

    await tester.longPress(find.text('ss-node'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ss-node'), findsNWidgets(2));
    expect(find.widgetWithText(ElevatedButton, 'OK'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'OK'));
    await tester.pumpAndSettle();
  });

  for (final connected in [true, false]) {
    testWidgets('订阅信息条目不作为节点展示（${connected ? '实时' : '离线'}分组）', (tester) async {
      const info = '🌐 官网地址：ncink.cc';
      // 实时分组来自内核：构建器已给信息条目打上隐藏标记。离线分组解析自订阅
      // 配置：信息条目原样在里面，由整份配置算出的排除集过滤。
      final shownInfo = connected ? '$info §hide§' : info;
      final (widget, container, _) = await _hostWithGroups(
        connected: connected,
        groups: [
          OutboundGroup(
            tag: 'select',
            type: 'selector',
            selected: 'auto',
            items: [
              const OutboundProxy(tag: 'auto', type: 'urltest'),
              OutboundProxy(tag: shownInfo, type: 'vless', delay: 80),
              const OutboundProxy(tag: '香港 01', type: 'vless', delay: 120),
              const OutboundProxy(
                tag: '香港02 官网优化 IEPL',
                type: 'vless',
                delay: 130,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('香港 01'), findsOneWidget);
      expect(
        find.text('香港02 官网优化 IEPL'),
        findsOneWidget,
        reason: '含关键词的真实线路照常展示',
      );
      expect(find.textContaining('官网地址'), findsNothing);
      expect(find.textContaining('ncink.cc'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 30));
    });
  }

  testWidgets('只有信息条目的分组排在前面：主组取后面有真实节点的分组，不显示空列表', (tester) async {
    final (widget, container, _) = await _hostWithGroups(
      connected: false,
      groups: const [
        OutboundGroup(
          tag: '订阅信息',
          type: 'selector',
          selected: '官网地址：a.cc',
          items: [
            OutboundProxy(tag: '官网地址：a.cc', type: 'vless'),
            OutboundProxy(tag: '剩余流量：1 GB', type: 'vless'),
          ],
        ),
        OutboundGroup(
          tag: '节点选择',
          type: 'selector',
          selected: '香港 01',
          items: [
            OutboundProxy(tag: '香港 01', type: 'vless'),
            OutboundProxy(tag: '日本 02', type: 'vless'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('无可用的线路'), findsNothing);
    expect(find.text('香港 01'), findsOneWidget);
    expect(find.text('日本 02'), findsOneWidget);
    expect(find.textContaining('官网地址'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('线路节点隐藏内部标记并保留原始 tag 选择', (tester) async {
    const taggedNode = '香港 01 §proxy§';
    final (widget, _, spy) = await _hostWithGroups(
      connected: true,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: taggedNode,
          items: [
            OutboundProxy(tag: taggedNode, type: 'shadowsocks'),
            OutboundProxy(tag: '隐藏节点 §hide§', type: 'shadowsocks'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('香港 01'), findsOneWidget);
    expect(find.text(taggedNode), findsNothing);
    expect(find.text('隐藏节点'), findsNothing);
    expect(find.text('隐藏节点 §hide§'), findsNothing);

    await tester.tap(find.text('香港 01'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(spy.selectOutboundCalls, 1);
    expect(spy.lastOutboundTag, taggedNode);

    await tester.longPress(find.text('香港 01'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('香港 01'), findsNWidgets(2));
    expect(find.text(taggedNode), findsNothing);
    await _drainToasts(tester);
  });

  testWidgets('测速结果缓存只写入当前订阅下的正数延迟', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final store = await seededProfileStore(prefs, [_activeProfile]);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(store)),
        activeProfileProvider.overrideWith((_) async => _activeProfile),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileStoreProvider.future);
    await container.read(activeProfileProvider.future);

    container.read(proxyDelayCacheProvider.notifier).persistFromGroups(const [
      OutboundGroup(
        tag: 'proxy',
        type: 'selector',
        selected: 'good',
        items: [
          OutboundProxy(tag: 'good', type: 'shadowsocks', delay: 88),
          OutboundProxy(tag: 'zero', type: 'shadowsocks'),
        ],
      ),
    ]);

    // 写入经 ProfileStore 的锁排队，等它落盘再断言。
    await store.commit<void>((_) => const Plan<void>.unchanged());
    // 新格式：{ms, measuredAt}；0 延迟的节点不写。
    final stored = decodeDelayCache(prefs.getString('proxy_delays_profile-1'));
    expect(stored.keys, ['good']);
    expect(stored['good']!.ms, 88);
    expect(stored['good']!.measuredAt, isNotNull);
  });

  testWidgets('name 排序时嵌套代理组排在普通节点前面（不管字母序）', (tester) async {
    final (widget, container, _) = await _hostWithGroups(
      connected: false,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'Node-A',
          items: [
            // 字母序上 Node-A 排在 Z-SubGroup 前面，但 Z-SubGroup 是嵌套代理组
            // （type: selector），分组类型优先规则下应该排到 Node-A 前面。
            OutboundProxy(tag: 'Node-A', type: 'shadowsocks'),
            OutboundProxy(tag: 'Z-SubGroup', type: 'selector'),
          ],
        ),
      ],
    );
    await container
        .read(proxiesSortProvider.notifier)
        .updateSort(ProxiesSort.name);

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final subGroupCenter = tester.getCenter(find.text('Z-SubGroup'));
    final nodeCenter = tester.getCenter(find.text('Node-A'));
    expect(
      subGroupCenter.dy,
      lessThan(nodeCenter.dy),
      reason: '嵌套代理组应该排在普通节点前面，不受字母序影响',
    );
  });

  testWidgets('delay 排序时嵌套代理组排在普通节点前面（不受延迟数值影响）', (tester) async {
    final (widget, container, _) = await _hostWithGroups(
      connected: false,
      groups: const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'Node-X',
          items: [
            // Node-X 有真实延迟（50ms），Sub-Group 没有测速数据（delay: 0）。
            // 旧的"仅按延迟排序"规则会把 0 延迟推到最后；分组类型优先规则下
            // Sub-Group 无论延迟数值如何都应该排在普通节点前面。
            OutboundProxy(tag: 'Node-X', type: 'shadowsocks', delay: 50),
            OutboundProxy(tag: 'Sub-Group', type: 'selector'),
          ],
        ),
      ],
    );
    await container
        .read(proxiesSortProvider.notifier)
        .updateSort(ProxiesSort.delay);

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final subGroupCenter = tester.getCenter(find.text('Sub-Group'));
    final nodeCenter = tester.getCenter(find.text('Node-X'));
    expect(
      subGroupCenter.dy,
      lessThan(nodeCenter.dy),
      reason: '嵌套代理组应该排在普通节点前面，不受延迟数值影响',
    );
  });

  testWidgets('多分组时不显示分组头部，只保留主列表结构', (tester) async {
    final (widget, _, spy) = await _hostWithGroups(
      connected: true,
      groups: [
        const OutboundGroup(
          tag: 'manual',
          type: 'selector',
          selected: 'ss-node',
          items: [OutboundProxy(tag: 'ss-node', type: 'shadowsocks')],
        ),
        const OutboundGroup(
          tag: 'other',
          type: 'selector',
          selected: 'other-node',
          items: [OutboundProxy(tag: 'other-node', type: 'shadowsocks')],
        ),
      ],
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('manual'), findsNothing);
    expect(find.text('other'), findsNothing);
    expect(find.text('ss-node'), findsOneWidget);
    expect(find.text('other-node'), findsNothing);
    expect(spy.urlTestCalls, isEmpty);
    await _drainToasts(tester);
  });
}
