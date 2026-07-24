import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:clashmiao/core/config/build_config.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 更新下载页外链——跟关于页"源代码"入口用的是同一个 dart-define
/// （`GITHUB_REPO_URL`），没有配置真实地址时兜底跳去项目主页，逻辑跟
/// `about_page.dart` 里的 `_tryLaunch` 完全一致，这里不重新发明一套。
const kUpdateDownloadUrl = githubRepoUrl;

/// 「发现新版本」弹窗：只在 `UpdateChecker.checkOnce` 确认存在新版本时展示。
///
/// 只有"立即更新"（跳转外链下载页）+ "稍后"（关闭弹窗）两个按钮——
/// 参照项目里对应的"忽略此版本"按钮经确认是死代码（唯一调用点写死传
/// `false`，从未真正渲染过），这里不复刻这个从未生效过的分支，避免过度设计。
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required String currentVersion,
  required String latestVersion,
  String updateUrl = kUpdateDownloadUrl,
  Future<void> Function(String url)? openUrl,
}) {
  return showAiUiModal<void>(
    context: context,
    builder: (context) => UpdateAvailableDialog(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      updateUrl: updateUrl,
      openUrl: openUrl,
    ),
  );
}

class UpdateAvailableDialog extends ConsumerWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.currentVersion,
    required this.latestVersion,
    this.updateUrl = kUpdateDownloadUrl,
    this.openUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String updateUrl;

  /// 供单测注入的外链跳转 mock；生产环境不传时走真实的 `launchUrl`。
  final Future<void> Function(String url)? openUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);

    return AiUiModalWrapper(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.arrow_circle_up_24_filled,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              t.appUpdate.dialogTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.appUpdate.updateMsg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).aiUi.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _VersionTile(
                    label: t.appUpdate.currentVersionLbl,
                    version: currentVersion,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    FluentIcons.arrow_right_24_regular,
                    size: 18,
                    color: Theme.of(context).aiUi.secondaryTextColor,
                  ),
                ),
                Expanded(
                  child: _VersionTile(
                    label: t.appUpdate.newVersionLbl,
                    version: latestVersion,
                    highlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(t.appUpdate.laterBtnTxt),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final launch = openUrl ?? _defaultOpenUrl;
                      await launch(updateUrl);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(t.appUpdate.updateNowBtnTxt),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

Future<void> _defaultOpenUrl(String url) async {
  if (url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.label,
    required this.version,
    this.highlight = false,
  });

  final String label;
  final String version;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : aiUi.glassColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aiUi.borderColor.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: aiUi.secondaryTextColor),
          ),
          const SizedBox(height: 4),
          Text(
            version,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: highlight
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
