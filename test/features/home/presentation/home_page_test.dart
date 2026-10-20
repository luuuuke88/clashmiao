import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/presentation/connection_button.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/latency_test_coordinator.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:clashmiao/shared/components/frosted_disc.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_connection_controller.dart';
import '../../../support/profile_store_support.dart';

/// 手写的假 [HttpClientAdapter]，跟
/// `test/domain/connection/application/egress_ip_service_test.dart` 里的同名类同一个写法——
/// 两个测试文件各自独立、自包含（跟这个仓库里其他测试文件的既有风格一致），
/// 没有抽共享 test helper。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _handler(options);

  @override
  void close({bool force = false}) {}
}

Dio _dioReturning(String body, int statusCode) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter((_) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  });
  return dio;
}

Future<Widget> _host(ProfileEntity profile) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const HomePage(),
      ),
    ),
  );
}

/// 跟 [_host] 一样搭一个真实的 HomePage，但额外返回 [ProviderContainer]，
/// 方便测试代码直接读写 provider（比如手动触发
/// [configChangeReconnectNoticeProvider] 来模拟"配置变更触发自动重连"）。
Future<(Widget, ProviderContainer)> _hostWithContainer(
  ProfileEntity profile,
) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  final widget = UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const HomePage(),
      ),
    ),
  );
  return (widget, container);
}

Future<Widget> _hostWithProfiles({
  required ProfileEntity? activeProfile,
  required List<ProfileEntity> profiles,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      activeProfileProvider.overrideWith((_) => Future.value(activeProfile)),
      profileListProvider.overrideWith((_) => Future.value(profiles)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  await container.read(profileListProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const HomePage(),
      ),
    ),
  );
}

