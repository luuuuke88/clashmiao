import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/region/region_detection_service.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/onboarding/widget/onboarding_page.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 假的地区识别服务：不发任何网络请求、不碰真实时区平台通道，直接返回预置的
/// 国家码（或者 `null` 表示"识别不到"）。默认（[_host] 不传 `regionResult`
/// 时）用 `null`，让已有的 5 个 smoke 测试维持"什么都没识别到、region/locale
/// 保持初始默认值"的既有行为，不因为新增的自动识别钩子产生任何副作用。
class _FakeRegionDetectionService extends RegionDetectionService {
  _FakeRegionDetectionService(this._result);

  final String? _result;

  @override
  Future<String?> detectCountryCode() async => _result;
}

Future<(Widget, SharedPreferences)> _host({
  Map<String, Object> prefs = const {'locale': 'zhCn'},
  String? regionDetectionResult,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(sp)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      regionDetectionServiceProvider.overrideWithValue(
        _FakeRegionDetectionService(regionDetectionResult),
      ),
    ],
  );
  await container.read(sharedPreferencesProvider.future);

  final widget = UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const OnboardingPage(),
      ),
    ),
  );
  return (widget, sp);
}

void main() {
  group('OnboardingPage smoke', () {
    testWidgets('渲染单页入口结构', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.text('语言'), findsOneWidget);
      expect(find.text('地区'), findsOneWidget);
      expect(find.text('启用分析'), findsOneWidget);
      expect(find.textContaining('继续即表示您同意'), findsOneWidget);
      expect(find.text('开始'), findsOneWidget);
      expect(find.text('代理模式'), findsNothing);
      expect(find.text('添加订阅'), findsNothing);
    });

    testWidgets('语言入口打开选择面板', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('语言'));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('简体中文'), findsWidgets);
    });

    testWidgets('地区入口打开选择面板', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('地区'));
      await tester.pumpAndSettle();

      expect(find.text('中国 (cn)'), findsOneWidget);
      expect(find.text('其它'), findsWidgets);
    });

    testWidgets('分析开关写入偏好', (tester) async {
      final (widget, prefs) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getBool('clashmiao_analytics_enabled'), isNull);
      await tester.tap(find.text('启用分析'));
      await tester.pumpAndSettle();

      expect(prefs.getBool('clashmiao_analytics_enabled'), isTrue);
    });

    // 此前是私有的 _IntroSwitchTile（独立卡片样式），跟 settings_page.dart
    // 私有的 _BoolPreferenceTile（强调色图标 + 单行样式）视觉不一致——两处
    // 控制的却是同一个持久化偏好 clashmiao_analytics_enabled。现在两处都改用
    // 共享的 AnalyticsToggleTile（跟 settings_page_test.dart 的对应断言呼应，
    // 一起证明两个页面渲染的是同一个组件类型）。
    testWidgets('分析开关用共享的 AnalyticsToggleTile 渲染', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(find.byType(AnalyticsToggleTile), findsOneWidget);
    });

    testWidgets('开始使用写入 onboarding 完成标记', (tester) async {
      final (widget, prefs) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(prefs.getBool('onboarding_done'), isTrue);
    });
  });

  group('OnboardingPage 首帧地区自动识别', () {
    testWidgets('初始默认态（region=other 且 onboarding 未完成）识别成功后写入 region+locale', (
      tester,
    ) async {
      // 初始 prefs 故意不设 clashmiao_region/onboarding_done，落在
      // network_settings.dart 的默认值 region='other' + onboarding 未完成，
      // 即 shouldAutoDetectRegion 判定为"应该自动识别"的那个状态。locale 种子
      // 用 zhCn，跟 IR 识别结果映射到的 fa 不同，保证下面的断言不会因为
      // "本来就是这个值"而变成假阳性。
      final (widget, prefs) = await _host(
        prefs: const {'locale': 'zhCn'},
        regionDetectionResult: 'IR',
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), 'ir');
      expect(prefs.getString('locale'), 'fa');
    });

    testWidgets('已手选过 region（非 other）时不自动识别，不覆盖用户选择', (tester) async {
      // 用户已经手动选过 'ru'；就算识别服务"识别到"了 IR，也不应该生效。
      final (widget, prefs) = await _host(
        prefs: const {'locale': 'zhCn', 'clashmiao_region': 'ru'},
        regionDetectionResult: 'IR',
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), 'ru');
      expect(prefs.getString('locale'), 'zhCn');
    });

    testWidgets('onboarding 已标记完成时不自动识别', (tester) async {
      // region 仍是默认值 'other'，但 onboarding 已完成——不应该再自动识别。
      final (widget, prefs) = await _host(
        prefs: const {'locale': 'zhCn', 'onboarding_done': true},
        regionDetectionResult: 'IR',
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), isNull);
      expect(prefs.getString('locale'), 'zhCn');
    });

    testWidgets('识别不到（两级兜底都失败）时保持默认 region/locale 不变', (tester) async {
      final (widget, prefs) = await _host(
        prefs: const {'locale': 'zhCn'},
        regionDetectionResult: null,
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), isNull);
      expect(prefs.getString('locale'), 'zhCn');
    });

    testWidgets('跨会话覆盖场景：上次手选过 other 但被打断（clashmiao_region==other 且 '
        'clashmiao_region_manually_set==true，onboarding 未完成）-> 重新挂载后'
        '不再自动识别，region/locale 保持手选结果，不被识别结果覆盖', (tester) async {
      // 复现真实 bug：用户在 onboarding 手选了"其它"——_applyRegion 已经把
      // clashmiao_region 持久化成 'other'，manuallySet 写入路径也已经把
      // clashmiao_region_manually_set 持久化成 true——但用户没点"开始"就被
      // 打断（来电/通知/后台被系统回收，移动端很常见），onboarding_done
      // 仍是 false。下次重开 App，OnboardingPage 重新 initState：只看
      // region=='other' && !onboardingDone 这两个条件的旧版本，看到的状态
      // 跟"第一次启动、什么都没选过"完全一样，会被误判成"应该自动识别"，
      // 把用户刚手选的"其它"覆盖成识别结果 IR。这个测试断言修复后不会
      // 再发生——manuallySet 标记必须能拦住这次自动识别。
      final (widget, prefs) = await _host(
        prefs: const {
          'locale': 'zhCn',
          'clashmiao_region': 'other',
          'clashmiao_region_manually_set': true,
        },
        regionDetectionResult: 'IR',
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), 'other');
      expect(prefs.getString('locale'), 'zhCn');
    });

    testWidgets('手选地区会写入"手动选过"标记，且不影响手选本身正常生效', (tester) async {
      // 只验证写入侧：手选弹窗选中任意地区后，clashmiao_region_manually_set
      // 必须被打上 true，否则上面那个跨会话测试所依赖的标记从一开始就不会
      // 存在，manuallySet 守卫也就无从谈起。选 'cn' 而不是 'other'，是为了
      // 复用已有测试验证过的、唯一匹配的文案 '中国 (cn)'（当前 region 默认是
      // 'other'，背景 tile 副标题不会显示 '中国 (cn)'，弹窗列表项是唯一匹配，
      // 不需要 .last 消歧）。
      final (widget, prefs) = await _host();
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      expect(prefs.getBool('clashmiao_region_manually_set'), isNull);

      await tester.tap(find.text('地区'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中国 (cn)'));
      await tester.pumpAndSettle();

      expect(prefs.getString('clashmiao_region'), 'cn');
      expect(prefs.getBool('clashmiao_region_manually_set'), isTrue);
    });
  });
}
