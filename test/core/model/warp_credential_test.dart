import 'dart:convert';

import 'package:clashmiao/core/model/warp_credential.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WarpCredential.parse', () {
    test('解析完整合法响应', () {
      final raw = jsonEncode({
        'account-id': 'acc-123',
        'access-token': 'token-abc',
        'log': 'registered ok',
        'config': {
          'private_key': 'aGVsbG8=',
          'peer_public_key': 'd29ybGQ=',
          'address': ['172.16.0.2/32'],
        },
      });

      final credential = WarpCredential.parse(raw);

      expect(credential.accountId, 'acc-123');
      expect(credential.accessToken, 'token-abc');
      expect(credential.log, 'registered ok');
      // wireguardConfig 是 config 字段原样重新序列化的 JSON 字符串，
      // 反解回来应该跟原始 map 完全一致（不需要 Dart 端理解其内部字段）。
      expect(jsonDecode(credential.wireguardConfig), {
        'private_key': 'aGVsbG8=',
        'peer_public_key': 'd29ybGQ=',
        'address': ['172.16.0.2/32'],
      });
    });

    test('log 字段缺失时默认空字符串，不影响其余字段解析', () {
      final raw = jsonEncode({
        'account-id': 'acc-1',
        'access-token': 'token-1',
        'config': {'k': 'v'},
      });

      final credential = WarpCredential.parse(raw);

      expect(credential.log, '');
      expect(credential.accountId, 'acc-1');
    });

    test('log 字段类型不对时降级为空字符串而不是抛异常', () {
      final raw = jsonEncode({
        'account-id': 'acc-1',
        'access-token': 'token-1',
        'config': {'k': 'v'},
        'log': 12345,
      });

      final credential = WarpCredential.parse(raw);

      expect(credential.log, '');
    });

    test('非 JSON 字符串抛 FormatException', () {
      expect(
        () => WarpCredential.parse('not json at all'),
        throwsFormatException,
      );
    });

    test('顶层是 JSON 数组而不是对象时抛 FormatException', () {
      expect(
        () => WarpCredential.parse(jsonEncode(['a', 'b'])),
        throwsFormatException,
      );
    });

    test('缺少 account-id 抛 FormatException', () {
      final raw = jsonEncode({
        'access-token': 'token-1',
        'config': {'k': 'v'},
      });

      expect(() => WarpCredential.parse(raw), throwsFormatException);
    });

    test('account-id 为空字符串抛 FormatException', () {
      final raw = jsonEncode({
        'account-id': '',
        'access-token': 'token-1',
        'config': {'k': 'v'},
      });

      expect(() => WarpCredential.parse(raw), throwsFormatException);
    });

    test('缺少 access-token 抛 FormatException', () {
      final raw = jsonEncode({
        'account-id': 'acc-1',
        'config': {'k': 'v'},
      });

      expect(() => WarpCredential.parse(raw), throwsFormatException);
    });

    test('缺少 config 抛 FormatException', () {
      final raw = jsonEncode({
        'account-id': 'acc-1',
        'access-token': 'token-1',
      });

      expect(() => WarpCredential.parse(raw), throwsFormatException);
    });

    test('config 类型不是对象时抛 FormatException', () {
      final raw = jsonEncode({
        'account-id': 'acc-1',
        'access-token': 'token-1',
        'config': 'not-a-map',
      });

      expect(() => WarpCredential.parse(raw), throwsFormatException);
    });

    test('空字符串输入抛 FormatException', () {
      expect(() => WarpCredential.parse(''), throwsFormatException);
    });

    test('toString 不泄露 access-token', () {
      final raw = jsonEncode({
        'account-id': 'acc-123',
        'access-token': 'super-secret-token',
        'config': {'k': 'v'},
      });

      final credential = WarpCredential.parse(raw);

      expect(credential.toString(), isNot(contains('super-secret-token')));
    });
  });
}
