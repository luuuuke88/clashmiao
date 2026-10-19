/// sing-box 服务在启动/运行过程中向 UI 上报的非致命错误。
///
/// 对应 Android `constant.Alert` 枚举（[Alert.kt](../../../android/app/src/main/kotlin/com/clashmiao/clashmiao/constant/Alert.kt)），
/// 以及 iOS / macOS Network Extension 之后会复用同一套 type 名。
enum BoxAlertType {
  requestVpnPermission,
  requestNotificationPermission,
  emptyConfiguration,
  startCommandServer,
  createService,
  startService,
  unknown;

  /// 容错解析原生侧 PascalCase 字符串（"RequestVPNPermission" 等），
  /// 不识别就降级成 [unknown] 而非抛异常。
  static BoxAlertType parse(String? raw) {
    switch (raw) {
      case 'RequestVPNPermission':
        return BoxAlertType.requestVpnPermission;
      case 'RequestNotificationPermission':
        return BoxAlertType.requestNotificationPermission;
      case 'EmptyConfiguration':
        return BoxAlertType.emptyConfiguration;
      case 'StartCommandServer':
        return BoxAlertType.startCommandServer;
      case 'CreateService':
        return BoxAlertType.createService;
      case 'StartService':
        return BoxAlertType.startService;
      default:
        return BoxAlertType.unknown;
    }
  }
}

class BoxAlert {
  const BoxAlert({required this.type, this.message});

  final BoxAlertType type;
  final String? message;

  @override
  String toString() => 'BoxAlert($type${message == null ? '' : ': $message'})';
}

/// 单一权威判定："致命"指内核压根没起来（建服务/起服务/空配置），
/// UI 层必须让用户真正看到并确认，而不是能被划走错过的 toast。
/// `ConnectionController`（强制回退 BoxStopped）和 `ShellPage`（选择
/// toast 还是阻断式弹窗）两处都要用同一份判断，避免各自维护一份判据、
/// 后续加新 alert 类型时两边判断悄悄漂移不一致。
extension BoxAlertTypeFatality on BoxAlertType {
  bool get isFatal =>
      this == BoxAlertType.startService ||
      this == BoxAlertType.createService ||
      this == BoxAlertType.emptyConfiguration;
}
