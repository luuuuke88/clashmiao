import 'dart:async';

import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 备份恢复进行中。为 true 期间订阅定时刷新暂停（由 `main.dart` 把它接给
/// `ProfileUpdateScheduler.isPaused`）。恢复结束、界面刷新完成后才回到 false。
final restoreInProgressProvider = StateProvider<bool>((ref) => false);

/// 恢复后需要额外失效的 provider。
///
/// 架构规则不允许 `features/config` 依赖其它 feature，而设置页开关、分应用代理、
/// 代理排序这几个 provider 属于别的 feature。所以由 app 层在启动时覆盖这个
/// provider 把它们补进来（见 `app/bootstrap/restore_wiring.dart`），本文件只
/// 失效 core / domain 里的那些。
final restoreExtraInvalidationsProvider = Provider<List<ProviderOrFamily>>(
  (ref) => const [],
);

/// 恢复成功（或回滚）之后，让界面与各 provider 立刻反映磁盘上的新状态。
///
/// 顺序（spec §10.4 ⑥）：先失效各偏好类 provider 与订阅相关 provider；主动读取
/// 并等待订阅列表、激活订阅就绪；最后才失效并重读网络设置——连接控制器监听
/// 网络设置变化，已连接时由它去抖后重连一次，此刻订阅与激活都已是最终状态，
/// 不会在中间态上重连。
class RestoreRefresher {
  RestoreRefresher({
    required this.container,
    List<ProviderOrFamily> extraInvalidations = const [],
    Future<void> Function(String profileId)? fetchProfile,
    String? Function()? activeProfileId,
    Future<void> Function()? reconnectIfConnected,
  }) : _extra = extraInvalidations,
       _fetchProfile = fetchProfile ?? _defaultFetch(container),
       _activeProfileId = activeProfileId ?? _defaultActiveId(container),
       _reconnectIfConnected =
           reconnectIfConnected ?? _defaultReconnect(container);

  final ProviderContainer container;
  final List<ProviderOrFamily> _extra;
  final Future<void> Function(String profileId) _fetchProfile;
  final String? Function() _activeProfileId;
  final Future<void> Function() _reconnectIfConnected;

  static Future<void> Function(String) _defaultFetch(
    ProviderContainer container,
  ) => (id) async {
    final repo = await container.read(profileRepositoryProvider.future);
    await repo.update(id);
  };

  static String? Function() _defaultActiveId(ProviderContainer container) =>
      () => container
          .read(profileRepositoryProvider)
          .valueOrNull
          ?.getActive()
          ?.id;

  /// 唯一接触连接控制器的地方：已连接则重连一次。连接控制器重写后（子项目 B）
  /// 在这里接新 API 即可。
  static Future<void> Function() _defaultReconnect(
    ProviderContainer container,
  ) => () async {
    final controller = container.read(connectionControllerProvider.notifier);
    if (controller.isStarted) await controller.reconnect();
  };

  /// 恢复整个流程：拿到恢复互斥 → 暂停定时刷新 → [BackupEngine.restoreHoldingLock]
  /// → 刷新界面 → 后台补拉缺配置的远程订阅。
  ///
  /// 已有恢复在进行时立刻抛 [RestoreFailureKind.busy]，且**不碰**暂停标志：
  /// 只有拿到互斥的那一次才有资格暂停、也只有它才会解除暂停。
  ///
  /// 失败（含回滚）也会刷新一次界面，确保 provider 缓存与磁盘状态一致，然后
  /// 把 [RestoreFailure] 原样抛出。返回的 [RestoreOutcome.backfill] 是后台补拉
  /// 的 Future（调用方可以不等；测试用它确定性地等到结束）。
  Future<RestoreOutcome> restore(BackupEngine engine, RestorePlan plan) {
    return engine.runExclusive(() async {
      final flag = container.read(restoreInProgressProvider.notifier);
      flag.state = true;
      try {
        final RestoreReport report;
        try {
          report = await engine.restoreHoldingLock(plan);
        } on RestoreFailure {
          await _refreshQuietly();
          rethrow;
        }
        await refresh();
        return RestoreOutcome(report, _startBackfill(plan.needsFetch));
      } finally {
        flag.state = false;
      }
    });
  }

  /// 启动时没完成的自动恢复的重试，走与导入同一套协调：拿到互斥 → 暂停定时刷新 →
  /// [BackupEngine.recoverHoldingLock] → **无论成败**都刷新界面（失败时回滚可能已经
  /// 写回了一部分偏好 / 订阅，缓存必须跟上磁盘）→ 最后才解除暂停。
  ///
  /// 已有恢复在进行时返回 [RecoveryOutcome.busy]，不碰暂停标志——哪怕那次恢复已经
  /// 清了标记、正在刷新界面（所以先拿互斥、再看线索）。拿到互斥后发现没有恢复线索
  /// 则返回 [RecoveryOutcome.none]：不暂停、不刷新。永不抛出。
  Future<RecoveryOutcome> recoverInterrupted(BackupEngine engine) async {
    try {
      return await engine.runExclusive(() async {
        if (!engine.hasRecoveryClue) return RecoveryOutcome.none;
        final flag = container.read(restoreInProgressProvider.notifier);
        flag.state = true;
        try {
          final outcome = await engine.recoverHoldingLock();
          if (outcome != RecoveryOutcome.none &&
              outcome != RecoveryOutcome.busy) {
            await _refreshQuietly();
          }
          return outcome;
        } finally {
          flag.state = false;
        }
      });
    } on RestoreFailure catch (e) {
      if (e.kind == RestoreFailureKind.busy) return RecoveryOutcome.busy;
      rethrow;
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      await refresh();
    } catch (e, st) {
      debugPrint('[restore] 刷新界面失败（忽略）: $e\n$st');
    }
  }

  /// 按顺序失效并等待关键 provider 就绪。
  Future<void> refresh() async {
    container.invalidate(themePreferencesProvider);
    container.invalidate(localePreferencesProvider);
    container.invalidate(proxyModeProvider);
    for (final target in _extra) {
      container.invalidate(target);
    }
    container.invalidate(profileListProvider);
    container.invalidate(activeProfileProvider);
    container.invalidate(offlineProxyGroupsProvider);
    container.invalidate(proxySelectionStoreProvider);
    container.invalidate(proxyDelayCacheProvider);

    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);

    // 网络设置最后：它的变化会触发（已连接时的）去抖重连。
    container.invalidate(networkSettingsProvider);
    container.read(networkSettingsProvider);
  }

  Future<void> _startBackfill(List<String> ids) {
    if (ids.isEmpty) return Future<void>.value();
    return backfill(ids);
  }

  /// 依次补拉 [ids]（备份里没带配置文件的远程订阅）。单条失败只记日志；补拉成功
  /// 且它是激活订阅、当前已连接时重连一次，让新配置生效。永不抛出。
  Future<void> backfill(List<String> ids) async {
    for (final id in ids) {
      try {
        await _fetchProfile(id);
        if (_activeProfileId() == id) await _reconnectIfConnected();
      } catch (e) {
        debugPrint('[restore] 补拉订阅失败 $id（可稍后手动刷新）: $e');
      }
    }
  }
}

/// [RestoreRefresher.restore] 的成功结果。
class RestoreOutcome {
  const RestoreOutcome(this.report, this.backfill);

  final RestoreReport report;

  /// 后台补拉远程订阅，完成（或全部失败）时结束，永不抛出。
  final Future<void> backfill;
}
