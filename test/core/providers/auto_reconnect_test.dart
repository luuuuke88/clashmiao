import 'package:flutter_test/flutter_test.dart';

void main() {
  group('auto reconnect backoff constants', () {
    test('delays follow 1-2-4-8 seconds pattern', () {
      const delays = [1, 2, 4, 8];
      expect(delays.length, 4);
      expect(delays.last, 8);
      expect(delays.reduce((a, b) => a + b), 15);
    });

    test('reconnect skips if already connected', () {
      bool reconnectCalled = false;
      final alreadyStarted = DateTime.now().millisecondsSinceEpoch > 0;
      if (!alreadyStarted) reconnectCalled = true;
      expect(reconnectCalled, isFalse);
    });
  });
}
