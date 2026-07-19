import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum LogLevel { all, info, warn, error, debug }

final _ansiEscapePattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');
final _escapedAnsiTextPattern = RegExp(r'\.?\[(?:\d{1,3})(?:;\d{1,3})*m');

String sanitizeLogLine(String line) {
  return line
      .replaceAll(_ansiEscapePattern, '')
      .replaceAll(_escapedAnsiTextPattern, '')
      .trim();
}

/// 日志级别严重程度顺序（数值越大越严重），与 sing-box/zerolog 的级别约定一致：
/// trace < debug < info < warn(ing) < error < fatal。同样的级别集合也出现在
/// `network_settings.dart` 的 `_validLogLevels` 与 `logs_page.dart` 的行级别探测
/// 正则里。`warning` 是 `warn` 的别名，两者同级。
const _levelSeverity = <String, int>{
  'trace': 0,
  'debug': 1,
  'info': 2,
  'warn': 3,
  'warning': 3,
  'error': 4,
  'fatal': 5,
};

final _levelDetectPattern = RegExp(
  r'\b(trace|debug|info|warn|warning|error|fatal)\b',
  caseSensitive: false,
);

/// 从一行日志里探测出它的严重程度；探测不到时返回 null（既有的"不匹配"行为，
/// 只有 all 才会显示这类行）。
int? _detectSeverity(String line) {
  final match = _levelDetectPattern.firstMatch(line);
  if (match == null) return null;
  return _levelSeverity[match.group(0)!.toLowerCase()];
}

class LogFilterState {
  const LogFilterState({
    this.level = LogLevel.all,
    this.query = '',
    this.lines = const [],
    this.paused = false,
  });
  final LogLevel level;
  final String query;
  final List<String> lines;
  final bool paused;

  LogFilterState copyWith({
    LogLevel? level,
    String? query,
    List<String>? lines,
    bool? paused,
  }) => LogFilterState(
    level: level ?? this.level,
    query: query ?? this.query,
    lines: lines ?? this.lines,
    paused: paused ?? this.paused,
  );
}

class LogFilterNotifier extends StateNotifier<LogFilterState> {
  LogFilterNotifier(this._ref) : super(const LogFilterState()) {
    // `ref.listen` 创建的订阅绑定在这个 provider 自己的 `_ref` 上，
    // Riverpod 会在这个 provider 被 dispose 时自动关闭它——配合下面
    // `logFilterProvider` 的 `.autoDispose`，用户离开日志页（不再有人
    // watch/listen 这个 provider）后，底层 boxLogStreamProvider 订阅、
    // ANSI 清洗、过滤逻辑就会随 notifier 一起被销毁，不再常驻内存消耗 CPU。
    _ref.listen(boxLogStreamProvider, (_, next) {
      if (state.paused) return;
      final raw = next.valueOrNull ?? [];
      _rawLines = _sanitizeLines(raw);
      state = state.copyWith(
        lines: _filter(_rawLines, state.level, state.query),
      );
    });
  }

  final Ref _ref;
  List<String> _rawLines = const [];

  void setLevel(LogLevel level) {
    state = state.copyWith(
      level: level,
      lines: _filter(_rawLines, level, state.query),
    );
  }

  void setQuery(String query) {
    state = state.copyWith(
      query: query,
      lines: _filter(_rawLines, state.level, query),
    );
  }

  void pause() {
    state = state.copyWith(paused: true);
  }

  void resume() {
    final raw = _ref.read(boxLogStreamProvider).valueOrNull ?? _rawLines;
    _rawLines = _sanitizeLines(raw);
    state = state.copyWith(
      paused: false,
      lines: _filter(_rawLines, state.level, state.query),
    );
  }

  Future<void> clear() async {
    _rawLines = const [];
    state = state.copyWith(lines: const []);
    await _ref.read(boxServiceProvider).clearLogs();
  }

  static List<String> _filter(List<String> raw, LogLevel level, String query) {
    // 门槛式过滤：选中某级别时，级别 >= 所选级别（更严重）的行都应该显示，
    // 而不是只显示恰好等于所选级别的行——比如选 warn 时 error/fatal 也应该
    // 出现，因为它们"至少和 warn 一样严重"。
    final threshold = level == LogLevel.all ? null : _levelSeverity[level.name];
    return _sanitizeLines(raw).where((line) {
      final levelMatch = threshold == null || _meetsThreshold(line, threshold);
      final queryMatch =
          query.isEmpty || line.toLowerCase().contains(query.toLowerCase());
      return levelMatch && queryMatch;
    }).toList();
  }

  static bool _meetsThreshold(String line, int threshold) {
    final severity = _detectSeverity(line);
    return severity != null && severity >= threshold;
  }

  static List<String> _sanitizeLines(List<String> raw) {
    return raw.map(sanitizeLogLine).where((line) => line.isNotEmpty).toList();
  }
}

// autoDispose：日志页关闭、没有任何 widget 再 watch/listen 这个 provider 时，
// notifier 及其对 boxLogStreamProvider 的订阅会被自动 dispose，避免"暂停"
// 之外唯一能停止后台日志处理的手段消失（之前非 autoDispose 时，离开日志页
// 后这个 provider 会一直存活，持续消耗 CPU）。
final logFilterProvider =
    StateNotifierProvider.autoDispose<LogFilterNotifier, LogFilterState>((
      ref,
    ) {
      return LogFilterNotifier(ref);
    });
