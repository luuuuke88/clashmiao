import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// MIUI / HyperOS「自启动」权限的状态。
enum MiuiAutoStartStatus {
  /// 不是 MIUI / HyperOS（或当前平台没有这个概念）：界面上不应出现任何入口。
  unsupported,

  /// 系统已允许本应用自启动。
  allowed,

  /// 系统拒绝本应用自启动：开机与更新后的广播到不了本应用，无法自动恢复连接。
  denied,

  /// 确认是 MIUI / HyperOS，但读不出权限状态。
  unknown,
}

/// MIUI / HyperOS 自启动权限的薄封装。
///
/// 背景：MIUI 在 AOSP 之外加了一个私有开关（自启动）。它被拒绝时，开机广播和
/// 「应用更新后」广播在系统派发阶段就被丢掉，进程都不会起来，按持久化意图
/// 恢复 VPN 的路径根本走不到。原生桥接层（`MethodBridge.kt`）提供
/// `get_miui_autostart_status` / `open_miui_autostart_settings` 两个方法，
/// 与 [BatteryOptimizationService] 一样走裸 [MethodChannel]，不接 Pigeon。
///
/// 平台门禁由调用方做；本类不做平台判断，方便注入 mock channel 测试。
class AutoStartPermissionService {
  AutoStartPermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.clashmiao.app/platform');

  final MethodChannel _channel;

  /// 查询当前自启动权限状态。
  ///
  /// - 平台根本没实现该方法（[MissingPluginException]，例如非 Android、测试宿主）
  ///   或返回 null：按 [MiuiAutoStartStatus.unsupported]，入口被藏起来。
  /// - 其它异常、不认识的字符串：[MiuiAutoStartStatus.unknown]。
  Future<MiuiAutoStartStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'get_miui_autostart_status',
      );
      if (raw == null) return MiuiAutoStartStatus.unsupported;
      return switch (raw) {
        'unsupported' => MiuiAutoStartStatus.unsupported,
        'allowed' => MiuiAutoStartStatus.allowed,
        'denied' => MiuiAutoStartStatus.denied,
        _ => MiuiAutoStartStatus.unknown,
      };
    } on MissingPluginException {
      return MiuiAutoStartStatus.unsupported;
    } catch (e) {
      debugPrint('AutoStartPermissionService: 查询自启动状态失败，已忽略: $e');
      return MiuiAutoStartStatus.unknown;
    }
  }

  /// 打开系统的自启动管理页（找不到则退回应用详情页）。
  ///
  /// 返回是否成功启动了某个系统页面；任何异常都返回 false。
  Future<bool> openSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'open_miui_autostart_settings',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('AutoStartPermissionService: 打开自启动设置失败，已忽略: $e');
      return false;
    }
  }
}

final autoStartPermissionServiceProvider = Provider<AutoStartPermissionService>(
  (ref) => AutoStartPermissionService(),
);
