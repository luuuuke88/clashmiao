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
    test('剩余超过 365 天 → Unlimited（此前只有 profiles_page 私有实现才有这条规则，'
        '合并成单一实现，避免同一订阅在首页/订阅列表两处显示不一致）', () {
      final farFuture = DateTime.now().add(const Duration(days: 400));
      expect(formatExpireDate(farFuture, en), 'Unlimited');
      expect(formatExpireDate(farFuture, zhCn), '无限期');
    });
    test('剩余恰好 365 天以内仍正常显示天数，不提前判无限期', () {
      final justUnder = DateTime.now().add(const Duration(days: 365, hours: 2));
      expect(formatExpireDate(justUnder, en), 'Remaining 365 days');
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
  _expiryConsistencyTests();
}

// ===========================================================
// 到期信息在界面上有两种展示形态（首页/列表给"剩余 N 天"，详情页给绝对
// 日期），但"什么算无限期"必须是同一条规则。此前详情页用的是
// `expire.year > 2099`、另外两处用的是"剩余 > 365 天"——一条 2028 年到期的
// 订阅会在首页显示"无限期"、在详情页显示一个具体日期，同一条订阅两个说法。
// ===========================================================
void _expiryConsistencyTests() {
  group('到期展示：两种形态共用同一条"无限期"判定', () {
    final t = Translations.build();

    test('两年后到期：两种展示都判为无限期（此前详情页会显示具体日期）', () {
      final expire = DateTime.now().add(const Duration(days: 730));

      expect(isEffectivelyUnlimited(expire), isTrue);
      expect(formatExpireDate(expire, t), t.profile.details.unlimited);
      expect(formatExpireAbsolute(expire, t), t.profile.details.unlimited);
    });

    test('半年后到期：两种展示都给出具体信息，不判无限期', () {
      final expire = DateTime.now().add(const Duration(days: 180));

      expect(isEffectivelyUnlimited(expire), isFalse);
      expect(formatExpireDate(expire, t), isNot(t.profile.details.unlimited));
      expect(
        formatExpireAbsolute(expire, t),
        isNot(t.profile.details.unlimited),
      );
    });

    test('null 到期时间两种展示都判无限期', () {
      expect(isEffectivelyUnlimited(null), isTrue);
      expect(formatExpireDate(null, t), t.profile.details.unlimited);
      expect(formatExpireAbsolute(null, t), t.profile.details.unlimited);
    });

    test('绝对日期用 ISO 风格补零，不是硬编码中文', () {
      // 必须落在一年以内，否则会被 isEffectivelyUnlimited 判成无限期，
      // 就测不到格式化本身了。挑一个月/日都是个位数的日子来验补零。
      final base = DateTime.now().add(const Duration(days: 100));
      final expire = DateTime(base.year, 3, 7).isAfter(DateTime.now())
          ? DateTime(base.year, 3, 7)
          : DateTime(base.year + 1, 3, 7);
      // 上面挑出来的日子可能又超过一年，兜底退回 100 天后
      final target = isEffectivelyUnlimited(expire) ? base : expire;

      final text = formatExpireAbsolute(target, t);
      expect(
        text,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        reason: 'ISO 风格 YYYY-MM-DD，月日补零',
      );
      expect(text, isNot(contains('年')), reason: '非中文用户不该看到中文日期格式');
      expect(text, isNot(contains('号')));
    });

    test('月/日为个位数时补零', () {
      // 直接验格式化函数本身的补零逻辑，绕开"多久算无限期"的时间依赖：
      // 取明天，再单独构造一个个位数月日的日期做纯字符串比对。
      final soon = DateTime.now().add(const Duration(days: 1));
      expect(formatExpireAbsolute(soon, t), hasLength(10));
      expect(formatExpireAbsolute(soon, t)[4], '-');
      expect(formatExpireAbsolute(soon, t)[7], '-');
    });

    test('已过期时绝对日期照实显示过去的日期（不谎报无限期）', () {
      final expire = DateTime.now().subtract(const Duration(days: 30));

      expect(isEffectivelyUnlimited(expire), isFalse);
      expect(
        formatExpireAbsolute(expire, t),
        isNot(t.profile.details.unlimited),
      );
      expect(formatExpireDate(expire, t), t.profile.subscription.expired);
    });
  });
}
