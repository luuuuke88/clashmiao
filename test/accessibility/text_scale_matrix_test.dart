import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/about/presentation/about_page.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../support/fake_box_service.dart';
import '../support/known_overflow.dart';

/// 文字缩放 × 窄屏 × 方向 的无障碍矩阵（规格 §9）。
///
/// - 缩放：1.3×、2.0×；宽度：320 dp；方向：LTR（简中）与 RTL（阿拉伯语）。
/// - 页面：首页、代理页、设置页、快速设置、关于页。
/// - 断言：不溢出（不允许用 FittedBox 缩小字号来过测）、
///   `androidTapTargetGuideline` 与 `labeledTapTargetGuideline` 通过。
///
/// ## 首页的已知项
///
/// 首页连接区（`ConnectionButton`、`_ModeSelector`）正在被重写、本期不得触碰，
/// 它们在 2.0× 下的溢出与 38 dp 的分段控件触控区是**已知**的：
/// - 溢出按 RenderFlex 创建者链精确识别，只放行这两类；其它任何溢出都让测试失败。
/// - 触控目标 / 标签两条 guideline 对首页「有订阅」场景只放行点名的连接区节点
///   （连接按钮、两个模式分段）；首页页头与订阅卡片的违规一律失败。
/// - 另有「无订阅」场景（页头 + 空态，没有连接区）整页完整通过两条 guideline。
/// 连接区被重写之后删掉对应的放行项即可，不要放宽过滤。

const _profile = ProfileEntity(
  id: 'p1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
  subInfo: SubscriptionInfo(upload: 1024, download: 2048, total: 4096),
);

const _scales = [1.3, 2.0];

/// 首页「有订阅」场景下连接区的已知溢出，按 (缩放, 方向/语言) 逐场景列出，
/// 每项带该场景在 320 dp 宽下**实测的溢出量基线**（容差见 [KnownOverflow]）。
/// 来自对连接区现状的实测；连接区重写后整张表应当清空。
final _homeKnownOverflows = <(double, TextDirection), List<KnownOverflow>>{
  (1.3, TextDirection.ltr): [connectionButtonOverflow.at(5.5)],
  (1.3, TextDirection.rtl): [modeSelectorOverflow.at(135)],
  (2.0, TextDirection.ltr): [
    connectionButtonOverflow.at(28),
    modeSelectorOverflow.at(22),
  ],
  (2.0, TextDirection.rtl): [modeSelectorOverflow.at(308)],
};

/// (名称, 语言, 方向)：LTR 用简中，RTL 用阿拉伯语（真实的 RTL 文案与长度）。
const _variants = <(String, String, TextDirection)>[
  ('LTR', 'zhCn', TextDirection.ltr),
  ('RTL', 'ar', TextDirection.rtl),
];

/// 一个被测页面：怎样搭 provider 覆盖与根 widget。
class _Page {
  const _Page(this.name, this.build, {this.overrides = _noOverrides});

  final String name;
  final Widget Function() build;
  final List<Override> Function() overrides;
}

List<Override> _noOverrides() => const [];

Future<Widget> _host(
  _Page page, {
  required String locale,
  required TextDirection direction,
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': locale,
    'clashmiao_set_system_proxy': true,
    'clashmiao_enable_tun': false,
  });
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
      ...page.overrides(),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          // 水波纹 shader 在测试引擎里不可用（见 settings_page_test 的说明）。
          splashFactory: NoSplash.splashFactory,
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: page.build(),
      ),
    ),
  );
}

final _homeWithProfile = _Page(
  '首页（有订阅）',
  () => const HomePage(),
  overrides: () => [
    activeProfileProvider.overrideWith((_) => Future.value(_profile)),
    outboundGroupsProvider.overrideWith(
      (_) => Stream<List<OutboundGroup>>.value(const []),
    ),
  ],
);

final _homeEmpty = _Page(
  '首页（无订阅）',
  () => const HomePage(),
  overrides: () => [
    activeProfileProvider.overrideWith((_) => Future.value(null)),
    profileListProvider.overrideWith((_) => Future.value(const [])),
    outboundGroupsProvider.overrideWith(
      (_) => Stream<List<OutboundGroup>>.value(const []),
    ),
  ],
);

