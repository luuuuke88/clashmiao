import 'package:clashmiao/shared/components/motion_progress.dart';

import 'dart:async';

import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:clashmiao/features/about/application/update_check_provider.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
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
    // 入口图标统一用品牌色，不再各染一色（绿/橙/红留给状态）。
    final brandIconColor = Theme.of(context).colorScheme.primary;

    // 背景晕染统一由 ShellPage 底下那层 BrandBackdrop 画，页面自己保持透明。
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            // 走 i18n（`about.pageTitle`，11 种语言都已有），
                            // 不硬编码英文——否则简中环境下只有这一页顶着英文
                            // 标题。品牌名在下面的大字标里已经出现，标题不必
                            // 再带一次，这样也跟「线路」「设置」的标题一致。
                            t.about.pageTitle,
                            // 跟设置页标题同一套：不显式给颜色的话会落到主题的
                            // bodyMedium（Slate 600），比别的页面标题淡一档，
                            // 看着就是"这一页的标题不对"。
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        const BrandMark(size: 112),
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
                                color: Theme.of(context)
                                    .aiUi
                                    .secondaryTextColor,
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
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _AboutTile(
                            icon: FluentIcons.arrow_sync_24_regular,
                            iconColor: brandIconColor,
                            label: t.about.checkForUpdate,
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: MotionProgress(),
                                  )
                                : _Chevron(
                                    color: Theme.of(context)
                                        .aiUi
                                        .secondaryTextColor,
                                  ),
                            onTap: _checkingUpdate
                                ? null
                                : () => _checkForUpdate(context, t),
                          ),
                          const _Divider(),
                          _AboutTile(
                            icon: FluentIcons.document_bullet_list_24_regular,
                            iconColor: brandIconColor,
                            label: t.about.openSourceLicenses,
                            trailing: _Chevron(
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                            onTap: () => _showLicenses(context),
                          ),
                          const _Divider(),
                          _AboutTile(
                            icon: FluentIcons.code_24_regular,
                            iconColor: brandIconColor,
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
                              iconColor: brandIconColor,
                              label: t.about.telegramChannel,
                              trailing: _Chevron(
                                color: Theme.of(context)
                                    .aiUi
                                    .secondaryTextColor,
                              ),
                              onTap: () => _tryLaunch(telegramChannelUrl),
                            ),
                          ],
                          if (hasPrivacyPolicy) ...[
                            const _Divider(),
                            _AboutTile(
                              icon: FluentIcons.shield_checkmark_24_regular,
                              iconColor: brandIconColor,
                              label: t.about.privacyPolicy,
                              trailing: _Chevron(
                                color: Theme.of(context)
                                    .aiUi
                                    .secondaryTextColor,
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
                          // 版权行：不写年份与「All Rights Reserved」，待许可证
                          // 确定后再定。12 sp、不加字距、允许换行（文字放大时
                          // 不溢出）。
                          Text(
                            '© ClashMiao',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 0,
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

  /// 手动检查更新。三种结论各有各的反馈：有新版本弹对话框；确认已是最新
  /// 提示「已是最新版本」；**检查失败**单独提示失败——不能把「没问到」当成
  /// 「已是最新」告诉用户，那等于骗人。
  Future<void> _checkForUpdate(BuildContext context, Translations t) async {
    setState(() => _checkingUpdate = true);
    try {
      ref.invalidate(updateCheckProvider);
      UpdateCheckResult result;
      try {
        result = await ref.read(updateCheckProvider.future);
      } catch (_) {
        // provider 本身抛了（读 prefs 失败等）同样是「没得到结论」。
        result = const UpdateCheckResult.failed();
      }
      if (!context.mounted) return;
      switch (result.status) {
        case UpdateCheckStatus.failed:
          AppToast.error(context, t.appUpdate.checkFailedMsg);
        case UpdateCheckStatus.upToDate:
          AppToast.info(context, t.appUpdate.notAvailableMsg);
        case UpdateCheckStatus.available:
          final info = await _packageInfoFuture;
          if (!context.mounted) return;
          // 故意不 await 弹窗关闭——「稍后」/「立即更新」什么时候点是用户的
          // 事，不该让"检查更新"这一行的 loading 态一直等到弹窗关掉才恢复。
          unawaited(
            showUpdateAvailableDialog(
              context,
              currentVersion: info.version,
              latestVersion: result.tag!.replaceFirst('v', ''),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// 系统的开源许可页：pub 依赖的许可由 Flutter 自动收集，sing-box 内核与
  /// 规则集由 `registerBundledLicenses()` 在启动时补登记。
  Future<void> _showLicenses(BuildContext context) async {
    final info = await _packageInfoFuture;
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'ClashMiao',
      applicationVersion: info.version,
      applicationIcon: const Padding(
        padding: EdgeInsets.all(8),
        child: BrandMark(size: 56),
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
