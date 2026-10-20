import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/application/latency_test_coordinator.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_box_service.dart';

/// 代理页的行布局、选中态与五种延迟状态。
final _now = DateTime(2026, 10, 20, 12);

const _profile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

class _Box extends FakeBoxService {
  final List<String> urlTests = [];
  final List<String> selected = [];

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async =>
      selected.add(outboundTag);

  @override
  Future<void> urlTest(String groupTag) async => urlTests.add(groupTag);
}

/// 直接给定协调器状态的替身：不接连接状态、不起定时器，只用来驱动页面渲染。
class _PresetCoordinator extends LatencyTestCoordinator {
  _PresetCoordinator(LatencyTestState preset)
    : super(
        urlTest: (_) async {},
        liveGroups: () => const [],
        cache: () => const {},
        recordMeasured: (_, __) {},
        now: () => _now,
      ) {
    state = preset;
  }

  /// 测试里在同一个宿主内切换协调器状态。
  void set(LatencyTestState next) => state = next;
}

OutboundGroup _group(
  List<OutboundProxy> items, {
  String selected = '',
  String tag = 'proxy',
}) => OutboundGroup(
  tag: tag,
  type: 'selector',
  selected: selected.isEmpty ? items.first.tag : selected,
  items: items,
);

OutboundProxy _node(String tag, {int delay = 0, String type = 'vmess'}) =>
    OutboundProxy(tag: tag, type: type, delay: delay);

class _Host {
  _Host(this.widget, this.container, this.box);
  final Widget widget;
  final ProviderContainer container;
  final _Box box;
}

Future<_Host> _host({
  required bool connected,
  required List<OutboundGroup> groups,
  Map<String, Object> prefsValues = const {},
  LatencyTestState? preset,
  Brightness brightness = Brightness.light,
  AppLocale? locale,
  TextDirection? direction,
  Stream<List<OutboundGroup>>? liveGroups,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn', ...prefsValues});
  final prefs = await SharedPreferences.getInstance();
  final box = _Box();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _profile),
      boxServiceProvider.overrideWithValue(box),
      isConnectedProvider.overrideWith((_) => connected),
      latencyClockProvider.overrideWithValue(() => _now),
      if (locale != null)
        translationsProvider.overrideWithValue(locale.buildSync()),
      if (connected)
        outboundGroupsProvider.overrideWith(
          (_) => liveGroups ?? Stream.value(groups),
        )
      else
        outboundGroupsProvider.overrideWith((_) => Stream.value(const [])),
      offlineProxyGroupsProvider.overrideWith(
        (_) async => connected ? const [] : groups,
      ),
      if (preset != null)
        latencyTestCoordinatorProvider.overrideWith(
          (_) => _PresetCoordinator(preset),
        ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  final widget = UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          colorSchemeSeed: const Color(0xFF6A64F8),
          extensions: <ThemeExtension<dynamic>>[
            brightness == Brightness.light ? AiUiTheme.light : AiUiTheme.dark,
          ],
        ),
        builder: direction == null
            ? null
            : (context, child) =>
                  Directionality(textDirection: direction, child: child!),
        home: const ProxiesPage(),
      ),
    ),
  );
  return _Host(widget, container, box);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
}

/// 把假时钟推过协调器的 2 s 预热与 10 s 测速超时，让定时器自然跑完。
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 13));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _tileOf(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(GlassCard));

List<LatencyLabel> _labels(WidgetTester tester) =>
    tester.widgetList<LatencyLabel>(find.byType(LatencyLabel)).toList();

