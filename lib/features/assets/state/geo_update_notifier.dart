import 'package:clashmiao/features/assets/logic/geo_update_service.dart';
import 'package:clashmiao/features/assets/model/geo_asset.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  GeoUpdateNotifier()
    : super({
        GeoAssetType.geoip: const GeoUpdateState(),
        GeoAssetType.geosite: const GeoUpdateState(),
      });

  Future<void> update(GeoAsset asset) async {
    state = {...state, asset.type: const GeoUpdateState(isUpdating: true)};
    final service = GeoUpdateService();
    try {
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
      service.dispose();
    }
  }
}

final geoUpdateProvider =
    StateNotifierProvider<GeoUpdateNotifier, Map<GeoAssetType, GeoUpdateState>>(
      (ref) {
        return GeoUpdateNotifier();
      },
    );
