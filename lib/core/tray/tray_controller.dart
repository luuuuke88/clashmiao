import 'dart:io';

import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// [buildTrayMenuLabels] 的返回值：托盘菜单四个条目当前该显示的文案。
typedef TrayMenuLabels = ({
  String toggle,
  String show,
  String hide,
  String quit,
});

/// 根据当前连接状态 + 当前语言的 [Translations]，算出托盘菜单四个条目的文案。
///
/// 抽成纯函数是为了可测——之前这些文案硬编码中文（'断开连接' / '连接' /
/// '切换中...' / '显示窗口' / '隐藏到托盘' / '退出 ClashMiao'），完全没走
/// i18n。现在读 `translations.g.dart` 里已有的 `tray.*` key：
/// `tray.status.connect/connecting/disconnect/disconnecting`、`tray.open`、
/// `tray.hide`（新增）、`tray.quit`。
@visibleForTesting
TrayMenuLabels buildTrayMenuLabels(BoxStatus status, Translations t) {
  final String toggle;
  if (status is BoxStarted) {
    toggle = t.tray.status.disconnect;
  } else if (status is BoxStarting) {
    toggle = t.tray.status.connecting;
  } else if (status is BoxStopping) {
    toggle = t.tray.status.disconnecting;
  } else {
    toggle = t.tray.status.connect;
  }
  return (
    toggle: toggle,
    show: t.tray.open,
    hide: t.tray.hide,
    quit: t.tray.quit,
  );
}

/// "服务模式"子菜单自身的标题（不是子菜单里"智能/全局"两个选项的文案，那两个走
/// 正规 i18n：`t.home.routingMode.global` / `t.home.routingMode.smart`）。
///
/// 现有 `translations.g.dart` 里找不到一个不会引起歧义的现成 key 给这个子菜单
/// 标题用：`config.serviceMode`（"服务模式"）名字本身很贴切，但在这个 App 里已经
/// 被"仅线路 / 系统线路 / VPN"这个完全不同的概念占用了（见
/// `quick_settings_modal.dart` 的 `_QuickServiceMode`：那是决定客户端本身怎么接入
/// 网络的选项，不是这里的"智能分流 / 全局代理"路由模式），复用会造成同名不同义。
/// 本任务的约束又只允许改这一个文件，没法去 `assets/translations` 加新 key。
/// 这里退而求其次，手动按当前 locale 二选一，只用于这一个子菜单的容器标题；
/// 其它语言一律回退英文——跟 [buildTrayMenuLabels] 里 `hide` 字段既有的回退策略
/// 一致（`fallback_strategy: base_locale`），不是新发明的处理方式。
@visibleForTesting
String proxyModeSubmenuLabel(Translations t) {
  return t.$meta.locale == AppLocale.zhCn ? '服务模式' : 'Service Mode';
}

