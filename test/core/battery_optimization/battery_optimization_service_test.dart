import 'package:clashmiao/core/battery_optimization/battery_optimization_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.clashmiao.app/platform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('BatteryOptimizationService', () {
    test('isIgnoringBatteryOptimizations 透传原生 true', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            received = call;
            return true;
          });

      final result = await BatteryOptimizationService()
          .isIgnoringBatteryOptimizations();

      expect(result, isTrue);
      expect(received?.method, 'is_ignoring_battery_optimizations');
    });

    test('isIgnoringBatteryOptimizations 透传原生 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => false);

      final result = await BatteryOptimizationService()
          .isIgnoringBatteryOptimizations();

      expect(result, isFalse);
    });

    test('isIgnoringBatteryOptimizations 在平台异常时保守返回 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'E_PLATFORM', message: 'boom');
          });

      final result = await BatteryOptimizationService()
          .isIgnoringBatteryOptimizations();

      expect(result, isFalse);
    });

    test('requestIgnoreBatteryOptimizations 调用正确方法名并透传 true', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            received = call;
            return true;
          });

      final result = await BatteryOptimizationService()
          .requestIgnoreBatteryOptimizations();

      expect(result, isTrue);
      expect(received?.method, 'request_ignore_battery_optimizations');
    });

    test('requestIgnoreBatteryOptimizations 用户拒绝时返回 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => false);

      final result = await BatteryOptimizationService()
          .requestIgnoreBatteryOptimizations();

      expect(result, isFalse);
    });

    test('requestIgnoreBatteryOptimizations 在平台异常时保守返回 false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(code: 'E_PLATFORM', message: 'boom');
          });

      final result = await BatteryOptimizationService()
          .requestIgnoreBatteryOptimizations();

      expect(result, isFalse);
    });

    test('未注册 mock handler（MissingPluginException）时保守返回 false', () async {
      // 不设置任何 handler，模拟真实场景中平台侧完全没实现该 channel 的极端情况。
      final result = await BatteryOptimizationService()
          .isIgnoringBatteryOptimizations();

      expect(result, isFalse);
    });
  });
}
