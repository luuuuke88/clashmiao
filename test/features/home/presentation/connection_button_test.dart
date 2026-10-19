import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/features/home/presentation/connection_button.dart';
import 'package:clashmiao/features/home/presentation/speed_cat_connection_mark.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_connection_controller.dart';

/// 把 ConnectionButton 放进可渲染的最小宿主：显式锁定 locale，预读
/// sharedPreferencesProvider，用假控制器提供「当前 phase」（门禁 toggleTarget 读它）。
Future<(Widget, ProviderContainer)> _host(
  ConnectionPhase phase, {
  VoidCallback? onTap,
  DateTime? startedAt,
  String locale = 'zhCn',
  double scale = 1,
  double textScale = 1,
  double width = 400,
}) async {
  SharedPreferences.setMockInitialValues({'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      connectionStartedAtProvider.overrideWith((_) => startedAt),
      connectionControllerProvider.overrideWith(
        (ref) => FakeConnectionController(ref, phase: phase),
      ),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  final widget = UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: _Phased(
                container: container,
                initial: phase,
                onTap: onTap ?? () {},
                scale: scale,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (widget, container);
}

/// 跟随假控制器的 phase 重建按钮，模拟首页 `ref.watch(connectionPhaseProvider)`。
class _Phased extends ConsumerWidget {
  const _Phased({
    required this.container,
    required this.initial,
    required this.onTap,
    required this.scale,
  });

  final ProviderContainer container;
  final ConnectionPhase initial;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(connectionPhaseProvider);
    return ConnectionButton(phase: phase, onTap: onTap, scale: scale);
  }
}

FakeConnectionController _ctl(ProviderContainer c) =>
    c.read(connectionControllerProvider.notifier) as FakeConnectionController;

void main() {
  group('ConnectionButton', () {
    testWidgets('所有阶段的连接按钮都显示猫咪 Logo，不显示通用状态图标', (tester) async {
      for (final phase in ConnectionPhase.values) {
        final (w, _) = await _host(phase);
        await tester.pumpWidget(w);
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.byType(SpeedCatConnectionMark), findsOneWidget);
        expect(find.byIcon(FluentIcons.power_24_regular), findsNothing);
        expect(find.byIcon(FluentIcons.arrow_sync_24_regular), findsNothing);
        expect(
          find.byIcon(FluentIcons.shield_checkmark_24_regular),
          findsNothing,
        );
      }
    });

    testWidgets('过渡期按钮可点（取消连接 / 重新连接），不再被禁用', (tester) async {
      for (final phase in [
        ConnectionPhase.connecting,
        ConnectionPhase.reconnecting,
        ConnectionPhase.disconnecting,
        ConnectionPhase.resolving,
      ]) {
        var taps = 0;
        final (w, _) = await _host(phase, onTap: () => taps++);
        await tester.pumpWidget(w);
        await tester.pump(const Duration(milliseconds: 20));

        await tester.tap(find.byType(ConnectionButton));
        await tester.pump();

        expect(taps, 1, reason: '$phase 期间点击必须到达 onTap');
      }
    });

    testWidgets('未连接显示"点击连接"且可点击；resolving 按未连接呈现', (tester) async {
      for (final phase in [
        ConnectionPhase.disconnected,
        ConnectionPhase.resolving,
      ]) {
        var tapped = 0;
        final (w, _) = await _host(phase, onTap: () => tapped++);
        await tester.pumpWidget(w);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('点击连接'), findsOneWidget);

        await tester.tap(find.byType(ConnectionButton));
        await tester.pump();
        expect(tapped, 1);
      }
    });

    testWidgets('未连接的"点击连接"用 onSurface，不是弱化的次要色', (tester) async {
      final (w, _) = await _host(ConnectionPhase.disconnected);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      final style = tester.widget<Text>(find.text('点击连接')).style!;
      final theme = Theme.of(tester.element(find.byType(ConnectionButton)));
      expect(style.color, theme.colorScheme.onSurface);
    });

    testWidgets('connecting / reconnecting 显示"正在连接"，disconnecting 显示"正在断开连接"', (
      tester,
    ) async {
      for (final (phase, text) in [
        (ConnectionPhase.connecting, '正在连接'),
        (ConnectionPhase.reconnecting, '正在连接'),
        (ConnectionPhase.disconnecting, '正在断开连接'),
      ]) {
        final (w, _) = await _host(phase);
        await tester.pumpWidget(w);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text(text), findsOneWidget, reason: '$phase');
      }
    });

    testWidgets('已连接显示"已连接"且 onTap 触发（用于断开）', (tester) async {
      var tapped = 0;
      final (w, _) = await _host(
        ConnectionPhase.connected,
        onTap: () => tapped++,
      );
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已连接'), findsOneWidget);

      await tester.tap(find.byType(ConnectionButton));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('已连接：状态字用连接绿，16 sp / w600，且不随猫与圆盘缩放', (tester) async {
      final (w, _) = await _host(ConnectionPhase.connected, scale: 0.733);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      final style = tester.widget<Text>(find.text('已连接')).style!;
      expect(style.color, BrandColors.connected);
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w600);
      // 渲染出来的文字高度等于 16 sp 排版高度（没被 FittedBox 缩小）。
      final h1 = tester.getSize(find.text('已连接')).height;
      await tester.pumpWidget(
        (await _host(ConnectionPhase.connected, scale: 1)).$1,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(find.text('已连接')).height, h1);
    });

    testWidgets('scale 只缩放猫与圆盘', (tester) async {
      final (full, _) = await _host(ConnectionPhase.disconnected, scale: 1);
      await tester.pumpWidget(full);
      await tester.pump(const Duration(milliseconds: 200));
      final disc = find.byKey(const ValueKey('connection-idle-disc'));
      // 缩放用 FittedBox 的变换实现，layout size 不变，要量变换后的屏幕尺寸。
      final big = tester.getBottomRight(disc) - tester.getTopLeft(disc);

      final (small, _) = await _host(ConnectionPhase.disconnected, scale: 0.5);
      await tester.pumpWidget(small);
      await tester.pump(const Duration(milliseconds: 200));
      final shrunk = tester.getBottomRight(disc) - tester.getTopLeft(disc);

      expect(shrunk.dx, closeTo(big.dx * 0.5, 0.5));
    });

    testWidgets('知道连接起点时，状态旁显示已连接时长（13 sp / w400 / 等宽数字）', (tester) async {
      // 多给半秒余量：起点到第一帧之间的真实耗时不会把 65 秒推成 66 秒。
      final startedAt = DateTime.now().subtract(
        const Duration(seconds: 65, milliseconds: 500),
      );
      final (w, _) = await _host(
        ConnectionPhase.connected,
        startedAt: startedAt,
      );
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('01:05'), findsOneWidget);
      final style = tester.widget<Text>(find.text('01:05')).style!;
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('不知道连接起点（挂上了已在跑的隧道）时不显示时长，绝不从 0 开始数', (tester) async {
      final (w, _) = await _host(ConnectionPhase.connected);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('connection-duration')), findsNothing);
    });

    testWidgets('最长的译文（俄语"点击连接"）、320 dp 窄屏 + 2.0 倍字号也不溢出', (tester) async {
      final (w, _) = await _host(
        ConnectionPhase.disconnected,
        locale: 'ru',
        textScale: 2.0,
        width: 320,
      );
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('НАЖМИТЕ ДЛЯ ПОДКЛЮЧЕНИЯ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 放不下时换行，而不是缩小字号。
      final style = tester
          .widget<Text>(find.text('НАЖМИТЕ ДЛЯ ПОДКЛЮЧЕНИЯ'))
          .style!;
      expect(style.fontSize, 16);
    });

    test('时长格式：一小时内 mm:ss，超过一小时 h:mm:ss', () {
      expect(formatConnectedDuration(const Duration(seconds: 5)), '00:05');
      expect(
        formatConnectedDuration(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
      expect(
        formatConnectedDuration(const Duration(hours: 1, seconds: 3)),
        '1:00:03',
      );
      expect(
        formatConnectedDuration(const Duration(hours: 26, minutes: 4)),
        '26:04:00',
      );
    });

    testWidgets('猫咪跟外面的 Logo 同比例：比底盘大一圈，状态文字落在圆盘下方', (tester) async {
      final (w, _) = await _host(ConnectionPhase.disconnected);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      final mark = tester.widget<SpeedCatConnectionMark>(
        find.byType(SpeedCatConnectionMark),
      );
      final disc = tester.getSize(
        find.byKey(const ValueKey('connection-idle-disc')),
      );
      expect(
        mark.size,
        greaterThan(disc.width),
        reason: '标记图自带留白，尺寸不比底盘大一圈的话猫脸就比外面那只小',
      );

      final discBottom = tester
          .getRect(find.byKey(const ValueKey('connection-idle-disc')))
          .bottom;
      expect(
        tester.getRect(find.text('点击连接')).top,
        greaterThan(discBottom),
        reason: '文字挪到圆盘外面，圆盘里只剩 Logo——跟空态那只猫的排版一致',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('状态文字立即跟随 phase；加载指示延迟出现、无最短展示', () {
    const indicator = ValueKey('connection-loading-indicator');
    const delay = ConnectionTiming.loadingIndicatorDelay;

    testWidgets('进入 connecting：文字当帧就变，加载指示延迟到 $delay 后才出现', (tester) async {
      final (w, container) = await _host(ConnectionPhase.disconnected);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('点击连接'), findsOneWidget);

      _ctl(container).emit(ConnectionPhase.connecting);
      await tester.pump();

      expect(find.text('正在连接'), findsOneWidget, reason: '文字不能等任何延迟');
      expect(find.byKey(indicator), findsNothing);

      await tester.pump(delay - const Duration(milliseconds: 20));
      expect(find.byKey(indicator), findsNothing, reason: '延迟窗口内不闪出指示');

      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byKey(indicator), findsOneWidget);
    });

    testWidgets('延迟窗口内就成功：指示从未出现，文字立即替换为"已连接"（无最短展示）', (tester) async {
      final (w, container) = await _host(ConnectionPhase.disconnected);
      await tester.pumpWidget(w);
      await tester.pump(const Duration(milliseconds: 200));

      _ctl(container).emit(ConnectionPhase.connecting);
      await tester.pump(const Duration(milliseconds: 50));
      _ctl(container).emit(ConnectionPhase.connected);
      await tester.pump();

      expect(find.text('已连接'), findsOneWidget);
      expect(find.byKey(indicator), findsNothing);
      await tester.pump(delay * 2);
      expect(find.byKey(indicator), findsNothing, reason: '成功后不会再冒出指示');
    });

    testWidgets('指示已出现后失败 / 成功：立即消失', (tester) async {
      final (w, container) = await _host(ConnectionPhase.connecting);
      await tester.pumpWidget(w);
      await tester.pump(delay + const Duration(milliseconds: 20));
      expect(find.byKey(indicator), findsOneWidget);

      _ctl(container).emit(ConnectionPhase.disconnected);
      await tester.pump();

      expect(find.byKey(indicator), findsNothing);
      expect(find.text('点击连接'), findsOneWidget);
    });

    testWidgets('已连接 / 未连接时没有加载指示', (tester) async {
      for (final phase in [
        ConnectionPhase.connected,
        ConnectionPhase.disconnected,
      ]) {
        final (w, _) = await _host(phase);
        await tester.pumpWidget(w);
        await tester.pump(delay * 3);
        expect(find.byKey(indicator), findsNothing, reason: '$phase');
      }
    });
  });
}
