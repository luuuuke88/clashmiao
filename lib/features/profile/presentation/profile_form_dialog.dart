import 'package:clashmiao/core/theme/motion.dart';
import 'dart:async';
import 'dart:io';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/domain/config/model/warp_terms.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/application/profile_failures.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/config/application/warp_config_service.dart';
import 'package:clashmiao/features/profile/presentation/qr_scanner_page.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/shared/components/agreement_modal.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:clashmiao/shared/components/motion_progress.dart';

/// 订阅表单弹窗（新增 / 编辑 共用）
///
/// [profile] 不传 = 新增模式，传入 = 编辑模式
Future<void> showProfileFormDialog(
  BuildContext context,
  WidgetRef ref, {
  ProfileEntity? profile,
}) {
  final isEdit = profile != null;

  if (!isEdit) return _showAddProfileSheet(context, ref);

  return showProfileManualFormDialog(context, ref, profile: profile);
}

/// 「添加订阅」弹窗关闭时带回来的后续动作。
enum _AddSheetResult { manualInput }

/// 打开「添加订阅」弹窗；用户选「手动输入」时，弹窗**先正常退出**，再由仍然
/// 活着的调用方页面（它自己的、稳定的 context 与 ref）打开手动表单。
///
/// 不能在弹窗内部「`maybePop()` 之后立刻再 push 手动表单」：`maybePop` 要等
/// `willPop`，等它返回时路由栈已经被新 push 的表单改了，pop 就放弃了，结果两层
/// 弹窗叠在一起，而且手动表单还拿着已销毁弹窗的 context。
Future<void> _showAddProfileSheet(BuildContext context, WidgetRef ref) async {
  final result = await showAiUiModal<_AddSheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AddProfileModal(ref: ref),
  );
  if (result == _AddSheetResult.manualInput && context.mounted) {
    await showProfileManualFormDialog(context, ref);
  }
}

class _AddProfileModal extends ConsumerStatefulWidget {
  const _AddProfileModal({required this.ref});

  final WidgetRef ref;

  @override
  ConsumerState<_AddProfileModal> createState() => _AddProfileModalState();
}

class _AddProfileModalState extends ConsumerState<_AddProfileModal> {
  bool _isLoading = false;
  bool _isGeneratingWarp = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    const buttonsPadding = 24.0;
    const buttonsGap = 16.0;

