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
/// 2. 本轮明确判定的超时（[timedOut]：确认失败，或没确认且没有任何旧值）→ 超时；
/// 3. 上一轮到点没确认出结果但有有效旧值（[unconfirmed]）→ 历史值，带旧值
///    （实时值有效用实时值，否则用缓存值）：不能当成新结果，也不能判超时。
///    协调器只对**实时值仍有效**的节点这样标；实时没有值的节点测完一律是
///    失败（内核测失败会删掉测速历史，分组流里表现为 0），缓存里的旧数字
///    顶替不了它。这一条排在裸哨兵前面：开测前就留在实时值里的超时哨兵
///    不能证明本轮失败；
/// 4. 实时值是内核的超时哨兵 → 超时；
/// 5. 实时值有效 → 成功；缓存里是同一个数且测量时间未知或已超过 5 分钟 →
///    历史值（旧版本留下的无时间缓存在确认出新结果前一直算历史值）；
/// 6. 缓存里记着这个节点上次测失败（[cachedFailed]）→ 超时：实时没有值，
///    缓存也已经被失败记录覆盖，不会再有成功的旧数字冒出来；
/// 7. 缓存有值且允许兜底 → 成功 / 历史值（按测量时间）；
/// 8. 否则未测。
///
/// [testing] 要按「分组 + 节点」传：只有这个节点在当前展示的分组里还没出
/// 本轮结果时才为真；已经出了结果的节点直接展示新值。
///
/// [cacheIsFallback] 为 false 时（已连接且有真实实时分组）缓存只参与第 1、3 条
/// 的旧值保留与第 5 条的「是否过期」判断，第 6 条不使用缓存：测完之后实时值
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
  bool cachedFailed = false,
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
  // 本轮明确判定的超时（确认失败，或到点没确认且一点旧值都没有）。
  if (timedOut) {
    return const NodeLatency(LatencyDisplayState.timeout);
  }
  // 本轮没确认、手上有有效旧值：历史值。必须排在裸哨兵前面——开测前就留在
  // 实时值里的超时哨兵证明不了本轮失败。
  if (unconfirmed && (liveOk || cachedOk)) {
    return NodeLatency(LatencyDisplayState.stale, liveOk ? liveMs : cachedMs);
  }
  // 实时值里的超时哨兵（没有本轮标记可参考时）。
  if (liveMs > kDelayTimeoutSentinelMs) {
    return const NodeLatency(LatencyDisplayState.timeout);
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
  // 缓存里记着上次测失败：不再往下拿别的缓存数字兜底。
  if (cachedFailed) {
    return const NodeLatency(LatencyDisplayState.timeout);
  }
  if (cachedOk && cacheIsFallback) {
    return NodeLatency(
      isStale() ? LatencyDisplayState.stale : LatencyDisplayState.success,
      cachedMs,
    );
  }
  return const NodeLatency(LatencyDisplayState.untested);
}
