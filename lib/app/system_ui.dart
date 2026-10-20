import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全 App 统一的系统栏样式：状态栏与导航栏**都透明**，图标明暗跟主题。
///
/// 以前只有 `ShellPage` 设置了样式，而且导航栏是写死的实色（深色 `#16161A`、浅色
/// 白）：深色主题页面底是纯黑，悬浮导航胶囊下面就露出一条与页面背景不同的色带；
/// 压进来的二级页面没有自己的样式，沿用上一个值，跳页时系统栏还会闪一下。
///
/// - `systemNavigationBarContrastEnforced: false`：Android 10+ 的三键导航在栏
///   透明时会自动垫一层半透明遮罩来保对比度，这层遮罩正是色带的另一个来源；
///   页面背景是我们自己控制的，对比度由主题保证。
/// - 分隔线透明：部分 ROM 在导航栏上沿画一条线。
SystemUiOverlayStyle appSystemUiOverlayStyle(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: isLight
        ? Brightness.dark
        : Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );
}

/// 挂在 `MaterialApp.builder` 里：整个 App 一个兜底的系统栏样式（随当前主题明暗），
/// 并在移动端开启 edge-to-edge，让内容画到系统栏后面。
///
/// 兜底的意思是：页面自己再包一层 `AnnotatedRegion`（或 `AppBar` 自带的样式）
/// 仍然优先；没有的页面也不会沿用上一页遗留的值。
class SystemUiScope extends StatefulWidget {
  const SystemUiScope({super.key, required this.child});

  final Widget child;

  @override
  State<SystemUiScope> createState() => _SystemUiScopeState();
}

class _SystemUiScopeState extends State<SystemUiScope> {
  @override
  void initState() {
    super.initState();
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: appSystemUiOverlayStyle(Theme.of(context).brightness),
      child: widget.child,
    );
  }
}