    return AiUiModalWrapper(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: AnimatedSize(
          duration: Motion.layoutDuration(context, Motion.medium),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final buttonWidth =
                  (constraints.maxWidth - (buttonsPadding * 2) - buttonsGap) /
                  2;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                        child: Column(
                          children: [
                            Text(
                              t.profile.add.shortBtnTxt,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t.profile.add.modalSubtitle.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.aiUi.secondaryTextColor,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      )
                      .animateWithMotion(context)
                      .fadeIn(duration: 300.ms, delay: 200.ms)
                      .slideX(
                        begin: 0.1,
                        end: 0,
                        duration: 300.ms,
                        delay: 200.ms,
                      ),
                  AnimatedCrossFade(
                    firstChild: SizedBox(
                      height: 160,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 64),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.profile.add.addingProfileMsg,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.aiUi.secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              // 减少动画时停成静态条，语义仍是「加载中」。
                              child: const MotionProgress.linear(
                                minHeight: 6,
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () {
                                if (mounted) setState(() => _isLoading = false);
                              },
                              child: Text(
                                MaterialLocalizations.of(
                                  context,
                                ).cancelButtonLabel,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        children: [
                          Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: buttonsPadding,
                                ),
                                child: Row(
                                  children: [
                                    _Button(
                                      key: const ValueKey(
                                        'add_from_clipboard_button',
                                      ),
                                      label: t.profile.add.fromClipboard,
                                      icon: FluentIcons
                                          .clipboard_paste_24_regular,
                                      size: buttonWidth,
                                      onTap: () async {
                                        final data = await Clipboard.getData(
                                          Clipboard.kTextPlain,
                                        );
                                        await _addValue(data?.text ?? '');
                                      },
                                    ),
                                    const SizedBox(width: buttonsGap),
                                    if (Platform.isAndroid || Platform.isIOS)
                                      _Button(
                                        key: const ValueKey(
                                          'add_by_qr_code_button',
                                        ),
                                        label: t.profile.add.scanQr,
                                        icon: FluentIcons.qr_code_24_regular,
                                        size: buttonWidth,
                                        onTap: () async {
                                          final value = await openQrScanner(
                                            context,
                                          );
                                          if (value != null) {
                                            await _addValue(value);
                                          }
                                        },
                                      )
                                    else
                                      _Button(
                                        key: const ValueKey(
                                          'add_manually_button',
                                        ),
                                        label: t.profile.add.manually,
                                        icon: FluentIcons.add_24_regular,
                                        size: buttonWidth,
                                        onTap: _showManualForm,
                                      ),
                                  ],
                                ),
                              )
                              .animateWithMotion(context)
                              .fadeIn(duration: 300.ms, delay: 250.ms)
                              .slideX(
                                begin: 0.1,
                                end: 0,
                                duration: 300.ms,
                                delay: 250.ms,
                              ),
                          const SizedBox(height: 16),
                          Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: buttonsPadding,
                                ),
                                child: Column(
                                  children: [
                                    _LongButton(
                                      key: const ValueKey('add_warp_button'),
                                      label: t.profile.add.addWarp,
                                      description:
                                          t.profile.add.warpDescription,
                                      icon: FluentIcons.shield_add_24_regular,
                                      color: Colors.orange.shade400,
                                      onTap: _showWarpConsent,
                                    ),
                                    if (Platform.isAndroid ||
                                        Platform.isIOS) ...[
                                      const SizedBox(height: 12),
                                      _LongButton(
                                        key: const ValueKey(
                                          'add_manually_button',
                                        ),
                                        label: t.profile.add.manually,
                                        description:
                                            t.profile.add.manuallyDescription,
                                        icon: FluentIcons.settings_24_regular,
                                        color: Colors.blue.shade400,
                                        onTap: _showManualForm,
                                      ),
                                    ],
                                  ],
                                ),
                              )
                              .animateWithMotion(context)
                              .fadeIn(duration: 300.ms, delay: 300.ms)
                              .slideX(
                                begin: 0.1,
                                end: 0,
                                duration: 300.ms,
                                delay: 300.ms,
                              ),
                        ],
                      ),
                    ),
                    crossFadeState: _isLoading
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    duration: Motion.duration(context, Motion.medium),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _addValue(String value) async {
    final text = value.trim();
    if (text.isEmpty || _isLoading) return;
    setState(() => _isLoading = true);
    await doAddProfile(context, widget.ref, text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    unawaited(Navigator.of(context).maybePop());
  }

  /// 选「手动输入」：只负责带着结果关闭本弹窗，手动表单由调用方在弹窗退出后
  /// 打开（见 [_showAddProfileSheet]）。
  void _showManualForm() =>
      Navigator.of(context).pop(_AddSheetResult.manualInput);

  Future<void> _showWarpConsent() async {
    final settings = ref.read(networkSettingsProvider);
    final notifier = ref.read(networkSettingsProvider.notifier);

    if (!settings.warpConsentGiven) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => const _WarpConsentModal(),
      );
      if (agreed != true) return;
      await notifier.setWarpConsentGiven(true);
    }

    if (!mounted || _isGeneratingWarp) return;
    setState(() => _isGeneratingWarp = true);
    AppToast.info(context, '正在生成 WARP 配置…');
    try {
      final licenseKey = ref.read(networkSettingsProvider).warpLicenseKey;
      await ref
          .read(warpConfigServiceProvider)
          .generateAndStore(licenseKey: licenseKey);
      await notifier.setEnableWarp(true);
      if (!mounted) return;
      AppToast.success(context, 'WARP 配置生成成功');
      unawaited(Navigator.of(context).maybePop());
    } catch (e) {
      if (mounted) AppToast.error(context, 'WARP 配置生成失败: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingWarp = false);
    }
  }
}

Future<void> showProfileManualFormDialog(
  BuildContext context,
  WidgetRef ref, {
  ProfileEntity? profile,
}) {
  final isEdit = profile != null;
  final nameCtrl = TextEditingController(text: profile?.name ?? '');
  final urlCtrl = TextEditingController(text: profile?.url ?? '');

  return showAiUiModal(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final t = ref.read(translationsProvider);

      Future<void> submit() async {
        final name = nameCtrl.text.trim();
        final url = urlCtrl.text.trim();

        if (isEdit && name.isEmpty) {
          AppToast.error(context, t.profile.detailsForm.emptyNameMsg);
          return;
        }
        if (url.isEmpty) {
          AppToast.error(context, t.profile.detailsForm.invalidUrlMsg);
          return;
        }

        Navigator.of(ctx).pop();
        if (isEdit) {
          await doEditProfile(context, ref, profile.id, name: name, url: url);
        } else {
          await doAddProfile(
            context,
            ref,
            url,
            customName: name.isEmpty ? null : name,
          );
        }
      }

      return AiUiModalWrapper(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            t.profile.detailsPageTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(t.profile.save.buttonText),
                        ),
                      ],
                    ),
                  )
                  .animateWithMotion(ctx)
                  .fadeIn(duration: 300.ms, delay: 150.ms)
                  .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 150.ms),
              _SectionHeader(title: t.profile.details.basicInfo),
              const SizedBox(height: 12),
              _ProfileGlassContainer(
                child: Column(
                  children: [
                    _ProfileTextField(
                      controller: nameCtrl,
                      label: t.profile.detailsForm.nameLabel,
                      hint: isEdit
                          ? t.profile.detailsForm.nameHint
                          : '自动识别（可选）',
                    ),
                    _ProfileTextField(
                      controller: urlCtrl,
                      label: t.profile.detailsForm.urlLabel,
                      hint: t.profile.detailsForm.urlHint,
                      keyboardType: TextInputType.url,
                      maxLines: 3,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (Platform.isAndroid || Platform.isIOS)
                            IconButton(
                              icon: const Icon(FluentIcons.qr_code_20_regular),
                              tooltip: t.profile.add.scanQr,
                              onPressed: () async {
                                final result = await openQrScanner(ctx);
                                if (result != null) urlCtrl.text = result;
                              },
                            ),
                          IconButton(
                            icon: const Icon(
                              FluentIcons.clipboard_paste_24_regular,
                            ),
                            tooltip: t.profile.add.fromClipboard,
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                Clipboard.kTextPlain,
                              );
                              if (data?.text != null &&
                                  data!.text!.isNotEmpty) {
                                urlCtrl.text = data.text!;
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.suffixIcon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: aiUi.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hint,
              // 占位提示同样是小字：用不透明的 onSurfaceVariant，不叠 alpha。
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: theme.canvasColor,
              suffixIcon: suffixIcon,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ProfileGlassContainer extends StatelessWidget {
  const _ProfileGlassContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).aiUi.borderColor),
      ),
      child: child,
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    super.key,
    required this.label,
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).aiUi.softBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).aiUi.borderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LongButton extends StatelessWidget {
  const _LongButton({
    super.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).aiUi.softBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).aiUi.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              FluentIcons.chevron_right_24_regular,
              size: 16,
              color: Theme.of(
                context,
              ).aiUi.secondaryTextColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 判断 [input] 是否是一个可以直接发 HTTP(S) 请求下载的订阅地址。
///
/// 只有 `http://` / `https://` scheme 才算“URL”。除此之外的一切
/// 输入（不管是不是认识的节点协议前缀，还是裸文本/base64/JSON）
/// 都不是可下载的地址，应该走“当节点/订阅内容直接解析”这条路，
/// 而不是反过来维护一份协议白名单去筛选“内容”。
bool isHttpDownloadUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

/// 添加订阅并反馈结果。
@visibleForTesting
Future<void> doAddProfile(
  BuildContext context,
  WidgetRef ref,
  String urlOrUri, {
  String? customName,
}) async {
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    if (isHttpDownloadUrl(urlOrUri)) {
      await repo.addByUrl(urlOrUri, customName: customName);
    } else {
      await repo.addByContent(urlOrUri, name: customName ?? '');
    }
    ref.invalidate(profileListProvider);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(offlineProxyGroupsProvider);
    if (context.mounted) AppToast.success(context, '添加成功');
  } catch (e) {
    if (context.mounted) {
      AppToast.error(
        context,
        profileStoreErrorMessage(e, () => ref.read(translationsProvider)) ??
            '添加失败: $e',
      );
    }
  }
}

/// 保存订阅的名称 / URL 编辑并反馈结果。
@visibleForTesting
Future<void> doEditProfile(
  BuildContext context,
  WidgetRef ref,
  String id, {
  String? name,
  String? url,
}) async {
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    await repo.editProfile(id, newName: name, newUrl: url);
    ref.invalidate(profileListProvider);
    if (context.mounted) AppToast.success(context, '保存成功');
  } catch (e) {
    if (context.mounted) {
      AppToast.error(
        context,
        profileStoreErrorMessage(e, () => ref.read(translationsProvider)) ??
            '保存失败: $e',
      );
    }
  }
}

/// WARP 同意弹窗：标题、正文与条款链接都是 WARP 专属内容，所以放在使用它的功能里，
/// 通用版式交给 shared 的 [AgreementModal]。
class _WarpConsentModal extends ConsumerWidget {
  const _WarpConsentModal();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return AgreementModal(
      title: t.config.warpConsent.title,
      body: t.config.warpConsent.description(
        tos: (text) => linkTextSpan(text, kWarpTermsOfServiceUrl),
        privacy: (text) => linkTextSpan(text, kWarpPrivacyPolicyUrl),
      ),
    );
  }
}