/// 根据当前连接状态 + 当前语言 + 当前生效的代理模式（[proxyMode]，对齐
/// `proxyModeProvider`：0 = 全局，1 = 智能），构建完整的托盘右键菜单结构。
///
/// 抽成纯函数是为了可测——`Menu`/`MenuItem`（来自 `package:tray_manager`）都是
/// 纯 Dart 数据类，构造它们不会触发任何平台 channel 调用，可以直接在纯 Dart
/// 测试里断言子菜单的条目数量/label/勾选状态，不需要真实的 ProviderContainer
/// 或者渲染完整 App。
///
/// 新增两个子菜单（原来只有 toggle/show/hide/quit 四个平铺条目）：
/// - `open_page`："打开..."子菜单，跳转到 App 内某个具体页面（首页/线路/设置）。
///   这个 App 没有按页面区分的 GoRouter 路由（见 `app_router.dart`，路由只有
///   `/` 和 `/onboarding`），实际的页面切换是 `ShellPage` 用
///   `selectedTabProvider`（一个 tab 下标）驱动 `IndexedStack`（见
///   `lib/app/shell_page.dart` / `lib/app/state/selected_tab.dart`）。所以"跳转
///   到具体页面"在这里等价于"把 selectedTabProvider 设成目标 tab，再把窗口显示
///   出来"，由 [performOpenPage] 负责。"订阅列表"对应的是这三个常驻 tab 里最
///   接近的 `AppTab.proxies`（线路列表）——真正的订阅管理页 `ProfilesPage` 不是
///   `ShellPage` 里常驻的可路由页面，而是从首页用 modal/sheet 弹出来的
///   （见 `shell_page.dart` 里 `showAiUiModal(builder: (_) => ProfilesPage(...))`），
///   从一个裸的 `ProviderContainer`（没有 `BuildContext`）触发这种 modal 需要
///   额外的挂钩机制，超出"列出几个固定选项+点击回调"这个子菜单该做的事，
///   所以这里只覆盖三个常驻 tab。
/// - `proxy_mode`："服务模式"子菜单，对齐 home 页那个"智能分流/全局代理"分段
///   选择器（`proxyModeProvider`，见 `lib/features/home/state/proxy_mode_notifier.dart`
///   和 `home_page.dart` 里的 `_ModeSelector`）。当前生效的模式用
///   `MenuItem.checkbox` 打勾。
Menu buildTrayMenu({
  required BoxStatus status,
  required Translations t,
  required int proxyMode,
}) {
  final isTransitioning = status is BoxStarting || status is BoxStopping;
  final labels = buildTrayMenuLabels(status, t);
  return Menu(
    items: [
      MenuItem(key: 'toggle', label: labels.toggle, disabled: isTransitioning),
      MenuItem.separator(),
      MenuItem(key: 'show', label: labels.show),
      MenuItem(key: 'hide', label: labels.hide),
      MenuItem.separator(),
      MenuItem.submenu(
        key: 'open_page',
        label: t.tray.dashboard,
        submenu: Menu(
          items: [
            MenuItem(key: 'open_home', label: t.home.pageTitle),
            MenuItem(key: 'open_proxies', label: t.proxies.pageTitle),
            MenuItem(key: 'open_settings', label: t.settings.pageTitle),
          ],
        ),
      ),
      MenuItem.submenu(
        key: 'proxy_mode',
        label: proxyModeSubmenuLabel(t),
        submenu: Menu(
          items: [
            MenuItem.checkbox(
              key: 'mode_global',
              label: t.home.routingMode.global,
              checked: proxyMode == 0,
            ),
            MenuItem.checkbox(
              key: 'mode_smart',
              label: t.home.routingMode.smart,
              checked: proxyMode == 1,
            ),
          ],
        ),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: labels.quit),
    ],
  );
}

/// 调 [setIcon] 设置托盘图标，失败时记录日志而不是静默吞掉。
///
/// 此前状态变化的监听回调里是 `trayManager.setIcon(...).catchError((_) {})`
/// ——`assets/images/tray_on/off/pending.png` 这几个资源文件目前并不存在，
/// 每次 setIcon 都会失败，而且这个失败被完全吞掉，连 debugPrint 都没有，
/// 排障时无从得知。这个函数统一收敛 setup() 里最初那次调用和状态变化时那次
/// 调用的失败处理，保证至少有日志。
@visibleForTesting
Future<void> setTrayIconWithLogging(
  Future<void> Function(String path) setIcon,
  String path,
) async {
  try {
    await setIcon(path);
  } catch (e) {
    if (kDebugMode) debugPrint('[Tray] setIcon failed: $e');
  }
}

