import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// UI / 消费者测试用的假控制器：直接以给定快照为状态，不接内核端口、不跑状态机。
///
/// 用法：
/// ```dart
/// connectionControllerProvider.overrideWith(
///   (ref) => FakeConnectionController(ref, phase: ConnectionPhase.connected),
/// )
/// ```
/// 之后通过 `container.read(connectionControllerProvider.notifier)` 拿到它，用
/// [emit] / [set] 推状态，用 [toggleCalls] 等计数断言交互。
class FakeConnectionController extends ConnectionController {
  FakeConnectionController(
    Ref ref, {
    ConnectionPhase phase = ConnectionPhase.disconnected,
    ConnectionSnapshot? snapshot,
  }) : super.preset(ref, snapshot ?? ConnectionSnapshot(phase: phase));

  int toggleCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int applyConfigCalls = 0;

  void emit(ConnectionPhase phase) => state = ConnectionSnapshot(phase: phase);

  void set(ConnectionSnapshot snapshot) => state = snapshot;

  @override
  Future<RequestOutcome> toggle() async {
    toggleCalls++;
    return const RequestSucceeded();
  }

  @override
  Future<RequestOutcome> connect() async {
    connectCalls++;
    return const RequestSucceeded();
  }

  @override
  Future<RequestOutcome> disconnect() async {
    disconnectCalls++;
    return const RequestSucceeded();
  }

  @override
  Future<RequestOutcome> applyConfig() async {
    applyConfigCalls++;
    return const RequestSucceeded();
  }
}
