import 'package:clashmiao/domain/connection/model/connection_failure.dart';

/// 一次 connect / disconnect 请求的终结结果（spec §10.6）。每个请求恰好得到一个。
sealed class RequestOutcome {
  const RequestOutcome();
}

/// 目标达成：connect → 已 connected；disconnect → 已 stopped。
final class RequestSucceeded extends RequestOutcome {
  const RequestSucceeded();

  @override
  bool operator ==(Object other) => other is RequestSucceeded;

  @override
  int get hashCode => (RequestSucceeded).hashCode;

  @override
  String toString() => 'RequestSucceeded';
}

/// 准备失败、RPC 失败、内核把该请求置为失败，或内核失联。
final class RequestFailed extends RequestOutcome {
  const RequestFailed(this.failure);

  final ConnectionFailure failure;

  @override
  bool operator ==(Object other) =>
      other is RequestFailed && other.failure == failure;

  @override
  int get hashCode => Object.hash(RequestFailed, failure);

  @override
  String toString() => 'RequestFailed($failure)';
}

/// 被更新的请求取代（更新的请求已被受理，或意图在发送前就被新意图替换）。
final class RequestSuperseded extends RequestOutcome {
  const RequestSuperseded();

  @override
  bool operator ==(Object other) => other is RequestSuperseded;

  @override
  int get hashCode => (RequestSuperseded).hashCode;

  @override
  String toString() => 'RequestSuperseded';
}

/// 内核纪元变化（原生进程重启）：请求已不可能再被确认。
final class RequestInterrupted extends RequestOutcome {
  const RequestInterrupted();

  @override
  bool operator ==(Object other) => other is RequestInterrupted;

  @override
  int get hashCode => (RequestInterrupted).hashCode;

  @override
  String toString() => 'RequestInterrupted';
}
