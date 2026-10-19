import 'package:flutter/material.dart';

/// 延迟分档：<300 ms 快、300–799 ms 中、≥800 ms 慢。
enum LatencyBand { fast, medium, slow }

LatencyBand latencyBandOf(int ms) {
  if (ms < 300) return LatencyBand.fast;
  if (ms < 800) return LatencyBand.medium;
  return LatencyBand.slow;
}

/// 状态色：绿 / 橙 / 红只留给状态，按明暗主题**分别**定义。
///
/// 浅色主题下用加深的色值，保证 12 sp 左右的小字压在卡片（白、近白、带
/// 8% 品牌色选中底）上对比度仍 ≥ 4.5:1；深色主题用提亮的色值。不要在这里
/// 再叠 alpha——压低透明度会把对比度吃掉。
///
/// 本期（U3）只放延迟分档，其余状态色由后续任务补进来。
abstract final class StatusColors {
  // 浅色：emerald-800 / 加深琥珀 / red-700。
  static const Color _latencyFastLight = Color(0xFF065F46);
  static const Color _latencyMediumLight = Color(0xFF92400E);
  static const Color _latencySlowLight = Color(0xFFB91C1C);

  // 深色：emerald-400 / amber-400 / red-400。
  static const Color _latencyFastDark = Color(0xFF34D399);
  static const Color _latencyMediumDark = Color(0xFFFBBF24);
  static const Color _latencySlowDark = Color(0xFFF87171);

  static Color latency(Brightness brightness, LatencyBand band) {
    final light = brightness == Brightness.light;
    return switch (band) {
      LatencyBand.fast => light ? _latencyFastLight : _latencyFastDark,
      LatencyBand.medium => light ? _latencyMediumLight : _latencyMediumDark,
      LatencyBand.slow => light ? _latencySlowLight : _latencySlowDark,
    };
  }

  /// 按毫秒数取分档色。
  static Color latencyFor(Brightness brightness, int ms) =>
      latency(brightness, latencyBandOf(ms));

  /// 超时 / 测速失败：与最慢档同色。
  static Color latencyTimeout(Brightness brightness) =>
      latency(brightness, LatencyBand.slow);
}
