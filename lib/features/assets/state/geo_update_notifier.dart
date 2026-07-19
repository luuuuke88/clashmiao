import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/features/assets/logic/geo_update_service.dart';
import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class GeoUpdateState {
  const GeoUpdateState({
    this.isUpdating = false,
    this.progress = 0.0,
    this.error,
    this.lastUpdated,
  });
  final bool isUpdating;
  final double progress;
  final String? error;
  final DateTime? lastUpdated;

  GeoUpdateState copyWith({
    bool? isUpdating,
    double? progress,
    String? error,
    DateTime? lastUpdated,
  }) => GeoUpdateState(
    isUpdating: isUpdating ?? this.isUpdating,
    progress: progress ?? this.progress,
    error: error,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

class GeoUpdateNotifier
    extends StateNotifier<Map<GeoAssetType, GeoUpdateState>> {
  GeoUpdateNotifier(this._ref)
    : super({
        GeoAssetType.geoip: const GeoUpdateState(),
        GeoAssetType.geosite: const GeoUpdateState(),
      }) {
    unawaited(_loadExistingFiles());
  }

  final Ref _ref;

  Future<void> _loadExistingFiles() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final next = Map<GeoAssetType, GeoUpdateState>.from(state);
      for (final asset in [GeoAsset.geoip, GeoAsset.geosite]) {
        final file = File('${dir.path}/${asset.filename}');
        if (!await file.exists()) continue;
        final stat = await file.stat();
        next[asset.type] = GeoUpdateState(lastUpdated: stat.modified);
      }
      if (!mounted) return;
      state = next;
    } catch (_) {
      // path_provider is unavailable in some widget tests; keep the empty state.
    }
  }

  void addRecommended() {
    // 并发触发两个资源各自的 update()，互不等待——update() 内部按 asset.type
    // 分别维护 state key，两次调用天然不会互相干扰。这里用 unawaited（跟构造
    // 函数里 `unawaited(_loadExistingFiles())` 同款写法）而不是顺序 await，
    // 否则 geosite 要等 geoip 整个下载/校验流程（含真实网络往返）跑完才会开始。
    unawaited(update(GeoAsset.geoip));
    unawaited(update(GeoAsset.geosite));
  }

  Future<void> update(GeoAsset asset) async {
    state = {...state, asset.type: const GeoUpdateState(isUpdating: true)};
    GeoUpdateService? service;
    StreamSubscription<double>? progressSub;
    try {
      // mixedPort 读取和 service 构造都放进 try：读设置/建 Dio 理论上不该
      // 失败，但万一 sharedPreferencesProvider 还没就绪，也应该跟网络失败
      // 一样落进下面的 error 状态，而不是变成一个未捕获异常从 update()
      // 里漏出去（update() 是被 addRecommended() 用 unawaited 触发的，
      // 没有人在外层 catch 它）。
      final mixedPort = _ref.read(networkSettingsProvider).mixedPort;
      service = GeoUpdateService(mixedPort: mixedPort);
      // 下载进度从 service 的 broadcast stream 来，必须在 update() 前订上，
      // 否则 UI 的 LinearProgressIndicator 一直停在 0%。
      progressSub = service.progress.listen((p) {
        if (!mounted) return;
        state = {
          ...state,
          asset.type: GeoUpdateState(isUpdating: true, progress: p),
        };
      });
      await service.update(asset);
      state = {
        ...state,
        asset.type: GeoUpdateState(
          isUpdating: false,
          lastUpdated: DateTime.now(),
        ),
      };
    } catch (e) {
      state = {...state, asset.type: GeoUpdateState(error: e.toString())};
    } finally {
      await progressSub?.cancel();
      service?.dispose();
    }
  }
}

final geoUpdateProvider =
    StateNotifierProvider<GeoUpdateNotifier, Map<GeoAssetType, GeoUpdateState>>(
      (ref) {
        return GeoUpdateNotifier(ref);
      },
    );
