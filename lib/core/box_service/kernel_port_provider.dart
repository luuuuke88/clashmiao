import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/emulated_kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/platform_kernel_port.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 内核端口单例：Android 走原生协调器（[PlatformKernelPort]），其余平台用
/// [EmulatedKernelPort] 包装 [boxServiceProvider]。
///
/// 接口与模型文件（`kernel_port.dart`）不依赖 Riverpod，Riverpod 接线只在这里。
final kernelPortProvider = Provider<KernelPort>((ref) {
  if (Platform.isAndroid) {
    final port = PlatformKernelPort();
    ref.onDispose(port.dispose);
    return port;
  }
  final port = EmulatedKernelPort(ref.watch(boxServiceProvider));
  ref.onDispose(port.dispose);
  return port;
});
