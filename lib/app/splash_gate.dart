import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/features/splash/widget/splash_page.dart';
import 'package:flutter/material.dart';

/// 冷启动时先放开屏动画，放完换成 [ShellPage]。
///
/// 只在**进程冷启动**时出现一次：它挂在路由的根 widget 上，切 tab、弹窗、
/// 热重载都不会重来一遍。用 [AnimatedSwitcher] 交叉淡出，从蓝底切到首页时
/// 不是硬切。
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  var _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      child: _showSplash
          ? SplashPage(
              key: const ValueKey('splash'),
              onFinished: () {
                if (mounted) setState(() => _showSplash = false);
              },
            )
          : const ShellPage(key: ValueKey('shell')),
    );
  }
}
