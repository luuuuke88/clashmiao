/// 界面看到的连接阶段，完全由 `ConnectionMachine` 从内核快照与本地请求派生。
///
/// 对照表见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
/// §5。
enum ConnectionPhase {
  /// 还没有收到任何内核快照。按钮可点：意图先被记录，快照到达后再发送。
  resolving,

  /// 正在连接：有未被内核确认的 on 请求（即便内核仍是 started、revision 相同），
  /// 或 desired=on 而 status≠started（含已连接会话的重载中间态；startedAt 照常保留）。
  connecting,

  /// 已连接，且运行实例使用的就是最新请求的配置。
  connected,

  /// 仍是 started，但已被确认的新配置尚未生效（协调器将重载 / 正在重载）。
  reconnecting,

  /// 正在断开（含「已点断开、请求尚未被内核确认」）。
  disconnecting,

  /// 已断开。可能带 failure（上一次连接失败的原因）。
  disconnected,
}
