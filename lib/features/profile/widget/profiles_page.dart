import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:clashmiao/features/profile/widget/profile_qr_dialog.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProfilesPage extends ConsumerStatefulWidget {
  const ProfilesPage({
    super.key,
    this.embedInSheet = false,
    this.debugOpenSortModal = false,
    this.debugOpenActionsModal = false,
  });

  final bool embedInSheet;
  final bool debugOpenSortModal;
  final bool debugOpenActionsModal;

  @override
  ConsumerState<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends ConsumerState<ProfilesPage> {
  bool _isLoading = false;
  bool _debugSortOpened = false;
  bool _debugActionsOpened = false;
  _ProfilesSort _sortBy = _ProfilesSort.lastUpdate;
  bool _sortAscending = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final profilesAsync = ref.watch(profileListProvider);
    if (widget.debugOpenSortModal && !_debugSortOpened) {
      _debugSortOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSortModal(context);
      });
    }
    if (widget.debugOpenActionsModal && !_debugActionsOpened) {
      _debugActionsOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final t = ref.read(translationsProvider);
        _showProfileActions(
          context,
          const ProfileEntity(
            id: 'debug-profile',
            name: '测试配置',
            url: 'ss://debug@example.com:443#debug',
            active: true,
          ),
          t,
        );
      });
    }

    if (widget.embedInSheet) {
      return AiUiModalWrapper(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: profilesAsync.when(
                  data: (profiles) {
                    final sortedProfiles = _sortedProfiles(profiles);
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      shrinkWrap: true,
                      itemCount: sortedProfiles.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final profile = sortedProfiles[index];
                        return _ProfileCard(
                              profile: profile,
                              onTap: () => _setActive(profile.id),
                              onLongPress: () =>
                                  _showProfileActions(context, profile, t),
                              onShare: () =>
                                  _copyProfileLink(context, profile, t),
                              onUpdate: () => _updateProfile(profile.id, t),
                              onEdit: () => _showEditDialog(context, profile),
                              onDelete: () => _confirmDeleteProfile(
                                profile.id,
                                profile.name,
                                t,
                              ),
                            )
                            .animate()
                            .fadeIn(
                              duration: 300.ms,
                              delay: (200 + index * 50).ms,
                            )
                            .slideX(
                              begin: 0.1,
                              end: 0,
                              duration: 300.ms,
                              delay: (200 + index * 50).ms,
                            );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${t.failure.unexpected}: $e'),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              decoration: const BoxDecoration(color: Colors.transparent),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: FluentIcons.add_24_regular,
                      label: t.profile.actionButtons.add,
                      onTap: () => _showAddDialog(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: FluentIcons.arrow_sync_24_regular,
                      label: t.profile.actionButtons.updateAll,
                      isLoading: _isLoading,
                      onTap: _isLoading ? null : () => _updateAll(t),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: FluentIcons.arrow_sort_24_regular,
                      label: t.profile.actionButtons.sort,
                      onTap: () => _showSortModal(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: widget.embedInSheet ? 0 : 24),
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
                    tooltip: t.profile.actionButtons.updateAll,
                    isLoading: _isLoading,
                    onTap: _isLoading ? null : () => _updateAll(t),
                  ),
                  const SizedBox(width: 12),
                  _HeaderButton(
                    icon: FluentIcons.add_24_regular,
                    tooltip: t.profile.add.shortBtnTxt,
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
                final sortedProfiles = _sortedProfiles(profiles);
                return ListView.separated(
                  padding: EdgeInsets.only(
                    bottom: widget.embedInSheet ? 24 : 120,
                  ),
                  itemCount: sortedProfiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final profile = sortedProfiles[index];
                    return _ProfileCard(
                          profile: profile,
                          onTap: () => _setActive(profile.id),
                          onLongPress: () =>
                              _showProfileActions(context, profile, t),
                          onShare: () => _copyProfileLink(context, profile, t),
                          onUpdate: () => _updateProfile(profile.id, t),
                          onEdit: () => _showEditDialog(context, profile),
                          onDelete: () => _confirmDeleteProfile(
                            profile.id,
                            profile.name,
                            t,
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 300.ms, delay: (200 + index * 50).ms)
                        .slideX(
                          begin: 0.1,
                          end: 0,
                          duration: 300.ms,
                          delay: (200 + index * 50).ms,
                        );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('${t.failure.unexpected}: $e')),
            ),
          ),
        ],
      ),
    );

    if (widget.embedInSheet) return content;

    return Scaffold(body: SafeArea(child: content));
  }

  void _showAddDialog(BuildContext context) {
    showProfileFormDialog(context, ref);
  }

  void _showEditDialog(BuildContext context, ProfileEntity profile) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => ProfileDetailsPage(profile.id)),
    );
  }

  void _showProfileActions(
    BuildContext context,
    ProfileEntity profile,
    TranslationsEn t,
  ) {
    // isScrollControlled: true——默认（false）会把弹窗内容高度限制在屏幕的
    // 9/16，多加一个"分享二维码"入口后（激活的远程订阅：分享链接/分享
    // 二维码/编辑配置/更新订阅/删除共 5 行）在小屏视口下会顶到这条隐藏限高，
    // 产生 RenderFlex overflow。改成按内容实际高度撑开，不受这个固定比例
    // 限制；backgroundColor/barrierColor 保持不变（barrierColor 走 Material
    // 默认的 Colors.black54，别处测试断言过这个颜色，不能悄悄改成
    // showAiUiModal 那种透明 barrier）。
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ProfileActionsModal(
        profile: profile,
        onShare: () => _copyProfileLink(context, profile, t),
        onShowQr: () => _showQrDialog(context, profile),
        onEdit: () => _showEditDialog(context, profile),
        onUpdate: () => _updateProfile(profile.id, t),
        onDelete: () => _confirmDeleteProfile(profile.id, profile.name, t),
      ),
    );
  }

  /// 弹出订阅二维码：内容是 [profileShareUrl]（远程订阅 URL，已把订阅名编码进
  /// fragment），跟 [_copyProfileLink] 复制到剪贴板的内容保持一致——对方无论
  /// 是粘贴还是扫码，导入后拿到的名称都是同一个。
  void _showQrDialog(BuildContext context, ProfileEntity profile) {
    showAiUiModal<void>(
      context: context,
      builder: (context) => ProfileQrDialog(
        data: profileShareUrl(profile),
        profileName: profile.name,
      ),
    );
  }

  Future<void> _copyProfileLink(
    BuildContext context,
    ProfileEntity profile,
    TranslationsEn t,
  ) async {
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      final content = await profileShareClipboardText(
        profile,
        configFilePath: repo.configFilePath,
      );
      await Clipboard.setData(ClipboardData(text: content));
      if (context.mounted) {
        final message = _isRemoteProfile(profile)
            ? t.profile.share.subscriptionLinkCopied
            : '配置内容已复制';
        AppToast.success(context, message);
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, '${t.failure.unexpected}: $e');
      }
    }
  }

  List<ProfileEntity> _sortedProfiles(List<ProfileEntity> profiles) {
    return sortProfilesByPriority(profiles, (a, b) {
      final result = switch (_sortBy) {
        _ProfilesSort.lastUpdate => (a.lastUpdate ?? DateTime(0)).compareTo(
          b.lastUpdate ?? DateTime(0),
        ),
        _ProfilesSort.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
      return _sortAscending ? result : -result;
    });
  }

  void _showSortModal(BuildContext context) {
    showAiUiModal<void>(
      context: context,
      builder: (context) => _ProfilesSortModal(
        sortBy: _sortBy,
        ascending: _sortAscending,
        onChanged: (sortBy, ascending) {
          setState(() {
            _sortBy = sortBy;
            _sortAscending = ascending;
          });
        },
      ),
    );
  }

  Future<void> _setActive(String id) async {
    try {
      // fire-and-forget：跟 connect/disconnect 那两处既有触点风格一致，触觉
      // 反馈绝不能 await 阻塞真正的切换逻辑（没有 mock 平台通道的测试环境下
      // await 会让这个 Future 永远挂起，拖死 repo.setActive）。
      unawaited(ref.read(hapticServiceProvider).lightImpact());
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.setActive(id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
      if (widget.embedInSheet && mounted) {
        unawaited(Navigator.of(context).maybePop());
      }
    } catch (e) {
      if (mounted) AppToast.error(context, '切换失败: $e');
    }
  }

  Future<void> _updateProfile(String id, TranslationsEn t) async {
    setState(() => _isLoading = true);
    try {
      unawaited(ref.read(hapticServiceProvider).lightImpact());
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.update(id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
      if (mounted) AppToast.success(context, t.profile.update.successMsg);
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '${t.profile.update.failureMsg}: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteProfile(
    String id,
    String name,
    TranslationsEn t,
  ) async {
    final ok = await showConfirmationDialog(
      context,
      title: '删除配置文件',
      message: '确定要删除"$name"吗？此操作不可撤销。',
      icon: FluentIcons.delete_24_regular,
    );
    if (!ok || !mounted) return;
    await _deleteProfile(id, t);
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
      ref.invalidate(activeProfileProvider);
      ref.invalidate(offlineProxyGroupsProvider);
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

enum _ProfilesSort {
  lastUpdate(FluentIcons.clock_24_regular),
  name(FluentIcons.text_sort_ascending_24_regular);

  const _ProfilesSort(this.icon);

  final IconData icon;

  String label(TranslationsEn t) {
    return switch (this) {
      _ProfilesSort.lastUpdate => t.profile.sortBy.lastUpdate,
      _ProfilesSort.name => t.profile.sortBy.name,
    };
  }
}

class _ProfilesSortModal extends ConsumerWidget {
  const _ProfilesSortModal({
    required this.sortBy,
    required this.ascending,
    required this.onChanged,
  });

  final _ProfilesSort sortBy;
  final bool ascending;
  final void Function(_ProfilesSort sortBy, bool ascending) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return AiUiModalWrapper(
      // ListTile 的背景与涟漪画在最近的 Material 祖先上；AiUiModalWrapper 的
      // 半透明圆角背景是个没有 Material 的 DecoratedBox，会盖住这些效果（debug
      // 模式断言：ListTile background color or ink splashes may be invisible）。
      // 包一层透明 Material 提供更近的挂载点，纯渲染层修正，无任何视觉变化。
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text(
                    t.general.sortBy,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            ..._ProfilesSort.values.map((sort) {
              final selected = sortBy == sort;
              final arrowTurn = ascending ? 0.0 : 0.5;
              return ListTile(
                    title: Text(sort.label(t)),
                    leading: Icon(sort.icon),
                    selected: selected,
                    onTap: () {
                      onChanged(sort, selected ? !ascending : ascending);
                    },
                    trailing: selected
                        ? IconButton(
                            onPressed: () => onChanged(sort, !ascending),
                            icon: AnimatedRotation(
                              turns: arrowTurn,
                              duration: const Duration(milliseconds: 100),
                              child: Icon(
                                FluentIcons.arrow_sort_up_24_regular,
                                semanticLabel: ascending
                                    ? 'ascending'
                                    : 'descending',
                              ),
                            ),
                          )
                        : null,
                  )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: (200 + sort.index * 50).ms)
                  .slideX(
                    begin: 0.1,
                    end: 0,
                    duration: 300.ms,
                    delay: (200 + sort.index * 50).ms,
                  );
            }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _ProfileActionsModal extends ConsumerWidget {
  const _ProfileActionsModal({
    required this.profile,
    required this.onShare,
    required this.onShowQr,
    required this.onEdit,
    required this.onUpdate,
    required this.onDelete,
  });

  final ProfileEntity profile;
  final VoidCallback onShare;
  final VoidCallback onShowQr;
  final VoidCallback onEdit;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final canUpdate = _isRemoteProfile(profile);
    return AiUiModalWrapper(
      // 同 _ProfilesSortModal：透明 Material 为内部 ListTile 提供更近的挂载点，
      // 避免 AiUiModalWrapper 的半透明背景盖住背景/涟漪（debug 断言），纯渲染层修正。
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                  leading: Icon(
                    FluentIcons.share_24_regular,
                    color: aiUi.secondaryTextColor,
                  ),
                  title: const Text(
                    '分享链接',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    onShare();
                  },
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 200.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 200.ms),
            // 只有远程订阅才有真正可分享的 URL 可编码——本地导入的
            // `content://` 伪 URL 不是一个能被扫码/粘贴复用的链接，同
            // "更新订阅" 入口一样按 canUpdate 收起。
            if (canUpdate)
              ListTile(
                    leading: Icon(
                      FluentIcons.qr_code_24_regular,
                      color: aiUi.secondaryTextColor,
                    ),
                    title: Text(
                      t.profile.share.subLinkQrCode,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.of(context).maybePop();
                      onShowQr();
                    },
                  )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 225.ms)
                  .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 225.ms),
            ListTile(
                  leading: Icon(
                    FluentIcons.edit_24_regular,
                    color: aiUi.secondaryTextColor,
                  ),
                  title: const Text(
                    '编辑配置',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    onEdit();
                  },
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 250.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 250.ms),
            if (canUpdate)
              ListTile(
                    leading: Icon(
                      FluentIcons.arrow_sync_24_regular,
                      color: aiUi.secondaryTextColor,
                    ),
                    title: const Text(
                      '更新订阅',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.of(context).maybePop();
                      onUpdate();
                    },
                  )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 300.ms)
                  .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 300.ms),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
              ),
            ).animate().fadeIn(duration: 300.ms, delay: 350.ms),
            ListTile(
                  leading: const Icon(
                    FluentIcons.delete_24_regular,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '删除',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    onDelete();
                  },
                )
                .animate()
                .fadeIn(duration: 300.ms, delay: 400.ms)
                .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 400.ms),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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
  final String tooltip;
  final bool filled;
  final bool isLoading;
  final VoidCallback? onTap;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    this.filled = false,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: filled
                  ? theme.colorScheme.primary
                  : aiUi.softBackgroundColor,
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
        ),
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
    required this.onLongPress,
    required this.onShare,
    required this.onUpdate,
    required this.onEdit,
    required this.onDelete,
  });

  final ProfileEntity profile;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onShare;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;
    final isRemote = _isRemoteProfile(profile);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : aiUi.glassColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: profile.active
                ? theme.colorScheme.primary
                : aiUi.borderColor.withValues(alpha: 0.05),
            width: profile.active ? 2 : 1,
          ),
          boxShadow: profile.active ? aiUi.primaryShadow : aiUi.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRemote
                      ? FluentIcons.link_24_regular
                      : FluentIcons.shield_24_regular,
                  color: profile.active
                      ? theme.colorScheme.primary
                      : aiUi.secondaryTextColor,
                  size: 20,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    profile.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: profile.active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                if (isRemote) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: onUpdate,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: aiUi.softBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        FluentIcons.arrow_sync_24_regular,
                        size: 16,
                        color: aiUi.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (profile.subInfo != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: aiUi.softBackgroundColor,
                    border: Border.all(color: aiUi.borderColor),
                    borderRadius: BorderRadius.circular(8),
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
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.6,
                            ),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${SubscriptionInfo.formatBytes(profile.subInfo!.used)} / ${SubscriptionInfo.formatBytes(profile.subInfo!.total)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: aiUi.secondaryTextColor,
                    ),
                  ),
                  Text(
                    formatExpireDate(profile.subInfo!.expire, t),
                    style: TextStyle(
                      fontSize: 12,
                      color: profile.subInfo!.isExpired
                          ? Colors.red
                          : aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallIconButton(
                  icon: FluentIcons.edit_20_regular,
                  onTap: onEdit,
                ),
                const SizedBox(width: 8),
                _SmallIconButton(
                  icon: FluentIcons.share_20_regular,
                  onTap: onShare,
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFF8FAFC) : aiUi.glassColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLight ? Colors.transparent : aiUi.borderColor,
          ),
        ),
        child: Column(
          children: [
            isLoading
                ? Icon(
                        icon,
                        size: 20,
                        color: isLight
                            ? theme.colorScheme.primary
                            : Colors.white,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: 1.seconds)
                : Icon(
                    icon,
                    size: 20,
                    color: isLight ? aiUi.secondaryTextColor : Colors.white70,
                  ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isLight ? aiUi.secondaryTextColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isRemoteProfile(ProfileEntity profile) {
  final uri = Uri.tryParse(profile.url.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

/// 订阅在列表中的展示优先级：数字越小越靠前。
///
/// 三档，参照本仓库排序机制的风格设计（同类思路可见于其它上游 profile 列表
/// 实现的"激活优先 + 可用性次优先"分层排序，但这里不依赖数据库排序表达式，
/// 直接用 Dart compare 回调实现，跟 `_sortedProfiles` 原有写法保持一致）：
///   0 - 当前激活的订阅，始终置顶（即便它已过期/流量耗尽，正在用的东西不该
///       从眼前消失）。
///   1 - 非激活但仍可用（未过期、流量未耗尽，或压根没有订阅信息——比如本地
///       导入、还没拉取过订阅信息的新配置）。
///   2 - 非激活且已过期或流量已耗尽——明显需要用户关注/清理，但不该挡在
///       "正常能用"的订阅前面，故降权排到最后。
/// 同一档内再按用户选择的排序字段（`_sortBy`/`_sortAscending`）排序。
int profileDisplayPriority(ProfileEntity profile) {
  if (profile.active) return 0;
  final subInfo = profile.subInfo;
  if (subInfo == null) return 1;
  final isExhausted = subInfo.total > 0 && subInfo.usageRatio >= 1.0;
  return (subInfo.isExpired || isExhausted) ? 2 : 1;
}

/// 按 [profileDisplayPriority] 分层排序，同一优先级内用 [tiebreaker] 决定
/// 先后顺序。不修改入参列表，返回新列表。
List<ProfileEntity> sortProfilesByPriority(
  List<ProfileEntity> profiles,
  int Function(ProfileEntity a, ProfileEntity b) tiebreaker,
) {
  final sorted = [...profiles];
  sorted.sort((a, b) {
    final tierCompare = profileDisplayPriority(
      a,
    ).compareTo(profileDisplayPriority(b));
    if (tierCompare != 0) return tierCompare;
    return tiebreaker(a, b);
  });
  return sorted;
}

/// 分享用的订阅 URL：把用户自己起的订阅名附加成 URL fragment（`#name`，
/// `Uri.encodeComponent` 编码），这样对方复制/扫码导入时，
/// `ProfileParser._parseName` 的 fragment fallback（见
/// `profile_parser.dart`）能直接还原出同一个名称，不需要额外协议。
///
/// 只对远程订阅（http/https）生效——本地导入的 `content://` 伪 URL 本来就不是
/// 一个真实可分享的链接，原样返回。名称为空白时同样原样返回，不附加空 fragment。
String profileShareUrl(ProfileEntity profile) {
  if (!_isRemoteProfile(profile)) return profile.url;
  final trimmedName = profile.name.trim();
  if (trimmedName.isEmpty) return profile.url;
  final uri = Uri.tryParse(profile.url.trim());
  if (uri == null) return profile.url;
  return uri.replace(fragment: Uri.encodeComponent(trimmedName)).toString();
}

Future<String> profileShareClipboardText(
  ProfileEntity profile, {
  String Function(String profileId)? configFilePath,
}) async {
  if (_isRemoteProfile(profile)) return profileShareUrl(profile);
  final path = configFilePath?.call(profile.id);
  if (path == null) return '';
  final file = File(path);
  return await file.exists() ? file.readAsString() : '';
}
