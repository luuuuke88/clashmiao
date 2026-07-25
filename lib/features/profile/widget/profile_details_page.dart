import 'dart:async';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/model/advanced_config.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:clashmiao/shared/components/settings_input_dialog.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfileDetailsPage extends ConsumerStatefulWidget {
  const ProfileDetailsPage(
    this.id, {
    super.key,
    this.debugOpenUpdateInterval = false,
  });

  final String id;
  final bool debugOpenUpdateInterval;

  @override
  ConsumerState<ProfileDetailsPage> createState() => _ProfileDetailsPageState();
}

class _ProfileDetailsPageState extends ConsumerState<ProfileDetailsPage> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  String? _loadedProfileId;
  bool _busy = false;
  bool _debugUpdateIntervalOpened = false;
  Duration? _updateInterval;
  String? _customUserAgent;
  bool _muxEnabled = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final profilesAsync = ref.watch(profileListProvider);

    return Scaffold(
      body: profilesAsync.when(
        data: (profiles) {
          final profile = profiles.cast<ProfileEntity?>().firstWhere(
            (profile) => profile?.id == widget.id,
            orElse: () => null,
          );
          if (profile == null) {
            return Center(child: Text(t.profile.detailsPageTitle));
          }
          _syncControllers(profile);
          if (widget.debugOpenUpdateInterval &&
              !_debugUpdateIntervalOpened &&
              _isRemoteProfile(profile) &&
              profile.subInfo != null) {
            _debugUpdateIntervalOpened = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _editUpdateInterval(profile);
            });
          }
          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 120,
                    pinned: true,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    surfaceTintColor: Colors.transparent,
                    flexibleSpace: FlexibleSpaceBar(
                      titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                      title: Text(
                        t.profile.detailsPageTitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: FilledButton(
                          onPressed: _busy ? null : () => _save(profile, t),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(t.profile.save.buttonText),
                        ),
                      ),
                    ],
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionHeader(title: t.profile.details.basicInfo),
                          const Gap(12),
                          _GlassContainer(
                            child: Column(
                              children: [
                                _StyledTextField(
                                  controller: _nameController,
                                  label: t.profile.detailsForm.nameLabel,
                                  hint: t.profile.detailsForm.nameHint,
                                ),
                                if (_isRemoteProfile(profile))
                                  _StyledTextField(
                                    controller: _urlController,
                                    label: t.profile.detailsForm.urlLabel,
                                    hint: t.profile.detailsForm.urlHint,
                                    maxLines: 3,
                                    keyboardType: TextInputType.url,
                                  ),
                              ],
                            ),
                          ),
                          if (profile.subInfo != null) ...[
                            const Gap(32),
                            _SectionHeader(
                              title: t.profile.details.subscriptionStatus,
                            ),
                            const Gap(12),
                            _SubscriptionStatusCard(profile: profile),
                          ],
                          const Gap(32),
                          _SectionHeader(title: t.profile.details.options),
                          const Gap(12),
                          _GlassContainer(
                            child: Column(
                              children: [
                                // User-Agent 仅对远程订阅有意义（本地导入没有 URL 可发
                                // HTTP 请求），继续挂在"远程且已取到 subInfo"门禁下；
                                // Mux 是连接期 runtime 注入的能力，
                                // runtime_config_builder.dart 对本地/远程订阅一视同仁，
                                // 按控制器修正放在该门禁之外，本地导入配置也应可见可切换。
                                if (_isRemoteProfile(profile) &&
                                    profile.subInfo != null) ...[
                                  _SwitchTile(
                                    title: t.profile.detailsForm.updateInterval,
                                    subtitle: _formatInterval(
                                      _updateInterval ?? profile.updateInterval,
                                    ),
                                    icon: FluentIcons.arrow_sync_24_regular,
                                    onTap: () => _editUpdateInterval(profile),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  _SwitchTile(
                                    title: t.profile.details.updateNow,
                                    subtitle:
                                        t.profile.details.updateNowDescription,
                                    icon: FluentIcons.arrow_download_24_regular,
                                    onTap: _busy
                                        ? null
                                        : () => _update(profile, t),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  _SwitchTile(
                                    title: t.profile.detailsForm.userAgent,
                                    subtitle:
                                        (_customUserAgent?.isNotEmpty ?? false)
                                        ? _customUserAgent!
                                        : t.profile.detailsForm.userAgentNotSet,
                                    icon:
                                        FluentIcons.window_dev_tools_24_regular,
                                    onTap: () => _editUserAgent(profile),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Divider(
                                      height: 1,
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withValues(alpha: 0.1),
                                    ),
                                  ),
                                ],
                                _ToggleTile(
                                  title: t.profile.detailsForm.mux,
                                  subtitle:
                                      t.profile.detailsForm.muxDescription,
                                  icon: FluentIcons.merge_24_regular,
                                  value: _muxEnabled,
                                  onChanged: (v) =>
                                      setState(() => _muxEnabled = v),
                                ),
                              ],
                            ),
                          ),
                          const Gap(48),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _delete(profile, t),
                              icon: const Icon(FluentIcons.delete_24_regular),
                              label: Text(t.profile.delete.buttonTxt),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Gap(48),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
        error: (error, _) =>
            Center(child: Text('${t.failure.unexpected}: $error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  void _syncControllers(ProfileEntity profile) {
    if (_loadedProfileId == profile.id) return;
    _loadedProfileId = profile.id;
    _nameController.text = profile.name;
    _urlController.text = profile.url;
    _updateInterval = profile.updateInterval;
    _customUserAgent = profile.customUserAgent;
    _muxEnabled = profile.advancedConfig?.muxEnabled ?? false;
  }

  Future<void> _save(ProfileEntity profile, TranslationsEn t) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.error(context, t.profile.detailsForm.emptyNameMsg);
      return;
    }
    final url = _urlController.text.trim();
    if (_isRemoteProfile(profile) && !_isValidHttpUrl(url)) {
      AppToast.error(context, t.profile.detailsForm.invalidUrlMsg);
      return;
    }

    // 保存前先记下 URL 是否真的变了——决定要不要触发下面的重新拉取。
    // 用原始 profile.url（trim 后）比较，而不是 _urlController 的初始值，
    // 避免受 _syncControllers 时序影响。
    final urlChanged = _isRemoteProfile(profile) && url != profile.url.trim();

    setState(() => _busy = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.editProfile(
        profile.id,
        newName: name,
        newUrl: _isRemoteProfile(profile) ? url : null,
      );
      await repo.updateProfile(
        profile.copyWith(
          name: name,
          url: _isRemoteProfile(profile) ? url : profile.url,
          updateInterval: _updateInterval ?? profile.updateInterval,
          customUserAgent: _customUserAgent,
          advancedConfig: AdvancedConfig(
            remoteDnsOverride: profile.advancedConfig?.remoteDnsOverride,
            muxEnabled: _muxEnabled,
            muxProtocol: profile.advancedConfig?.muxProtocol ?? 'h2mux',
            muxConcurrency: profile.advancedConfig?.muxConcurrency ?? 4,
            fragmentEnabled: profile.advancedConfig?.fragmentEnabled ?? false,
            fragmentRange: profile.advancedConfig?.fragmentRange,
          ),
        ),
      );
      if (urlChanged) {
        // URL 变了：磁盘上的配置文件还是旧地址下载的内容，必须真的重新拉取
        // 一次新地址（复用手动"立即更新"同一条 ProfileRepository.update 逻辑），
        // 否则用户会以为保存了新地址、实际连接用的还是旧配置。拉取失败会被
        // 下面的 catch 捕获并明确提示，不静默吞掉——旧配置文件保持不变，
        // 用户至少还能用旧的。
        await repo.update(profile.id);
      }
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      if (mounted) {
        AppToast.success(context, t.profile.save.successMsg);
        unawaited(Navigator.of(context).maybePop());
      }
    } catch (error) {
      if (mounted) {
        AppToast.error(context, '${t.profile.save.failureMsg}: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(ProfileEntity profile, TranslationsEn t) async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.update(profile.id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      if (mounted) AppToast.success(context, t.profile.update.successMsg);
    } catch (error) {
      if (mounted) {
        AppToast.error(context, '${t.profile.update.failureMsg}: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(ProfileEntity profile, TranslationsEn t) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: t.profile.delete.buttonTxt,
      message: t.profile.delete.confirmationMsg,
      icon: FluentIcons.delete_24_regular,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.delete(profile.id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
      if (mounted) {
        AppToast.success(context, t.profile.delete.successMsg);
        unawaited(Navigator.of(context).maybePop());
      }
    } catch (error) {
      if (mounted) AppToast.error(context, '${t.failure.unexpected}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editUpdateInterval(ProfileEntity profile) async {
    final t = ref.read(translationsProvider);
    final result = await SettingsInputDialog<int>(
      title: t.profile.detailsForm.updateIntervalDialogTitle,
      initialValue: (_updateInterval ?? profile.updateInterval).inHours,
      icon: FluentIcons.arrow_sync_24_regular,
      digitsOnly: true,
      keyboardType: TextInputType.number,
      validator: (value) {
        final hours = int.tryParse(value);
        return hours != null && hours > 0;
      },
      mapTo: int.tryParse,
      optionalAction: (
        t.general.state.disable,
        () => setState(() => _updateInterval = Duration.zero),
      ),
    ).show(context);
    if (result == null || result <= 0) return;
    setState(() => _updateInterval = Duration(hours: result));
  }

  Future<void> _editUserAgent(ProfileEntity profile) async {
    final t = ref.read(translationsProvider);
    final result = await SettingsInputDialog<String>(
      title: t.profile.detailsForm.userAgent,
      initialValue: _customUserAgent ?? '',
      icon: FluentIcons.window_dev_tools_24_regular,
      keyboardType: TextInputType.text,
    ).show(context);
    if (result == null) return;
    setState(
      () => _customUserAgent = result.trim().isEmpty ? null : result.trim(),
    );
  }
}

class _SubscriptionStatusCard extends ConsumerWidget {
  const _SubscriptionStatusCard({required this.profile});

  final ProfileEntity profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final subInfo = profile.subInfo!;
    final expire = subInfo.expire;
    // 展示形态跟首页/列表不同（这里给绝对日期，那边给剩余天数），但"什么算
    // 无限期"共用同一条规则——见 formatters.dart 的 isEffectivelyUnlimited。
    final expireText = formatExpireAbsolute(expire, t);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).aiUi.borderColor),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '流量使用',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).aiUi.secondaryTextColor,
                ),
              ),
              Text(
                '${SubscriptionInfo.formatBytes(subInfo.used)} / ${SubscriptionInfo.formatBytes(subInfo.total)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const Gap(16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: subInfo.usageRatio.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const Gap(24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatItem(
                  label: t.profile.subscription.upload,
                  value: SubscriptionInfo.formatBytes(subInfo.upload),
                  icon: FluentIcons.arrow_upload_24_regular,
                  color: Colors.orange,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: t.profile.subscription.download,
                  value: SubscriptionInfo.formatBytes(subInfo.download),
                  icon: FluentIcons.arrow_download_24_regular,
                  color: Colors.green,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: t.profile.details.expireDate,
                  value: expireText,
                  icon: FluentIcons.calendar_clock_24_regular,
                  color: Colors.blue,
                ),
              ),
            ],
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

class _GlassContainer extends StatelessWidget {
  const _GlassContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).aiUi.borderColor),
      ),
      // ListTile 系组件（_SwitchTile/_ToggleTile）需要就近的 Material 祖先才能正确
      // 绘制背景与水波纹；这里的 Container 自带 BoxDecoration.color，若不插入一层
      // transparency 类型的 Material，ListTile 会在 debug 模式下抛出
      // "ListTile background color or ink splashes may be invisible" 断言。
      // 用法与 lib/shared/components/warp_license_agreement_modal.dart 一致。
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
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
              color: Theme.of(context).aiUi.secondaryTextColor,
            ),
          ),
          const Gap(8),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Theme.of(
                  context,
                ).aiUi.secondaryTextColor.withValues(alpha: 0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).canvasColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const Gap(8),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const Gap(2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).aiUi.secondaryTextColor,
          ),
        ),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
      trailing: Icon(
        FluentIcons.chevron_right_24_regular,
        size: 16,
        color: Theme.of(context).aiUi.secondaryTextColor,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => onChanged(!value),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

bool _isRemoteProfile(ProfileEntity profile) {
  final uri = Uri.tryParse(profile.url.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

bool _isValidHttpUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  return uri != null &&
      uri.hasAuthority &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String _formatInterval(Duration duration) {
  final hours = duration.inHours;
  if (hours <= 0) return '关闭';
  if (hours < 24) return '$hours 小时';
  final days = hours / 24;
  if (hours % 24 == 0) return '${days.toStringAsFixed(0)} 天';
  return '$hours 小时';
}
