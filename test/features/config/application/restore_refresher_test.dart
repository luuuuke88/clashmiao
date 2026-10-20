import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/settings/application/setting_toggles.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/restore_harness.dart';

Map<String, dynamic> _profile(String id, {String? url}) => {
  'id': id,
  'name': 'backup-$id',
  'url': url ?? 'https://example.com/$id',
  'lastUpdate': null,
  'updateInterval': 1,
  'subInfo': null,
  'customUserAgent': null,
  'rev': 1,
};

String _backup({
  List<String> withConfig = const ['b', 'c'],
  List<String> withoutConfig = const [],
  Map<String, Object> prefs = const {},
  String active = 'c',
}) => jsonEncode({
  'version': 2,
  'schema': 1,
  'createdAt': 1,
  'profiles': [
    for (final id in [...withConfig, ...withoutConfig]) _profile(id),
  ],
  'activeProfileId': active,
  'profileConfigs': {for (final id in withConfig) id: sampleConfig(id)},
  'preferences': prefs,
});

const _toggleSpec = (key: 'clashmiao_auto_ip_check', defaultValue: true);

void main() {
  late RestoreHarness h;
  late ProviderContainer container;
  late List<String> fetched;
  late List<String> reconnects;
  String? activeForBackfill;
  Map<String, Object> fetchError = {};

  setUp(() async {
    h = await RestoreHarness.create(
      initialPrefs: {
        'theme_mode': 'dark',
        'clashmiao_proxy_mode': 1,
        'clashmiao_mixed_port': 2080,
        'clashmiao_auto_ip_check': true,
      },
    );
    await h.seed('a', active: true);
    await h.seed('b');
    final repo = ProfileRepository(
      dio: Dio(),
      configDir: h.tmp,
      prefs: h.prefs,
      boxService: const StubBoxService(),
      store: h.store,
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => h.prefs),
        profileStoreProvider.overrideWith((ref) async => h.store),
        profileRepositoryProvider.overrideWith((ref) async => repo),
        restoreExtraInvalidationsProvider.overrideWithValue([
          boolPreferenceProvider,
        ]),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    fetched = [];
    reconnects = [];
    activeForBackfill = null;
    fetchError = {};
  });

  tearDown(() async {
    container.dispose();
    await h.dispose();
  });

  RestoreRefresher refresher() => RestoreRefresher(
    container: container,
    extraInvalidations: container.read(restoreExtraInvalidationsProvider),
    fetchProfile: (id) async {
      fetched.add(id);
      final err = fetchError[id];
      if (err != null) throw err;
    },
    activeProfileId: () => activeForBackfill,
    reconnectIfConnected: () async => reconnects.add('reconnect'),
  );

  test('恢复后各 provider 立刻反映新状态（偏好类、订阅列表、激活、网络设置、设置页开关）', () async {
    // 先让各 provider 缓存旧值。
    expect(container.read(themePreferencesProvider), AppThemeMode.dark);
    expect(container.read(proxyModeProvider), 1);
    expect(container.read(networkSettingsProvider).mixedPort, 2080);
    final toggleSub = container.listen(
      boolPreferenceProvider(_toggleSpec),
      (_, _) {},
    );
    expect(toggleSub.read(), isTrue);
    expect(
      [for (final e in await container.read(profileListProvider.future)) e.id],
      ['a', 'b'],
    );
    expect((await container.read(activeProfileProvider.future))!.id, 'a');

    final plan = h.engine.prepare(
      _backup(
        prefs: {
          'theme_mode': 'light',
          'clashmiao_proxy_mode': 0,
          'clashmiao_mixed_port': 3000,
          'clashmiao_auto_ip_check': false,
        },
      ),
    );
    final outcome = await refresher().restore(h.engine, plan);
    await outcome.backfill;

    expect(container.read(themePreferencesProvider), AppThemeMode.light);
    expect(container.read(proxyModeProvider), 0);
    expect(container.read(networkSettingsProvider).mixedPort, 3000);
    expect(toggleSub.read(), isFalse);
    expect(
      [for (final e in container.read(profileListProvider).requireValue) e.id],
      ['b', 'c'],
    );
    expect(container.read(activeProfileProvider).requireValue!.id, 'c');
    expect(outcome.report.profilesImported, 2);
  });

  test('网络设置最后才变：它变化（已连接时会触发去抖重连）的时刻，订阅列表与激活已是最终状态', () async {
    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);
    container.read(networkSettingsProvider);

    final seenAtNetworkChange = <String>[];
    container.listen(networkSettingsProvider, (prev, next) {
      seenAtNetworkChange.add(
        [
          for (final e
              in container.read(profileListProvider).valueOrNull ??
                  const <ProfileEntity>[])
            e.id,
        ].join(','),
      );
      seenAtNetworkChange.add(
        container.read(activeProfileProvider).valueOrNull?.id ?? '-',
      );
    });

    final plan = h.engine.prepare(_backup());
    await (await refresher().restore(h.engine, plan)).backfill;

    expect(seenAtNetworkChange, ['b,c', 'c'], reason: '只变化一次，且此时订阅状态已就绪');
  });

  test('恢复期间 restoreInProgress 为 true（定时刷新据此暂停），结束后为 false', () async {
    final seen = <bool>[];
    h.prefs.beforeWrite = (op, key) async {
      if (key == 'clashmiao_mixed_port') {
        seen.add(container.read(restoreInProgressProvider));
      }
    };
    expect(container.read(restoreInProgressProvider), isFalse);
    final plan = h.engine.prepare(
      _backup(prefs: {'clashmiao_mixed_port': 3000}),
    );
    await refresher().restore(h.engine, plan);
    expect(seen, [true]);
    expect(container.read(restoreInProgressProvider), isFalse);
  });

  test('恢复失败（已回滚）：界面仍然刷新到磁盘上的状态，标志复位，错误原样抛出', () async {
    final before = await h.state();
    // 提前缓存旧列表；失败的恢复中间提交过，列表 provider 随 changes 失效，
    // 这里要确认最终读到的是回滚后的状态。
    expect((await container.read(profileListProvider.future)).length, 2);
    var armed = true;
    h.prefs.failWhen = (op, key) {
      if (armed && key == 'clashmiao_mixed_port') {
        armed = false;
        return true;
      }
      return false;
    };
    final plan = h.engine.prepare(
      _backup(prefs: {'clashmiao_mixed_port': 3000}),
    );
    await expectLater(
      refresher().restore(h.engine, plan),
      throwsA(
        isA<RestoreFailure>().having(
          (e) => e.kind,
          'kind',
          RestoreFailureKind.rolledBack,
        ),
      ),
    );
    expect(container.read(restoreInProgressProvider), isFalse);
    expect(
      [for (final e in await container.read(profileListProvider.future)) e.id],
      ['a', 'b'],
    );
    expect((await container.read(activeProfileProvider.future))!.id, 'a');
    expect(container.read(networkSettingsProvider).mixedPort, 2080);
    expect(await h.state(), before);
    expect(fetched, isEmpty);
  });

  test('两次恢复交错：第二次被拒绝，暂停标志只由拿到互斥的第一次释放', () async {
    final reached = Completer<void>();
    final release = Completer<void>();
    h.prefs.beforeWrite = (op, key) async {
      if (op == 'set' && key == 'clashmiao_mixed_port') {
        if (!reached.isCompleted) reached.complete();
        await release.future;
      }
    };
    final plan = h.engine.prepare(
      _backup(prefs: {'clashmiao_mixed_port': 3000}),
    );
    final first = refresher().restore(h.engine, plan);
    await reached.future;
    expect(container.read(restoreInProgressProvider), isTrue);

    // 第二次导入（新建的引擎实例）：被拒绝，而且不能动暂停标志。
    final other = BackupEngine(
      store: h.store,
      prefs: h.prefs,
      backupsDir: h.backupsDir,
      extraValidators: networkPrefValidators,
    );
    await expectLater(
      refresher().restore(other, other.prepare(_backup())),
      throwsA(
        isA<RestoreFailure>().having(
          (e) => e.kind,
          'kind',
          RestoreFailureKind.busy,
        ),
      ),
    );
    expect(
      container.read(restoreInProgressProvider),
      isTrue,
      reason: '被拒绝的那次不能提前解除第一次的暂停',
    );

    h.prefs.beforeWrite = null;
    release.complete();
    final outcome = await first;
    await outcome.backfill;
    expect(container.read(restoreInProgressProvider), isFalse);
    expect(container.read(networkSettingsProvider).mixedPort, 3000);
    expect(h.snapshots(), hasLength(1), reason: '被拒绝的那次没有写快照');
  });

  group('后台补拉缺配置的远程订阅', () {
    test('只补拉备份里缺配置的订阅；激活订阅补拉成功且已连接时重连一次', () async {
      activeForBackfill = 'c';
      final plan = h.engine.prepare(
        _backup(withConfig: ['b'], withoutConfig: ['c', 'd']),
      );
      final outcome = await refresher().restore(h.engine, plan);
      expect(outcome.report.refreshQueued, 2);
      await outcome.backfill;
      expect(fetched, ['c', 'd']);
      expect(reconnects, hasLength(1), reason: '只有激活订阅（c）补拉成功才重连');
    });

    test('补拉的不是激活订阅：不重连', () async {
      activeForBackfill = 'b';
      final plan = h.engine.prepare(
        _backup(withConfig: ['b'], withoutConfig: ['c'], active: 'b'),
      );
      await (await refresher().restore(h.engine, plan)).backfill;
      expect(fetched, ['c']);
      expect(reconnects, isEmpty);
    });

    test('一条补拉失败不影响后面的；失败的激活订阅不触发重连', () async {
      activeForBackfill = 'c';
      fetchError = {'c': StateError('network down')};
      final plan = h.engine.prepare(
        _backup(withConfig: ['b'], withoutConfig: ['c', 'd']),
      );
      final outcome = await refresher().restore(h.engine, plan);
      await outcome.backfill; // 永不抛出
      expect(fetched, ['c', 'd']);
      expect(reconnects, isEmpty);
    });

    test('备份里每条订阅都带了配置：不补拉', () async {
      final plan = h.engine.prepare(_backup());
      final outcome = await refresher().restore(h.engine, plan);
      await outcome.backfill;
      expect(outcome.report.refreshQueued, 0);
      expect(fetched, isEmpty);
    });

    test('补拉发生在界面刷新之后（不阻塞恢复本身）', () async {
      final gate = Completer<void>();
      final r = RestoreRefresher(
        container: container,
        fetchProfile: (id) async {
          fetched.add(id);
          await gate.future;
        },
        activeProfileId: () => null,
        reconnectIfConnected: () async {},
      );
      final plan = h.engine.prepare(
        _backup(withConfig: ['b'], withoutConfig: ['c']),
      );
      final outcome = await r.restore(h.engine, plan);
      expect(container.read(restoreInProgressProvider), isFalse);
      expect(
        [
          for (final e in container.read(profileListProvider).requireValue)
            e.id,
        ],
        ['b', 'c'],
        reason: '恢复已返回、界面已是新状态，而补拉还卡在网络上',
      );
      var done = false;
      unawaited(outcome.backfill.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);
      gate.complete();
      await outcome.backfill;
      expect(fetched, ['c']);
    });
  });
}
