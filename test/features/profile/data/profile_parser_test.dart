import 'package:clashmiao/features/profile/data/profile_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileParser.parse', () {
    test('subscription-userinfo header 解析流量信息', () {
      final p = ProfileParser.parse('https://example.com/sub#MySub', {
        'subscription-userinfo': [
          'upload=100; download=200; total=1000; expire=1730000000',
        ],
      });
      expect(p.subInfo, isNotNull);
      expect(p.subInfo!.upload, 100);
      expect(p.subInfo!.download, 200);
      expect(p.subInfo!.total, 1000);
      expect(p.subInfo!.expire?.millisecondsSinceEpoch, 1730000000 * 1000);
    });

    test('profile-title header 优先于 URL fragment', () {
      final p = ProfileParser.parse('https://example.com/sub#FragmentName', {
        'profile-title': ['HeaderName'],
      });
      expect(p.name, 'HeaderName');
    });

    test('profile-title 缺失时 fallback URL fragment', () {
      final p = ProfileParser.parse('https://example.com/sub#MyFragment', {});
      expect(p.name, 'MyFragment');
    });

    test('全部都缺 fallback 到 "远程订阅"', () {
      final p = ProfileParser.parse('https://example.com/', {});
      expect(p.name, '远程订阅');
    });
  });
}
