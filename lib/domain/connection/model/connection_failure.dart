import 'package:clashmiao/core/box_service/kernel_port.dart';

/// 连接失败的类型化原因。文案由 `connection_error_classifier` 负责，这里只有
/// 语义，不含任何 i18n 或 Flutter 依赖。
sealed class ConnectionFailure {
  const ConnectionFailure();

  /// 把内核快照里的 [KernelFailure] 映射为界面层失败。
  factory ConnectionFailure.fromKernel(KernelFailure f) {
    switch (f.code) {
      case KernelFailureCode.startTimeout:
        return const StartTimeout();
      case KernelFailureCode.permissionDenied:
        return const PermissionDenied();
      case KernelFailureCode.kernelUnresponsive:
        return const KernelUnresponsive();
      case KernelFailureCode.coreUnavailable:
        return const CoreUnavailable();
      case KernelFailureCode.emptyConfiguration:
      case KernelFailureCode.createService:
      case KernelFailureCode.startService:
      case KernelFailureCode.startCommandServer:
      case KernelFailureCode.kernelExited:
        return KernelStartFailed(f.code, f.message);
      case KernelFailureCode.unknown:
        return UnexpectedFailure(f.message);
    }
  }

  /// 致命类：需要阻断式提示（并在数据分析开启时上报）。
  bool get isFatal => false;
}

/// 没有选中的订阅/配置。
final class NoActiveProfile extends ConnectionFailure {
  const NoActiveProfile();

  @override
  bool operator ==(Object other) => other is NoActiveProfile;

  @override
  int get hashCode => (NoActiveProfile).hashCode;

  @override
  String toString() => 'NoActiveProfile';
}

/// 配置文件缺失或为空。
final class ConfigMissing extends ConnectionFailure {
  const ConfigMissing();

  @override
  bool operator ==(Object other) => other is ConfigMissing;

  @override
  int get hashCode => (ConfigMissing).hashCode;

  @override
  String toString() => 'ConfigMissing';
}

/// 运行时配置文件留存已达上限且无法证明可以回收：为避免继续写盘，这次连接
/// 被拒绝。用户重启应用通常可以恢复。
final class RuntimeFilesExhausted extends ConnectionFailure {
  const RuntimeFilesExhausted();

  @override
  bool operator ==(Object other) => other is RuntimeFilesExhausted;

  @override
  int get hashCode => (RuntimeFilesExhausted).hashCode;

  @override
  String toString() => 'RuntimeFilesExhausted';
}

/// 核心库不可用（桌面 libcore 加载失败）。
final class CoreUnavailable extends ConnectionFailure {
  const CoreUnavailable();

  @override
  bool operator ==(Object other) => other is CoreUnavailable;

  @override
  int get hashCode => (CoreUnavailable).hashCode;

  @override
  String toString() => 'CoreUnavailable';
}

/// VPN 授权被拒绝/未授予。
final class PermissionDenied extends ConnectionFailure {
  const PermissionDenied();

  @override
  bool operator ==(Object other) => other is PermissionDenied;

  @override
  int get hashCode => (PermissionDenied).hashCode;

  @override
  String toString() => 'PermissionDenied';
}

/// 协调器内的启动超时。
final class StartTimeout extends ConnectionFailure {
  const StartTimeout();

  @override
  bool operator ==(Object other) => other is StartTimeout;

  @override
  int get hashCode => (StartTimeout).hashCode;

  @override
  String toString() => 'StartTimeout';
}

/// 内核启动/重载失败，或意外退出。[code] 是原生失败码（`emptyConfiguration`、
/// `createService`、`startService`、`startCommandServer`、`kernelExited`）。
final class KernelStartFailed extends ConnectionFailure {
  const KernelStartFailed(this.code, this.message);

  final KernelFailureCode code;
  final String message;

  @override
  bool get isFatal => switch (code) {
    KernelFailureCode.emptyConfiguration ||
    KernelFailureCode.createService ||
    KernelFailureCode.startService ||
    KernelFailureCode.startCommandServer => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is KernelStartFailed &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(KernelStartFailed, code, message);

  @override
  String toString() => 'KernelStartFailed(${code.name}, $message)';
}

/// 内核的某个阻塞调用超过 20 s 仍未返回（状态保持 stopping）。
final class KernelUnresponsive extends ConnectionFailure {
  const KernelUnresponsive();

  @override
  bool get isFatal => true;

  @override
  bool operator ==(Object other) => other is KernelUnresponsive;

  @override
  int get hashCode => (KernelUnresponsive).hashCode;

  @override
  String toString() => 'KernelUnresponsive';
}

/// 原生桥接失联（状态流断开超过 10 s，或请求长时间得不到确认）。
final class NativeUnresponsive extends ConnectionFailure {
  const NativeUnresponsive();

  @override
  bool operator ==(Object other) => other is NativeUnresponsive;

  @override
  int get hashCode => (NativeUnresponsive).hashCode;

  @override
  String toString() => 'NativeUnresponsive';
}

/// 平台调用失败（RPC 抛错、被内核反复拒绝等）。[code] 是平台错误码。
final class PlatformFailure extends ConnectionFailure {
  const PlatformFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is PlatformFailure &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(PlatformFailure, code, message);

  @override
  String toString() => 'PlatformFailure($code, $message)';
}

/// 无法归类的失败。
final class UnexpectedFailure extends ConnectionFailure {
  const UnexpectedFailure([this.message = '']);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is UnexpectedFailure && other.message == message;

  @override
  int get hashCode => Object.hash(UnexpectedFailure, message);

  @override
  String toString() => 'UnexpectedFailure($message)';
}
