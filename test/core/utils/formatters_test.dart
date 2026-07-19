import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = Translations.build();
  final zhCn = TranslationsZhCn.build();

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

  group('formatExpireDate', () {
    test('null → Unlimited (en)', () {
      expect(formatExpireDate(null, en), 'Unlimited');
    });
    test('null → 无限期 (zh-CN)', () {
      expect(formatExpireDate(null, zhCn), '无限期');
    });
    test('过期 → Expired (en)', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(formatExpireDate(past, en), 'Expired');
    });
    test('过期 → 已过期 (zh-CN)', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      expect(formatExpireDate(past, zhCn), '已过期');
    });
    test('未过期 → Remaining N days (en)', () {
      final future = DateTime.now().add(const Duration(days: 10, hours: 2));
      expect(formatExpireDate(future, en), 'Remaining 10 days');
    });
    test('未过期 → 剩余 N 天 (zh-CN)', () {
      final future = DateTime.now().add(const Duration(days: 10, hours: 2));
      expect(formatExpireDate(future, zhCn), '剩余 10 天');
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
