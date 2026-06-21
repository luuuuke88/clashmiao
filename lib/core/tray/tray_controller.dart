import 'dart:io';

import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端（macOS / Windows / Linux）系统托盘控制。
///
/// 用法：在 `main()` setup 完 windowManager 后 `await TrayController.instance.setup(ref)`。
/// 内部会注册 TrayListener，并 listen connectionControllerProvider 同步图标 + 菜单。
class TrayController extends TrayListener {
  TrayController._();
  static final instance = TrayController._();

  ProviderContainer? _container;
  ProviderSubscription<AsyncValue<BoxStatus>>? _statusSub;
  bool _initialized = false;

  Future<void> setup(ProviderContainer container) async {
    if (!_isDesktop) return;
    if (_initialized) return;
    _initialized = true;
    _container = container;

    try {
      // 图标路径：macOS 用 16x16 PNG（template image 系统会自动反色）
      await trayManager.setIcon(_iconPath(const BoxStopped()));
    } catch (e) {
      // 没图标先用文字模式
      if (kDebugMode) debugPrint('[Tray] setIcon failed: $e');
    }
    await _rebuildMenu(const BoxStopped());
    trayManager.addListener(this);

    _statusSub = container.listen<AsyncValue<BoxStatus>>(
      connectionControllerProvider,
      (_, next) {
        final status = next.valueOrNull ?? const BoxStopped();
        _rebuildMenu(status);
        trayManager.setIcon(_iconPath(status)).catchError((_) {});
      },
    );
  }

  Future<void> dispose() async {
    _statusSub?.close();
    trayManager.removeListener(this);
    await trayManager.destroy();
    _initialized = false;
  }

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Use the bundled tray icon on desktop.
  String _iconPath(BoxStatus status) {
    return 'assets/images/tray_icon.png';
  }

  Future<void> _rebuildMenu(BoxStatus status) async {
    final isConnected = status is BoxStarted;
    final isTransitioning = status is BoxStarting || status is BoxStopping;
    final menu = Menu(
      items: [
        MenuItem(
          key: 'toggle',
          label: isConnected ? '断开连接' : (isTransitioning ? '切换中...' : '连接'),
          disabled: isTransitioning,
        ),
        MenuItem.separator(),
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem(key: 'hide', label: '隐藏到托盘'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出 ClashMiao'),
      ],
    );
    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      if (kDebugMode) debugPrint('[Tray] setContextMenu failed: $e');
    }
  }

  @override
  void onTrayIconMouseDown() async {
    // 左键：toggle 窗口可见
    final visible = await windowManager.isVisible();
    if (visible) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    final c = _container;
    if (c == null) return;
    switch (menuItem.key) {
      case 'toggle':
        await c.read(connectionControllerProvider.notifier).toggle();
        break;
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'hide':
        await windowManager.hide();
        break;
      case 'quit':
        // 退出前先停 sing-box 释放系统代理
        try {
          await c.read(connectionControllerProvider.notifier).disconnect();
        } catch (_) {}
        await windowManager.destroy();
        break;
    }
  }
}
