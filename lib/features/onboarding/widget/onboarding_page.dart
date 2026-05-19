import 'package:clashmiao/core/onboarding/onboarding_state.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _State();
}

class _State extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await markOnboardingDone(prefs);
    if (mounted) {
      ref.invalidate(onboardingDoneProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(onPressed: _finish, child: const Text('跳过')),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _WelcomePage(
                    onNext: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  _ImportPage(
                    onImported: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ),
                  _ModePage(onDone: _finish),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const FlutterLogo(size: 80),
        const SizedBox(height: 24),
        Text(
          '欢迎使用 ClashMiao',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '一个简洁的代理管理工具，支持 Android / iOS / 桌面端',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: onNext, child: const Text('下一步')),
      ],
    );
  }
}

class _ImportPage extends ConsumerWidget {
  const _ImportPage({required this.onImported});
  final VoidCallback onImported;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.link, size: 64),
        const SizedBox(height: 24),
        Text('添加订阅', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('粘贴订阅链接或扫描二维码'),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            await showProfileFormDialog(context, ref);
            onImported();
          },
          child: const Text('添加订阅'),
        ),
        TextButton(onPressed: onImported, child: const Text('稍后添加')),
      ],
    );
  }
}

class _ModePage extends StatelessWidget {
  const _ModePage({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.tune, size: 64),
        const SizedBox(height: 24),
        Text('选择模式', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '智能模式：国内直连，海外走代理（推荐）\n全局模式：所有流量走代理',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(onPressed: onDone, child: const Text('开始使用')),
      ],
    );
  }
}
