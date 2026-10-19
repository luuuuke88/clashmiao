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
  });

  final LatencyDisplayState state;

  /// 毫秒数；[LatencyDisplayState.untested] 与 [LatencyDisplayState.timeout]
  /// 忽略它，[LatencyDisplayState.testing] 时是保留的旧值（可为空）。
  final int? ms;
  final double fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final neutral = latencyNeutralColor(theme);

    final value = ms;
    final hasValue = value != null && value > 0;

    final String text;
    final String semantics;
    final Color color;
    switch (state) {
      case LatencyDisplayState.untested:
        text = '—';
        semantics = t.proxies.delaySemantics.untested;
        color = neutral;
      case LatencyDisplayState.testing:
        text = hasValue ? '${value}ms' : '—';
        semantics = t.proxies.delaySemantics.testing;
        color = neutral;
      case LatencyDisplayState.success:
        text = hasValue ? '${value}ms' : '—';
        semantics = hasValue
            ? t.proxies.delaySemantics.result(delay: value)
            : t.proxies.delaySemantics.untested;
        color = hasValue ? StatusColors.latencyFor(brightness, value) : neutral;
      case LatencyDisplayState.timeout:
        text = t.proxies.delayTimeout;
        semantics = t.proxies.delaySemantics.timeout;
        color = StatusColors.latencyTimeout(brightness);
      case LatencyDisplayState.stale:
        text = hasValue ? '${value}ms' : '—';
        semantics = hasValue
            ? t.proxies.delaySemantics.stale(delay: value)
            : t.proxies.delaySemantics.untested;
        color = neutral;
    }

    return Text(
      text,
      semanticsLabel: semantics,
      textAlign: textAlign,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 未测、测量中、历史值共用的中性色：不透明，明暗两套主题下压在卡片与选中底
/// 上都 ≥ 4.5:1（见 latency_label_test 的对比度用例）。
Color latencyNeutralColor(ThemeData theme) =>
    theme.colorScheme.onSurfaceVariant;