final _proxies = _Page(
  '代理页',
  () => const ProxiesPage(),
  overrides: () => [
    activeProfileProvider.overrideWith((_) async => _profile),
    boxServiceProvider.overrideWithValue(const FakeBoxService()),
    isConnectedProvider.overrideWith((_) => false),
    offlineProxyGroupsProvider.overrideWith(
      (_) async => const [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'Singapore 02',
          items: [
            OutboundProxy(tag: 'auto-group', type: 'urltest'),
            OutboundProxy(
              tag: '🇭🇰 香港 01 | 一个相当长的节点名称用来换行',
              type: 'shadowsocks',
            ),
            OutboundProxy(tag: 'Singapore 02', type: 'vless'),
            OutboundProxy(tag: 'Tokyo 03', type: 'trojan'),
          ],
        ),
      ],
    ),
  ],
);

final _settings = _Page('设置页', () => const SettingsPage(debugIsAndroid: true));

final _quickSettings = _Page(
  '快速设置',
  () =>
      const Scaffold(body: SingleChildScrollView(child: QuickSettingsModal())),
);

final _about = _Page('关于页', () => const AboutPage());

void _useView(WidgetTester tester, {required double height, double scale = 1}) {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 首页「有订阅」场景里放行的连接区节点：两个模式分段（高 32–38 dp，连接区
/// 重写时一并扩到 48 dp）。只按语义标签**精确**放行；页头、订阅卡片、连接按钮
/// 的违规一律不在此列。
const _knownModeSegmentLabels = {'全局代理', '智能分流', 'بروكسي عام', 'توجيه ذكي'};

/// 把 guideline 报告里的违规节点逐条取出（去掉 `See also` 说明行与空行）。
List<String> _violations(String? reason) => reason == null
    ? const []
    : reason
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('See also'))
          .toList();

bool _isKnownModeSegment(String violation) {
  final label = RegExp(r'label: "([^"]*)"').firstMatch(violation)?.group(1);
  return label != null && _knownModeSegmentLabels.contains(label);
}

void main() {
  const mockedChannel = MethodChannel('com.clashmiao.app/platform');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mockedChannel, (call) async {
          if (call.method == 'is_ignoring_battery_optimizations') return false;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mockedChannel, null);
  });

  final pages = [
    _homeWithProfile,
    _homeEmpty,
    _proxies,
    _settings,
    _quickSettings,
    _about,
  ];

  for (final page in pages) {
    for (final scale in _scales) {
      for (final (dirName, locale, direction) in _variants) {
        testWidgets('${page.name} / 320 dp / $scale× / $dirName：不溢出，'
            '触控目标与标签 guideline', (tester) async {
          // 视口足够高，让整页内容都被构建出来（懒加载列表也一次建完）。
          _useView(tester, height: 4000, scale: scale);
          final handle = tester.ensureSemantics();

          final isHomeWithProfile = identical(page, _homeWithProfile);
          // 只有首页「有订阅」场景有已知溢出（连接区），且按 (缩放, 方向)
          // 逐场景列出、每项恰好一次；其它页面一处都不许有。
          final expected = isHomeWithProfile
              ? _homeKnownOverflows[(scale, direction)]!
              : const <KnownOverflow>[];
          final seen = await runAllowingKnownOverflows(expected, () async {
            await tester.pumpWidget(
              await _host(page, locale: locale, direction: direction),
            );
            await _settle(tester);
          });
          expect(
            seen,
            unorderedEquals(expected.map((k) => k.name)),
            reason: '${page.name} 的已知溢出应各出现恰好一次',
          );
          expect(tester.takeException(), isNull);

          // 触控目标 + 标签。
          for (final guideline in [
            androidTapTargetGuideline,
            labeledTapTargetGuideline,
          ]) {
            if (!isHomeWithProfile) {
              await expectLater(tester, meetsGuideline(guideline));
            } else {
              final result = await guideline.evaluate(tester);
              final offending = _violations(
                result.reason,
              ).where((v) => !_isKnownModeSegment(v)).toList();
              expect(
                offending,
                isEmpty,
                reason: '首页非连接区违规（${guideline.description}）',
              );
            }
          }
          handle.dispose();
        });
      }
    }
  }

  // 可滚动：窄屏 + 2.0× 时内容比视口高，且能滚到底。
  for (final page in [_settings, _about]) {
    testWidgets('${page.name} / 320×640 / 2.0×：内容比视口高且可滚动到底', (tester) async {
      _useView(tester, height: 640, scale: 2.0);
      await tester.pumpWidget(
        await _host(page, locale: 'zhCn', direction: TextDirection.ltr),
      );
      await _settle(tester);

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0), reason: '2.0× 下内容应超出视口');
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pump();
      expect(position.pixels, greaterThan(0), reason: '手势应当真的滚动页面');
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
