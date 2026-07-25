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
  routes: [
    GoRoute(path: '/', builder: (context, state) => const _RootGate()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingPage(),
    ),
  ],
);

class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboardingDone = ref.watch(onboardingDoneProvider);
    return onboardingDone.when(
      data: (done) => done ? const ShellPage() : const OnboardingPage(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const OnboardingPage(),
    );
  }
}
