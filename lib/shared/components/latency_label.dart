import 'dart:math' as math;

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

  /// 标签实际显示的文字（与 [build] 同一份规则）。
  ///
  /// 未测一律是 `—`（忽略 [ms]）；超时是本地化文字；其余状态有有效数值就显示
  /// `123ms`，否则 `—`。
  static String displayText(
    Translations t,
    LatencyDisplayState state,
    int? ms,
  ) {
    final hasValue = ms != null && ms > 0;
    return switch (state) {
      LatencyDisplayState.untested => '—',
      LatencyDisplayState.timeout => t.proxies.delayTimeout,
      LatencyDisplayState.testing ||
      LatencyDisplayState.success ||
      LatencyDisplayState.stale => hasValue ? '${ms}ms' : '—',
    };
  }

  /// 不含颜色的文字样式（颜色只影响绘制，不影响宽度）。
  static TextStyle baseStyle(double fontSize) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// 布局预算里「最长的合理数字」：测速超时前最多就是几秒，四位毫秒数封顶。
  static const int budgetMs = 9999;

  static final Map<Object, Size> _budgetCache = {};

  /// 这一套字体、文字缩放、语言下，标签**所有状态**里最大的排版尺寸。
  ///
  /// 行布局（延迟放右侧还是挪到下一行、给它留多大的位置）只能按这个预算定，
  /// 不能按当前结果定：否则测速从 `—` 变成长数字或超时文字时，行会改结构、
  /// 改高度，把后面的节点整体推上推下。
  ///
  /// 量的是每种状态在「无值」与 [budgetMs] 下实际显示的文字（`—`、`9999ms`、
  /// 本地化超时文字；历史值 / 测量中旧值与成功同样是 `9999ms`）。
  /// - 宽度：单行排开的最大宽度；
  /// - 高度：[wrapWidth] 为空时是单行的最大高度；给了 [wrapWidth] 时是按该宽度
  ///   允许换行（挪到下一行的布局）排开后的最大高度。
  ///
  /// 结果按（样式、缩放、方向、各状态文字、换行宽度）缓存，同一屏所有行、
  /// 每一帧共用一次测量。
  static Size budget(
    BuildContext context,
    Translations t, {
    double fontSize = 13,
    double? wrapWidth,
  }) {
    final style = DefaultTextStyle.of(context).style.merge(baseStyle(fontSize));
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final texts = <String>{
      for (final state in LatencyDisplayState.values)
        for (final ms in const <int?>[null, budgetMs])
          displayText(t, state, ms),
    }.toList()..sort();
    final key = (style, scaler, direction, texts.join('\u0000'), wrapWidth);
    final cached = _budgetCache[key];
    if (cached != null) return cached;

    var width = 0.0;
    var height = 0.0;
    for (final text in texts) {
      final single = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      width = math.max(width, single.width);
      if (wrapWidth == null) height = math.max(height, single.height);
      single.dispose();
      if (wrapWidth != null) {
        final wrapped = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: direction,
          textScaler: scaler,
        )..layout(maxWidth: math.max(0, wrapWidth));
        height = math.max(height, wrapped.height);
        wrapped.dispose();
      }
    }
    final size = Size(width, height);
    if (_budgetCache.length >= 64) _budgetCache.clear();
    _budgetCache[key] = size;
    return size;
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
