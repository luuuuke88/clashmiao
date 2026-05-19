import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/core/onboarding/onboarding_state.dart';
import 'package:clashmiao/features/onboarding/widget/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
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
