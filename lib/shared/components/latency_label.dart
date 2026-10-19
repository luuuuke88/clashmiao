import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/shared/latency/node_latency.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:clashmiao/shared/latency/node_latency.dart'
    show LatencyDisplayState, NodeLatency, resolveNodeLatency;

/// 延迟的纯文字标签（不套徽标、不带图标）。
///
/// 代理页每一行和首页节点胶囊共用它：输入就是一个 [LatencyDisplayState] 加
/// 一个数值，输出一行右对齐、等宽数字的文字。五种状态：
/// - 未测：`—`，中性色；
/// - 测量中：有旧值就显示旧值（中性色，表示「这还不是本轮结果」），没有就是 `—`；
/// - 成功：`123ms`，按分档上色；
/// - 超时：「超时」，最慢档的颜色；
/// - 历史值：`123ms`，中性色。
///
/// 「弱化」一律用不透明的中性色（`colorScheme.onSurfaceVariant`）表达，**不**
/// 叠 alpha：分档色压低透明度后，小字在卡片、选中底上的对比度会掉到 4.5:1
/// 以下。所有状态的颜色都是不透明的。
class LatencyLabel extends ConsumerWidget {
  const LatencyLabel({
    super.key,
    required this.state,
    this.ms,
    this.fontSize = 13,
    this.textAlign = TextAlign.end,
    this.wrap = false,
  });

  final LatencyDisplayState state;

  /// 毫秒数；[LatencyDisplayState.untested] 与 [LatencyDisplayState.timeout]
  /// 忽略它，[LatencyDisplayState.testing] 时是保留的旧值（可为空）。
  final int? ms;
  final double fontSize;
  final TextAlign textAlign;

  /// 默认单行、不换行（右侧延迟列里数字不能折断）。行宽不够、延迟被挪到名称
  /// 下方时传 true：长的本地化文字（如超时）可以在词间换行，而不是溢出。
  final bool wrap;

  /// 标签实际显示的文字（与 [build] 同一份规则），供布局预先量宽度。
  static String displayText(
    Translations t,
    LatencyDisplayState state,
    int? ms,
  ) {
    final hasValue = ms != null && ms > 0;
    return switch (state) {
      LatencyDisplayState.timeout => t.proxies.delayTimeout,
      _ => hasValue ? '${ms}ms' : '—',
    };
  }

  /// 不含颜色的文字样式（颜色只影响绘制，不影响宽度）。
  static TextStyle baseStyle(double fontSize) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// 按当前字体、文字缩放与方向，量出标签单行排开的宽度（逻辑像素）。
  static double measureWidth(
    BuildContext context,
    Translations t,
    LatencyDisplayState state,
    int? ms, {
    double fontSize = 13,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: displayText(t, state, ms),
        style: DefaultTextStyle.of(context).style.merge(baseStyle(fontSize)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final neutral = latencyNeutralColor(theme);

    final value = ms;
    final hasValue = value != null && value > 0;
    final text = displayText(t, state, value);

    final String semantics;
    final Color color;
    switch (state) {
      case LatencyDisplayState.untested:
        semantics = t.proxies.delaySemantics.untested;
        color = neutral;
      case LatencyDisplayState.testing:
        semantics = t.proxies.delaySemantics.testing;
        color = neutral;
      case LatencyDisplayState.success:
        semantics = hasValue
            ? t.proxies.delaySemantics.result(delay: value)
            : t.proxies.delaySemantics.untested;
        color = hasValue ? StatusColors.latencyFor(brightness, value) : neutral;
      case LatencyDisplayState.timeout:
        semantics = t.proxies.delaySemantics.timeout;
        color = StatusColors.latencyTimeout(brightness);
      case LatencyDisplayState.stale:
        semantics = hasValue
            ? t.proxies.delaySemantics.stale(delay: value)
            : t.proxies.delaySemantics.untested;
        color = neutral;
    }

    return Text(
      text,
      semanticsLabel: semantics,
      textAlign: textAlign,
      maxLines: wrap ? null : 1,
      softWrap: wrap,
      overflow: TextOverflow.visible,
      style: baseStyle(fontSize).copyWith(color: color),
    );
  }
}

/// 未测、测量中、历史值共用的中性色：不透明，明暗两套主题下压在卡片与选中底
/// 上都 ≥ 4.5:1（见 latency_label_test 的对比度用例）。
Color latencyNeutralColor(ThemeData theme) =>
    theme.colorScheme.onSurfaceVariant;
