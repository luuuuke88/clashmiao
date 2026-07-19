import 'package:clashmiao/core/window/silent_start.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 回归测试：桌面端"静默启动"开关（设置页 clashmiao_silent_start）此前只
/// 写偏好，没有任何启动流程读它——main.dart 的 waitUntilReadyToShow 回调
/// 无条件 show()+focus()，开关在 UI 上能打开，重启 App 窗口照样弹出来，是
/// 纯粹的假开关。
///
/// [showWindowUnlessSilentStart] 是从 main.dart 启动流程里抽出来的可测单元：
/// 读偏好 → 决定要不要 show()+focus()，不需要真的跑一遍完整的 main()
/// （会触发真实 sing-box / 网络 / 深链等初始化）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          // window_manager 的 show() 内部会先调 isMinimized() 判断要不要
          // restore()，返回类型是 bool，不能像别的方法那样兜底返回 null。
          if (call.method == 'isMinimized') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('showWindowUnlessSilentStart', () {
    test('偏好缺省（未设置）时按旧行为 show + focus', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await showWindowUnlessSilentStart(prefs);

      expect(calls, containsAll(['show', 'focus']));
    });

    test('clashmiao_silent_start=false 时 show + focus', () async {
      SharedPreferences.setMockInitialValues({
        'clashmiao_silent_start': false,
      });
      final prefs = await SharedPreferences.getInstance();

      await showWindowUnlessSilentStart(prefs);

      expect(calls, containsAll(['show', 'focus']));
    });

    test('clashmiao_silent_start=true 时窗口保持隐藏，绝不调用 show/focus', () async {
      SharedPreferences.setMockInitialValues({
        'clashmiao_silent_start': true,
      });
      final prefs = await SharedPreferences.getInstance();

      await showWindowUnlessSilentStart(prefs);

      expect(
        calls,
        isEmpty,
        reason:
            '静默启动应该让原生窗口保持初始隐藏状态（不 show 就不会露出来），'
            '而不是"先 show 再 hide"——那样用户会看到窗口先弹出又消失的闪烁',
      );
    });
  });
}
