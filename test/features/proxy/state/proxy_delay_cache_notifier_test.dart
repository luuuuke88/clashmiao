import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:clashmiao/features/proxy/state/proxy_delay_cache_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxyDelayCacheNotifier 按订阅分区，不跨订阅泄漏延迟缓存', () {
    test('切换到另一个订阅后，读到的是新订阅自己的缓存，不是旧订阅的', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final containerA = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-a')),
          ),
        ],
      );
      addTearDown(containerA.dispose);
      await containerA.read(sharedPreferencesProvider.future);
      await containerA.read(activeProfileProvider.future);

      containerA.read(proxyDelayCacheProvider.notifier).persistFromGroups([
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: '香港01',
          items: [OutboundProxy(tag: '香港01', type: 'ss', delay: 111)],
        ),
      ]);

      expect(containerA.read(proxyDelayCacheProvider), {'香港01': 111});

      // 切换到另一个订阅：全新 container 模拟 activeProfileProvider 变化后
      // provider 重建（Riverpod 里 watch 到的依赖变化会重建 provider state，
      // 这里用独立 container 直接验证"新订阅初始读到的缓存"这个结果状态，
      // 不依赖具体的 rebuild 时序细节）。
      final containerB = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-b')),
          ),
        ],
      );
      addTearDown(containerB.dispose);
      await containerB.read(sharedPreferencesProvider.future);
      await containerB.read(activeProfileProvider.future);

      expect(
        containerB.read(proxyDelayCacheProvider),
        isEmpty,
        reason:
            '订阅 B 从未测过速，即便订阅 A 有节点恰好同名"香港01"且测过延迟，'
            'B 也不应该显示 A 的延迟缓存——两者的持久化 key 按 profileId 分区，'
            '互不可见',
      );
    });

    test('同一订阅内，即使换了新的 Container 实例，缓存仍然能正确读回', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container1 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-same')),
          ),
        ],
      );
      addTearDown(container1.dispose);
      await container1.read(sharedPreferencesProvider.future);
      await container1.read(activeProfileProvider.future);
      container1.read(proxyDelayCacheProvider.notifier).persistFromGroups([
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'US',
          items: [OutboundProxy(tag: 'US', type: 'vmess', delay: 88)],
        ),
      ]);

      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-same')),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(sharedPreferencesProvider.future);
      await container2.read(activeProfileProvider.future);

      expect(
        container2.read(proxyDelayCacheProvider),
        {'US': 88},
        reason: '同一 profileId 的缓存应该能持久化并被下一次读取到',
      );
    });
  });
}

ProfileEntity _profile(String id) => ProfileEntity(
  id: id,
  name: id,
  url: 'https://example.com/$id',
  active: true,
);
