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
