/// 界面看到的连接阶段，完全由 `ConnectionMachine` 从内核快照与本地请求派生。
///
/// 对照表见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
/// §5。
enum ConnectionPhase {
  /// 还没有收到任何内核快照。按钮可点：意图先被记录，快照到达后再发送。
  resolving,

  /// 正在连接（含「已点连接、请求尚未被内核确认」）。
  connecting,

  /// 已连接，且运行实例使用的就是最新请求的配置。
  connected,

  /// 已连接过的会话正在应用新配置 / 重载。
  reconnecting,

  /// 正在断开（含「已点断开、请求尚未被内核确认」）。
  disconnecting,

  /// 已断开。可能带 failure（上一次连接失败的原因）。
  disconnected,
}
