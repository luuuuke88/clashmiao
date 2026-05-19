import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum LogLevel { all, info, warn, error, debug }

class LogFilterState {
  const LogFilterState({
    this.level = LogLevel.all,
    this.query = '',
    this.lines = const [],
  });
  final LogLevel level;
  final String query;
  final List<String> lines;

  LogFilterState copyWith({
    LogLevel? level,
    String? query,
    List<String>? lines,
  }) => LogFilterState(
    level: level ?? this.level,
    query: query ?? this.query,
    lines: lines ?? this.lines,
  );
}

class LogFilterNotifier extends StateNotifier<LogFilterState> {
  LogFilterNotifier(this._ref) : super(const LogFilterState()) {
    _ref.listen(boxLogStreamProvider, (_, next) {
      final raw = next.valueOrNull ?? [];
      state = state.copyWith(lines: _filter(raw, state.level, state.query));
    });
  }

  final Ref _ref;

  void setLevel(LogLevel level) {
    final raw = _ref.read(boxLogStreamProvider).valueOrNull ?? [];
    state = state.copyWith(
      level: level,
      lines: _filter(raw, level, state.query),
    );
  }

  void setQuery(String query) {
    final raw = _ref.read(boxLogStreamProvider).valueOrNull ?? [];
    state = state.copyWith(
      query: query,
      lines: _filter(raw, state.level, query),
    );
  }

  static List<String> _filter(List<String> raw, LogLevel level, String query) {
    return raw.where((line) {
      final levelMatch =
          level == LogLevel.all ||
          line.contains('[${level.name.toUpperCase()}]');
      final queryMatch =
          query.isEmpty || line.toLowerCase().contains(query.toLowerCase());
      return levelMatch && queryMatch;
    }).toList();
  }
}

final logFilterProvider =
    StateNotifierProvider<LogFilterNotifier, LogFilterState>((ref) {
      return LogFilterNotifier(ref);
    });
