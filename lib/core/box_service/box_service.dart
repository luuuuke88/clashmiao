import 'dart:io';

import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/box_service/ffi_box_service.dart';
import 'package:clashmiao/core/box_service/platform_box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';

/// sing-box 核心服务接口
///
/// 统一的抽象层，iOS/Android 通过 PlatformChannel 实现，
/// macOS/Windows/Linux 通过 FFI 实现
abstract interface class BoxService {
  /// 工厂构造，根据平台自动选择实现
  /// 桌面端加载核心库失败时回退到桩实现
  factory BoxService() {
    if (Platform.isAndroid || Platform.isIOS) {
      return PlatformBoxService();
    } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        return FFIBoxService();
      } catch (_) {
        // 桌面端 libcore 缺失/加载失败。以前这里静默降级，界面一切正常但点
        // 什么都不工作——用 coreLoadFailed 标记出来，让首页能明确告警。
        return const StubBoxService(reason: StubReason.coreLoadFailed);
      }
    }
    return const StubBoxService();
  }

  /// 初始化服务
  Future<void> init();

  /// 配置目录和初始参数
  Future<void> setup(AppDirectories directories, {bool debug = false});

  /// 验证配置文件是否有效
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  });

  /// 设置配置选项（必须在 start 前调用）
  Future<void> changeConfigOptions(String jsonOptions);

  /// 启动 sing-box 服务
  Future<void> start(String configPath, {String name = ''});

  /// 停止服务
  Future<void> stop();

  /// 重启服务
  Future<void> restart(String configPath, {String name = ''});

  /// 切换出站代理节点
  Future<void> selectOutbound(String groupTag, String outboundTag);

  /// 触发分组的延迟测试
  Future<void> urlTest(String groupTag);

  /// 监听服务状态变化
  Stream<BoxStatus> watchStatus();

  /// 监听非致命错误：VPN 权限缺失、配置为空、Service 启动失败等。
  Stream<BoxAlert> watchAlerts();

  /// 监听流量统计
  Stream<BoxStats> watchStats();

  /// 监听代理分组列表
  Stream<List<OutboundGroup>> watchGroups();

  /// 生成完整配置
  Future<String?> generateFullConfig(String path);

  /// 生成一份新的 WARP 账号凭证 + WireGuard 配置（Cloudflare WARP 注册）。
  ///
  /// [licenseKey] 为空字符串表示走免费额度注册；非空则视为 WARP+ license。
  /// [previousAccountId] / [previousAccessToken] 传入已有账号信息，native
  /// 侧会尝试续用该账号而不是重新注册一个新的；首次生成留空/null 即可。
  ///
  /// 成功时返回 native 原始 JSON 字符串（形如
  /// `{"account-id":..,"access-token":..,"log":..,"config":{...}}`），
  /// 由调用方解析后写入 [NetworkSettings] 的 warpAccountId /
  /// warpAccessToken / warpWireguardConfig 三个字段。
  ///
  /// 错误处理跟 [generateFullConfig] 一样并不统一：有的平台把失败包装成
  /// 抛出的异常（例如 Android 的 `PlatformException`），有的用返回 null
  /// 表示（桌面 FFI 的 error 前缀约定）——调用方需要同时处理这两种情况。
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  });

  /// 清除日志
  Future<void> clearLogs();

  /// 监听日志
  Stream<List<String>> watchLogs(String path);

  /// 监听网络切换事件（WiFi ↔ 蜂窝，或短暂断网恢复）。
  /// 仅在已连接状态下由调用方决定是否触发重连。
  Stream<void> watchNetworkChanged();

  /// 强制重置隧道（iOS 专用：取消用户主动断开标记，触发重连）。
  /// 其他平台为空操作。
  Future<void> resetTunnel();
}
