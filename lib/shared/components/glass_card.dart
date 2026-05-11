import 'dart:ui';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';

/// 毛玻璃卡片组件
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(16.0),
    this.blur = 12.0,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: aiUi.glassColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: aiUi.borderColor),
            boxShadow: aiUi.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}
