import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/profile_store_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxyDelayCacheNotifier 按订阅分区，不跨订阅泄漏延迟缓存', () {
    test('切换到另一个订阅后，读到的是新订阅自己的缓存，不是旧订阅的', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await seededProfileStore(prefs, [
        _profile('profile-a'),
        _profile('profile-b'),
        _profile('profile-same'),
        _profile('profile-x'),
      ]);

      final containerA = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-a')),
          ),
        ],
      );
      addTearDown(containerA.dispose);
      await containerA.read(sharedPreferencesProvider.future);
      await containerA.read(profileStoreProvider.future);
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
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-b')),
          ),
        ],
      );
      addTearDown(containerB.dispose);
      await containerB.read(sharedPreferencesProvider.future);
      await containerB.read(profileStoreProvider.future);
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
      final store = await seededProfileStore(prefs, [
        _profile('profile-a'),
        _profile('profile-b'),
        _profile('profile-same'),
        _profile('profile-x'),
      ]);

      final container1 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-same')),
          ),
        ],
      );
      addTearDown(container1.dispose);
      await container1.read(sharedPreferencesProvider.future);
      await container1.read(profileStoreProvider.future);
      await container1.read(activeProfileProvider.future);
      container1.read(proxyDelayCacheProvider.notifier).persistFromGroups([
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'US',
          items: [OutboundProxy(tag: 'US', type: 'vmess', delay: 88)],
        ),
      ]);
      // 写入经 ProfileStore 的锁排队落盘；等它排空，下一个 container 才读得到。
      await store.commit<void>((_) => const Plan<void>.unchanged());

      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-same')),
          ),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(sharedPreferencesProvider.future);
      await container2.read(profileStoreProvider.future);
      await container2.read(activeProfileProvider.future);

      expect(
        container2.read(proxyDelayCacheProvider),
        {'US': 88},
        reason: '同一 profileId 的缓存应该能持久化并被下一次读取到',
      );
    });

    test('订阅被删除或换代后，旧 notifier 的延迟缓存写入被丢弃', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await seededProfileStore(prefs, [
        _profile('profile-a', inc: 'g1'),
      ]);
      const groups = [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'US',
          items: [OutboundProxy(tag: 'US', type: 'vmess', delay: 88)],
        ),
      ];
      ProxyDelayCacheNotifier notifierFor(String inc) =>
          ProxyDelayCacheNotifier(
            prefs: prefs,
            store: store,
            profileId: 'profile-a',
            profileInc: inc,
          );

      // 换代：旧一代写不进去。
      final oldGen = notifierFor('g1');
      await store.commit<void>(
        (view) =>
            Plan<void>(profiles: [view.profiles.single.copyWith(inc: 'g2')]),
      );
      oldGen.persistFromGroups(groups);
      await store.commit<void>((_) => const Plan<void>.unchanged());
      expect(prefs.getString('proxy_delays_profile-a'), isNull);

      // 新一代可以写。
      notifierFor('g2').persistFromGroups(groups);
      await store.commit<void>((_) => const Plan<void>.unchanged());
      expect(prefs.getString('proxy_delays_profile-a'), '{"US":88}');

      // 删除：附属键被清掉，之后任何一代的写入都不会把它写回来。
      await store.commit<void>(
        (_) => const Plan<void>(profiles: [], removedProfileIds: ['profile-a']),
      );
      expect(prefs.getString('proxy_delays_profile-a'), isNull);
      notifierFor('g2').persistFromGroups(groups);
      await store.commit<void>((_) => const Plan<void>.unchanged());
      expect(prefs.getString('proxy_delays_profile-a'), isNull);
    });
  });
}

ProfileEntity _profile(String id, {String inc = ''}) => ProfileEntity(
  id: id,
  name: id,
  url: 'https://example.com/$id',
  active: true,
  inc: inc,
);
