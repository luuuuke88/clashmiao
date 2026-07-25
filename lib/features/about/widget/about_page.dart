import 'dart:async';
import 'dart:ui';

import 'package:clashmiao/core/config/build_config.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/update_available_dialog.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  late final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();
  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0
                        : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: CustomScrollView(
                physics: const NeverScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'About ClashMiao',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                ? Colors.white
                                : Theme.of(context).aiUi.glassColor,
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).aiUi.borderColor.withValues(alpha: 0.05),
                            ),
                            boxShadow: Theme.of(context).aiUi.primaryShadow,
                          ),
                          child: Icon(
                            FluentIcons.animal_paw_print_20_filled,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'ClashMiao',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<PackageInfo>(
                          future: _packageInfoFuture,
                          builder: (context, snapshot) {
                            final info = snapshot.data;
                            final version = info == null
                                ? ''
                                : 'Version ${info.version} (Build ${info.buildNumber})'
                                      .toUpperCase();
                            return Text(
                              version,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Monospace',
                                color: Theme.of(
                                  context,
                                ).aiUi.secondaryTextColor,
                                letterSpacing: 1.5,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _AboutTile(
                            icon: FluentIcons.arrow_sync_24_regular,
                            iconColor: Colors.blue.shade400,
                            label: t.about.checkForUpdate,
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    FluentIcons.chevron_right_24_regular,
                                    size: 18,
                                    color: Theme.of(context)
                                        .aiUi
                                        .secondaryTextColor
                                        .withValues(alpha: 0.3),
                                  ),
                            onTap: _checkingUpdate
                                ? null
                                : () async {
                                    setState(() => _checkingUpdate = true);
                                    try {
                                      ref.invalidate(updateAvailableProvider);
                                      final version = await ref.read(
                                        updateAvailableProvider.future,
                                      );
                                      if (!context.mounted) return;
                                      // version == null 覆盖"已是最新版本"和
                                      // "静默检查失败"两种情况——两者在
                                      // UpdateChecker.checkOnce 里本来就是同一
                                      // 条返回路径（网络失败会被内部吞掉当作
                                      // "没有更新"处理），保留原有的提示文案。
                                      if (version == null) {
                                        AppToast.info(
                                          context,
                                          t.appUpdate.notAvailableMsg,
                                        );
                                        return;
                                      }
                                      final info = await _packageInfoFuture;
                                      if (!context.mounted) return;
                                      // 故意不 await 弹窗关闭——「稍后」/
                                      // 「立即更新」什么时候点是用户的事，不该
                                      // 让"检查更新"这一行的 loading 态一直等
                                      // 到弹窗关掉才恢复。
                                      unawaited(
                                        showUpdateAvailableDialog(
                                          context,
                                          currentVersion: info.version,
                                          latestVersion: version.replaceFirst(
                                            'v',
                                            '',
                                          ),
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _checkingUpdate = false);
                                      }
                                    }
                                  },
                          ),
                          const _Divider(),
                          _AboutTile(
                            icon: FluentIcons.code_24_regular,
                            iconColor: Colors.grey.shade400,
                            label: t.about.sourceCode,
                            trailing: _Chevron(
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                            onTap: () => _tryLaunch(githubRepoUrl),
                          ),
                          // 没配置就整项不显示——给用户一个点了没反应的死链，
                          // 比不给这一项糟糕。下同。
                          if (hasTelegramChannel) ...[
                            const _Divider(),
                            _AboutTile(
                              icon: FluentIcons.people_community_24_regular,
                              iconColor: Colors.lightBlue.shade400,
                              label: t.about.telegramChannel,
                              trailing: _Chevron(
                                color: Theme.of(
                                  context,
                                ).aiUi.secondaryTextColor,
                              ),
                              onTap: () => _tryLaunch(telegramChannelUrl),
                            ),
                          ],
                          if (hasPrivacyPolicy) ...[
                            const _Divider(),
                            _AboutTile(
                              icon: FluentIcons.shield_checkmark_24_regular,
                              iconColor: Colors.purple.shade400,
                              label: t.about.privacyPolicy,
                              trailing: _Chevron(
                                color: Theme.of(
                                  context,
                                ).aiUi.secondaryTextColor,
                              ),
                              onTap: () => _tryLaunch(privacyPolicyUrl),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Made with Love for Cats'.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '© 2024 ClashMiao Studio. All Rights Reserved.',
                            style: TextStyle(
                              fontSize: 9,
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _tryLaunch(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(FluentIcons.chevron_right_24_regular, size: 18, color: color);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).aiUi.borderColor.withValues(alpha: 0.05),
    );
  }
}
