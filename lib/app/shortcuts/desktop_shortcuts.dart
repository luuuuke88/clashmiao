import 'dart:async';
import 'dart:io';

import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/app/router/app_router.dart';
import 'package:clashmiao/app/tray/tray_controller.dart';
import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart'
    show isHttpDownloadUrl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端（macOS / Windows / Linux）全局键盘快捷键。
///
/// 用法：仅在桌面平台包一层在 `ClashMiaoApp` 外面（见 `main.dart`），移动端
/// 不需要。放在 `MaterialApp.router` 外面是关键——Flutter 处理键盘事件时，
/// 从当前拿到焦点的节点往上找最近的 [Shortcuts] 祖先，逐级尝试匹配，一旦某一
/// 级匹配上就不再往上找。文本输入框（`TextField`/`TextFormField` 等）的
/// 复制/粘贴/剪切快捷键是由 Flutter 框架内置的 `DefaultTextEditingShortcuts`
/// 提供的，它嵌在 `WidgetsApp`（`MaterialApp` 内部）里，比包在最外层的这个
/// wrapper 更靠近任何一个正在输入的文本框。也就是说：只要本 wrapper 包在
/// `MaterialApp.router` 外面，用户在任意文本框里按 Cmd/Ctrl+V 时，
/// `DefaultTextEditingShortcuts` 会先一步命中并完成正常的文本粘贴，事件根本
/// 不会冒泡到这里的全局"粘贴导入"处理——不需要手动判断"当前是否聚焦在输入
/// 框"，Flutter 自带的最近祖先优先规则已经保证了这一点。见
/// `test/core/shortcuts/desktop_shortcuts_test.dart` 里聚焦文本框时的回归测试。
class DesktopShortcutsWrapper extends ConsumerWidget {
  const DesktopShortcutsWrapper({
    super.key,
    required this.child,
    this.onPasteImport,
    this.onCloseWindow,
    this.onOpenSettings,
    this.onQuitApp,
    this.isMacOS,
    this.isLinux,
  });

  final Widget child;

  /// 测试注入点：不传时使用真实的 [defaultPasteImport] 等实现。
  final Future<void> Function(WidgetRef ref)? onPasteImport;
  final Future<void> Function(WidgetRef ref)? onCloseWindow;
  final void Function(WidgetRef ref)? onOpenSettings;
  final Future<void> Function(WidgetRef ref)? onQuitApp;

  /// 测试注入：不传时使用真实的 [Platform.isMacOS] / [Platform.isLinux]——
  /// 用来在非 mac/linux 的测试跑机上也能覆盖到平台专属快捷键的注册/不注册。
  final bool? isMacOS;
  final bool? isLinux;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final macOS = isMacOS ?? Platform.isMacOS;
    final linux = isLinux ?? Platform.isLinux;

