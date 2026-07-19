import 'package:clashmiao/core/box_service/platform_box_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 裸 MethodChannel —— 跟 native 侧 MethodBridge.kt 的 CHANNEL_KERNEL /
// ChannelMethodHandler.swift 的 channelName 完全一致（`$_channelPrefix/method`）。
const _channel = MethodChannel('com.clashmiao.app/method');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('PlatformBoxService.generateWarpConfig', () {
    test('调用方法名 generate_warp_config，参数键跟 native 契约逐字一致', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            received = call;
            return '{"account-id":"a","access-token":"b","config":{}}';
          });

      await PlatformBoxService().generateWarpConfig(
        licenseKey: 'license-1',
        previousAccountId: 'acc-1',
        previousAccessToken: 'token-1',
      );

      expect(received?.method, 'generate_warp_config');
      final args = received?.arguments as Map;
      expect(args['license-key'], 'license-1');
      expect(args['previous-account-id'], 'acc-1');
      expect(args['previous-access-token'], 'token-1');
    });

    test('previousAccountId / previousAccessToken 省略时用空字符串占位（native 端 as String 强转不接受 null）', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            received = call;
            return '{"account-id":"a","access-token":"b","config":{}}';
          });

      await PlatformBoxService().generateWarpConfig(licenseKey: '');

      final args = received?.arguments as Map;
      expect(args['previous-account-id'], '');
      expect(args['previous-access-token'], '');
    });

    test('透传 native 返回的原始 JSON 字符串', () async {
      const rawResponse =
          '{"account-id":"acc-x","access-token":"tok-x","config":{"k":1}}';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => rawResponse);

      final result = await PlatformBoxService().generateWarpConfig(
        licenseKey: '',
      );

      expect(result, rawResponse);
    });

    test('native 抛异常（Android E_KERNEL）时透传 PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            throw PlatformException(
              code: 'E_KERNEL',
              message: 'warp registration failed: rate limited',
            );
          });

      expect(
        () => PlatformBoxService().generateWarpConfig(licenseKey: ''),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'E_KERNEL'),
        ),
      );
    });

    test('未注册 mock handler 时抛 MissingPluginException（未接线的极端情况）', () async {
      expect(
        () => PlatformBoxService().generateWarpConfig(licenseKey: ''),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
