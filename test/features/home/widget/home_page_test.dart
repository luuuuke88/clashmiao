import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/egress_ip/egress_ip_service.dart';
import 'package:clashmiao/core/health/connection_health_monitor.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 手写的假 [HttpClientAdapter]，跟
/// `test/core/egress_ip/egress_ip_service_test.dart` 里的同名类同一个写法——
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

/// 可控的 [ConnectionController] fake：测试代码通过 [emit] 直接把
/// connectionControllerProvider 的状态推到任意 [BoxStatus]，用来精确控制
/// "连接状态切换"发生的时间点——跟 [_FakeAdapter] + `Completer` 控制
/// "查询几时 resolve"配合，才能在 widget 测试里真实复现出口 IP 展示的竞态
/// （连接状态切换 vs. 一次仍在飞行的旧查询，谁先谁后）。
///
/// 继承自真实的 [ConnectionController] 而不是从零实现一个假 notifier——
/// 这样构造函数原有的副作用（比如 `boxServiceProvider` 是 [StubBoxService]
/// 时跳过 watchStatus/watchAlerts 订阅）保持不变，测试只需要像 [_host] 一样
/// 把 `boxServiceProvider` 覆盖成 [StubBoxService]，不需要再额外 mock 任何
/// stream。
class _FakeConnectionController extends ConnectionController {
  _FakeConnectionController(super.ref);

  void emit(BoxStatus status) => state = AsyncData(status);
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
  required BoxStatus status,
  required List<OutboundGroup> groups,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(groups),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Scaffold(body: ConnectionInfoForTest(status: status)),
    ),
  );
}

Future<Widget> _hostFooterStats({required Dio dio}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      egressIpServiceProvider.overrideWith(
        (ref) => EgressIpService(ref, dio: dio),
      ),
    ],
  );
  // monitor 的周期探测定时器挂在 container 上，不 dispose 会留下
  // pending timer 让测试框架报错（也是本来就该有的测试卫生）。
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: const Scaffold(body: FooterStatsForTest()),
    ),
  );
}