Future<Widget> _hostConnectionInfo({
  required ConnectionPhase phase,
  ValueListenable<ConnectionPhase>? phaseListenable,
  required List<OutboundGroup> groups,
  void Function(ProviderContainer)? onContainer,
  Future<List<Override>> Function(SharedPreferences prefs)? extraOverrides,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final extra = await extraOverrides?.call(prefs) ?? const <Override>[];
  final container = ProviderContainer(
    overrides: [
      ...extra,
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(groups),
      ),
      // 节点胶囊的延迟读测速协调器，协调器跟着连接阶段走：给它同一个阶段。
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(
        (ref) => FakeConnectionController(ref, phase: phase),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  onContainer?.call(container);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Scaffold(
        body: phaseListenable == null
            ? ConnectionInfoForTest(phase: phase)
            : ValueListenableBuilder<ConnectionPhase>(
                valueListenable: phaseListenable,
                builder: (_, p, _) => ConnectionInfoForTest(phase: p),
              ),
      ),
    ),
  );
}

/// 已连接时测速协调器会排 2 s 预热、10 s 测速超时：把假时钟推过去，让定时器
/// 自然跑完（与代理页测试同一做法）。
Future<void> _drainLatency(WidgetTester tester) =>
    tester.pump(kLatencyWarmupDelay + kLatencyRoundTimeout);

/// [phase] 决定出口 IP 探测是否有意义（只有已连接才查）；[autoCheck] 对应设置页
/// 「自动检查 IP」开关，默认关，让测试自己决定何时触发查询。
Future<(Widget, ProviderContainer)> _hostFooterStats({
  required Dio dio,
  ConnectionPhase phase = ConnectionPhase.disconnected,
  bool autoCheck = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    'clashmiao_auto_ip_check': autoCheck,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(
        (ref) => FakeConnectionController(ref, phase: phase),
      ),
      egressProbeServiceProvider.overrideWith(
        (ref) => EgressIpService(ref, dio: dio),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  // 探测器随 App 创建（见 main.dart）；测试里同样先建出来再渲染。
  container.read(egressIpProbeProvider);
  final widget = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: const Scaffold(body: FooterStatsForTest()),
    ),
  );
  return (widget, container);
}

void main() {
  testWidgets('HomePage 页头不再带版本号，保留远程订阅更新入口与页头按钮提示', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = ProfileEntity(
      id: 'remote-profile',
      name: 'ClashMiao Pro',
      url: 'https://example.com/sub',
      active: true,
      subInfo: SubscriptionInfo(
        upload: 1024,
        download: 2048,
        total: 4096,
        expire: DateTime(2026, 12, 31),
      ),
    );

    await tester.pumpWidget(await _host(profile));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ClashMiao'), findsWidgets);
    // 版本号已从首页页头移除（「关于」页里有）。
    expect(find.text('V1.2.3'), findsNothing);
    expect(find.textContaining('1.2.3'), findsNothing);
    // 页头两颗圆按钮的提示走 i18n（简中）。
    expect(find.byTooltip('快速设置'), findsOneWidget);
    expect(find.byTooltip('新的配置文件'), findsOneWidget);
    expect(find.text('ClashMiao Pro'), findsOneWidget);
    expect(find.byTooltip('更新配置文件'), findsOneWidget);
  });

  testWidgets('宽屏（≥840）首页仍展示三个统计 tile，且排成一行', (tester) async {
    // 宽屏分支（width ≥ 840）实际只有真机横屏 / 平板才会触发——桌面窗口被
    // 锁死在 420 宽、不可缩放，永远走窄屏。历史上这里整段 `if (isCompact)`
    // 把流量 / 速度 / 检测 IP 三个 tile 一起隐藏，宽屏下什么都不剩；本测试
    // 钉住"宽屏也要展示这三个 tile，并且排成一行"这个行为。
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final profile = ProfileEntity(
      id: 'wide-profile',
      name: 'ClashMiao Pro',
      url: 'https://example.com/sub',
      active: true,
      subInfo: SubscriptionInfo(
        upload: 1024,
        download: 2048,
        total: 4096,
        expire: DateTime(2026, 12, 31),
      ),
    );

    await tester.pumpWidget(await _host(profile));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('本次流量'), findsOneWidget);
    expect(find.text('下载速度'), findsOneWidget);
    expect(find.text('出口 IP'), findsOneWidget);

    // 三个 tile 排成一行：标签垂直位置一致（同一行），水平从左到右。
    final trafficCenter = tester.getCenter(find.text('本次流量'));
    final speedCenter = tester.getCenter(find.text('下载速度'));
    final ipCenter = tester.getCenter(find.text('出口 IP'));
    expect(speedCenter.dy, closeTo(trafficCenter.dy, 1.0));
    expect(ipCenter.dy, closeTo(trafficCenter.dy, 1.0));
    expect(trafficCenter.dx, lessThan(speedCenter.dx));
    expect(speedCenter.dx, lessThan(ipCenter.dx));
  });

  testWidgets('HomePage 无配置时渲染新增配置空态', (tester) async {
    await tester.pumpWidget(
      await _hostWithProfiles(activeProfile: null, profiles: const []),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('还没有线路喵'), findsOneWidget);
    expect(find.text('点击下方按钮开始探索'), findsOneWidget);
    expect(find.text('新的配置文件'), findsOneWidget);
    expect(find.text('未选择配置文件'), findsNothing);
    expect(find.byType(BrandMark), findsOneWidget);
    final brand = tester.widget<BrandMark>(find.byType(BrandMark));
    expect(brand.variant, BrandMarkVariant.transparent);
  });

  testWidgets('HomePage 空态的品牌标记压在不透明底盘上（白猫不会消失在浅色背景里）', (tester) async {
    await tester.pumpWidget(
      await _hostWithProfiles(activeProfile: null, profiles: const []),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final disc = tester.widget<FrostedDisc>(
      find.byKey(const ValueKey('empty_brand_disc')),
    );
    expect(
      disc.tintAlpha,
      greaterThanOrEqualTo(0.5),
      reason: '磨砂玻璃的染色不能再淡了，否则白色标记又会跟浅色背景糊在一起',
    );
  });

  testWidgets('HomePage 有配置但无激活配置时渲染未选择空态', (tester) async {
    const profile = ProfileEntity(
      id: 'profile-1',
      name: '备用配置',
      url: 'https://example.com/sub',
      active: false,
    );

    await tester.pumpWidget(
      await _hostWithProfiles(activeProfile: null, profiles: [profile]),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('未选择配置文件'), findsOneWidget);
    expect(find.text('选择配置文件'), findsOneWidget);
    expect(find.text('配置文件'), findsOneWidget);
    expect(find.text('还没有线路喵'), findsNothing);
  });

  testWidgets('节点胶囊与代理页同一套展示名：去掉 § 后缀，推断出的旗帜放在名称前（真机 BUG-6）', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'select',
            type: 'selector',
            selected: 'ThrowawayQA § 0',
            items: [OutboundProxy(tag: 'ThrowawayQA § 0', type: 'shadowsocks')],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('ThrowawayQA'), findsOneWidget);
    expect(find.textContaining('§'), findsNothing);

    await _drainLatency(tester);
  });

  // 真机验收 BUG-C：默认选中自动选择组、内核没推自动选择组本身时，胶囊曾显示
  // 原始 tag「auto」。
  testWidgets('默认选中自动选择组：胶囊显示「自动选择」，不显示原始 tag auto', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'select',
            type: 'selector',
            selected: 'auto',
            items: [
              OutboundProxy(tag: 'auto', type: 'urltest'),
              OutboundProxy(tag: 'shadowsocks § 0', type: 'shadowsocks'),
            ],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('自动选择'), findsOneWidget);
    expect(find.text('auto'), findsNothing);

    await _drainLatency(tester);
  });

  testWidgets('自动选择组报了选中的节点：胶囊显示「自动选择 · 节点名」', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'select',
            type: 'selector',
            selected: 'auto',
            items: [
              OutboundProxy(tag: 'auto', type: 'urltest'),
              OutboundProxy(tag: 'ThrowawayQA § 0', type: 'shadowsocks'),
            ],
          ),
          OutboundGroup(
            tag: 'auto',
            type: 'urltest',
            selected: 'ThrowawayQA § 0',
            items: [OutboundProxy(tag: 'ThrowawayQA § 0', type: 'shadowsocks')],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('自动选择 · ThrowawayQA'), findsOneWidget);

    await _drainLatency(tester);
  });

  testWidgets('连接态中间信息保持单行节点和延迟，不显示连接时长', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: '香港 01 | SS',
            items: [
              OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks', delay: 128),
            ],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('🇭🇰 香港 01 | SS'), findsOneWidget);
    expect(find.text('128ms'), findsOneWidget);
    expect(find.textContaining('已连接 '), findsNothing);

    await _drainLatency(tester);
  });

  testWidgets('节点胶囊的延迟用共用延迟标签：成功/占位，且不再有 Wi-Fi 图标', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: '香港 01 | SS',
            items: [
              OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks', delay: 128),
            ],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final label = tester.widget<LatencyLabel>(find.byType(LatencyLabel));
    expect(label.state, LatencyDisplayState.success);
    expect(label.ms, 128);
    expect(find.byIcon(FluentIcons.wifi_1_24_filled), findsNothing);

    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: '香港 01 | SS',
            items: [OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks')],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<LatencyLabel>(find.byType(LatencyLabel)).state,
      LatencyDisplayState.untested,
    );

    await _drainLatency(tester);
  });

  // 与代理页同一套 resolveNodeLatency：只有离线兜底分组时缓存可以顶上（历史值），
  // 有真实实时分组时实时值缺席不拿缓存冒充（cacheIsFallback 接线两个方向）。
  for (final live in [false, true]) {
    testWidgets(
      '节点胶囊与代理页同一套延迟规则：${live ? '实时分组在、实时值缺席 → 不拿缓存冒充' : '只有离线兜底分组 → 显示缓存的历史值'}',
      (tester) async {
        const group = OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: '香港 01 | SS',
          items: [OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks')],
        );
        late ProviderContainer container;
        await tester.pumpWidget(
          await _hostConnectionInfo(
            phase: ConnectionPhase.connected,
            groups: live ? const [group] : const [],
            onContainer: (c) => container = c,
            // 延迟缓存按订阅分区、写入经 ProfileStore 校验：给一个真实的激活订阅。
            extraOverrides: (prefs) async {
              const profile = ProfileEntity(
                id: 'p1',
                name: 'p1',
                url: 'https://example.com/p1',
                active: true,
              );
              final store = await seededProfileStore(prefs, [profile]);
              return [
                profileStoreProvider.overrideWith((_) => Future.value(store)),
                activeProfileProvider.overrideWith(
                  (_) => Future.value(profile),
                ),
                offlineProxyGroupsProvider.overrideWith(
                  (_) async => const [group],
                ),
              ];
            },
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        container.read(proxyDelayCacheProvider.notifier).recordMeasured({
          '香港 01 | SS': 222,
        }, at: DateTime.now().subtract(const Duration(hours: 1)));
        await tester.pump(const Duration(milliseconds: 250));

        final label = tester.widget<LatencyLabel>(find.byType(LatencyLabel));
        if (live) {
          expect(label.state, LatencyDisplayState.untested);
          expect(label.ms, isNull);
        } else {
          expect(label.state, LatencyDisplayState.stale);
          expect(label.ms, 222);
        }

        await _drainLatency(tester);
      },
    );
  }

  testWidgets('节点行看得出能点：带箭头，点了跳到线路页', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: '香港 01 | SS',
            items: [
              OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks', delay: 128),
            ],
          ),
        ],
        onContainer: (c) => container = c,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(FluentIcons.chevron_right_16_regular), findsOneWidget);
    expect(container.read(selectedTabProvider), AppTab.home);

    await tester.tap(find.text('🇭🇰 香港 01 | SS'));
    await tester.pump();

    expect(container.read(selectedTabProvider), AppTab.proxies);

    await _drainLatency(tester);
  });

  testWidgets('节点区：过渡期留白（加载指示在连接按钮上），已连接才出现节点胶囊；高度恒为 48', (tester) async {
    for (final phase in [
      ConnectionPhase.disconnected,
      ConnectionPhase.connecting,
      ConnectionPhase.disconnecting,
      ConnectionPhase.reconnecting,
    ]) {
      await tester.pumpWidget(
        await _hostConnectionInfo(phase: phase, groups: const []),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Connecting...'), findsNothing);
      expect(find.text('正在连接'), findsNothing, reason: '$phase：文字属于连接按钮，节点区不重复');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.getSize(find.byType(ConnectionInfoForTest)).height,
        48,
        reason: '$phase：节点区高度固定，状态切换页面不跳动',
      );
    }

    await tester.pumpWidget(
      await _hostConnectionInfo(
        phase: ConnectionPhase.connected,
        groups: const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: '香港 01 | SS',
            items: [OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks')],
          ),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Checking'), findsNothing);
    expect(find.text('—'), findsOneWidget, reason: '延迟未知显示破折号，不是 Checking');
    expect(tester.getSize(find.byType(ConnectionInfoForTest)).height, 48);

    await _drainLatency(tester);
  });

  testWidgets('节点区出现 / 消失是 150–200 ms 的淡入淡出，没有弹性高度（easeOutBack）', (
    tester,
  ) async {
    const groups = [
      OutboundGroup(
        tag: 'proxy',
        type: 'selector',
        selected: 'A',
        items: [OutboundProxy(tag: 'A', type: 'shadowsocks', delay: 10)],
      ),
    ];
    // 同一个宿主里把 phase 从 disconnected 切到 connected：用 StatefulBuilder 驱动。
    final phase = ValueNotifier(ConnectionPhase.disconnected);
    addTearDown(phase.dispose);
    final host = await _hostConnectionInfo(
      phase: ConnectionPhase.disconnected,
      groups: groups,
      phaseListenable: phase,
    );
    await tester.pumpWidget(host);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('A'), findsNothing);

    phase.value = ConnectionPhase.connected;
    await tester.pump();
    // 每一帧高度都是 48，不会因为动画弹性伸缩。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getSize(find.byType(ConnectionInfoForTest)).height, 48);
    }
    expect(find.text('A'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    // 淡入淡出（不是位移 / 缩放）：动画结束后旧子树已移除，只剩一个节点胶囊。
    expect(find.text('A'), findsOneWidget);
  });

  group('出口 IP 卡：五种内容（UI 设计 §1）', () {
    testWidgets('未连接：「连接后显示出口 IP」，整卡不可点、没有刷新图标，点了也不查询', (tester) async {
      var requests = 0;
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((_) {
        requests++;
        return Future.value(ResponseBody.fromString('{}', 200));
      });
      final (widget, _) = await _hostFooterStats(dio: dio);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('出口 IP'), findsOneWidget);
      expect(find.text('连接后显示出口 IP'), findsOneWidget);
      expect(find.text('未知的 IP'), findsNothing, reason: '不再出现「未知的 IP」');
      expect(find.byIcon(FluentIcons.arrow_sync_24_regular), findsNothing);

      await tester.tap(find.text('出口 IP'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(requests, 0, reason: '没连接时不会去查：那只是设备自己的 IP');
    });

    testWidgets('已连接且自动检测关闭：「点击检测出口 IP」，点击后查询并展示完整 IP（含国旗）', (tester) async {
      final dio = _dioReturning(
        jsonEncode({
          'success': true,
          'ip': '156.243.244.222',
          'country_code': 'JP',
        }),
        200,
      );
      final (widget, _) = await _hostFooterStats(
        dio: dio,
        phase: ConnectionPhase.connected,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('点击检测出口 IP'), findsOneWidget);
      expect(find.byIcon(FluentIcons.arrow_sync_24_regular), findsOneWidget);

      await tester.tap(find.text('出口 IP'));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('156.243.244.222'), findsOneWidget);
      expect(find.text('点击检测出口 IP'), findsNothing);
    });

    testWidgets('已连接且自动检测开启：不用点击，连上后自动查出出口 IP', (tester) async {
      final dio = _dioReturning(
        jsonEncode({
          'success': true,
          'ip': '198.51.100.9',
          'country_code': 'US',
        }),
        200,
      );
      final (widget, _) = await _hostFooterStats(
        dio: dio,
        phase: ConnectionPhase.connected,
        autoCheck: true,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.textContaining('198.51.100.9'), findsOneWidget);
    });

    testWidgets('查询中：「正在检测…」+ 转圈，不显示「未知的 IP」；完成后转圈消失', (tester) async {
      final completer = Completer<ResponseBody>();
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((_) => completer.future);

      final (widget, _) = await _hostFooterStats(
        dio: dio,
        phase: ConnectionPhase.connected,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('出口 IP'));
      await tester.pump(); // 只推进一帧：fetch 还没完成，应该已经进入加载态

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('正在检测…'), findsOneWidget);
      expect(find.text('未知的 IP'), findsNothing, reason: '加载期间不显示「未知的 IP」');

      completer.complete(
        ResponseBody.fromString(
          jsonEncode({'success': true, 'ip': '1.2.3.4'}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('1.2.3.4'), findsOneWidget);
    });

    testWidgets('全部尝试失败：「检测失败，点击重试」，可再点一次', (tester) async {
      var requests = 0;
      final dio = Dio();
      dio.httpClientAdapter = _FakeAdapter((_) {
        requests++;
        return Future.value(
          ResponseBody.fromString(
            jsonEncode({'success': false, 'message': 'boom'}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
      });
      final (widget, _) = await _hostFooterStats(
        dio: dio,
        phase: ConnectionPhase.connected,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(find.text('出口 IP'));
      await tester.pump(const Duration(seconds: 25));

      expect(find.text('检测失败，点击重试'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(requests, 4, reason: '串行最多 4 次');

      await tester.tap(find.text('出口 IP'));
      await tester.pump();
      expect(find.text('正在检测…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 25));
    });

    testWidgets('完整 IPv6 允许换行，不用省略号截断', (tester) async {
      const ipv6 = '2001:0db8:85a3:0000:0000:8a2e:0370:7334';
      final dio = _dioReturning(
        jsonEncode({'success': true, 'ip': ipv6, 'country_code': 'JP'}),
        200,
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (widget, _) = await _hostFooterStats(
        dio: dio,
        phase: ConnectionPhase.connected,
        autoCheck: true,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 250));

      final text = tester.widget<Text>(
        find.byKey(const ValueKey('egress-ip-value')),
      );
      expect(text.data, contains(ipv6));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('配置变更触发的自动重连应该弹一条轻提示，而不是纯静默', (tester) async {
    const profile = ProfileEntity(
      id: 'notice-profile',
      name: '提示测试配置',
      url: 'https://example.com/sub',
      active: true,
    );
    final (widget, container) = await _hostWithContainer(profile);

    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('重新连接以使更改生效'), findsNothing);

    // 模拟 ConnectionController 检测到"配置变更触发的自动重连"
    // （configChangeReconnectNoticeProvider 是它和 HomePage 之间唯一的信号）。
    container.read(configChangeReconnectNoticeProvider.notifier).state++;
    // toastification 首次弹出时，实际的 toast item 要等 overlay entry 创建完
    // 之后再延迟 100ms 才插入动画列表（见 ToastificationManager
    // `_createOverlayDelay`），这里 pump 超过这个延迟才能让文字真正出现。
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('重新连接以使更改生效'), findsOneWidget);

    // 收尾：drain toast 的 auto-close timer，避免 "A Timer is still pending"。
    await tester.pump(const Duration(seconds: 6));
    toastification.dismissAll(delayForAnimation: false);
    await tester.pump(const Duration(milliseconds: 500));
  });

  // ===========================================================
  // 桌面端 libcore 加载失败会被 `BoxService` 工厂 catch 住、静默降级成桩实现。
  // 修复前这个状态在界面上完全不可见：首页照常渲染连接按钮，用户点了没反应
  // 也没有任何解释。这两个测试锁定"真故障必须可见"和"测试替身不能误报"
  // 这两条互相制衡的行为。
  // ===========================================================
  group('核心库加载失败时首页给出阻断提示', () {
    Future<Widget> hostWithService(StubBoxService service) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      PackageInfo.setMockInitialValues(
        appName: 'ClashMiao',
        packageName: 'com.clashmiao.app',
        version: '1.2.3',
        buildNumber: '45',
        buildSignature: '',
      );
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(service),
          activeProfileProvider.overrideWith((_) => Future.value(null)),
          outboundGroupsProvider.overrideWith(
            (_) => Stream<List<OutboundGroup>>.value(const []),
          ),
        ],
      );
      // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
      // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      return UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: const HomePage(),
          ),
        ),
      );
    }

    testWidgets('coreLoadFailed 时显示阻断文案，而不是一个点了没反应的连接按钮', (tester) async {
      await tester.pumpWidget(
        await hostWithService(
          const StubBoxService(reason: StubReason.coreLoadFailed),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('未找到核心库'), findsOneWidget);
      expect(
        find.byType(ConnectionButton),
        findsNothing,
        reason: '核心库都没有，不该再给用户一个必定无效的连接按钮',
      );
    });

    testWidgets('默认 StubBoxService（测试替身/平台不支持）不得误报核心库缺失', (tester) async {
      await tester.pumpWidget(await hostWithService(const StubBoxService()));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.text('未找到核心库'),
        findsNothing,
        reason: '大量既有 widget 测试把桩实现当替身用，按类型判断会让它们全部误报',
      );
    });
  });

  // ===========================================================
  // "已连接但实际不通"（黑洞）此前在界面上完全没有反馈：内核报 BoxStarted
  // 之后 UI 就一直显示已连接，哪怕整机流量早已被黑洞掉。
  // ===========================================================
  group('黑洞告警条', () {
    Future<Widget> hostWithHealth(ConnectionHealth health) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      PackageInfo.setMockInitialValues(
        appName: 'ClashMiao',
        packageName: 'com.clashmiao.app',
        version: '1.2.3',
        buildNumber: '45',
        buildSignature: '',
      );
      final prefs = await SharedPreferences.getInstance();
      const profile = ProfileEntity(
        id: 'health-profile',
        name: '健康度测试',
        url: 'https://example.com/sub',
        active: true,
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(const StubBoxService()),
          activeProfileProvider.overrideWith((_) => Future.value(profile)),
          outboundGroupsProvider.overrideWith(
            (_) => Stream<List<OutboundGroup>>.value(const []),
          ),
          connectionHealthProvider.overrideWith(
            (ref) => _FixedHealthMonitor(ref, health),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);
      return UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: const HomePage(),
          ),
        ),
      );
    }

    testWidgets('degraded 时明确告诉用户"已连接但无法访问网络"', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await hostWithHealth(ConnectionHealth.degraded));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('已连接，但无法访问网络'), findsOneWidget);
      expect(find.text('重新检测'), findsOneWidget);
    });

    testWidgets('healthy 时不显示告警条（不能误报）', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await hostWithHealth(ConnectionHealth.healthy));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('已连接，但无法访问网络'), findsNothing);
    });
  });
}

/// 把健康度钉死在某个值的 monitor，让 widget 测试能独立验证渲染，
/// 不用去真的跑一遍探测流程（探测逻辑本身由
/// `test/domain/connection/application/connection_health_monitor_test.dart` 覆盖）。
class _FixedHealthMonitor extends ConnectionHealthMonitor {
  _FixedHealthMonitor(super.ref, ConnectionHealth health) {
    state = health;
  }

  @override
  void start() {} // 不起定时器：渲染一个 widget 不该启动后台任务
}