    return Shortcuts(
      shortcuts: {
        // 最高优先级：粘贴导入订阅，macOS 用 Cmd+V，Windows/Linux 用 Ctrl+V。
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
            const PasteImportIntent(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const PasteImportIntent(),

        if (macOS) ...{
          // Cmd+W：隐藏窗口到托盘（跟点窗口关闭按钮的行为保持一致，不退出
          // 进程、不断开 VPN）。
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
              const CloseWindowIntent(),
          // Cmd+,：切到设置 tab。
          const SingleActivator(LogicalKeyboardKey.comma, meta: true):
              const OpenSettingsIntent(),
        },

        if (linux)
          // Ctrl+Q：真正退出（断开 VPN + 清理托盘 + 销毁窗口）。
          const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
              const QuitAppIntent(),
      },
      child: Actions(
        actions: {
          PasteImportIntent: CallbackAction<PasteImportIntent>(
            onInvoke: (intent) {
              unawaited((onPasteImport ?? defaultPasteImport)(ref));
              return null;
            },
          ),
          CloseWindowIntent: CallbackAction<CloseWindowIntent>(
            onInvoke: (intent) {
              unawaited((onCloseWindow ?? defaultCloseWindow)(ref));
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (intent) {
              (onOpenSettings ?? defaultOpenSettings)(ref);
              return null;
            },
          ),
          QuitAppIntent: CallbackAction<QuitAppIntent>(
            onInvoke: (intent) {
              unawaited((onQuitApp ?? defaultQuitApp)(ref));
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class PasteImportIntent extends Intent {
  const PasteImportIntent();
}

class CloseWindowIntent extends Intent {
  const CloseWindowIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class QuitAppIntent extends Intent {
  const QuitAppIntent();
}

/// Cmd/Ctrl+V 的真实处理：读剪贴板 → 复用 [isHttpDownloadUrl] 的判断方向 →
/// 调 [ProfileRepository] 对应方法落地 → toast 反馈。
///
/// 特意不依赖任何"当前打开了哪个页面/弹窗"的假设——这正是全局快捷键存在的
/// 意义：任意界面按下都能直接导入，不需要先点开"添加订阅"弹窗。剪贴板为空、
/// 读取剪贴板失败、内容解析失败这三种情况都必须给出明确 toast，不能静默无
/// 反应（用户按了快捷键却什么都没发生，会以为快捷键没生效）。
///
/// 用 [appRouterNavigatorKey] 拿 BuildContext 而不是 wrapper 自己的
/// context——wrapper 包在 `MaterialApp.router` 外面，自己的 context 找不到
/// Overlay/Navigator，没法弹 toast；`appRouterNavigatorKey` 绑定在
/// GoRouter 的根 Navigator 上，任意时刻都能拿到一个位于 Overlay 之下的
/// 有效 context（只要 App 已经跑起来）。
@visibleForTesting
Future<void> defaultPasteImport(WidgetRef ref) async {
  final context = appRouterNavigatorKey.currentContext;
  if (context == null) return;

  String clipboardText;
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    clipboardText = data?.text?.trim() ?? '';
  } catch (e) {
    if (context.mounted) AppToast.error(context, '读取剪贴板失败：$e');
    return;
  }

  if (clipboardText.isEmpty) {
    if (context.mounted) {
      AppToast.warning(context, '剪贴板为空，无法导入订阅');
    }
    return;
  }

  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    final ProfileEntity profile;
    if (isHttpDownloadUrl(clipboardText)) {
      profile = await repo.addByUrl(clipboardText);
    } else {
      profile = await repo.addByContent(clipboardText, name: '');
    }
    ref.invalidate(profileListProvider);
    ref.invalidate(activeProfileProvider);
    ref.invalidate(offlineProxyGroupsProvider);
    if (context.mounted) {
      AppToast.success(context, '已导入订阅：${profile.name}');
    }
  } catch (e) {
    if (context.mounted) AppToast.error(context, '导入失败：$e');
  }
}

/// Cmd+W（macOS）：隐藏窗口到托盘，语义上跟点窗口关闭按钮一致（见
/// `main.dart` 的 `DesktopShutdownGuard`）——不断开 VPN、不退出进程。
@visibleForTesting
Future<void> defaultCloseWindow(WidgetRef ref) async {
  await windowManager.hide();
}

/// Cmd+,（macOS）：切到底部导航的"设置" tab。
@visibleForTesting
void defaultOpenSettings(WidgetRef ref) {
  ref.read(selectedTabProvider.notifier).state = AppTab.settings;
}

/// Ctrl+Q（Linux）：真正退出——断开 VPN、清理托盘、销毁窗口，复用托盘菜单
/// "退出"项同一条 [performQuitSequence]。
@visibleForTesting
Future<void> defaultQuitApp(WidgetRef ref) async {
  await performQuitSequence(
    disconnect: () =>
        ref.read(connectionControllerProvider.notifier).disconnect(),
    disposeTray: TrayController.instance.dispose,
    destroyWindow: windowManager.destroy,
  );
}
