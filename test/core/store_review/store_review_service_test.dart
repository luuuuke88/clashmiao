import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `in_app_review` 包底层用的 MethodChannel，方法名/通道名取自
/// `in_app_review_platform_interface` 的 `MethodChannelInAppReview`
/// （channel: `dev.britannio.in_app_review`，`isAvailable` 返回 bool，
/// `requestReview` 返回 void）。跟仓库里其它 native 插件测试
/// （test/core/haptic/haptic_service_test.dart）同一个思路：在 binary
/// messenger 层面直接 mock，而不是引入额外的 mock 框架。
const _channel = MethodChannel('dev.britannio.in_app_review');

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
  var isAvailableResponse = true;

  setUp(() {
    calls.clear();
    isAvailableResponse = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isAvailable':
              return isAvailableResponse;
            case 'requestReview':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('StoreReviewService', () {
    test('可用且从未请求过时 → 调用 requestReview 一次，并持久化"已请求过"', () async {
      final container = await _container({});

      await container.read(storeReviewServiceProvider).maybeRequestReview();

      expect(
        calls.map((c) => c.method),
        ['isAvailable', 'requestReview'],
        reason: '先确认设备可用，再真正弹出评分请求',
      );

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(
        prefs.getBool('clashmiao_store_review_requested'),
        isTrue,
        reason: '必须持久化"已经请求过"，否则下次连接会重复弹扰用户',
      );
    });

    test('已经持久化"请求过"时 → 不再调用 isAvailable/requestReview', () async {
      final container = await _container({
        'clashmiao_store_review_requested': true,
      });

      await container.read(storeReviewServiceProvider).maybeRequestReview();

      expect(
        calls,
        isEmpty,
        reason: '这辈子只弹一次：已经标记过就不该再触碰原生评分 API',
      );
    });

    test('isAvailable 返回 false 时 → 不调用 requestReview，也不持久化标记', () async {
      isAvailableResponse = false;
      final container = await _container({});

      await container.read(storeReviewServiceProvider).maybeRequestReview();

      expect(
        calls.map((c) => c.method),
        ['isAvailable'],
        reason: '设备当前不可用时不应该尝试弹窗',
      );

      final prefs = await container.read(sharedPreferencesProvider.future);
      expect(
        prefs.getBool('clashmiao_store_review_requested'),
        isNot(isTrue),
        reason: '这次没有真正弹出过评分请求，不应该被当成"已经弹过"，'
            '否则以后设备变得可用了也再也没有机会弹',
      );
    });

    test('连续调用两次（模拟两次连接）→ 只有第一次真正触达原生 API', () async {
      final container = await _container({});

      await container.read(storeReviewServiceProvider).maybeRequestReview();
      expect(calls, hasLength(2)); // isAvailable + requestReview

      await container.read(storeReviewServiceProvider).maybeRequestReview();
      expect(
        calls,
        hasLength(2),
        reason: '第二次调用应该被持久化标记挡住，调用次数不应该增加',
      );
    });
  });
}
