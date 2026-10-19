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

  /// 界面加载指示延迟出现的时间（§10.9：120–150 ms 之间），防止闪烁。
  static const loadingIndicatorDelay = Duration(milliseconds: 140);
}
