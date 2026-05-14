import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfilesPage extends ConsumerStatefulWidget {
  const ProfilesPage({super.key});

  @override
  ConsumerState<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ConsumerState<ProfilesPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final profilesAsync = ref.watch(profileListProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.profile.overviewPageTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Row(
                    children: [
                      _HeaderButton(
                        icon: FluentIcons.arrow_sync_24_regular,
                        isLoading: _isLoading,
                        onTap: _isLoading ? null : () => _updateAll(t),
                      ),
                      const SizedBox(width: 12),
                      _HeaderButton(
                        icon: FluentIcons.add_24_regular,
                        filled: true,
                        onTap: () => _showAddDialog(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 内容
              Expanded(
                child: profilesAsync.when(
                  data: (profiles) {
                    if (profiles.isEmpty) {
                      return _EmptyState(onAdd: () => _showAddDialog(context));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: profiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _ProfileCard(
                          profile: profiles[index],
                          onTap: () => _setActive(profiles[index].id),
                          onUpdate: () => _updateProfile(profiles[index].id, t),
                          onEdit: () =>
                              _showEditDialog(context, profiles[index]),
                          onDelete: () => _deleteProfile(profiles[index].id, t),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text('${t.failure.unexpected}: $e')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showProfileFormDialog(context, ref);
  }

  void _showEditDialog(BuildContext context, ProfileEntity profile) {
    showProfileFormDialog(context, ref, profile: profile);
  }

  Future<void> _setActive(String id) async {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.setActive(id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
    } catch (e) {
      if (mounted) AppToast.error(context, '切换失败: $e');
    }
  }

  Future<void> _updateProfile(String id, TranslationsEn t) async {
    setState(() => _isLoading = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.update(id);
      ref.invalidate(profileListProvider);
      if (mounted) AppToast.success(context, t.profile.update.successMsg);
    } catch (e) {
      if (mounted)
        AppToast.error(context, '${t.profile.update.failureMsg}: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteProfile(String id, TranslationsEn t) async {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.delete(id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
      if (mounted) AppToast.info(context, t.profile.delete.successMsg);
    } catch (e) {
      if (mounted) AppToast.error(context, '${t.failure.unexpected}: $e');
    }
  }

  Future<void> _updateAll(TranslationsEn t) async {
    setState(() => _isLoading = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.updateAll();
      ref.invalidate(profileListProvider);
      if (mounted) AppToast.success(context, t.profile.update.successMsg);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '${t.profile.update.failureMsg}: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final aiUi = Theme.of(context).aiUi;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: aiUi.softBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.document_add_24_regular,
              size: 36,
              color: aiUi.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            t.home.emptyProfilesMsg,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: aiUi.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '',
            style: TextStyle(
              fontSize: 13,
              color: aiUi.secondaryTextColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(FluentIcons.add_16_regular),
            label: Text(t.profile.add.shortBtnTxt),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool isLoading;
  final VoidCallback? onTap;

  const _HeaderButton({
    required this.icon,
    this.filled = false,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? theme.colorScheme.primary : aiUi.softBackgroundColor,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: aiUi.borderColor),
          boxShadow: filled ? aiUi.primaryShadow : null,
        ),
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(10),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: filled ? Colors.white : aiUi.secondaryTextColor,
                ),
              )
            : Icon(
                icon,
                size: 20,
                color: filled
                    ? Colors.white
                    : (isLight ? aiUi.secondaryTextColor : Colors.white70),
              ),
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onUpdate,
    required this.onEdit,
    required this.onDelete,
  });

  final ProfileEntity profile;
  final VoidCallback onTap;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    final bgColor = profile.active
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : (isLight ? Colors.white : aiUi.glassColor);
    final borderColor = profile.active
        ? theme.colorScheme.primary.withValues(alpha: 0.3)
        : aiUi.borderColor.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: profile.active ? 1.5 : 1,
          ),
          boxShadow: profile.active ? aiUi.primaryShadow : aiUi.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: profile.active
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    FluentIcons.shield_24_filled,
                    size: 18,
                    color: profile.active
                        ? Colors.white
                        : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: profile.active
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile.active)
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(
                                color: Color(0xFF10b981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: aiUi.secondaryTextColor,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (profile.active)
                  Text(
                    t.profile.overview.currentlyUsing,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),

            // 流量
            if (profile.subInfo != null) ...[
              const SizedBox(height: 16),
              if (profile.subInfo!.total > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: aiUi.softBackgroundColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: profile.subInfo!.usageRatio.clamp(0.0, 1.0),
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              const Color(0xFF22d3ee),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${SubscriptionInfo.formatBytes(profile.subInfo!.used)} / ${SubscriptionInfo.formatBytes(profile.subInfo!.total)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: aiUi.secondaryTextColor,
                    ),
                  ),
                  Text(
                    _formatExpire(profile.subInfo!.expire, t),
                    style: TextStyle(
                      fontSize: 11,
                      color: profile.subInfo!.isExpired
                          ? Colors.red
                          : aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],

            // 更新时间
            if (profile.lastUpdate != null) ...[
              const SizedBox(height: 6),
              Text(
                t.profile.subscription.updatedTimeAgo(
                  timeago: _fmtTime(profile.lastUpdate!),
                ),
                style: TextStyle(fontSize: 10, color: aiUi.secondaryTextColor),
              ),
            ],
            const SizedBox(height: 16),
            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallIconButton(
                  icon: FluentIcons.arrow_sync_20_regular,
                  onTap: onUpdate,
                ),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: FluentIcons.share_20_regular,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: profile.url));
                    if (context.mounted) {
                      AppToast.success(
                        context,
                        t.profile.share.subscriptionLinkCopied,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: FluentIcons.edit_20_regular,
                  onTap: onEdit,
                ),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: FluentIcons.delete_20_regular,
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatExpire(DateTime? dt, TranslationsEn t) {
    if (dt == null) return t.profile.details.unlimited;
    final days = dt.difference(DateTime.now()).inDays;
    if (days > 365) return t.profile.details.unlimited;
    if (days < 0) return t.profile.subscription.expired;
    return t.profile.overview.remainingDays(days: days);
  }

  String _fmtTime(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).aiUi.softBackgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: color ?? Theme.of(context).aiUi.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}
