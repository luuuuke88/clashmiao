import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 当前平台是否应使用 Apple（iOS / macOS）风格的图标。
///
/// 读的是 [defaultTargetPlatform] 而不是 `dart:io` 的 `Platform.isIOS`——
/// 前者可以在 widget test 里用 `debugDefaultTargetPlatformOverride` 直接
/// mock，不需要真机/模拟器就能验证 Android / iOS 两条分支。
bool isApplePlatform() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// 在“Apple 风格”（[apple]）和“其它平台风格”（[other]，含 Android）两个
/// 图标之间，按当前平台选择一个返回。
///
/// 用来替代散落在各调用点的 `Platform.isIOS ? a : b` 判断；供需要裸
/// [IconData]（而不是 [Widget]）的调用点使用，例如自定义按钮组件的
/// `icon: IconData` 字段。
IconData resolveAdaptiveIcon({
  required IconData apple,
  required IconData other,
}) {
  return isApplePlatform() ? apple : other;
}

/// [Icon] 的平台自适应封装：Apple 平台（iOS/macOS）渲染 [apple]，
/// 其它平台（含 Android）渲染 [other]。可以直接当 `icon:` 参数用
/// （`IconButton`/`PopupMenuButton` 等）。
class AdaptiveIcon extends StatelessWidget {
  const AdaptiveIcon({
    super.key,
    required this.apple,
    required this.other,
    this.size,
    this.color,
  });

  final IconData apple;
  final IconData other;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      resolveAdaptiveIcon(apple: apple, other: other),
      size: size,
      color: color,
    );
  }
}