/// 托盘菜单“退出”那一项的完整退出序列：断开连接 → 清理托盘 → 销毁窗口。
///
/// 抽成纯函数（三个动作都以回调注入）是为了可测——真实的
/// [TrayController.onTrayMenuItemClick] 里这三步分别是
/// `connectionControllerProvider.notifier.disconnect()`、
/// `TrayController.dispose()`、`windowManager.destroy()`，都挂在真实的
/// Riverpod container / 平台 channel 上，没法在纯 Dart 测试里直接跑。
///
/// 此前这里退出前只 disconnect（还带 try/catch 兜底失败）就直接
/// `windowManager.destroy()`，没有显式清理托盘图标/监听器——[TrayController]
/// 自己的 [TrayController.dispose] 方法其实早就写好了，只是从来没人调用过
/// （零调用方，属于遗留清理项）。这里补上：disconnect 之后、销毁窗口之前，
/// 显式调一次托盘清理，避免退出后系统托盘残留幽灵图标（尤其 Windows 上
/// 窗口/进程销毁不一定会连带清掉 shell notification icon）。
///
/// 三步都不能因为前一步失败就中止退出流程——disconnect 失败照样要能退出
/// （沿用原有 try/catch 行为），托盘清理失败也一样：记录日志，然后继续
/// `destroyWindow`，不能让用户点了“退出”卡住退不出去。
///
/// 特意保持 public（曾经是 `@visibleForTesting`）：桌面端全局快捷键 Ctrl+Q
/// （`lib/core/shortcuts/desktop_shortcuts.dart` 的 `defaultQuitApp`）需要
/// 复用同一条退出序列，不应该另外维护一份重复逻辑。
Future<void> performQuitSequence({
  required Future<void> Function() disconnect,
  required Future<void> Function() disposeTray,
  required Future<void> Function() destroyWindow,
}) async {
  try {
    await disconnect();
  } catch (_) {}
  try {
    await disposeTray();
  } catch (e) {
    if (kDebugMode) debugPrint('[Tray] dispose failed during quit: $e');
  }
  await destroyWindow();
}

/// "打开..."子菜单里点某个页面跳转项之后的实际动作：先把 [tabIndex] 写进
/// `selectedTabProvider`，再显示 + 聚焦窗口。
///
/// 抽成纯函数（依赖全部以回调注入）是为了可测——真实调用点里
/// `setSelectedTab` 是 `container.read(selectedTabProvider.notifier).state = ...`，
/// `showWindow`/`focusWindow` 是 `windowManager.show()`/`windowManager.focus()`，
/// 都挂在真实 Riverpod container / 平台 channel 上。
///
/// 先切 tab 再显示窗口（而不是反过来）：`ShellPage` 的 `IndexedStack` 在窗口显示
/// 的第一帧就该已经是目标页，不能让用户先看见旧页面再跳一下。
@visibleForTesting
Future<void> performOpenPage({
  required int tabIndex,
  required void Function(int tabIndex) setSelectedTab,
  required Future<void> Function() showWindow,
  required Future<void> Function() focusWindow,
}) async {
  setSelectedTab(tabIndex);
  await showWindow();
  await focusWindow();
}

