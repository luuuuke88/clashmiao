import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSubscriptionInfoTag：按「标签 + 分隔 + 值」模板识别', () {
    const infoTags = [
      // 真实订阅里的条目（全角冒号）。
      '🌐 官网地址：ncink.cc',
      '官网地址: ncink.cc',
      '官网：https://ncink.cc/',
      '最新网址 example.com',
      '网址：example.com',
      '剩余流量：123.4 GB',
      '剩余流量：100G',
      '已用流量 12.3 GB',
      '总流量：402.27 GB',
      '距离下次重置剩余：23 天',
      '流量重置日：每月 1 日',
      '重置：2026-11-01',
      '套餐到期：2026-12-01',
      '套餐到期时间：2026年12月1日',
      '到期时间: 2027-01-01 12:00:00',
      '过期时间: 2027-01-01',
      '公告：example.com',
      'Expire: 2026-12-01',
      'Expires 2026/12/01',
      'Expiration 2026-12-01',
      'Expire Date: 2026-12-01',
      'Traffic: 10GB / 100GB',
      'Traffic: 35%',
      'Remaining 12 GB',
      'Remaining: 30 days',
      'Reset: 5 days',
      'Website: example.com',
      'URL: https://example.com',
      // 整个名字只是网址或域名。
      'ncink.cc',
      '🌐 ncink.cc',
      'https://ncink.cc/login',
      '【www.example.com】',
      '最新网址：example.com。',
    ];
    for (final tag in infoTags) {
      test('信息条目：$tag', () {
        expect(isSubscriptionInfoTag(tag), isTrue);
      });
    }

    const realTags = [
      // 含标签关键词、但不是「标签 + 分隔 + 值」的真实线路名。
      '香港01 官网优化 IEPL',
      '🇭🇰 香港 官网专线 01',
      'HK Official IEPL 01',
      'HK Traffic IEPL 01',
      'JP Reset 02',
      'US Remaining 03 | 1.5x',
      'SG 网址优化 01',
      '日本 重置版 IEPL',
      '台湾 公告专线',
      'HK-Website-01',
      // 长得像域名的线路名。
      // 审阅反例：标签后跟着带宽、编号、日期状序号，再跟线路描述。
      'HK Traffic 10Gbps IEPL 02',
      'HK Traffic 10G IEPL',
      'HK Reset 01-02 IEPL',
      'SG Reset 2024-05-01 IEPL',
      'JP Expire 2025-01 专线',
      '香港 重置 12-01 BGP',
      '到期 2026-12-01 IEPL 中继',
      '剩余流量 100GB 专线',
      'US Remaining 5 days IEPL',
      'JP.Tokyo',
      'HK.IEPL.01',
      // 常见真实线路名。
      '🇭🇰 香港01-BGP|IEPL中继',
      '🇭🇰 香港[直连|备用]',
      '🇻🇳 越南-边缘节点',
      '香港 0.5倍流量',
      '日本 大流量专线 2',
      'US Los Angeles 03',
      'Singapore 04 | 1.5x',
      'hk §default§',
      // 关键词宽泛的旧规则会误判、但没有值的：拿不准一律保留。
      '官方 TG 群',
      '订阅更新时间',
      '流量：不限',
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
          '香港01 官网优化 IEPL',
          '剩余流量：1 GB',
          '套餐到期：2026-12-01 §hide§',
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

  group('candidateLeafTags：叶子视图，含端点', () {
    test('出站里的叶子 + 端点，不含分组 / 直连 / 阻断 / DNS', () {
      final tags = candidateLeafTags({
        'outbounds': [
          {'type': 'selector', 'tag': 'sel'},
          {'type': 'vless', 'tag': 'v'},
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'block', 'tag': 'block'},
          {'type': 'dns', 'tag': 'dns-out'},
          {'type': 'urltest', 'tag': 'auto'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg'},
        ],
      });
      expect(tags, ['v', 'wg']);
    });

    test('只有端点的订阅：候选不为空', () {
      expect(
        candidateLeafTags({
          'outbounds': <Object>[],
          'endpoints': [
            {'type': 'wireguard', 'tag': 'wg-hk'},
          ],
        }),
        ['wg-hk'],
      );
    });

    test('端点上的信息条目同样被排除，且订阅级保护照常（全是信息条目则不排除）', () {
      final cfg = <String, dynamic>{
        'outbounds': [
          {'type': 'vless', 'tag': '剩余流量：100 GB'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg-hk'},
        ],
      };
      expect(subscriptionInfoExclusionsForConfig(cfg), {'剩余流量：100 GB'});
      final onlyInfo = <String, dynamic>{
        'outbounds': <Object>[],
        'endpoints': [
          {'type': 'wireguard', 'tag': '剩余流量：100 GB'},
        ],
      };
      expect(subscriptionInfoExclusionsForConfig(onlyInfo), isEmpty);
    });
  });
}
