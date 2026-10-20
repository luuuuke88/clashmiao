import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSubscriptionInfoTag：订阅信息条目', () {
    const infoTags = [
      // 真实订阅里的条目（全角冒号）。
      '🌐 官网地址：ncink.cc',
      '官网地址: ncink.cc',
      '最新网址 example.com',
      '官方网站 example.com',
      '剩余流量：123.4 GB',
      '距离下次重置剩余：23 天',
      '流量重置日：每月 1 日',
      '套餐到期：2026-12-01',
      '过期时间: 2027-01-01',
      '有效期至 2027-01-01',
      '流量：100GB',
      '已用流量 12.3 GB',
      'Expire: 2026-12-01',
      'Expiration 2026-12-01',
      'Traffic: 10GB / 100GB',
      'Remaining 12 GB',
      'Website: example.com',
      '官方 TG 群',
      '订阅更新时间：10-20',
      'Official site',
    ];
    for (final tag in infoTags) {
      test('信息条目：$tag', () {
        expect(isSubscriptionInfoTag(tag), isTrue);
      });
    }

    const realTags = [
      '🇭🇰 香港01-BGP|IEPL中继',
      '🇭🇰 香港[直连|备用]',
      '🇻🇳 越南-边缘节点',
      '香港 0.5倍流量',
      '日本 大流量专线 2',
      'US Los Angeles 03',
      'Singapore 04 | 1.5x',
      'hk §default§',
    ];
    for (final tag in realTags) {
      test('真实线路：$tag', () {
        expect(isSubscriptionInfoTag(tag), isFalse);
      });
    }
  });

  group('subscriptionInfoTagsToExclude', () {
    test('只排除信息条目，真实节点与带隐藏标记的节点不在结果里', () {
      expect(
        subscriptionInfoTagsToExclude([
          '🌐 官网地址：ncink.cc',
          '🇭🇰 香港01-BGP|IEPL中继',
          '剩余流量：1 GB',
          '套餐到期 §hide§',
        ]),
        {'🌐 官网地址：ncink.cc', '剩余流量：1 GB'},
      );
    });

    test('排除后一个真实节点都不剩：不排除（不能让整份订阅不可用）', () {
      expect(
        subscriptionInfoTagsToExclude(['官网地址：a.cc', '剩余流量：1 GB']),
        isEmpty,
      );
      expect(
        subscriptionInfoTagsToExclude(['官网地址：a.cc', 'hk §hide§']),
        isEmpty,
      );
    });

    test('hasHideMarker 识别内核隐藏标记', () {
      expect(hasHideMarker('x $kHideNodeMarker'), isTrue);
      expect(hasHideMarker('x §default§'), isFalse);
    });
  });
}
