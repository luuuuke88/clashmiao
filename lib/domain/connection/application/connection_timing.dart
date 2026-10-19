/// 连接状态机与界面过渡用到的时间常量（spec §5、§10.8、§10.9）。
///
/// 状态机本身不读时钟；这些值只用来比较事件携带的时间。
abstract final class ConnectionTiming {
  /// 请求已发出（或已被受理）后，快照的 appliedSeq 迟迟追不上：超过此时长
  /// 先重新同步一次（spec §5）。
  static const unconfirmedRequestTimeout = Duration(seconds: 5);

  /// 重新同步发出后等待结果的上限（略大于端口自身的 2 s 超时）。超过即视为
  /// 重新同步失败。
  static const resyncGrace = Duration(seconds: 3);

  /// 状态流失联（或始终没有首个快照）超过此时长 → nativeUnresponsive（§10.8）。
  static const nativeLostTimeout = Duration(seconds: 10);

  /// 同一意图因 stale / wrongEpoch 回执最多重发的次数，防止与原生互相拉扯。
  static const maxResends = 3;

  /// 发送被「先重新同步」挡住（失联/无响应之后，或 wrongEpoch 回执之后）时，单个
  /// 意图等待有效重同步结果的上限；到期仍未放行 → failed(nativeUnresponsive)。
  static const resyncWaitTimeout = Duration(seconds: 10);

  /// 同一次等待中最多发起的重新同步次数（含首次）；用尽仍未放行 → failed。
  static const maxResyncAttempts = 3;

  /// 一次重新同步失败（current() 抛错、宽限到期、取回的仍是旧纪元）后，下一次
  /// 重试前的间隔。
  static const resyncRetryDelay = Duration(seconds: 1);

  /// KernelPort 契约（spec §2）：`request()` / `current()` 必须在此时长内返回或抛
  /// `KernelPortException`。状态机不自己计时这一段，只把它当作估算预算的前提。
  static const kernelPortCallBound = Duration(seconds: 2);

  /// **重试阶段**的最坏耗时估算，即常说的「约 40 s」：从首次发送起，到最后一次重发
  /// 被受理（或意图因反复拒绝 / 重同步用尽而失败）为止。每次发送的回执不超过
  /// [kernelPortCallBound]；每次 wrongEpoch 之后等待有效重同步结果不超过
  /// [resyncWaitTimeout]；同一意图最多重发 [maxResends] 次——
  /// (3 + 1) × 2 s + 3 × 10 s = 38 s。
  ///
  /// 它**不是**整个请求 Future 的上界。最后一次请求被受理之后，终结由原生协调器
  /// 给出：启动 / 重载最长 30 s 启动超时，停止时单个阻塞调用超过 20 s 报
  /// kernelUnresponsive（停止仍会在调用返回后完成）；快照迟迟追不上 appliedSeq 时，
  /// 状态机另以 [unconfirmedRequestTimeout] + [resyncGrace] 判 nativeUnresponsive。
  /// 发送之前准备启动产物（本地文件 IO）也不计在内。
  static Duration get retryPhaseBudget =>
      kernelPortCallBound * (maxResends + 1) + resyncWaitTimeout * maxResends;

  /// 界面加载指示延迟出现的时间（§10.9：120–150 ms 之间），防止闪烁。
  static const loadingIndicatorDelay = Duration(milliseconds: 140);
}
