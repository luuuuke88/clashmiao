import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面端"静默启动"偏好 key，与
/// `lib/features/settings/widget/settings_page.dart` 里
/// `_BoolPreferenceTile(prefKey: 'clashmiao_silent_start')` 共用同一个 key。
const silentStartPrefKey = 'clashmiao_silent_start';

/// 读 `clashmiao_silent_start` 偏好，决定桌面端启动时窗口要不要露出来。
///
/// 之前的 bug：设置页的静默启动开关只写偏好，没有任何启动流程读它——
/// `main.dart` 的 `waitUntilReadyToShow` 回调无条件 `show()` + `focus()`，
/// 开关在 UI 上能打开，重启 App 窗口照样弹出来，是纯粹的假开关。
///
/// 这里直接跳过 `show()`/`focus()`（而不是"先 show 再 hide"）来避免用户看到
/// 窗口先弹出又消失的闪烁——`window_manager` 的原生窗口在 `show()` 被调用
/// 之前本来就是隐藏状态，不 show 就完全不会露出来。
Future<void> showWindowUnlessSilentStart(SharedPreferences prefs) async {
  final silentStart = prefs.getBool(silentStartPrefKey) ?? false;
  if (silentStart) return;
  await windowManager.show();
  await windowManager.focus();
}
