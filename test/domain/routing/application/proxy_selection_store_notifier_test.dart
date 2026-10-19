import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/profile_store_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxySelectionStoreNotifier 按订阅分区持久化手选节点', () {
    test('切换到另一个订阅后，读到的是新订阅自己的选择，不是旧订阅的', () async {
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

      await containerA
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'JP-Reality-Stable');

      expect(containerA.read(proxySelectionStoreProvider), {
        'proxy': 'JP-Reality-Stable',
      });

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
        containerB.read(proxySelectionStoreProvider),
        isEmpty,
        reason: '订阅 B 从未选过节点，不应该看到订阅 A 的手选结果——两者按 profileId 分区持久化',
      );
    });

    test('同一订阅内，即使换了新的 Container 实例，选择仍然能正确读回', () async {
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
      await container1
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'US-node');

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
        container2.read(proxySelectionStoreProvider),
        {'proxy': 'US-node'},
        reason: '同一 profileId 的手选结果应该能持久化并被下一次读取到',
      );
    });

    test('对同一个 group 重新选择会覆盖旧值，而不是两个都保留', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await seededProfileStore(prefs, [
        _profile('profile-a'),
        _profile('profile-b'),
        _profile('profile-same'),
        _profile('profile-x'),
      ]);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-x')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileStoreProvider.future);
      await container.read(activeProfileProvider.future);

      final notifier = container.read(proxySelectionStoreProvider.notifier);
      await notifier.persist('proxy', 'JP-node');
      await notifier.persist('proxy', 'US-node');

      expect(
        container.read(proxySelectionStoreProvider),
        {'proxy': 'US-node'},
        reason: '用户后选的节点应该覆盖同一 group 之前的选择',
      );
    });

    group('写入经 ProfileStore.writeAux 校验：删除或换代后旧 notifier 的写入被丢弃', () {
      test('订阅被删除后，旧 notifier 的 persist 不会复活孤儿键', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = await seededProfileStore(prefs, [
          _profile('profile-a', inc: 'g1'),
        ]);
        final notifier = ProxySelectionStoreNotifier(
          prefs: prefs,
          store: store,
          profileId: 'profile-a',
          profileInc: 'g1',
        );

        await notifier.persist('proxy', 'before-delete');
        expect(prefs.getString('proxy_selection_profile-a'), isNotNull);

        await store.commit<void>(
          (_) =>
              const Plan<void>(profiles: [], removedProfileIds: ['profile-a']),
        );
        expect(
          prefs.getString('proxy_selection_profile-a'),
          isNull,
          reason: '删除订阅时附属键被一并清理',
        );

        await notifier.persist('proxy', 'after-delete');
        expect(
          prefs.getString('proxy_selection_profile-a'),
          isNull,
          reason: '订阅已经不存在，旧 notifier 的写入必须被丢弃',
        );
      });

      test('同 id 换代（删除后恢复）后，旧一代 notifier 的写入被丢弃，新一代照常写', () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = await seededProfileStore(prefs, [
          _profile('profile-a', inc: 'g1'),
        ]);
        final oldNotifier = ProxySelectionStoreNotifier(
          prefs: prefs,
          store: store,
          profileId: 'profile-a',
          profileInc: 'g1',
        );
        await store.commit<void>(
          (view) =>
              Plan<void>(profiles: [view.profiles.single.copyWith(inc: 'g2')]),
        );

        await oldNotifier.persist('proxy', 'stale-write');
        expect(prefs.getString('proxy_selection_profile-a'), isNull);

        final newNotifier = ProxySelectionStoreNotifier(
          prefs: prefs,
          store: store,
          profileId: 'profile-a',
          profileInc: 'g2',
        );
        await newNotifier.persist('proxy', 'fresh-write');
        expect(
          prefs.getString('proxy_selection_profile-a'),
          '{"proxy":"fresh-write"}',
        );
      });
    });

    test('restore：恢复到旧值或删除记录，并经 writeAux 写回磁盘', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await seededProfileStore(prefs, [_profile('profile-r')]);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          profileStoreProvider.overrideWith((_) => Future.value(store)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-r')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileStoreProvider.future);
      await container.read(activeProfileProvider.future);
      final notifier = container.read(proxySelectionStoreProvider.notifier);

      await notifier.persist('proxy', 'A');
      await notifier.persist('proxy', 'B');
      await notifier.restore('proxy', 'A');
      expect(container.read(proxySelectionStoreProvider), {'proxy': 'A'});
      expect(prefs.getString('proxy_selection_profile-r'), '{"proxy":"A"}');

      await notifier.restore('proxy', null);
      expect(container.read(proxySelectionStoreProvider), isEmpty);
      expect(prefs.getString('proxy_selection_profile-r'), '{}');
    });

    test('restore：订阅已删除后旧 notifier 的回滚同样被丢弃，不复活孤儿键', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = await seededProfileStore(prefs, [
        _profile('profile-a', inc: 'g1'),
      ]);
      final notifier = ProxySelectionStoreNotifier(
        prefs: prefs,
        store: store,
        profileId: 'profile-a',
        profileInc: 'g1',
      );
      await notifier.persist('proxy', 'A');
      await notifier.persist('proxy', 'B');

      await store.commit<void>(
        (_) => const Plan<void>(profiles: [], removedProfileIds: ['profile-a']),
      );
      expect(prefs.getString('proxy_selection_profile-a'), isNull);

      await notifier.restore('proxy', 'A');
      expect(
        prefs.getString('proxy_selection_profile-a'),
        isNull,
        reason: '回滚与 persist 走同一条 writeAux 校验',
      );
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
