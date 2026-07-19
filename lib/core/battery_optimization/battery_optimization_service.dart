import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Android 电池优化豁免的薄封装。
///
/// 背景：原生桥接层（`android/.../bridge/MethodBridge.kt` 的
/// `CHANNEL_PLATFORM`）早就注册好了 `is_ignoring_battery_optimizations` /
/// `request_ignore_battery_optimizations` 两个方法，但这两个方法没有走 Pigeon，
/// Dart 侧此前也是零调用方——本类是唯一的调用方，直接用裸 [MethodChannel]
/// （故意不接 Pigeon codegen，那是更大范围的改动，不在这次范围内）。
///
/// 只在 Android 上有意义；是否展示入口由调用方（settings 页）自行做
/// `Platform.isAndroid` 门禁，本类不做任何平台判断，方便直接注入 mock
/// channel 测试。
class BatteryOptimizationService {
  BatteryOptimizationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.clashmiao.app/platform');

  final MethodChannel _channel;

  /// 当前 App 是否已被系统排除在电池优化名单外（即已豁免）。
  ///
  /// 调用失败（例如平台侧异常）时保守返回 false，让 UI 继续展示"未豁免"，
  /// 用户可以重试，而不是让异常向上传播、拖垮设置页。
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'is_ignoring_battery_optimizations',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('BatteryOptimizationService: 查询豁免状态失败，已忽略: $e');
      return false;
    }
  }

  /// 弹系统对话框请求豁免。
  ///
  /// 返回值对应 Android 侧 `resultCode == Activity.RESULT_OK`
  /// （用户是否同意豁免）。调用失败时同样保守返回 false。
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'request_ignore_battery_optimizations',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('BatteryOptimizationService: 请求豁免失败，已忽略: $e');
      return false;
    }
  }
}

final batteryOptimizationServiceProvider =
    Provider<BatteryOptimizationService>((ref) {
      return BatteryOptimizationService();
    });
