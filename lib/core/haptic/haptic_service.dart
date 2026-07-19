import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 与 settings_page.dart `_BoolPreferenceTile`（"触觉反馈"开关）共用的 pref key。
const _hapticFeedbackPrefKey = 'clashmiao_haptic_feedback';

/// 默认开启，和 settings 页该开关的 `defaultValue: true` 保持一致。
const _hapticFeedbackDefault = true;

/// 触觉反馈的薄封装。
///
/// 背景：设置页的"触觉反馈"开关此前只把 [_hapticFeedbackPrefKey] 写进
/// SharedPreferences，全代码库没有任何地方读取它——开关本身不产生任何
/// 实际效果。本类是唯一的读取方，让开关真正生效：偏好开启时转发到系统
/// [HapticFeedback]，关闭时整个调用是 no-op。
///
/// 每次调用都重新读一次 pref（不做缓存），确保用户在设置页切换开关后
/// 立刻生效，不需要重启 App 或重新连接。
class HapticService {
  HapticService(this._ref);

  final Ref _ref;

  bool get _enabled {
    try {
      final prefs = _ref.read(sharedPreferencesProvider).requireValue;
      return prefs.getBool(_hapticFeedbackPrefKey) ?? _hapticFeedbackDefault;
    } catch (e) {
      // 触觉反馈是锦上添花的副作用，绝不能因为 prefs 还没就绪之类的边缘
      // 情况抛出异常、拖累调用方（VPN 连接/断开）主流程。
      debugPrint('HapticService: 读取偏好失败，回退默认值: $e');
      return _hapticFeedbackDefault;
    }
  }

  /// VPN 连接成功时使用。
  Future<void> heavyImpact() => _dispatch(HapticFeedback.heavyImpact);

  /// 用户断开连接成功时使用。
  Future<void> mediumImpact() => _dispatch(HapticFeedback.mediumImpact);

  Future<void> lightImpact() => _dispatch(HapticFeedback.lightImpact);

  Future<void> _dispatch(Future<void> Function() invoke) async {
    if (!_enabled) return;
    try {
      await invoke();
    } catch (e) {
      // 平台没有实现该 MethodChannel（例如部分桌面平台或测试环境）时静默
      // 忽略——触觉反馈失败绝不能拖垮连接/断开流程。
      debugPrint('HapticService: 触觉反馈调用失败，已忽略: $e');
    }
  }
}

final hapticServiceProvider = Provider<HapticService>((ref) {
  return HapticService(ref);
});