/// "服务模式"子菜单里点某个模式项之后的实际动作：切模式 + （如果当前已连接）
/// 立刻 reconnect 让新模式生效。
///
/// 抽成纯函数（依赖全部以回调注入）是为了可测——真实调用点里 `currentMode`/
/// `updateMode` 挂在 `proxyModeProvider`，`isConnected`/`reconnect` 挂在
/// `connectionControllerProvider`，都是真实 Riverpod container 上的读写，没法在
/// 纯 Dart 测试里直接跑。
///
/// 不需要在这里重新拼一遍 `home_page.dart` 的 `_ModeSelector._onModeTap` 那一整套
/// `getDefaultConfigOptions` + `changeConfigOptions` 推送逻辑——
/// `connectionControllerProvider` 的 `connect()`/`reconnect()` 本来就会在每次调用
/// 时现读 `proxyModeProvider` 的最新值去决定 `executeConfigAsIs`/`isSmart`（见
/// `app_providers.dart` 里 `reconnect()` 的实现），所以：
/// - 没连接时，只要模式状态更新 + 持久化了，下次用户点连接自然用的是新模式；
/// - 已连接时，reconnect 一次就会用新模式重新生效，不需要在这里手动去拼
///   fork-side options 再推一遍。
/// 这样避免了在托盘这一层重复一份跟 box service 强耦合的业务逻辑。
@visibleForTesting
Future<void> performProxyModeSwitch({
  required int targetMode,
  required int Function() currentMode,
  required Future<void> Function(int mode) updateMode,
  required bool Function() isConnected,
  required Future<void> Function() reconnect,
}) async {
  if (currentMode() == targetMode) return;
  await updateMode(targetMode);
  if (isConnected()) {
    await reconnect();
  }
}

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

    // 图标路径：macOS 用 16x16 PNG（template image 系统会自动反色）
    await setTrayIconWithLogging(
      trayManager.setIcon,
      _iconPath(const BoxStopped()),
    );
    await _rebuildMenu(const BoxStopped());
    trayManager.addListener(this);

    _statusSub = container.listen<AsyncValue<BoxStatus>>(
      connectionControllerProvider,
      (_, next) {
        final status = next.valueOrNull ?? const BoxStopped();
        _rebuildMenu(status);
        setTrayIconWithLogging(trayManager.setIcon, _iconPath(status));
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

  /// 本该按状态用 tray_on/pending/off.png 三态图标，但美术素材缺失
  /// （assets/images/ 下只有一个通用 tray_icon.png），三态分别指向
  /// 不存在的文件会导致 setIcon 在任何状态下都失败——托盘图标从未
  /// 真正显示过。在拿到真实三态素材前，先全部兜底到这个通用图标，
  /// 好过完全没有图标（尤其是和"静默启动"叠加时，图标渲染失败会
  /// 让用户找不到任何入口）。
  String _iconPath(BoxStatus status) {
    return 'assets/images/tray_icon.png';
  }

  Future<void> _rebuildMenu(BoxStatus status) async {
    final container = _container;
    if (container == null) return;
    final menu = buildTrayMenu(
      status: status,
      t: container.read(translationsProvider),
      proxyMode: container.read(proxyModeProvider),
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
      case 'open_home':
        await _openPage(AppTab.home);
        break;
      case 'open_proxies':
        await _openPage(AppTab.proxies);
        break;
      case 'open_settings':
        await _openPage(AppTab.settings);
        break;
      case 'mode_global':
        await _switchProxyMode(c, 0);
        break;
      case 'mode_smart':
        await _switchProxyMode(c, 1);
        break;
      case 'quit':
        // 退出前先停 sing-box 释放系统代理，再清理托盘图标，最后销毁窗口。
        await performQuitSequence(
          disconnect: () =>
              c.read(connectionControllerProvider.notifier).disconnect(),
          disposeTray: dispose,
          destroyWindow: windowManager.destroy,
        );
        break;
    }
  }

  /// "打开..."子菜单里某个页面跳转项被点击——切 tab + 显示/聚焦窗口。
  Future<void> _openPage(int tabIndex) async {
    final container = _container;
    if (container == null) return;
    await performOpenPage(
      tabIndex: tabIndex,
      setSelectedTab: (i) =>
          container.read(selectedTabProvider.notifier).state = i,
      showWindow: windowManager.show,
      focusWindow: windowManager.focus,
    );
  }

  /// "服务模式"子菜单里某个模式项被点击——切模式，成功后重建菜单让勾选标记
  /// 跟着刷新（`tray_manager` 自带的"点击前后 checked 有变化才重刷"逻辑只看
  /// 被点的那一个 MenuItem，处理不了"选中另一项时前一项要取消勾选"这种互斥
  /// 场景，所以这里手动重刷一次）。
  Future<void> _switchProxyMode(ProviderContainer c, int targetMode) async {
    try {
      await performProxyModeSwitch(
        targetMode: targetMode,
        currentMode: () => c.read(proxyModeProvider),
        updateMode: (mode) =>
            c.read(proxyModeProvider.notifier).updateMode(mode),
        isConnected: () =>
            c.read(connectionControllerProvider).valueOrNull is BoxStarted,
        reconnect: () =>
            c.read(connectionControllerProvider.notifier).reconnect(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Tray] switch proxy mode failed: $e');
    }
    final status =
        c.read(connectionControllerProvider).valueOrNull ?? const BoxStopped();
    await _rebuildMenu(status);
  }
}
