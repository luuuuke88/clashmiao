import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _maxSamples = 60;

class StatsHistoryNotifier extends StateNotifier<List<BoxStats>> {
  StatsHistoryNotifier(this._ref) : super([]) {
    _ref.listen(boxStatsProvider, (_, next) {
      if (next is! AsyncData) return;
      final updated = [...state, next.requireValue];
      state = updated.length > _maxSamples
          ? updated.sublist(updated.length - _maxSamples)
          : updated;
    });
  }

  final Ref _ref;
}

final statsHistoryProvider =
    StateNotifierProvider<StatsHistoryNotifier, List<BoxStats>>((ref) {
      return StatsHistoryNotifier(ref);
    });
