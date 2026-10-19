import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/application/profiles_update_scheduler.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/config/application/startup_restore_notice.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/gate_adapter.dart';
import '../../../support/restore_harness.dart';

Map<String, dynamic> _profile(String id) => {
  'id': id,
  'name': 'backup-$id',
  'url': 'https://example.com/$id',
  'lastUpdate': null,
  'updateInterval': 1,
  'subInfo': null,
  'customUserAgent': null,
  'rev': 1,
};

/// 启动重试的集成测试：**真实**引擎、真实 Store、真实调度器、真实 provider；
/// 唯一被替换的是「磁盘 / 平台」那一层（可注入写故障的偏好）与网络。
void main() {
  late RestoreHarness h;
  late ProviderContainer container;
  late GateAdapter gate;
  late ProfileUpdateScheduler scheduler;

  setUp(() async {
    h = await RestoreHarness.create(
      initialPrefs: {'theme_mode': 'dark', 'clashmiao_mixed_port': 2080},
    );
    await h.seed('a', active: true, config: sampleConfig('local-a'));
    await h.seed('b', config: sampleConfig('local-b'));

    // 一次恢复在写偏好的途中被杀：订阅已替换为 b、c，mixed_port 已经写成 3000，
    // theme_mode 还没写，标记与快照留在磁盘上。
    final killed = Completer<void>();
    final never = Completer<void>();
    var firstMarkerWrite = true;
    h.prefs.beforeWrite = (op, key) async {
      if (key == kRestoreMarkerKey && op == 'set' && firstMarkerWrite) {
        firstMarkerWrite = false;
        return;
      }
      if (op == 'set' && key == 'theme_mode') {
        if (!killed.isCompleted) killed.complete();
        await never.future;
      }
    };
    final raw = jsonEncode({
      'version': 2,
      'profiles': [_profile('b'), _profile('c')],
      'activeProfileId': 'c',
      'profileConfigs': {
        'b': sampleConfig('backup-b'),
        'c': sampleConfig('backup-c'),
      },
      'preferences': {'clashmiao_mixed_port': 3000, 'theme_mode': 'light'},
    });
    unawaited(
      h.engine
          .restore(h.engine.prepare(raw))
          .then<void>((_) {}, onError: (_) {}),
    );
    await killed.future;
    h.prefs.beforeWrite = null;

    // 「新进程」：全新的 Store 与引擎，只看磁盘与偏好。
    final restarted = h.restartedStore();
    final engine = BackupEngine(
      store: restarted,
      prefs: h.prefs,
      backupsDir: h.backupsDir,
      extraValidators: networkPrefValidators,
    );
    gate = GateAdapter();
    final repo = ProfileRepository(
      dio: Dio()..httpClientAdapter = gate,
      configDir: h.tmp,
      prefs: h.prefs,
      boxService: const StubBoxService(),
      store: restarted,
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => h.prefs),
        profileStoreProvider.overrideWith((ref) async => restarted),
        profileRepositoryProvider.overrideWith((ref) async => repo),
        backupEngineProvider.overrideWith((ref) async => engine),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    scheduler = ProfileUpdateScheduler(
      repositoryProvider: () =>
          container.read(profileRepositoryProvider.future),
      isPaused: () => container.read(restoreInProgressProvider),
    );
  });

  tearDown(() async {
    container.dispose();
    await h.dispose();
  });

  Future<RecoveryOutcome> retry() =>
      container.read(startupRestoreRetryProvider)();

  test('重试在互斥内：暂停调度器 → 恢复；失败也刷新 provider（反映已写入的部分状态）；成功后才放开暂停', () async {
    // 先让 provider 缓存被杀现场的状态。
    expect(container.read(networkSettingsProvider).mixedPort, 3000);
    expect(container.read(themePreferencesProvider), AppThemeMode.dark);
    expect(
      [for (final e in await container.read(profileListProvider.future)) e.id],
      ['b', 'c'],
    );

    // ── 第一次重试：恢复写回了 mixed_port=2080 之后，theme_mode 写失败 ──
    final duringFlag = <bool>[];
    final duringScheduler = <int>[];
    h.prefs.failWhen = (op, key) => op == 'set' && key == 'theme_mode';
    h.prefs.beforeWrite = (op, key) async {
      if (op == 'set' && key == 'clashmiao_mixed_port') {
        duringFlag.add(container.read(restoreInProgressProvider));
        // 真实调度器在恢复进行中被触发：必须让路，不发起任何网络请求。
        duringScheduler.add((await scheduler.checkAndRefreshDue()).length);
        duringScheduler.add(gate.requests.length);
      }
    };
    expect(await retry(), RecoveryOutcome.failed);

    expect(duringFlag, [true]);
    expect(duringScheduler, [0, 0]);
    expect(container.read(restoreInProgressProvider), isFalse);
    expect(
      h.real.containsKey(kRestoreMarkerKey),
      isTrue,
      reason: '失败：标记保留，可再重试',
    );
    // 失败也刷新了：缓存跟上磁盘上已写入的部分状态。
    expect(container.read(networkSettingsProvider).mixedPort, 2080);
    expect(
      [for (final e in container.read(profileListProvider).requireValue) e.id],
      ['a', 'b'],
      reason: '订阅部分已经回到恢复前',
    );
    expect(container.read(activeProfileProvider).requireValue!.id, 'a');

    // ── 第二次重试：问题消失，成功；并发的第三次被拒（busy）且不动暂停标志 ──
    h.prefs.failWhen = null;
    final concurrent = <RecoveryOutcome>[];
    final flagAfterConcurrent = <bool>[];
    h.prefs.beforeWrite = (op, key) async {
      if (op == 'set' && key == 'theme_mode') {
        concurrent.add(await retry());
        flagAfterConcurrent.add(container.read(restoreInProgressProvider));
      }
    };
    expect(await retry(), RecoveryOutcome.recovered);
    expect(concurrent, [RecoveryOutcome.busy]);
    expect(flagAfterConcurrent, [true], reason: '被拒的重试不能提前解除暂停');

    expect(container.read(restoreInProgressProvider), isFalse);
    expect(h.real.containsKey(kRestoreMarkerKey), isFalse);
    expect(container.read(themePreferencesProvider), AppThemeMode.dark);
    expect(container.read(networkSettingsProvider).mixedPort, 2080);

    // 暂停最后才放开：现在调度器恢复工作（订阅到期，真的发起了请求）。
    h.prefs.beforeWrite = null;
    await scheduler.checkAndRefreshDue();
    expect(gate.requests, isNotEmpty);
  });

  test('没有待处理的恢复（none）：不暂停、不刷新、不改任何东西', () async {
    h.prefs.failWhen = null;
    expect(await retry(), RecoveryOutcome.recovered);
    final flags = <bool>[];
    h.prefs.beforeWrite = (op, key) async =>
        flags.add(container.read(restoreInProgressProvider));
    expect(await retry(), RecoveryOutcome.none);
    expect(flags, isEmpty);
    expect(container.read(restoreInProgressProvider), isFalse);
  });
}
