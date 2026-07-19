import 'package:clashmiao/core/utils/formatters.dart' as formatters;
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionInfo getters', () {
    test('used = upload + download', () {
      const info = SubscriptionInfo(upload: 100, download: 200, total: 1000);
      expect(info.used, 300);
    });

    test('remaining = total - used', () {
      const info = SubscriptionInfo(upload: 100, download: 200, total: 1000);
      expect(info.remaining, 700);
    });

    test('usageRatio = used / total', () {
      const info = SubscriptionInfo(upload: 100, download: 200, total: 1000);
      expect(info.usageRatio, closeTo(0.3, 0.001));
    });

    test('usageRatio total=0 时返回 0（不爆 divide-by-zero）', () {
      const info = SubscriptionInfo(upload: 100, download: 0, total: 0);
      expect(info.usageRatio, 0);
    });

    test('isExpired 在过期时间之后为 true', () {
      final info = SubscriptionInfo(
        upload: 0,
        download: 0,
        total: 100,
        expire: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(info.isExpired, isTrue);
    });

    test('isExpired 在未来时间为 false', () {
      final info = SubscriptionInfo(
        upload: 0,
        download: 0,
        total: 100,
        expire: DateTime.now().add(const Duration(days: 1)),
      );
      expect(info.isExpired, isFalse);
    });

    test('isExpired 没设 expire 为 false', () {
      const info = SubscriptionInfo(upload: 0, download: 0, total: 100);
      expect(info.isExpired, isFalse);
    });
  });

  group('SubscriptionInfo.formatBytes', () {
    test('B / KB / MB / GB 分支', () {
      expect(SubscriptionInfo.formatBytes(512), '512 B');
      expect(SubscriptionInfo.formatBytes(2048), '2.0 KB');
      expect(SubscriptionInfo.formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(SubscriptionInfo.formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('是 core/utils/formatters.dart 顶层 formatBytes 的薄委托，不是各改各的第二份实现', () {
      // 曾经这里和顶层 formatBytes 是两份逐字节相同的硬编码实现（重复代码，
      // 容易日后各改各的漂移）。现在改成直接调用顶层实现——这个测试对着一批
      // 跨边界的取值(B/KB/MB/GB 各档 + 边界值) 断言两边输出恒等，用来在未来
      // 有人不小心把这里重新变回独立实现、悄悄改出偏差时能第一时间报红。
      for (final bytes in [
        0,
        1,
        1023,
        1024,
        1025,
        2048,
        1024 * 1024 - 1,
        1024 * 1024,
        5 * 1024 * 1024,
        1024 * 1024 * 1024 - 1,
        1024 * 1024 * 1024,
        3 * 1024 * 1024 * 1024,
      ]) {
        expect(
          SubscriptionInfo.formatBytes(bytes),
          formatters.formatBytes(bytes),
          reason: 'bytes=$bytes 时两边应产出完全相同的字符串',
        );
      }
    });
  });

  group('SubscriptionInfo JSON roundtrip', () {
    test('toJson + fromJson 保留字段', () {
      final original = SubscriptionInfo(
        upload: 10,
        download: 20,
        total: 100,
        expire: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        webPageUrl: 'https://example.com/panel',
        supportUrl: 'https://example.com/support',
      );
      final round = SubscriptionInfo.fromJson(original.toJson());
      expect(round.upload, original.upload);
      expect(round.download, original.download);
      expect(round.total, original.total);
      expect(round.expire, original.expire);
      expect(round.webPageUrl, original.webPageUrl);
      expect(round.supportUrl, original.supportUrl);
    });
  });
}
