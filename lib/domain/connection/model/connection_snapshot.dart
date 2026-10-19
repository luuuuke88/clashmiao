import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';

/// 对外的连接状态（只读）：所有消费者读取的唯一真值，由 `ConnectionMachine`
/// 从内核快照与本地请求记录派生。
class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.phase,
    this.failure,
    this.failureSeq = 0,
    this.startedAt,
    this.origin,
    this.stale = false,
    this.epoch,
    this.attempt,
    this.replayPending = false,
  });

  /// 尚无任何内核快照时的初始值。
  static const initial = ConnectionSnapshot(phase: ConnectionPhase.resolving);

  final ConnectionPhase phase;

  /// 当前应展示的失败；与 [phase] 一同给出（见 spec §5 的失败归属）。
  final ConnectionFailure? failure;

  /// 每出现一个新的、需要提示的失败 +1，永不回退；界面按它去重 toast/弹窗。
  /// 冷启动时已存在于首个快照里的旧失败只展示、不递增。
  final int failureSeq;

  /// 本次连接成功建立的时间；冷启动挂上运行中隧道、或未连接时为 null。
  /// 重载期间保持不变。
  final DateTime? startedAt;

  /// 当前期望状态由谁设定（本地有未确认请求时为 [DesiredSource.app]）；无快照时为 null。
  final DesiredSource? origin;

  /// 与内核的状态流失联：phase 是最后已知值。
  final bool stale;

  /// 当前内核纪元与 attempt（出口 IP 探测按 (epoch, attempt) 作废）。
  final String? epoch;
  final int? attempt;

  /// 当前 attempt 的手选重放尚未被确认。
  final bool replayPending;

  /// 处于过渡态（含 resolving）。界面据此显示加载指示。
  bool get isBusy =>
      phase != ConnectionPhase.connected &&
      phase != ConnectionPhase.disconnected;

  @override
  bool operator ==(Object other) =>
      other is ConnectionSnapshot &&
      other.phase == phase &&
      other.failure == failure &&
      other.failureSeq == failureSeq &&
      other.startedAt == startedAt &&
      other.origin == origin &&
      other.stale == stale &&
      other.epoch == epoch &&
      other.attempt == attempt &&
      other.replayPending == replayPending;

  @override
  int get hashCode => Object.hash(
    phase,
    failure,
    failureSeq,
    startedAt,
    origin,
    stale,
    epoch,
    attempt,
    replayPending,
  );

  @override
  String toString() =>
      'ConnectionSnapshot(${phase.name}, failure=$failure#$failureSeq, '
      'startedAt=$startedAt, origin=${origin?.name}, stale=$stale, '
      'epoch=$epoch, attempt=$attempt, replayPending=$replayPending)';
}
