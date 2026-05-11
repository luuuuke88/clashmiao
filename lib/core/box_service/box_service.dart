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
        return StubBoxService();
      }
    }
    return StubBoxService();
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

  /// 清除日志
  Future<void> clearLogs();

  /// 监听日志
  Stream<List<String>> watchLogs(String path);
}
