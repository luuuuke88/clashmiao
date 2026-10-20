// 由 srsdump 反编译出的 JSON 生成 lib/domain/config/data/cn_direct_rules.dart。
//
// 用法（在仓库根目录跑，前两个参数是 srsdump 的产物，见 README.md）：
//
//   dart tools/srsdump/gen_cn_direct_rules.dart out/site.json out/ip.json
//
// 会先应用 tools/srsdump/cn_direct_exclusions.txt（谷歌系域名 / 地址段排除表），
// 再覆盖写入生成文件，并把这次排除了哪些条目打印到 stderr 供核对。
library;

import 'dart:convert';
import 'dart:io';

import 'cn_direct_filter.dart';

const _exclusionsPath = 'tools/srsdump/cn_direct_exclusions.txt';
const _outputPath = 'lib/domain/config/data/cn_direct_rules.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart tools/srsdump/gen_cn_direct_rules.dart <site.json> <ip.json>',
    );
    exit(2);
  }
  final site = _readJson(args[0]);
  final ip = _readJson(args[1]);
  final exclusions = CnDirectExclusions.parse(
    File(_exclusionsPath).readAsStringSync(),
  );

  final lists = applyCnDirectExclusions(
    cidrs: _stringList(ip, 'ip_cidr'),
    domains: _stringList(site, 'domain'),
    suffixes: _stringList(site, 'domain_suffix'),
    exclusions: exclusions,
  );

  File(_outputPath).writeAsStringSync(renderCnDirectRules(lists));

  stderr
    ..writeln('wrote $_outputPath')
    ..writeln(
      '  cidrs ${lists.cidrs.length}, domains ${lists.domains.length}, '
      'suffixes ${lists.suffixes.length}, regexes ${lists.regexes.length}',
    )
    ..writeln('  removed cidrs:    ${lists.removedCidrs.join(' ')}')
    ..writeln('  removed domains:  ${lists.removedDomains.length}')
    ..writeln('  removed suffixes: ${lists.removedSuffixes.join(' ')}')
    ..writeln('  suffix -> regex:  ${lists.rewrittenSuffixes.join(' ')}');
}

Map<String, Object?> _readJson(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

List<String> _stringList(Map<String, Object?> json, String key) =>
    ((json[key] as List?) ?? const []).cast<String>();

String _list(String name, List<String> items, {bool raw = false}) {
  final b = StringBuffer('const List<String> $name = [\n');
  for (final item in items) {
    if (item.contains("'")) {
      throw FormatException('条目里不该有单引号：$item');
    }
    b.writeln(raw ? "  r'$item'," : "  '$item',");
  }
  b.write('];\n');
  return b.toString();
}

/// 渲染生成文件的完整内容。
String renderCnDirectRules(CnDirectLists lists) =>
    '''
// GENERATED FILE — 不要手改。
//
// 由 assets/rule-sets/ 下的两个 .srs 反编译生成，再应用排除表：
//   assets/rule-sets/geoip-cn.srs   -> cnDirectCidrRanges
//   assets/rule-sets/geosite-cn.srs -> cnDirectDomains / cnDirectDomainSuffixes
//                                      / cnDirectDomainRegexes
//   tools/srsdump/cn_direct_exclusions.txt -> 从上面几个清单里剔除的条目
//
// ## 为什么要反编译成 Dart 源码，而不是让内核直接读 .srs
//
// 实际发布用的 libcore 在 region:"other" 前提下**物理上不支持任何形式的
// rule-set**（本地或远程），三条独立证据：
//
//   1. 它的 Rule 结构体虽然有 rule-set-url 字段，但 MakeRule() 从不读它——
//      对预编译二进制做 strings 反查，domains/outbound 两个 tag 在，
//      rule-set-url 这个 tag 根本不存在；
//   2. 构造 route 时 RuleSet/GeoIP/Geosite 三个 provider 配置全被注释掉，
//      strings 也找不到 GeoSitePath——就算让 MakeRule() 填上 Geosite 引用，
//      也没有任何 provider 去解析它，配置加载必然失败；
//   3. 唯一会创建 rule-set 的代码路径被 `if Region != "other"` 包住，且全是
//      指向被墙 URL 的 remote 类型——本项目正是为了绕开它才故意永远传
//      region:"other"（见 deferred-and-blocked.md H 节）。
//
// 所以分流数据只能以明文列表的形式，经 configOptions.rules 注入。
//
// ## 为什么有排除表
//
// geosite-cn 里带着一批谷歌系域名（当年谷歌北京节点还在时可直连），现在在
// 大陆网络下直连全部超时，智能模式下引用谷歌字体/静态资源的网站会卡住。
// 排除表把它们剔掉，让它们落到代理；仍会盖住它们的更宽后缀（顶级域 `cn`）
// 改写成跳过它们的正则。细节见 tools/srsdump/cn_direct_exclusions.txt。
//
// ## 生成方式
//
// srs.Read(reader, recovery=true)：recovery 为 true 时内核 common/srs/binary.go
// 会对域名规则调用 matcher.Dump()，把 succinct trie 还原成 Domain/DomainSuffix
// 两个字符串列表——域名数据是能导出的。工具源码与用法见 tools/srsdump/。
//
//   docker run --rm -v "\$PWD/core/sing-box:/src" \\
//     -v "\$PWD/assets/rule-sets:/geo:ro" -v "\$PWD/out:/out" \\
//     -w /src golang:1.22 sh -c \\
//     "go run ./cmd/srsdump /geo/geosite-cn.srs > /out/site.json && \\
//      go run ./cmd/srsdump /geo/geoip-cn.srs > /out/ip.json"
//   dart tools/srsdump/gen_cn_direct_rules.dart out/site.json out/ip.json
//
// 规则库更新或排除表改动后重跑上面两步即可，排除表会自动重新应用。

/// 中国大陆 IP 段（IPv4 + IPv6，共 ${lists.cidrs.length} 条），命中即直连。
${_list('cnDirectCidrRanges', lists.cidrs)}
/// 需要**精确**匹配的国内域名（${lists.domains.length} 条），注入时加 `full:` 前缀。
${_list('cnDirectDomains', lists.domains)}
/// 国内域名后缀（${lists.suffixes.length} 条），注入时加 `domain:` 前缀。
///
/// 带前导点的条目（如 `.baidu`）是有意保留的：内核里带点只匹配子域，
/// 不带点同时匹配域名本身和子域，语义不同，照搬原始数据不做加工。
${_list('cnDirectDomainSuffixes', lists.suffixes)}
/// 由后缀改写来的正则（${lists.regexes.length} 条），注入时加 `regexp:` 前缀。
///
/// 每条对应一个原本的宽后缀（典型是顶级域 `cn`）：后缀语义不变，但跳过排除表
/// 里落在它下面的域名，否则 `google.cn` 这类被排除的域名会被 `cn` 重新捞回
/// 直连。RE2 语法，不含逗号（内核按逗号切分 domains 字段）。
${_list('cnDirectDomainRegexes', lists.regexes, raw: true)}''';
