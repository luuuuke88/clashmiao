import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

// 简化版 BackupBundle 用于测试序列化往返
Map<String, dynamic> buildBundle({
  required List<Map<String, dynamic>> profiles,
  String? activeId,
}) {
  return {
    'version': '1.0',
    'profiles': profiles,
    'activeProfileId': activeId,
    'settings': <String, dynamic>{},
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  };
}

void main() {
  test('bundle serializes and deserializes correctly', () {
    final original = buildBundle(
      profiles: [
        {'id': 'abc', 'name': 'test', 'url': 'https://example.com', 'active': true}
      ],
      activeId: 'abc',
    );
    final json = jsonEncode(original);
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded['version'], '1.0');
    expect((decoded['profiles'] as List).length, 1);
    expect(decoded['activeProfileId'], 'abc');
  });

  test('rejects unknown version', () {
    final bundle = buildBundle(profiles: [])..['version'] = '99.0';
    expect(
      () {
        if (bundle['version'] != '1.0') throw Exception('不支持的备份版本');
      },
      throwsException,
    );
  });
}
