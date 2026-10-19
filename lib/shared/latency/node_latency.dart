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

  /// 历史值：超过 5 分钟（或旧版本留下、不知何时测的）的数字，降低不透明度显示。
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

/// 把「实时值 / 缓存值 / 是否在测 / 本轮是否超时」归结成一个展示状态。
///
/// 纯函数，代理页的每一行和首页节点胶囊共用它，保证两处口径一致。
/// 优先级自上而下：
/// 1. 实时值有效 → 成功（缓存里同值且测量时间太久则为历史值）；
/// 2. 正在测 → 测量中（带上缓存里的旧值）；
/// 3. 内核给了超时哨兵、或本轮测完没结果 → 超时；
/// 4. 缓存有值 → 成功 / 历史值（按测量时间）；
/// 5. 否则未测。
///
/// [cacheIsFallback] 为 false 时（已连接且有真实实时分组）缓存只参与第 1 条
/// 的「是否过期」判断，第 2、4 条不使用缓存。
///
/// 第 3 条排在第 4 条前面：测过一轮没结果的节点，不能再拿缓存里冻结的旧数字
/// 顶替——那会显示一个永远不变的假数字。
NodeLatency resolveNodeLatency({
  required int liveMs,
  required int? cachedMs,
  required DateTime? cachedAt,
  required bool testing,
  required bool timedOut,
  required DateTime now,
  bool cacheIsFallback = true,
}) {
  final cachedOk = isMeasurableDelay(cachedMs);
  // 缓存能不能在实时值缺席时顶上：已连接且拿到了真实的实时分组时不能——
  // 那样某个测失败的节点会一直显示缓存里冻结的旧数字。此时缓存只用来判断
  // 「实时值是不是很久以前测的」。
  final fallbackOk = cachedOk && cacheIsFallback;
  bool isStale() =>
      cachedAt == null || now.difference(cachedAt) > kLatencyStaleAfter;

  if (isMeasurableDelay(liveMs)) {
    // 实时值本身就是这次连接里测到的；只有缓存里恰好是同一个数、且那条记录
    // 已经很旧时，才说明这个数是很久以前测的。
    final stale =
        cachedOk && cachedMs == liveMs && cachedAt != null && isStale();
    return NodeLatency(
      stale ? LatencyDisplayState.stale : LatencyDisplayState.success,
      liveMs,
    );
  }
  if (testing) {
    return NodeLatency(
      LatencyDisplayState.testing,
      fallbackOk && !timedOut ? cachedMs : null,
    );
  }
  if (liveMs > kDelayTimeoutSentinelMs || timedOut) {
    return const NodeLatency(LatencyDisplayState.timeout);
  }
  if (fallbackOk) {
    return NodeLatency(
      isStale() ? LatencyDisplayState.stale : LatencyDisplayState.success,
      cachedMs,
    );
  }
  return const NodeLatency(LatencyDisplayState.untested);
}
