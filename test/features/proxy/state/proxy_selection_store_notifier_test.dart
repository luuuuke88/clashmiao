import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/proxy/state/proxy_selection_store_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProxySelectionStoreNotifier 按订阅分区持久化手选节点', () {
    test('切换到另一个订阅后，读到的是新订阅自己的选择，不是旧订阅的', () async {
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

      await containerA
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'JP-Reality-Stable');

      expect(containerA.read(proxySelectionStoreProvider), {
        'proxy': 'JP-Reality-Stable',
      });

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
        containerB.read(proxySelectionStoreProvider),
        isEmpty,
        reason: '订阅 B 从未选过节点，不应该看到订阅 A 的手选结果——两者按 profileId 分区持久化',
      );
    });

    test('同一订阅内，即使换了新的 Container 实例，选择仍然能正确读回', () async {
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
      await container1
          .read(proxySelectionStoreProvider.notifier)
          .persist('proxy', 'US-node');

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
        container2.read(proxySelectionStoreProvider),
        {'proxy': 'US-node'},
        reason: '同一 profileId 的手选结果应该能持久化并被下一次读取到',
      );
    });

    test('对同一个 group 重新选择会覆盖旧值，而不是两个都保留', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith(
            (_) => Future.value(_profile('profile-x')),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
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
  });
}

ProfileEntity _profile(String id) => ProfileEntity(
  id: id,
  name: id,
  url: 'https://example.com/$id',
  active: true,
);