void main() {
  group('延迟五种状态', () {
    testWidgets('已连接：成功 / 历史值 / 超时 / 未测 四种同时出现，且顺序与节点一致', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([
            _node('n-success', delay: 120),
            _node('n-stale', delay: 450),
            _node('n-timeout'),
            _node('n-untested'),
          ]),
        ],
        prefsValues: {
          'proxy_delays_profile-1':
              '{"n-success":{"ms":120,"measuredAt":${_now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}},'
              '"n-stale":{"ms":450,"measuredAt":${_now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch}}}',
        },
        preset: const LatencyTestState(timedOutNodes: {'n-timeout'}),
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      final labels = _labels(tester);
      expect(labels.map((l) => l.state), [
        LatencyDisplayState.success,
        LatencyDisplayState.stale,
        LatencyDisplayState.timeout,
        LatencyDisplayState.untested,
      ]);
      expect(labels[0].ms, 120);
      expect(labels[1].ms, 450);

      expect(find.text('120ms'), findsOneWidget);
      expect(find.text('450ms'), findsOneWidget);
      expect(find.text('超时'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);

      Color colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.color!;
      expect(
        colorOf('120ms'),
        StatusColors.latency(Brightness.light, LatencyBand.fast),
      );
      final scheme = Theme.of(tester.element(find.byType(ProxiesPage)))
          .colorScheme;
      expect(
        colorOf('450ms'),
        scheme.onSurfaceVariant,
        reason: '历史值用不透明的中性色弱化，不压低透明度',
      );
      expect(colorOf('450ms').a, 1.0);
      await _drain(tester);
    });

    testWidgets('测量中：行保留旧值（离线缓存）、无旧值显示占位，顶部按钮变指示器', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('has-old'), _node('no-old')]),
        ],
        prefsValues: {
          'proxy_delays_profile-1':
              '{"has-old":{"ms":210,"measuredAt":${_now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch}}}',
        },
        preset: const LatencyTestState(
          testingGroups: {'proxy'},
          pendingNodes: {
            'proxy': {'has-old', 'no-old'},
          },
        ),
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      final labels = _labels(tester);
      expect(
        labels.map((l) => l.state),
        everyElement(LatencyDisplayState.testing),
      );
      expect(labels[0].ms, 210);
      expect(labels[1].ms, isNull);
      expect(find.text('210ms'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(FluentIcons.flash_24_regular), findsNothing);
    });

    testWidgets('已连接测量中：已出本轮结果的行直接显示数字，其余占位', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('done', delay: 88), _node('pending')]),
        ],
        preset: const LatencyTestState(
          testingGroups: {'proxy'},
          pendingNodes: {
            'proxy': {'pending'},
          },
        ),
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(_labels(tester).map((l) => l.state), [
        LatencyDisplayState.success,
        LatencyDisplayState.testing,
      ]);
      expect(find.text('88ms'), findsOneWidget);
    });

    testWidgets('真实连接状态下重测：测量中保留旧值，到点没确认的显示历史值而非超时', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('a'), _node('b', delay: 100)]),
        ],
        prefsValues: {
          'proxy_delays_profile-1':
              '{"a":{"ms":150,"measuredAt":${_now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}},'
              '"b":{"ms":100,"measuredAt":${_now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}}}',
        },
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);
      // 连接后、测速前：实时值缺席的 a 不拿缓存顶替（防冻结假数字）。
      LatencyLabel labelOf(String node) => tester.widget<LatencyLabel>(
        find.descendant(of: _tileOf(node), matching: find.byType(LatencyLabel)),
      );
      expect(labelOf('a').state, LatencyDisplayState.untested);
      expect(labelOf('b').state, LatencyDisplayState.success);

      // 2 s 预热后自动开测（真实协调器，不是预设状态）。
      await tester.pump(const Duration(seconds: 2));
      expect(host.box.urlTests, ['proxy']);
      expect(labelOf('a').state, LatencyDisplayState.testing);
      expect(labelOf('a').ms, 150, reason: '测量中保留缓存里的旧值');
      expect(labelOf('b').state, LatencyDisplayState.testing);
      expect(labelOf('b').ms, 100, reason: '测量中保留实时旧值');
      expect(find.text('150ms'), findsOneWidget);

      // 内核一直没推来新值：10 s 到点，两个节点都没确认出本轮结果。它们手上
      // 有旧值，所以显示历史值（旧数字 + 中性色），而不是超时或成功。
      await tester.pump(const Duration(seconds: 10));
      expect(labelOf('a').state, LatencyDisplayState.stale);
      expect(labelOf('a').ms, 150);
      expect(labelOf('b').state, LatencyDisplayState.stale);
      expect(labelOf('b').ms, 100);
      expect(find.text('超时'), findsNothing, reason: '稳定节点不能被标成超时');
      await _drain(tester);
    });

    testWidgets('分组重叠：同一节点在别的分组里的状态不覆盖主组', (tester) async {
      Future<List<LatencyDisplayState>> statesWith(
        LatencyTestState preset,
      ) async {
        final host = await _host(
          connected: true,
          groups: [
            _group([_node('shared'), _node('own')]),
            _group([_node('shared'), _node('x')], tag: 'other'),
          ],
          preset: preset,
        );
        await tester.pumpWidget(host.widget);
        await _settle(tester);
        return _labels(tester).map((l) => l.state).toList();
      }

      // 主组在测、另一组不在测：主组里的 shared 仍是测量中（旧实现会被
      // 后遍历的 other 组覆盖成未测）。
      expect(
        await statesWith(
          const LatencyTestState(
            testingGroups: {'proxy'},
            pendingNodes: {
              'proxy': {'shared', 'own'},
            },
          ),
        ),
        [LatencyDisplayState.testing, LatencyDisplayState.testing],
      );

      // 反过来：只有 other 组在测，主组里的 shared 不是测量中。
      expect(
        await statesWith(
          const LatencyTestState(
            testingGroups: {'other'},
            pendingNodes: {
              'other': {'shared', 'x'},
            },
          ),
        ),
        [LatencyDisplayState.untested, LatencyDisplayState.untested],
      );
    });

    testWidgets('深色主题：分档色取深色色值', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('fast', delay: 100), _node('slow', delay: 900)]),
        ],
        brightness: Brightness.dark,
        preset: const LatencyTestState(),
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(
        tester.widget<Text>(find.text('100ms')).style!.color,
        StatusColors.latency(Brightness.dark, LatencyBand.fast),
      );
      expect(
        tester.widget<Text>(find.text('900ms')).style!.color,
        StatusColors.latency(Brightness.dark, LatencyBand.slow),
      );
    });

    testWidgets('不再有 Wi-Fi 信号图标', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([
            _node('a', delay: 100),
            _node('b', delay: 400),
            _node('c', delay: 900),
            _node('d'),
          ]),
        ],
        preset: const LatencyTestState(timedOutNodes: {'d'}),
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      for (final icon in [
        FluentIcons.wifi_1_24_regular,
        FluentIcons.wifi_1_24_filled,
        FluentIcons.wifi_warning_24_regular,
        FluentIcons.wifi_off_24_regular,
        FluentIcons.error_circle_24_regular,
      ]) {
        expect(find.byIcon(icon), findsNothing, reason: '$icon');
      }
    });
  });

  group('行布局与选中态', () {
    testWidgets(
      '行距 8 dp（不再是外层 padding 与卡片 margin 叠加的 16 dp），正常字号行高在 68–72 dp（含描边）',
      (tester) async {
        final host = await _host(
          connected: false,
          groups: [
            _group([_node('first'), _node('second')], selected: 'first'),
          ],
        );
        await tester.pumpWidget(host.widget);
        await _settle(tester);

        final first = tester.getRect(_tileOf('first'));
        final second = tester.getRect(_tileOf('second'));
        expect(second.top - first.bottom, 8);
        // 真机验收量到 74–85 dp：最小高度 72 加在描边里面，名称首选字体（Emoji）
        // 的行度量又很高。spec 是 68–72 dp。
        expect(first.height, inInclusiveRange(68, 72), reason: '选中行');
        expect(second.height, inInclusiveRange(68, 72), reason: '未选中行');
        expect(first.height, second.height, reason: '选中与否行高一致，不跳动');
      },
    );

    testWidgets('选中态：1.5 dp 品牌色描边 + 约 8% 品牌色底 + 18 dp 对勾', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('picked'), _node('other')], selected: 'picked'),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      final primary = Theme.of(tester.element(find.byType(ProxiesPage)))
          .colorScheme
          .primary;

      final picked = tester.widget<GlassCard>(_tileOf('picked'));
      expect(picked.borderColor, primary);
      expect(picked.borderWidth, 1.5);
      final other = tester.widget<GlassCard>(_tileOf('other'));
      expect(other.borderColor, isNull);
      expect(other.borderWidth, 1);

      // 底色：选中行有 8% 品牌色的 Ink，未选中行没有。
      Iterable<Ink> inks(String text) => tester.widgetList<Ink>(
        find.descendant(of: _tileOf(text), matching: find.byType(Ink)),
      );
      expect(
        inks('picked').single.decoration,
        isA<BoxDecoration>().having(
          (d) => d.color,
          'color',
          primary.withValues(alpha: 0.08),
        ),
      );
      expect(inks('other').single.decoration, isNull, reason: '未选中行没有品牌色底');

      final check = find.descendant(
        of: _tileOf('picked'),
        matching: find.byIcon(FluentIcons.checkmark_24_filled),
      );
      expect(check, findsOneWidget);
      expect(tester.getSize(check), const Size(18, 18));
      expect(
        find.descendant(
          of: _tileOf('other'),
          matching: find.byIcon(FluentIcons.checkmark_24_filled),
        ),
        findsNothing,
      );
    });

    testWidgets('对勾位固定占位：选中与否，名称和延迟的水平位置都不变', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('picked'), _node('other')], selected: 'picked'),
        ],
        prefsValues: {
          'proxy_delays_profile-1':
              '{"picked":{"ms":100,"measuredAt":${_now.millisecondsSinceEpoch}},'
              '"other":{"ms":100,"measuredAt":${_now.millisecondsSinceEpoch}}}',
        },
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      final pickedName = tester.getTopLeft(find.text('picked'));
      final otherName = tester.getTopLeft(find.text('other'));
      expect(pickedName.dx, otherName.dx);
      final labels = find.text('100ms');
      expect(labels, findsNWidgets(2));
      expect(
        tester.getTopRight(labels.at(0)).dx,
        tester.getTopRight(labels.at(1)).dx,
      );
    });

    testWidgets('选中语义：selected + button', (tester) async {
      final handle = tester.ensureSemantics();
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('picked'), _node('other')], selected: 'picked'),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      final pickedNode = tester.getSemantics(find.text('picked'));
      expect(pickedNode, isSemantics(isSelected: true, isButton: true));
      final otherNode = tester.getSemantics(find.text('other'));
      expect(
        otherNode,
        isSemantics(isSelected: false, hasSelectedState: true, isButton: true),
      );
      handle.dispose();
    });
  });

  group('文字放大', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320 dp、文字 $scale 倍：行不溢出，选中对勾仍在', (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final host = await _host(
          connected: true,
          groups: [
            _group([
              _node('🇭🇰 香港 01 | 一个相当长的节点名称用来换行', delay: 120),
              _node('Singapore 02', delay: 900),
            ], selected: 'Singapore 02'),
          ],
          preset: const LatencyTestState(),
        );
        await tester.pumpWidget(host.widget);
        await _settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.byIcon(FluentIcons.checkmark_24_filled), findsOneWidget);
        expect(find.text('120ms'), findsOneWidget);
      });
    }
  });

  group('延迟列大字号布局矩阵（320 dp、2.0×、LTR / RTL）', () {
    // 本地化超时文字里实际排出来最宽的那条（按标签同款字号、2.0× 量），不手写
    // 某个语言：以后谁的翻译更长，这里自动换成它。
    (AppLocale, String) widestTimeout() {
      AppLocale? best;
      var bestWidth = -1.0;
      for (final locale in AppLocale.values) {
        final text = locale.buildSync().proxies.delayTimeout;
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(2),
        )..layout();
        if (painter.width > bestWidth) {
          bestWidth = painter.width;
          best = locale;
        }
        painter.dispose();
      }
      return (best!, best.buildSync().proxies.delayTimeout);
    }

    const node = '香港 01 | 一个相当长的节点名称用来换行';
    final fresh = _now.subtract(const Duration(minutes: 1));
    final old = _now.subtract(const Duration(minutes: 10));
    String cache(DateTime at) =>
        '{"$node":{"ms":9999,"measuredAt":${at.millisecondsSinceEpoch}}}';

    final cases =
        <
          ({
            String name,
            bool connected,
            int liveDelay,
            DateTime cachedAt,
            LatencyTestState preset,
            LatencyDisplayState expected,
          })
        >[
          (
            name: '成功 9999ms',
            connected: true,
            liveDelay: 9999,
            cachedAt: fresh,
            preset: const LatencyTestState(),
            expected: LatencyDisplayState.success,
          ),
          (
            name: '历史值 9999ms',
            connected: false,
            liveDelay: 0,
            cachedAt: old,
            preset: const LatencyTestState(),
            expected: LatencyDisplayState.stale,
          ),
          (
            name: '测量中保留旧值 9999ms',
            connected: true,
            liveDelay: 9999,
            cachedAt: old,
            preset: const LatencyTestState(
              testingGroups: {'proxy'},
              pendingNodes: {
                'proxy': {node},
              },
            ),
            expected: LatencyDisplayState.testing,
          ),
          (
            name: '超时（最长本地化文字）',
            connected: true,
            liveDelay: 0,
            cachedAt: old,
            preset: const LatencyTestState(timedOutNodes: {node}),
            expected: LatencyDisplayState.timeout,
          ),
        ];

    for (final direction in TextDirection.values) {
      for (final c in cases) {
        testWidgets(
          '${direction.name.toUpperCase()} / ${c.name}：行不溢出，名称保有合理宽度',
          (tester) async {
            tester.view.physicalSize = const Size(320, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            tester.platformDispatcher.textScaleFactorTestValue = 2.0;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            final (locale, timeoutText) = widestTimeout();
            final host = await _host(
              connected: c.connected,
              groups: [
                _group([
                  _node(node, delay: c.liveDelay),
                  _node('Singapore 02'),
                ], selected: node),
              ],
              prefsValues: {'proxy_delays_profile-1': cache(c.cachedAt)},
              preset: c.preset,
              locale: locale,
              direction: direction,
            );
            await tester.pumpWidget(host.widget);
            await _settle(tester);

            expect(tester.takeException(), isNull, reason: '不应有任何溢出');

            final label = _labels(tester).first;
            expect(label.state, c.expected, reason: '用例要真的落在 ${c.name}');
            final shown = c.expected == LatencyDisplayState.timeout
                ? timeoutText
                : '9999ms';
            final latency = find.text(shown);
            expect(latency, findsOneWidget);

            final tile = tester.getRect(_tileOf(node).first);
            final name = tester.getRect(find.text(node));
            final lat = tester.getRect(latency);

            // 全部落在屏内、落在自己那张卡里。
            for (final r in [tile, name, lat]) {
              expect(r.left, greaterThanOrEqualTo(-0.5));
              expect(r.right, lessThanOrEqualTo(320.5));
            }
            for (final r in [name, lat]) {
              expect(r.left, greaterThanOrEqualTo(tile.left - 0.5));
              expect(r.right, lessThanOrEqualTo(tile.right + 0.5));
              expect(r.bottom, lessThanOrEqualTo(tile.bottom + 0.5));
            }
            // 名称与延迟不重叠。
            expect(name.overlaps(lat), isFalse, reason: '名称与延迟文字不能叠在一起');
            // 名称保有合理宽度：至少是卡片宽度的 40%，不被延迟列挤成一条缝。
            expect(
              name.width,
              greaterThanOrEqualTo(tile.width * 0.4),
              reason: '名称只剩 ${name.width} dp（卡片 ${tile.width} dp）',
            );
            // 选中对勾仍在。
            expect(
              find.byIcon(FluentIcons.checkmark_24_filled),
              findsOneWidget,
            );
            await _drain(tester);
          },
        );
      }
    }
    for (final direction in TextDirection.values) {
      testWidgets(
        '对照：${direction.name.toUpperCase()} / 360 dp、1.0×、120ms：延迟仍在名称末端的右对齐列里，不被挪到下一行',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final host = await _host(
            connected: true,
            groups: [
              _group([_node(node, delay: 120)]),
            ],
            prefsValues: {
              'proxy_delays_profile-1':
                  '{"$node":{"ms":120,"measuredAt":${fresh.millisecondsSinceEpoch}}}',
            },
            preset: const LatencyTestState(),
            direction: direction,
          );
          await tester.pumpWidget(host.widget);
          await _settle(tester);
          expect(tester.takeException(), isNull);

          final name = tester.getRect(find.text(node));
          final lat = tester.getRect(find.text('120ms'));
          // 同一行：延迟的竖向范围与名称块相交，且排在名称的末端一侧。
          expect(lat.top, lessThan(name.bottom), reason: '延迟不应被挪到名称下方');
          if (direction == TextDirection.ltr) {
            expect(lat.left, greaterThanOrEqualTo(name.right));
          } else {
            expect(lat.right, lessThanOrEqualTo(name.left));
          }
          await _drain(tester);
        },
      );
    }
  });

  group('测速状态切换时行不跳动（同一宿主内连续切换）', () {
    const node = '香港 01 | 一个相当长的节点名称用来换行';
    const next = 'Singapore 02';

    for (final (width, scale) in [(320.0, 2.0), (360.0, 1.0)]) {
      for (final direction in TextDirection.values) {
        testWidgets(
          '${width.toInt()} dp、$scale×、${direction.name.toUpperCase()}：'
          '占位 → 四位 / 五位实时值 → 五位历史缓存 → 超时 → 再次测速保留旧值 → 成功，'
          '行高 / 名称 / 下一行位置不变',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            final live = StreamController<List<OutboundGroup>>.broadcast();
            addTearDown(live.close);
            List<OutboundGroup> groupsWith(int delay) => [
              _group([_node(node, delay: delay), _node(next)], selected: node),
            ];

            final host = await _host(
              connected: true,
              groups: groupsWith(0),
              liveGroups: live.stream,
              preset: const LatencyTestState(),
              direction: direction,
            );
            await tester.pumpWidget(host.widget);
            live.add(groupsWith(0));
            await _settle(tester);
            final coordinator = host.container.read(
              latencyTestCoordinatorProvider.notifier,
            ) as _PresetCoordinator;

            final cache = host.container.read(proxyDelayCacheProvider.notifier);
            final longAgo = _now.subtract(const Duration(hours: 1));

            /// [staleCachedMs] 不为空时，先把它写成一条很久以前测的缓存，再让
            /// 实时值缺席、本轮未确认：显示的就是这条历史缓存。
            Future<void> step(
              int delay,
              LatencyTestState state, {
              int? staleCachedMs,
            }) async {
              if (staleCachedMs != null) {
                cache.recordMeasured({node: staleCachedMs}, at: longAgo);
              }
              coordinator.set(state);
              live.add(groupsWith(delay));
              await _settle(tester);
            }

            const unconfirmed = LatencyTestState(unconfirmedNodes: {node});
            final steps =
                <
                  (
                    String,
                    int,
                    LatencyTestState,
                    int?,
                    LatencyDisplayState,
                    String,
                  )
                >[
                  (
                    '占位',
                    0,
                    const LatencyTestState(),
                    null,
                    LatencyDisplayState.untested,
                    '—',
                  ),
                  (
                    '四位实时值',
                    9999,
                    const LatencyTestState(),
                    null,
                    LatencyDisplayState.success,
                    '9999ms',
                  ),
                  (
                    '五位实时值 10000',
                    10000,
                    const LatencyTestState(),
                    null,
                    LatencyDisplayState.success,
                    '10000ms',
                  ),
                  (
                    '五位实时值 65000（有效上限）',
                    kDelayTimeoutSentinelMs,
                    const LatencyTestState(),
                    null,
                    LatencyDisplayState.success,
                    '65000ms',
                  ),
                  (
                    '五位历史缓存 10000',
                    0,
                    unconfirmed,
                    10000,
                    LatencyDisplayState.stale,
                    '10000ms',
                  ),
                  (
                    '五位历史缓存 65000',
                    0,
                    unconfirmed,
                    kDelayTimeoutSentinelMs,
                    LatencyDisplayState.stale,
                    '65000ms',
                  ),
                  (
                    '超时',
                    0,
                    const LatencyTestState(timedOutNodes: {node}),
                    null,
                    LatencyDisplayState.timeout,
                    '超时',
                  ),
                  (
                    '再次测速保留旧值',
                    9999,
                    const LatencyTestState(
                      testingGroups: {'proxy'},
                      pendingNodes: {
                        'proxy': {node},
                      },
                    ),
                    null,
                    LatencyDisplayState.testing,
                    '9999ms',
                  ),
                  (
                    '成功',
                    120,
                    const LatencyTestState(),
                    null,
                    LatencyDisplayState.success,
                    '120ms',
                  ),
                ];

            Rect? tile0;
            Rect? name0;
            double? next0;
            for (final (label, delay, state, stale, expected, text) in steps) {
              await step(delay, state, staleCachedMs: stale);
              expect(tester.takeException(), isNull, reason: '$label：不应溢出');
              final shown = _labels(tester).first;
              expect(shown.state, expected, reason: '$label：状态要真的切到');
              // 名称那一行的延迟文字确实变了（只在这一行里找）。
              expect(
                find.descendant(
                  of: _tileOf(node).first,
                  matching: find.text(text),
                ),
                findsOneWidget,
                reason: '$label：应显示 $text',
              );

              final tile = tester.getRect(_tileOf(node).first);
              final name = tester.getRect(find.text(node));
              final nextTop = tester.getRect(_tileOf(next).first).top;
              if (tile0 == null) {
                tile0 = tile;
                name0 = name;
                next0 = nextTop;
                continue;
              }
              expect(tile.height, tile0.height, reason: '$label：行高变了');
              expect(name, name0, reason: '$label：名称位置 / 宽度变了');
              expect(nextTop, next0, reason: '$label：下一行被推动了');
            }
            await _drain(tester);
          },
        );
      }
    }
  });

  group('旗帜只出现一次', () {
    testWidgets('开头旗帜搬到左侧旗帜区，名称里不再重复', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('🇭🇰 香港 01 §2')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(find.text('🇭🇰'), findsOneWidget);
      expect(find.text('香港 01'), findsOneWidget);
      expect(find.textContaining('§'), findsNothing);
    });

    testWidgets('名字只有一面旗帜：旗帜只出现一次，名称位是中性占位', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('🇭🇰')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(find.text('🇭🇰'), findsOneWidget);
      expect(find.text('未知'), findsOneWidget);
    });

    testWidgets('台湾节点推断为 🇹🇼 而不是 🇨🇳', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('台湾 03')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(find.text('🇹🇼'), findsOneWidget);
      expect(find.text('🇨🇳'), findsNothing);
    });

    testWidgets('推断不出国家：中性地球图标，不乱挂旗帜', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('Premium Node 12')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      expect(find.byIcon(FluentIcons.globe_24_regular), findsOneWidget);
      expect(find.text('🌐'), findsNothing);
    });

    testWidgets('选择仍使用原始 tag（含旗帜与 § 后缀），展示名只用于显示', (tester) async {
      const raw = '🇭🇰 香港 01 §2';
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('other'), _node(raw)], selected: 'other'),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);

      await tester.tap(find.text('香港 01'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(host.box.selected, [raw]);
      await _drain(tester);
    });
  });

  group('自动测速接线', () {
    testWidgets('连接状态下切到代理页：该组无数据则测一次；30 s 内再切不重复', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('a'), _node('b')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);
      expect(host.box.urlTests, isEmpty);

      host.container.read(selectedTabProvider.notifier).state = AppTab.proxies;
      await tester.pump();
      expect(host.box.urlTests, ['proxy']);

      host.container.read(selectedTabProvider.notifier).state = AppTab.home;
      await tester.pump();
      host.container.read(selectedTabProvider.notifier).state = AppTab.proxies;
      await tester.pump();
      expect(host.box.urlTests, ['proxy'], reason: '30 s 内同组自动测速去重');
      await _drain(tester);
    });

    testWidgets('连接后 2 s 自动测当前组（不需要用户打开代理页）', (tester) async {
      final host = await _host(
        connected: true,
        groups: [
          _group([_node('a')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      await _settle(tester);
      expect(host.box.urlTests, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      expect(host.box.urlTests, ['proxy']);
      await _drain(tester);
    });

    testWidgets('未连接：不触发自动测速', (tester) async {
      final host = await _host(
        connected: false,
        groups: [
          _group([_node('a')]),
        ],
      );
      await tester.pumpWidget(host.widget);
      host.container.read(selectedTabProvider.notifier).state = AppTab.proxies;
      await tester.pump(const Duration(seconds: 5));
      expect(host.box.urlTests, isEmpty);
    });
  });
}
