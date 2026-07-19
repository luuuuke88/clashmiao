import 'dart:async';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/logs/state/log_filter_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 这些测试直接驱动真实的 [logFilterProvider] / [LogFilterNotifier]
/// （通过 [ProviderContainer] + `boxLogStreamProvider` 覆盖），
/// 而不是维护一份脱离生产代码的过滤逻辑拷贝。

ProviderContainer _makeContainer(Stream<List<String>> stream) {
  final container = ProviderContainer(
    overrides: [boxLogStreamProvider.overrideWith((ref) => stream)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('threshold-based level filtering', () {
    // sing-box / zerolog 约定的级别顺序：trace < debug < info < warn < error < fatal。
    const testLines = [
      '2026-01-01 00:00:00 DEBUG packet received',
      '2026-01-01 00:00:01 INFO proxy started',
      '2026-01-01 00:00:02 WARN high latency on node-1',
      '2026-01-01 00:00:03 ERROR connection refused',
      '2026-01-01 00:00:04 FATAL core crashed',
    ];

    test('level=all returns all lines', () async {
      final container = _makeContainer(Stream.value(testLines));
      final sub = container.listen(logFilterProvider, (_, __) {});
      addTearDown(sub.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(logFilterProvider).lines.length, 5);
    });

    test(
      'level=warn cascades to more severe levels (warn/error/fatal shown, '
      'debug/info hidden)',
      () async {
        final container = _makeContainer(Stream.value(testLines));
        final sub = container.listen(logFilterProvider, (_, __) {});
        addTearDown(sub.close);
        await container.pump();
        await Future<void>.delayed(Duration.zero);

        container.read(logFilterProvider.notifier).setLevel(LogLevel.warn);

        final result = container.read(logFilterProvider).lines;
        expect(result.any((l) => l.contains('WARN')), isTrue);
        expect(result.any((l) => l.contains('ERROR')), isTrue);
        expect(result.any((l) => l.contains('FATAL')), isTrue);
        expect(result.any((l) => l.contains('DEBUG')), isFalse);
        expect(result.any((l) => l.contains('INFO')), isFalse);
        expect(result.length, 3);
      },
    );

    test('level=error only cascades to error/fatal', () async {
      final container = _makeContainer(Stream.value(testLines));
      final sub = container.listen(logFilterProvider, (_, __) {});
      addTearDown(sub.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      container.read(logFilterProvider.notifier).setLevel(LogLevel.error);

      final result = container.read(logFilterProvider).lines;
      expect(result.any((l) => l.contains('ERROR')), isTrue);
      expect(result.any((l) => l.contains('FATAL')), isTrue);
      expect(result.any((l) => l.contains('WARN')), isFalse);
      expect(result.length, 2);
    });

    test('query filters case-insensitively', () async {
      final container = _makeContainer(Stream.value(testLines));
      final sub = container.listen(logFilterProvider, (_, __) {});
      addTearDown(sub.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      container.read(logFilterProvider.notifier).setQuery('LATENCY');

      expect(container.read(logFilterProvider).lines.length, 1);
    });

    test('combined level+query narrows result', () async {
      final container = _makeContainer(Stream.value(testLines));
      final sub = container.listen(logFilterProvider, (_, __) {});
      addTearDown(sub.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(logFilterProvider.notifier);
      notifier.setLevel(LogLevel.error);
      notifier.setQuery('refused');

      expect(container.read(logFilterProvider).lines.length, 1);
    });
  });

  group('logFilterProvider lifecycle (autoDispose)', () {
    test(
      'disposes and stops reacting to the log stream once no longer watched',
      () async {
        final controller = StreamController<List<String>>.broadcast();
        addTearDown(controller.close);
        final container = _makeContainer(controller.stream);

        final sub = container.listen(logFilterProvider, (_, __) {});
        final notifier = container.read(logFilterProvider.notifier);

        var updateCount = 0;
        notifier.addListener((_) => updateCount++, fireImmediately: false);

        controller.add(const ['2026-01-01 00:00:00 INFO hello']);
        await container.pump();
        await Future<void>.delayed(Duration.zero);
        expect(updateCount, greaterThanOrEqualTo(1));
        expect(notifier.mounted, isTrue);

        // 模拟用户离开日志页：最后一个 watcher 消失。
        sub.close();
        await container.pump();

        expect(
          notifier.mounted,
          isFalse,
          reason:
              'logFilterProvider 应为 autoDispose，'
              '离开日志页后底层 notifier 应该被 dispose',
        );

        final countAfterDispose = updateCount;
        controller.add(const ['2026-01-01 00:00:01 should be ignored']);
        await Future<void>.delayed(Duration.zero);
        expect(
          updateCount,
          countAfterDispose,
          reason: '已 dispose 的 notifier 不应该再对日志流的新数据产生状态更新',
        );

        final freshNotifier = container.read(logFilterProvider.notifier);
        expect(
          identical(freshNotifier, notifier),
          isFalse,
          reason: '重新进入日志页应该拿到全新的 notifier，而不是复用已 dispose 的旧实例',
        );
      },
    );
  });
}
