// 连接状态的只读派生 provider：所有消费者读同一份真值（控制器的
// [ConnectionSnapshot]），不再各自订阅底层内核状态。

import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 当前连接阶段。
final connectionPhaseProvider = Provider<ConnectionPhase>((ref) {
  return ref.watch(connectionControllerProvider.select((s) => s.phase));
});

/// 当前是否已连接（`phase == connected`）。名字与类型与迁移前一致。
///
/// 重载中（`reconnecting`）与「已发出连接请求、尚未确认」都不算已连接。
final isConnectedProvider = Provider<bool>((ref) {
  return ref.watch(
    connectionControllerProvider.select(
      (s) => s.phase == ConnectionPhase.connected,
    ),
  );
});

/// 本次连接成功建立的时间；挂上早就在跑的隧道（冷启动）、未连接时为 null——
/// 界面此时不显示时长，宁可不显示也不从 0 开始数。
final connectionStartedAtProvider = Provider<DateTime?>((ref) {
  return ref.watch(connectionControllerProvider.select((s) => s.startedAt));
});

/// 当前应展示的失败及其序号。
typedef ConnectionFailureView = ({ConnectionFailure? failure, int seq});

/// 连接失败（只读派生）。界面按 [ConnectionFailureView.seq] 去重：每个新失败
/// seq 递增，冷启动时已存在的旧失败只展示、不递增（不会重复弹窗）。
final connectionFailureProvider = Provider<ConnectionFailureView>((ref) {
  return ref.watch(
    connectionControllerProvider.select(
      (s) => (failure: s.failure, seq: s.failureSeq),
    ),
  );
});