/// 跟 [_host] 一样搭一个真实的 HomePage，但额外把
/// [connectionControllerProvider] 换成 [_FakeConnectionController]、把
/// [egressIpServiceProvider] 换成用可控 dio 的实例——用于精确控制"连接状态
/// 切换"和"查询 resolve 时机"两条独立时间线的先后顺序，复现出口 IP 展示的
/// 竞态（见文件末尾"竞态"相关的两个 testWidgets）。返回 [ProviderContainer]
/// 本身而不只是 widget，方便测试代码直接拿到 fake controller 触发状态切换。
Future<(Widget, ProviderContainer)> _hostForEgressRace({
  required ProfileEntity profile,
  required Dio dio,
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
      activeProfileProvider.overrideWith((_) => Future.value(profile)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
      connectionControllerProvider.overrideWith(
        (ref) => _FakeConnectionController(ref),
      ),
      egressIpServiceProvider.overrideWith(
        (ref) => EgressIpService(ref, dio: dio),
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

void main() {
  testWidgets('HomePage renders package version and remote update entry', (
    tester,
  ) async {
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
    expect(find.text('V1.2.3'), findsOneWidget);
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

    expect(find.text('流量使用'), findsOneWidget);
    expect(find.text('实时速度'), findsOneWidget);
    expect(find.text('检测 IP 地址'), findsOneWidget);

    // 三个 tile 排成一行：标签垂直位置一致（同一行），水平从左到右。
    final trafficCenter = tester.getCenter(find.text('流量使用'));
    final speedCenter = tester.getCenter(find.text('实时速度'));
    final ipCenter = tester.getCenter(find.text('检测 IP 地址'));
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

  testWidgets('连接态中间信息保持单行节点和延迟，不显示连接时长', (tester) async {
    await tester.pumpWidget(
      await _hostConnectionInfo(
        status: const BoxStarted(),
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

    expect(find.text('香港 01 | SS'), findsOneWidget);
    expect(find.text('128ms'), findsOneWidget);
    expect(find.textContaining('已连接 '), findsNothing);
  });

  testWidgets('FooterStats 未查询过时展示未知 IP 文案', (tester) async {
    await tester.pumpWidget(await _hostFooterStats(dio: Dio()));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('检测 IP 地址'), findsOneWidget);
    expect(find.text('未知的 IP'), findsOneWidget);
  });

  testWidgets('点击 FooterStats 的 IP tile 触发查询并展示结果（含国旗）', (tester) async {
    final dio = _dioReturning(
      jsonEncode({
        'success': true,
        'ip': '156.243.244.222',
        'country_code': 'JP',
      }),
      200,
    );
    await tester.pumpWidget(await _hostFooterStats(dio: dio));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('未知的 IP'), findsOneWidget);

    await tester.tap(find.text('检测 IP 地址'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('156.243.244.222'), findsOneWidget);
    expect(find.text('未知的 IP'), findsNothing);
  });

  testWidgets('查询失败时点击后仍然展示未知 IP 文案', (tester) async {
    final dio = _dioReturning(
      jsonEncode({'success': false, 'message': 'boom'}),
      200,
    );
    await tester.pumpWidget(await _hostFooterStats(dio: dio));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('检测 IP 地址'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('未知的 IP'), findsOneWidget);
  });

  testWidgets('查询进行中展示加载态（转圈），完成后转圈消失', (tester) async {
    final completer = Completer<ResponseBody>();
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((_) => completer.future);

    await tester.pumpWidget(await _hostFooterStats(dio: dio));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('检测 IP 地址'));
    await tester.pump(); // 只推进一帧：fetch 还没完成，应该已经进入加载态

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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

  testWidgets('断连竞态：断连前发起的旧查询 resolve 时不应覆盖断连后的展示', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final completer = Completer<ResponseBody>();
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((_) => completer.future);

    const profile = ProfileEntity(
      id: 'race-profile-1',
      name: '竞态测试配置',
      url: 'https://example.com/sub',
      active: true,
    );

    final (widget, container) = await _hostForEgressRace(
      profile: profile,
      dio: dio,
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('未知的 IP'), findsOneWidget);

    final controller =
        container.read(connectionControllerProvider.notifier)
            as _FakeConnectionController;

    // 1) 连接成功：HomePage 的 ref.listen 自动发起查询（开关默认开启），
    //    但 fetch 被 completer 卡住，不会立刻 resolve。
    controller.emit(const BoxStarted());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 2) 查询 resolve 之前用户断开连接：ref.listen 应该立即把展示重置为
    //    未知 IP，不等这次仍在飞行的查询。
    controller.emit(const BoxStopped());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('未知的 IP'), findsOneWidget);

    // 3) 断连前发起的旧查询才姗姗来迟地 resolve（带一个连接期间查到的隧道 IP）。
    completer.complete(
      ResponseBody.fromString(
        jsonEncode({'success': true, 'ip': '9.9.9.9', 'country_code': 'JP'}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    // 核心断言：旧结果不应该覆盖断连后的展示——用户已经断开，不该看到一个
    // "看起来仍受保护"的过期隧道 IP。
    expect(find.textContaining('9.9.9.9'), findsNothing);
    expect(find.text('未知的 IP'), findsOneWidget);

    // 收尾：ConnectionButton 连接态渲染时用 flutter_animate 起了几个错开
    // delay（0/1000/2000ms）的涟漪动画，跟本次修复的竞态逻辑无关——纯粹是
    // 让它们在测试结束前触发完，避免测试框架的 "A Timer is still pending"
    // 收尾断言误报。
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('反向竞态：连接后更快的新查询不应被断连前较慢的旧查询事后覆盖', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final oldQueryCompleter = Completer<ResponseBody>();
    var callCount = 0;
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((_) {
      callCount++;
      if (callCount == 1) return oldQueryCompleter.future;
      return Future.value(
        ResponseBody.fromString(
          jsonEncode({'success': true, 'ip': '7.7.7.7', 'country_code': 'US'}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
      );
    });

    const profile = ProfileEntity(
      id: 'race-profile-2',
      name: '竞态测试配置2',
      url: 'https://example.com/sub',
      active: true,
    );

    final (widget, container) = await _hostForEgressRace(
      profile: profile,
      dio: dio,
    );
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 250));

    // 1) 断开态手动点一次（慢——第一次请求被 oldQueryCompleter 卡住）。
    await tester.tap(find.text('检测 IP 地址'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 2) 紧接着连接：ref.listen 重置 + 自动发起第二个新查询（第二次请求，
    //    立刻 resolve，比第一个手动查询快）。
    final controller =
        container.read(connectionControllerProvider.notifier)
            as _FakeConnectionController;
    controller.emit(const BoxStarted());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('7.7.7.7'), findsOneWidget);

    // 3) 断连前那次更旧、更慢的手动查询这才 resolve（一个连接前查到的、
    //    未受保护的真实 ISP IP）。
    oldQueryCompleter.complete(
      ResponseBody.fromString(
        jsonEncode({'success': true, 'ip': '203.0.113.5'}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    // 核心断言：旧的、较慢的查询不应该把新连接查到的隧道 IP 覆盖回去——
    // 用户已经连接，不该看到一个未受保护的 IP。
    expect(find.textContaining('203.0.113.5'), findsNothing);
    expect(find.textContaining('7.7.7.7'), findsOneWidget);

    // 收尾：同上一个测试，让 ConnectionButton 连接态的涟漪动画触发完再结束。
    await tester.pump(const Duration(seconds: 3));
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
/// `test/core/health/connection_health_monitor_test.dart` 覆盖）。
class _FixedHealthMonitor extends ConnectionHealthMonitor {
  _FixedHealthMonitor(super.ref, ConnectionHealth health) {
    state = health;
  }

  @override
  void start() {} // 不起定时器：渲染一个 widget 不该启动后台任务
}
