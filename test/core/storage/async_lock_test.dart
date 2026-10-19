import 'dart:async';

import 'package:clashmiao/core/storage/async_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsyncLock', () {
    test('严格按调用顺序串行，后来者不会插队', () async {
      final lock = AsyncLock();
      final log = <String>[];
      final gate = Completer<void>();

      final first = lock.synchronized(() async {
        log.add('a:start');
        await gate.future;
        log.add('a:end');
        return 1;
      });
      final second = lock.synchronized(() async {
        log.add('b:start');
        return 2;
      });
      final third = lock.synchronized(() {
        log.add('c:start');
        return 3;
      });

      await pumpEventQueue();
      expect(log, ['a:start'], reason: '第一个没放行前，后面的都不能开始');

      gate.complete();
      expect(await Future.wait([first, second, third]), [1, 2, 3]);
      expect(log, ['a:start', 'a:end', 'b:start', 'c:start']);
    });

    test('动作抛错只让它自己失败，不会卡死后面的排队者', () async {
      final lock = AsyncLock();
      final failing = lock.synchronized<void>(() async {
        throw StateError('boom');
      });
      final next = lock.synchronized(() async => 'ok');

      await expectLater(failing, throwsStateError);
      expect(await next, 'ok');
    });

    test('同步抛错同样被隔离', () async {
      final lock = AsyncLock();
      await expectLater(
        lock.synchronized<void>(() => throw ArgumentError('x')),
        throwsArgumentError,
      );
      expect(await lock.synchronized(() => 7), 7);
    });
  });
}
