import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 复用仓库内既有的 sharedPreferencesProvider 覆盖模式
/// （见 test/core/theme/theme_preferences_test.dart）。
Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await c.read(sharedPreferencesProvider.future);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    // HapticFeedback.xxxImpact() 全部经 SystemChannels.platform 发送
    // method='HapticFeedback.vibrate'，用 arguments 区分具体类型。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('HapticService', () {
    test('pref 开启时 heavyImpact 触发真实平台调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': true});
      await c.read(hapticServiceProvider).heavyImpact();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.heavyImpact');
    });

    test('pref 开启时 mediumImpact 触发真实平台调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': true});
      await c.read(hapticServiceProvider).mediumImpact();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.mediumImpact');
    });

    test('pref 开启时 lightImpact 触发真实平台调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': true});
      await c.read(hapticServiceProvider).lightImpact();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    });

    test('pref 未设置时默认开启（与 settings 页 defaultValue: true 一致）', () async {
      final c = await _container({});
      await c.read(hapticServiceProvider).heavyImpact();
      expect(calls, hasLength(1), reason: '默认值应和 settings_page 的 defaultValue: true 一致');
    });

    test('pref 关闭时 heavyImpact 零调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': false});
      await c.read(hapticServiceProvider).heavyImpact();
      expect(calls, isEmpty);
    });

    test('pref 关闭时 mediumImpact 零调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': false});
      await c.read(hapticServiceProvider).mediumImpact();
      expect(calls, isEmpty);
    });

    test('pref 关闭时 lightImpact 零调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': false});
      await c.read(hapticServiceProvider).lightImpact();
      expect(calls, isEmpty);
    });

    test('关闭状态下连续调用三种方法仍然零调用', () async {
      final c = await _container({'clashmiao_haptic_feedback': false});
      final service = c.read(hapticServiceProvider);
      await service.heavyImpact();
      await service.mediumImpact();
      await service.lightImpact();
      expect(calls, isEmpty);
    });
  });
}
