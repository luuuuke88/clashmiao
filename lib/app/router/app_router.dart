import 'package:clashmiao/app/splash_gate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 根 Navigator 的 key，导出给需要"从没有 BuildContext 的地方"（比如
/// main.dart 里的启动自动检查更新钩子，见 core/update/startup_update_check.dart）
/// 拿一个可用 BuildContext 的场景使用。
final appRouterNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: appRouterNavigatorKey,
  initialLocation: '/',
  routes: [GoRoute(path: '/', builder: (context, state) => const SplashGate())],
);
