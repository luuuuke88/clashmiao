import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/core/onboarding/onboarding_state.dart';
import 'package:clashmiao/features/onboarding/widget/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 根 Navigator 的 key，导出给需要"从没有 BuildContext 的地方"（比如
/// main.dart 里的启动自动检查更新钩子，见 core/update/startup_update_check.dart）
/// 拿一个可用 BuildContext 的场景使用。
final appRouterNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: appRouterNavigatorKey,
  initialLocation: '/',
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context);
    final done = container.read(onboardingDoneProvider).valueOrNull;
    if (done == null || done == true) return null;
    if (state.matchedLocation == '/onboarding') return null;
    return '/onboarding';
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ShellPage()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
  ],
);
