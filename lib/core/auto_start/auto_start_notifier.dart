import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// macOS 13+ 使用 SMAppService 实现开机启动
/// Windows 使用 Registry 或 Startup folder（后续扩展）
class AutoStartNotifier extends StateNotifier<bool> {
  AutoStartNotifier() : super(false) {
    _init();
  }

  static const _channel = MethodChannel('com.clashmiao/auto_start');

  Future<void> _init() async {
    if (!Platform.isMacOS) return;
    try {
      final enabled = await _channel.invokeMethod<bool>('getAutoStart');
      state = enabled ?? false;
    } catch (_) {
      state = false;
    }
  }

  Future<void> toggle() async {
    if (!Platform.isMacOS) return;
    try {
      final newValue = !state;
      await _channel.invokeMethod('setAutoStart', {'enabled': newValue});
      state = newValue;
    } catch (_) {
      // native 调用失败，保持原状态
    }
  }
}

final autoStartProvider = StateNotifierProvider<AutoStartNotifier, bool>((ref) {
  return AutoStartNotifier();
});
