import 'package:clashmiao/core/latency/latency_rules.dart';

/// 一个节点的延迟在界面上处于哪种状态（五种）。
enum LatencyDisplayState {
  /// 从没测过：静态占位 `—`。
  untested,

  /// 正在测：有旧值就保留旧值，没有就占位。
  testing,

  /// 刚测到的有效延迟：数字 + 分档颜色。
  success,

  /// 本轮测了没结果（超时 / 失败）：「超时」。
  timeout,

  /// 历史值：超过 5 分钟（或旧版本留下、不知何时测的）的数字，用中性色
  /// 弱化显示（不靠压低透明度，免得小字对比度不达标）。
  stale,
}

/// 展示层的结果：状态 + 要显示的毫秒数（[LatencyDisplayState.untested] 与
/// [LatencyDisplayState.timeout] 没有数字，[LatencyDisplayState.testing] 的
/// 数字是保留的旧值，可能为空）。
class NodeLatency {
  const NodeLatency(this.state, [this.ms]);

  final LatencyDisplayState state;
  final int? ms;

  @override
  bool operator ==(Object other) =>
      other is NodeLatency && other.state == state && other.ms == ms;

  @override
  int get hashCode => Object.hash(state, ms);

  @override
  String toString() => 'NodeLatency($state, $ms)';
}

/// 把「实时值 / 缓存值 / 是否在等本轮结果 / 本轮是否超时」归结成一个展示状态。
///
/// 纯函数，代理页的每一行和首页节点胶囊共用它，保证两处口径一致。
/// 优先级自上而下：
/// 1. 该节点还在等本轮结果（[testing]）→ 测量中，保留旧值：实时值有效用
///    实时值，否则用缓存值（**不受** [cacheIsFallback] 限制），都没有就占位；
/// 2. 本轮测完没结果（[timedOut]）、或内核给了超时哨兵 → 超时；
/// 3. 上一轮到点没确认出结果但有旧值（[unconfirmed]）→ 历史值，带旧值（实时
///    值有效用实时值，否则用缓存值）：不能当成新结果，也不能判超时；
/// 4. 实时值有效 → 成功；缓存里是同一个数且测量时间未知或已超过 5 分钟 →
///    历史值（旧版本留下的无时间缓存在确认出新结果前一直算历史值）；
/// 5. 缓存有值且允许兜底 → 成功 / 历史值（按测量时间）；
/// 6. 否则未测。
///
/// [testing] 要按「分组 + 节点」传：只有这个节点在当前展示的分组里还没出
/// 本轮结果时才为真；已经出了结果的节点直接展示新值。
///
/// [cacheIsFallback] 为 false 时（已连接且有真实实时分组）缓存只参与第 1、3 条
/// 的旧值保留与第 4 条的「是否过期」判断，第 5 条不使用缓存：测完之后实时值
/// 缺席的节点，不能再拿缓存里冻结的旧数字当成功顶替——那会显示一个永远不变
/// 的假数字。第 3 条用到缓存时明确标成历史值，不冒充新结果。
NodeLatency resolveNodeLatency({
  required int liveMs,
  required int? cachedMs,
  required DateTime? cachedAt,
  required bool testing,
  required bool timedOut,
  required DateTime now,
  bool unconfirmed = false,
  bool cacheIsFallback = true,
}) {
  final liveOk = isMeasurableDelay(liveMs);
  final cachedOk = isMeasurableDelay(cachedMs);
  bool isStale() =>
      cachedAt == null || now.difference(cachedAt) > kLatencyStaleAfter;

  if (testing) {
    return NodeLatency(
      LatencyDisplayState.testing,
      liveOk ? liveMs : (cachedOk ? cachedMs : null),
    );
  }
  if (timedOut || liveMs > kDelayTimeoutSentinelMs) {
    return const NodeLatency(LatencyDisplayState.timeout);
  }
  if (unconfirmed && (liveOk || cachedOk)) {
    return NodeLatency(LatencyDisplayState.stale, liveOk ? liveMs : cachedMs);
  }
  if (liveOk) {
    // 实时值一般是这次连接里测到的；只有缓存里恰好是同一个数、且那条记录
    // 很旧或根本不知道是什么时候测的，才说明这个数是很久以前的。
    final stale = cachedOk && cachedMs == liveMs && isStale();
    return NodeLatency(
      stale ? LatencyDisplayState.stale : LatencyDisplayState.success,
      liveMs,
    );
  }
  if (cachedOk && cacheIsFallback) {
    return NodeLatency(
      isStale() ? LatencyDisplayState.stale : LatencyDisplayState.success,
      cachedMs,
    );
  }
  return const NodeLatency(LatencyDisplayState.untested);
}
