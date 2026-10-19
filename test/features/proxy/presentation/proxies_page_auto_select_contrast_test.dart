import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_box_service.dart';

/// 「自动选择」卡的两行字（14 sp 标题、11 sp 说明）在选中与普通两种状态下，
/// 按**实际合成后的底色**算 WCAG 对比度 ≥ 4.5:1。
///
/// 前景从真实渲染的 Text 里读（含 alpha 时先合成到底色上），卡片底色从真实
/// 渲染的 GlassCard 里读，再压到页面底（scaffold + 品牌晕染各种叠法）上。
/// 以后谁再给这两行字叠 alpha，或者把卡片材质调得更透，这里会直接红。
class _QuietBoxService extends FakeBoxService {
  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {}
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
}

const _profile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

ThemeData _theme(Brightness b) => b == Brightness.light
    ? AppTheme(AppThemeMode.light, 'Roboto').lightTheme()
    : AppTheme(AppThemeMode.dark, 'Roboto').darkTheme();

/// 页面底：scaffold 色 + BrandBackdrop 两团径向晕染（按峰值透明度，含两种叠序）。
Map<String, Color> _pages(ThemeData theme) {
  final light = theme.brightness == Brightness.light;
  final base = theme.scaffoldBackgroundColor;
  final indigo = BrandColors.indigo.withValues(alpha: light ? 0.16 : 0.22);
  final gold = BrandColors.gold.withValues(alpha: light ? 0.14 : 0.07);
  return {
    '无晕染': base,
    '靛蓝晕染': _over(indigo, base),
    '金色晕染': _over(gold, base),
    '靛蓝+金色': _over(gold, _over(indigo, base)),
    '金色+靛蓝': _over(indigo, _over(gold, base)),
  };
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required bool autoSelected,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final groups = [
    OutboundGroup(
      tag: 'proxy',
      type: 'selector',
      selected: autoSelected ? 'auto-group' : 'node-a',
      items: const [
        OutboundProxy(tag: 'auto-group', type: 'urltest'),
        OutboundProxy(tag: 'node-a', type: 'shadowsocks'),
      ],
    ),
  ];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _profile),
      boxServiceProvider.overrideWithValue(_QuietBoxService()),
      offlineProxyGroupsProvider.overrideWith((_) async => groups),
      isConnectedProvider.overrideWith((_) => false),
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
          theme: _theme(brightness),
          home: const ProxiesPage(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

/// 卡片在页面上实际画出的颜色：读真实 GlassCard 里那层 Container 的底色。
Color _cardPaint(WidgetTester tester, Finder text) {
  final card = find.ancestor(of: text, matching: find.byType(GlassCard)).first;
  final box = tester.widget<Container>(
    find.descendant(of: card, matching: find.byType(Container)).first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final selected in [true, false]) {
      final state = selected ? '选中' : '普通';
      testWidgets('${brightness.name} / $state：自动选择卡标题与 11 sp 说明在合成底色上 ≥ 4.5', (
        tester,
      ) async {
        await _pump(tester, brightness: brightness, autoSelected: selected);
        final theme = _theme(brightness);
        final caption = find.text('自动连接到最快的节点');
        final title = find.text('自动选择');
        expect(caption, findsOneWidget);
        expect(title, findsOneWidget);

        final captionStyle = tester.widget<Text>(caption).style!;
        expect(captionStyle.fontSize, 11);

        final card = _cardPaint(tester, caption);
        final report = <String>[];
        for (final (name, finder) in [('标题', title), ('说明', caption)]) {
          final fg = tester.widget<Text>(finder).style!.color!;
          var worst = double.infinity;
          var worstOn = '';
          for (final page in _pages(theme).entries) {
            final bg = _over(card, page.value);
            final ratio = _contrast(_over(fg, bg), bg);
            if (ratio < worst) {
              worst = ratio;
              worstOn = page.key;
            }
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$state卡$name 压在 卡片/${page.key} 上只有 $ratio',
            );
          }
          report.add('$name ${worst.toStringAsFixed(2)}（卡片/$worstOn）');
        }
        debugPrint(
          '[auto-select contrast ${brightness.name}/$state] ${report.join(' | ')}',
        );
        if (selected) {
          // 选中态说明文字用不透明色：弱化不靠透明度。
          expect(captionStyle.color!.a, 1.0, reason: '选中卡的 11 sp 说明不能再叠 alpha');
        }
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(seconds: 6));
      });
    }
  }
}
