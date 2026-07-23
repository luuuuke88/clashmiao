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

    test(
      'previousAccountId / previousAccessToken 省略时用空字符串占位（native 端 as String 强转不接受 null）',
      () async {
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
      },
    );

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

  group('事件流多订阅者共享同一条平台订阅（真机 bug 回归）', () {
    // 真机实测发现的 bug：watchAlerts() 每次调用都重新
    // receiveBroadcastStream()，产生一个全新的平台订阅。EventChannel 同一
    // 时刻只服务一个活跃的 listen——第二个订阅者出现时，第一个的事件流被
    // 顶掉，静默收不到任何事件。实际后果：ConnectionController 和
    // boxAlertsProvider（ShellPage 弹窗用）都订阅 alerts，其中一个永远
    // 收不到 fatal alert → 阻断式弹窗在真机上不弹（widget 测试因为
    // override 了 provider 而测不出来）。
    //
    // 契约：同一个 service 实例上多次调用 watchAlerts()/watchStats()/
    // watchGroups()/watchNetworkChanged() 必须返回同一条共享流（broadcast，
    // 多 listener 各自都能收到事件），而不是每次新建平台订阅。
    test('watchAlerts 两个订阅者都能收到同一条 alert 事件', () async {
      final service = PlatformBoxService();
      final received1 = <String>[];
      final received2 = <String>[];

      // 捕获平台侧的 event sink，等两个订阅者都挂上之后再发事件——
      // broadcast 流不回放历史事件，onListen 里立刻发的话第二个订阅者
      // 天然收不到，测不出想测的"共享订阅"问题。
      MockStreamHandlerEventSink? sink;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            const EventChannel(
              'com.clashmiao.app/service.alerts',
              JSONMethodCodec(),
            ),
            MockStreamHandler.inline(
              onListen: (arguments, events) {
                sink = events;
              },
            ),
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              const EventChannel(
                'com.clashmiao.app/service.alerts',
                JSONMethodCodec(),
              ),
              null,
            );
      });

      // 模拟真机里的两个独立订阅者（ConnectionController + boxAlertsProvider）。
      final sub1 = service.watchAlerts().listen(
        (a) => received1.add(a.type.name),
      );
      final sub2 = service.watchAlerts().listen(
        (a) => received2.add(a.type.name),
      );
      addTearDown(sub1.cancel);
      addTearDown(sub2.cancel);
      // EventChannel 的 listen 是经由 binary messenger 的异步握手，单个
      // microtask 可能不够，轮询等待 onListen 真正送达 mock handler。
      for (var i = 0; i < 40 && sink == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      sink!.success(<String, String?>{
        'alert': 'StartService',
        'message': 'boom',
      });
      await Future<void>.delayed(Duration.zero);

      expect(received1, ['startService'], reason: '第一个订阅者不能因为第二个订阅者的出现而被顶掉');
      expect(received2, ['startService'], reason: '第二个订阅者也要能收到事件');
    });

    test(
      'watchAlerts/watchStats/watchGroups/watchNetworkChanged 重复调用返回同一条流',
      () {
        final service = PlatformBoxService();
        expect(
          identical(service.watchAlerts(), service.watchAlerts()),
          isTrue,
          reason: '每次调用新建 receiveBroadcastStream 会让先订阅者被平台顶掉',
        );
        expect(identical(service.watchStats(), service.watchStats()), isTrue);
        expect(identical(service.watchGroups(), service.watchGroups()), isTrue);
        expect(
          identical(
            service.watchNetworkChanged(),
            service.watchNetworkChanged(),
          ),
          isTrue,
        );
      },
    );
  });
}
