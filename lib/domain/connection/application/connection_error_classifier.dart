import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:flutter/services.dart' show PlatformException;

/// 连接失败归类之后的类别。
///
/// 目的：把 native [BoxAlert] 的几种类型，以及 `connect()`/`disconnect()`
/// try/catch 里常见的 Dart 异常类型，统一收敛成少数几类人类可读的本地化文案，
/// 而不是把 `e.toString()` / alert 的原始 message 直接糊给用户看
/// （原始文本要么是英文技术堆栈信息，要么是原生侧的内部错误码，普通用户看不懂）。
///
/// 归纳成以下 7 类：
/// - [invalidConfig] 配置解析失败 —— `BoxAlertType.emptyConfiguration`
/// - [vpnPermissionDenied] VPN 权限被拒绝 —— `BoxAlertType.requestVpnPermission`
/// - [notificationPermissionDenied] 通知权限被拒绝 ——
///   `BoxAlertType.requestNotificationPermission`
/// - [serviceStartFailed] 后台服务启动失败 —— `BoxAlertType.createService` /
///   `startService` / `startCommandServer`。这三种原生 alert 分别对应内核服务
///   生命周期里不同的失败阶段（建服务 / 起 command server / 起服务本身），但
///   对用户来说都只是"后台服务没能起来"这一件事，拆开展示没有实际价值，所以
///   归并成一类。
/// - [networkUnavailable] 网络不可用 —— 捕获到 `SocketException`
/// - [timeout] 启动超时 —— 捕获到 `TimeoutException`
/// - [unexpected] 未知错误 —— `BoxAlertType.unknown`（原生传来无法识别的
///   alert 类型）以及其它未归类异常的兜底
enum ConnectionErrorCategory {
  invalidConfig,
  vpnPermissionDenied,
  notificationPermissionDenied,
  serviceStartFailed,
  networkUnavailable,
  timeout,
  unexpected;

  /// 该类别对应的本地化文案。
  String localizedMessage(Translations t) => switch (this) {
    ConnectionErrorCategory.invalidConfig => t.failure.singbox.invalidConfig,
    ConnectionErrorCategory.vpnPermissionDenied =>
      t.failure.connectivity.missingVpnPermission,
    ConnectionErrorCategory.notificationPermissionDenied =>
      t.failure.connectivity.missingNotificationPermission,
    ConnectionErrorCategory.serviceStartFailed => t.failure.singbox.start,
    ConnectionErrorCategory.networkUnavailable =>
      t.failure.connectivity.networkUnavailable,
    ConnectionErrorCategory.timeout => t.failure.singbox.startTimeout,
    ConnectionErrorCategory.unexpected => t.failure.unexpected,
  };
}

/// 把原生上报的 [BoxAlert] 归类。
ConnectionErrorCategory classifyBoxAlert(BoxAlert alert) {
  switch (alert.type) {
    case BoxAlertType.emptyConfiguration:
      return ConnectionErrorCategory.invalidConfig;
    case BoxAlertType.requestVpnPermission:
      return ConnectionErrorCategory.vpnPermissionDenied;
    case BoxAlertType.requestNotificationPermission:
      return ConnectionErrorCategory.notificationPermissionDenied;
    case BoxAlertType.createService:
    case BoxAlertType.startService:
    case BoxAlertType.startCommandServer:
      return ConnectionErrorCategory.serviceStartFailed;
    case BoxAlertType.unknown:
      return ConnectionErrorCategory.unexpected;
  }
}

/// 把 `connect()` / `disconnect()` try/catch 里捕获的异常归类。
///
/// 只识别几种常见、值得单独提示的类型（网络不可用 / 超时），其余（包括
/// method channel 抛出的 `PlatformException`、`FormatException` 等）一律
/// 归入 [ConnectionErrorCategory.unexpected] 兜底 —— 不是漏判，是这些情形
/// 目前没有比"未知错误"更适合展示给用户的分类文案，为避免过度设计，不强行
/// 拆出更多类别。
ConnectionErrorCategory classifyException(Object error) {
  if (error is SocketException) {
    return ConnectionErrorCategory.networkUnavailable;
  }
  if (error is TimeoutException) {
    return ConnectionErrorCategory.timeout;
  }
  return ConnectionErrorCategory.unexpected;
}

/// 分类 + 本地化一步到位，供 `connectionErrorProvider` 的写入点直接使用。
String classifyBoxAlertMessage(BoxAlert alert, Translations t) =>
    classifyBoxAlert(alert).localizedMessage(t);

/// 分类 + 本地化一步到位（异常版本）。
String classifyExceptionMessage(Object error, Translations t) =>
    classifyException(error).localizedMessage(t);

// ─────────────────────────────────────────────────────────────────────────
// 类型化失败（子项目 B）：ConnectionFailure ↔ 文案 / 异常 → ConnectionFailure
// ─────────────────────────────────────────────────────────────────────────

/// 类型化连接失败 → 本地化文案。
///
/// 这是界面展示连接失败的唯一出口：toast 与阻断式弹窗用的都是这里的文案，
/// 不再有第二份按字符串匹配的分类。
String connectionFailureMessage(ConnectionFailure failure, Translations t) {
  return switch (failure) {
    NoActiveProfile() => t.failure.profiles.noActive,
    ConfigMissing() => t.failure.profiles.notFound,
    ProfileStoreReadOnly() => t.failure.profiles.readOnlyUpgrade,
    CoreUnavailable() => t.failure.singbox.coreLibraryMissing,
    PermissionDenied() => t.failure.connectivity.missingVpnPermission,
    StartTimeout() => t.failure.singbox.startTimeout,
    KernelStartFailed(:final code) => switch (code) {
      KernelFailureCode.emptyConfiguration => t.failure.singbox.invalidConfig,
      KernelFailureCode.kernelExited => t.failure.singbox.kernelExited,
      KernelFailureCode.permissionDenied =>
        t.failure.connectivity.missingVpnPermission,
      _ => t.failure.singbox.start,
    },
    KernelUnresponsive() => t.failure.singbox.kernelUnresponsive,
    NativeUnresponsive() => t.failure.connectivity.nativeUnresponsive,
    PlatformFailure() => t.failure.unexpected,
    UnexpectedFailure() => t.failure.unexpected,
  };
}

/// 本地调用（准备产物、`KernelPort.request`）抛出的异常 → [ConnectionFailure]。
///
/// 内核自己的失败不走这里（它们以快照里的 `lastFailure` 到达，由
/// `ConnectionFailure.fromKernel` 映射）。
ConnectionFailure failureFromError(Object error) {
  if (error is KernelPortException) {
    // 端口 2 s 内没有应答：与「状态流失联」同一类问题。
    if (error.code == 'timeout') return const NativeUnresponsive();
    return PlatformFailure(error.code, error.message);
  }
  if (error is PlatformException) {
    return PlatformFailure(error.code, error.message ?? '');
  }
  if (error is TimeoutException) return const StartTimeout();
  return UnexpectedFailure('$error');
}
