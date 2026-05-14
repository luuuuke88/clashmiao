import 'package:clashmiao/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBytes', () {
    test('B 范围', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
    });
    test('KB 范围', () => expect(formatBytes(2048), '2.0 KB'));
    test('MB 范围', () => expect(formatBytes(5 * 1024 * 1024), '5.0 MB'));
    test('GB 范围', () => expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB'));
  });

  group('formatSpeed', () {
    test('B/s', () => expect(formatSpeed(500), '500 B/s'));
    test('KB/s', () => expect(formatSpeed(2048), '2.0 KB/s'));
    test('MB/s', () => expect(formatSpeed(5 * 1024 * 1024), '5.0 MB/s'));
  });

  group('formatDuration', () {
    test('秒', () => expect(formatDuration(const Duration(seconds: 30)), '30秒'));
    test('分钟', () => expect(formatDuration(const Duration(minutes: 5)), '5分钟'));
    test('小时', () => expect(formatDuration(const Duration(hours: 3)), '3小时'));
    test('天', () => expect(formatDuration(const Duration(days: 7)), '7天'));
  });

  group('formatExpireDate', () {
    test('null → 永不过期', () => expect(formatExpireDate(null), '永不过期'));
    test('过期', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(formatExpireDate(past), '已过期');
    });
    test('未过期 → 剩余 N 天', () {
      final future = DateTime.now().add(const Duration(days: 10, hours: 2));
      expect(formatExpireDate(future), '剩余 10 天');
    });
  });

  group('isValidUrl', () {
    test('http / https ok', () {
      expect(isValidUrl('https://example.com'), isTrue);
      expect(isValidUrl('http://example.com/path'), isTrue);
    });
    test('其他 scheme 不算', () {
      expect(isValidUrl('ftp://example.com'), isFalse);
      expect(isValidUrl('ws://example.com'), isFalse);
    });
    test('非法字符串不算', () {
      expect(isValidUrl('not a url'), isFalse);
      expect(isValidUrl(''), isFalse);
    });
  });
}
