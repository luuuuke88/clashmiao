import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;

/// 跨功能的页面跳转目标。
///
/// 页面只在 `app/` 里构造（见 `app/router/app_routes.dart`）；功能之间要打开
/// 别的功能的页面，只写 [AppRoute]，由 [AppRouteScope] 提供真正的页面构造器。
enum AppRoute {
  /// 配置选项页（整页）。
  configOptions,

  /// 规则资源页（整页）。
  assets,

  /// 日志页（整页）。
  logs,

  /// 订阅管理页。注册的是可嵌入底部弹层的形态（`embedInSheet: true`），
  /// 用 [buildAppRoute] 取页面放进弹层，而不是 [pushAppRoute] 整页压栈。
  profiles,
}

typedef AppRouteBuilder = Widget Function(BuildContext context);

/// 在 `MaterialApp` 外层提供 [AppRoute] 到页面构造器的映射。
class AppRouteScope extends InheritedWidget {
  const AppRouteScope({
    super.key,
    required this.builders,
    required super.child,
  });

  final Map<AppRoute, AppRouteBuilder> builders;

  static AppRouteScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppRouteScope>();
    if (scope == null) {
      throw FlutterError('AppRouteScope 缺失：请在 MaterialApp 外层放置 AppRouteScope');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(AppRouteScope oldWidget) =>
      builders != oldWidget.builders;
}

AppRouteBuilder _resolve(BuildContext context, AppRoute route) {
  final builder = AppRouteScope.of(context).builders[route];
  if (builder == null) {
    throw FlutterError('AppRoute.${route.name} 未注册');
  }
  return builder;
}

/// 等价于 `Navigator.of(context, rootNavigator: rootNavigator)`
/// 上 push 一个以 `builders[route]` 为 builder 的 `MaterialPageRoute`。
Future<T?> pushAppRoute<T>(
  BuildContext context,
  AppRoute route, {
  bool rootNavigator = false,
}) {
  final builder = _resolve(context, route);
  return Navigator.of(
    context,
    rootNavigator: rootNavigator,
  ).push<T>(MaterialPageRoute<T>(builder: builder));
}

/// 取 [route] 对应的页面 widget，不压栈。用于要把页面放进底部弹层等非整页容器里的场景。
Widget buildAppRoute(BuildContext context, AppRoute route) =>
    _resolve(context, route)(context);
