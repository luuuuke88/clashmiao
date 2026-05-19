import 'package:flutter_test/flutter_test.dart';

enum LogLevel { all, info, warn, error, debug }

List<String> filterLogs(List<String> lines, LogLevel level, String query) {
  return lines.where((line) {
    final levelMatch =
        level == LogLevel.all || line.contains('[${level.name.toUpperCase()}]');
    final queryMatch =
        query.isEmpty || line.toLowerCase().contains(query.toLowerCase());
    return levelMatch && queryMatch;
  }).toList();
}

void main() {
  final testLines = [
    '[INFO] proxy started',
    '[WARN] high latency on node-1',
    '[ERROR] connection refused',
    '[DEBUG] packet received',
  ];

  test('level=all returns all lines', () {
    expect(filterLogs(testLines, LogLevel.all, '').length, 4);
  });

  test('level=warn filters to warn lines only', () {
    final result = filterLogs(testLines, LogLevel.warn, '');
    expect(result.length, 1);
    expect(result.first, contains('[WARN]'));
  });

  test('query filters case-insensitively', () {
    final result = filterLogs(testLines, LogLevel.all, 'latency');
    expect(result.length, 1);
  });

  test('combined level+query narrows result', () {
    final result = filterLogs(testLines, LogLevel.error, 'refused');
    expect(result.length, 1);
  });
}
