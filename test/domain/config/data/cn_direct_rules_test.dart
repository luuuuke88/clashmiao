import 'dart:io';

import 'package:clashmiao/domain/config/data/cn_direct_rules.dart';
import 'package:flutter_test/flutter_test.dart';

// 排除步骤的实现在生成管线里（tools/ 不在 lib/ 下，只能相对路径引用）。
import '../../../../tools/srsdump/cn_direct_filter.dart';

/// 按内核的匹配语义判断一个域名会不会命中智能模式的域名直连规则：
/// `full:` 精确、`domain:` 后缀（带前导点只匹配子域）、`regexp:` 正则。
bool _routedDirect(String domain) {
  if (cnDirectDomains.contains(domain)) return true;
  for (final s in cnDirectDomainSuffixes) {
    if (s.startsWith('.')) {
      if (domain.endsWith(s)) return true;
    } else if (domain == s || domain.endsWith('.$s')) {
      return true;
    }
  }
  return cnDirectDomainRegexes.any((r) => RegExp(r).hasMatch(domain));
}

void main() {
  final exclusions = CnDirectExclusions.parse(
    File('tools/srsdump/cn_direct_exclusions.txt').readAsStringSync(),
  );

  // 背景：geosite-cn 带着一批谷歌系域名，在大陆网络下直连全部超时（真机实测
  // www.gstatic.com / fonts.gstatic.com / www.google.cn 等都是 5.4 s 后 000），
  // 智能模式下引用谷歌字体/静态资源的网站会卡住。生成管线用排除表剔掉它们。
  group('国内直连清单不含谷歌系域名', () {
    test('排除表覆盖了所有已知的谷歌系主域', () {
      expect(
        exclusions.domains,
        containsAll(<String>[
          'gstatic.com',
          'google.cn',
          'googleapis.cn',
          'g.cn',
          'ggpht.cn',
          'googleapis.com',
          'googleusercontent.com',
          'gvt1.com',
          'gvt2.com',
          'googletagmanager.com',
          'google-analytics.com',
          'doubleclick.net',
          'youtube.com',
          'gmail.com',
          'android.com',
          'googlevideo.com',
        ]),
      );
    });

    test('精确清单与后缀清单里没有任何落在排除域名之下的条目', () {
      final leaked = [
        ...cnDirectDomains,
        ...cnDirectDomainSuffixes,
      ].where((d) => exclusions.domains.any((b) => isUnderDomain(d, b)));
      expect(leaked, isEmpty);
    });

    // 兜底：不依赖排除表本身。规则库升级后冒出排除表没覆盖到的谷歌域名，
    // 这里会直接失败，提醒把它补进 tools/srsdump/cn_direct_exclusions.txt。
    test('关键词兜底：清单里没有疑似谷歌系的条目', () {
      // 关键词只认标签开头（或 `-` 之后），免得 elongstatic.com 这类误伤。
      final keyword = RegExp(
        r'(^|[.-])(google|gstatic|ggpht|gvt[0-9]|doubleclick|youtube|ytimg|'
        r'gmail|recaptcha|2mdn|app-measurement|admob|crashlytics|widevine)|'
        r'(^|\.)android\.com$|(^|\.)g\.cn$|\.goog$',
      );
      // 命中关键词但确认不是谷歌的条目（小米自己的广告平台、网易的崩溃上报）。
      const notGoogle = {'admob.xiaomi.com', 'crashlytics.163.com'};
      final suspicious = [
        ...cnDirectDomains,
        ...cnDirectDomainSuffixes,
      ].where((d) => keyword.hasMatch(d) && !notGoogle.contains(d));
      expect(suspicious, isEmpty);
    });

    test('实测超时的谷歌域名不再命中直连规则（落到代理）', () {
      const google = [
        'www.gstatic.com',
        'connectivitycheck.gstatic.com',
        'fonts.gstatic.com',
        'csi.gstatic.com',
        'www.google.cn',
        'google.cn',
        'g.cn',
        'fonts.googleapis.cn',
        'lh3.ggpht.cn',
        'www.gstatic.cn',
        'fonts.googleapis.com',
        'www.googletagmanager.com',
        'www.google-analytics.com',
        'ad.doubleclick.net',
        'redirector.gvt1.com',
        'beacons.gvt2.com',
        'www.youtube.com',
        'rr1---sn-abc.googlevideo.com',
        'lh3.googleusercontent.com',
        'www.android.com',
        'mail.gmail.com',
      ];
      expect(google.where(_routedDirect), isEmpty);
    });

    test('常见国内域名仍然直连', () {
      const cn = [
        'baidu.com',
        'www.baidu.com',
        'qq.com',
        'www.qq.com',
        'taobao.com',
        'www.taobao.com',
        // 顶级域 cn 改写成正则之后，普通 .cn 域名照样直连。
        'www.gov.cn',
        'example.cn',
        'a.b.example.com.cn',
        'gg.cn',
        'googlex.cn',
        'gstatic2.cn',
      ];
      expect(cn.where((d) => !_routedDirect(d)), isEmpty);
    });

    test('谷歌北京地址段不在 IP 直连清单里，常见国内地址仍在', () {
      for (final ip in ['203.208.32.1', '203.208.40.66', '2401:3800::1']) {
        expect(cidrListContainsIp(cnDirectCidrRanges, ip), isFalse, reason: ip);
      }
      for (final ip in ['1.0.1.1', '223.5.5.5', '119.29.29.29']) {
        expect(cidrListContainsIp(cnDirectCidrRanges, ip), isTrue, reason: ip);
      }
    });

    test('生成文件已经是排除之后的结果（再应用一次没有可删的）', () {
      final again = applyCnDirectExclusions(
        cidrs: cnDirectCidrRanges,
        domains: cnDirectDomains,
        suffixes: cnDirectDomainSuffixes,
        exclusions: exclusions,
      );
      expect(again.removedCidrs, isEmpty);
      expect(again.removedDomains, isEmpty);
      expect(again.removedSuffixes, isEmpty);
      expect(again.rewrittenSuffixes, isEmpty);
    });

    test('正则清单不含逗号（内核按逗号切分 domains 字段）', () {
      expect(cnDirectDomainRegexes, isNotEmpty);
      expect(cnDirectDomainRegexes.where((r) => r.contains(',')), isEmpty);
    });
  });

  group('排除步骤本身', () {
    test('补集正则：后缀语义不变，只跳过被排除的标签', () {
      final re = RegExp(
        suffixRegexExcluding(
          suffix: 'cn',
          subdomainOnly: false,
          excludedLabels: {'g', 'google', 'googleapis'},
        ),
      );
      for (final d in ['cn', 'baidu.cn', 'www.gov.cn', 'gg.cn', 'goo.cn']) {
        expect(re.hasMatch(d), isTrue, reason: d);
      }
      for (final d in [
        'g.cn',
        'google.cn',
        'www.google.cn',
        'googleapis.cn',
        'fonts.googleapis.cn',
      ]) {
        expect(re.hasMatch(d), isFalse, reason: d);
      }
      expect(re.hasMatch('googleapi.cn'), isTrue);
      expect(re.hasMatch('googleapisx.cn'), isTrue);
    });

    test('补集正则：带前导点的后缀只匹配子域', () {
      final re = RegExp(
        suffixRegexExcluding(
          suffix: 'baidu',
          subdomainOnly: true,
          excludedLabels: {'x'},
        ),
      );
      expect(re.hasMatch('baidu'), isFalse);
      expect(re.hasMatch('a.baidu'), isTrue);
      expect(re.hasMatch('x.baidu'), isFalse);
    });

    test('宽后缀盖住排除域名时改写成正则，而不是原样保留', () {
      final out = applyCnDirectExclusions(
        cidrs: const [],
        domains: const ['www.gstatic.com', 'www.baidu.com'],
        suffixes: const ['cn', 'google.cn', 'qq.com'],
        exclusions: CnDirectExclusions.parse('gstatic.com\ngoogle.cn\n'),
      );
      expect(out.domains, ['www.baidu.com']);
      expect(out.suffixes, ['qq.com']);
      expect(out.rewrittenSuffixes, ['cn']);
      expect(out.regexes, hasLength(1));
      final re = RegExp(out.regexes.single);
      expect(re.hasMatch('www.google.cn'), isFalse);
      expect(re.hasMatch('www.gov.cn'), isTrue);
    });

    test('排除段落在大网段里时只挖掉那一段', () {
      final out = applyCnDirectExclusions(
        cidrs: const ['10.0.0.0/8', '192.168.0.0/16', '203.208.32.0/19'],
        domains: const [],
        suffixes: const [],
        exclusions: CnDirectExclusions.parse('10.1.0.0/16\n203.208.32.0/19\n'),
      );
      expect(out.removedCidrs, ['10.0.0.0/8', '203.208.32.0/19']);
      expect(cidrListContainsIp(out.cidrs, '10.1.2.3'), isFalse);
      expect(cidrListContainsIp(out.cidrs, '10.0.0.1'), isTrue);
      expect(cidrListContainsIp(out.cidrs, '10.255.0.1'), isTrue);
      expect(cidrListContainsIp(out.cidrs, '192.168.1.1'), isTrue);
      expect(cidrListContainsIp(out.cidrs, '203.208.40.1'), isFalse);
    });

    test('排除域名比宽后缀深不止一级时直接报错，不静默放过', () {
      expect(
        () => applyCnDirectExclusions(
          cidrs: const [],
          domains: const [],
          suffixes: const ['cn'],
          exclusions: CnDirectExclusions.parse('google.com.cn\n'),
        ),
        throwsStateError,
      );
    });
  });
}
