import 'package:clashmiao/core/auto_start_permission/auto_start_permission_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.clashmiao.app/platform');

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => _mock(null));

  group('AutoStartPermissionService.status', () {
    final cases = {
      'unsupported': MiuiAutoStartStatus.unsupported,
      'allowed': MiuiAutoStartStatus.allowed,
      'denied': MiuiAutoStartStatus.denied,
      'unknown': MiuiAutoStartStatus.unknown,
    };
    for (final entry in cases.entries) {
      test('原生返回 ${entry.key} 解析为 ${entry.value}', () async {
        MethodCall? received;
        _mock((call) async {
          received = call;
          return entry.key;
        });

        final result = await AutoStartPermissionService().status();

        expect(result, entry.value);
        expect(received?.method, 'get_miui_autostart_status');
      });
    }

    test('不认识的字符串解析为 unknown', () async {
      _mock((call) async => 'banana');
      expect(
        await AutoStartPermissionService().status(),
        MiuiAutoStartStatus.unknown,
      );
    });

    test('平台异常解析为 unknown', () async {
      _mock((call) async {
        throw PlatformException(code: 'E_PLATFORM', message: 'boom');
      });
      expect(
        await AutoStartPermissionService().status(),
        MiuiAutoStartStatus.unknown,
      );
    });

    test('平台未实现（MissingPluginException）解析为 unsupported', () async {
      // 不设置任何 handler：模拟非 Android / 测试宿主上该 channel 完全没有实现。
      expect(
        await AutoStartPermissionService().status(),
        MiuiAutoStartStatus.unsupported,
      );
    });

    test('原生返回 null 按 unsupported（藏起入口，而不是编造状态）', () async {
      _mock((call) async => null);
      expect(
        await AutoStartPermissionService().status(),
        MiuiAutoStartStatus.unsupported,
      );
    });
  });

  group('AutoStartPermissionService.openSettings', () {
    test('调用正确方法名并透传 true', () async {
      MethodCall? received;
      _mock((call) async {
        received = call;
        return true;
      });

      expect(await AutoStartPermissionService().openSettings(), isTrue);
      expect(received?.method, 'open_miui_autostart_settings');
    });

    test('原生返回 false 时返回 false', () async {
      _mock((call) async => false);
      expect(await AutoStartPermissionService().openSettings(), isFalse);
    });

    test('平台异常返回 false', () async {
      _mock((call) async {
        throw PlatformException(code: 'E_PLATFORM', message: 'boom');
      });
      expect(await AutoStartPermissionService().openSettings(), isFalse);
    });

    test('平台未实现返回 false', () async {
      expect(await AutoStartPermissionService().openSettings(), isFalse);
    });
  });
}
