// 国内直连清单的排除步骤：生成管线（gen_cn_direct_rules.dart）和单元测试共用。
//
// 输入是 srsdump 反编译出来的原始清单 + cn_direct_exclusions.txt，输出是真正
// 写进 lib/domain/config/data/cn_direct_rules.dart 的四个清单。纯函数，不碰
// 文件系统——读文件由调用方负责。
//
// 匹配语义与内核（libcore 的 makeDomainRule → sing-box 路由规则）一致：
// - 精确清单（`full:`）只匹配域名本身；
// - 后缀清单（`domain:`）不带前导点时匹配域名本身和所有子域，带前导点
//   （如 `.baidu`）只匹配子域；
// - 正则清单（`regexp:`）按 RE2 语法匹配完整域名。
library;

import 'dart:io';
import 'dart:typed_data';

/// 解析后的排除表。
class CnDirectExclusions {
  const CnDirectExclusions({required this.domains, required this.cidrs});

  /// 被排除的域名：它本身和所有子域都不许直连。
  final List<String> domains;

  /// 被排除的地址段。
  final List<String> cidrs;

  /// 解析 cn_direct_exclusions.txt 的文本：一行一条，`#` 之后是注释，
  /// 含 `/` 的是 CIDR，其余是域名。
  static CnDirectExclusions parse(String text) {
    final domains = <String>[];
    final cidrs = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.split('#').first.trim().toLowerCase();
      if (line.isEmpty) continue;
      if (line.contains('/')) {
        _Cidr.parse(line); // 格式不对直接抛，别让一条坏数据静默失效
        cidrs.add(line);
      } else {
        if (!_domainPattern.hasMatch(line)) {
          throw FormatException('排除表里的域名格式不对：$line');
        }
        domains.add(line);
      }
    }
    return CnDirectExclusions(domains: domains, cidrs: cidrs);
  }
}

/// 应用排除表之后的清单，即生成文件里的四个常量。
class CnDirectLists {
  const CnDirectLists({
    required this.cidrs,
    required this.domains,
    required this.suffixes,
    required this.regexes,
    required this.removedCidrs,
    required this.removedDomains,
    required this.removedSuffixes,
    required this.rewrittenSuffixes,
  });

  final List<String> cidrs;
  final List<String> domains;
  final List<String> suffixes;
  final List<String> regexes;

  /// 下面几项只用于生成时打印摘要，便于核对这次排除了什么。
  final List<String> removedCidrs;
  final List<String> removedDomains;
  final List<String> removedSuffixes;
  final List<String> rewrittenSuffixes;
}

final _domainPattern = RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)*$');
final _labelPattern = RegExp(r'^[a-z0-9-]+$');

/// [domain] 是否等于 [base] 或是它的子域。[domain] 可以带前导点（后缀清单
/// 里 `.baidu` 这种只匹配子域的写法），比较时去掉。
bool isUnderDomain(String domain, String base) {
  final d = domain.startsWith('.') ? domain.substring(1) : domain;
  return d == base || d.endsWith('.$base');
}

/// 把排除表应用到原始清单上。
///
/// 1. 精确/后缀清单里落在被排除域名之下的条目直接删掉；
/// 2. 剩下的后缀里如果有更宽的、仍会盖住被排除域名的（典型是顶级域 `cn`
///    盖住 `google.cn`），把它从后缀清单移出，改写成一条"同样的后缀匹配，
///    但跳过被排除域名"的正则——否则删掉的条目会被这条宽后缀重新捞回直连；
/// 3. CIDR 清单里被排除段覆盖的删掉，覆盖排除段的更大网段拆开、只挖掉那段。
CnDirectLists applyCnDirectExclusions({
  required List<String> cidrs,
  required List<String> domains,
  required List<String> suffixes,
  required CnDirectExclusions exclusions,
}) {
  bool excluded(String d) =>
      exclusions.domains.any((base) => isUnderDomain(d, base));

  final keptDomains = <String>[];
  final removedDomains = <String>[];
  for (final d in domains) {
    (excluded(d) ? removedDomains : keptDomains).add(d);
  }

  final keptSuffixes = <String>[];
  final removedSuffixes = <String>[];
  final rewrittenSuffixes = <String>[];
  final regexes = <String>[];
  for (final s in suffixes) {
    if (excluded(s)) {
      removedSuffixes.add(s);
      continue;
    }
    final subdomainOnly = s.startsWith('.');
    final bare = subdomainOnly ? s.substring(1) : s;
    final covered = exclusions.domains
        .where((base) => base.endsWith('.$bare'))
        .toList();
    if (covered.isEmpty) {
      keptSuffixes.add(s);
      continue;
    }
    rewrittenSuffixes.add(s);
    regexes.add(
      suffixRegexExcluding(
        suffix: bare,
        subdomainOnly: subdomainOnly,
        excludedLabels: {
          for (final base in covered)
            base.substring(0, base.length - bare.length - 1),
        },
      ),
    );
  }

  final excludedCidrs = exclusions.cidrs.map(_Cidr.parse).toList();
  final keptCidrs = <String>[];
  final removedCidrs = <String>[];
  for (final c in cidrs) {
    var pieces = [_Cidr.parse(c)];
    for (final ex in excludedCidrs) {
      pieces = [for (final p in pieces) ...p.subtract(ex)];
    }
    if (pieces.length == 1 &&
        pieces.single.toString() == _Cidr.parse(c).toString()) {
      keptCidrs.add(c);
    } else {
      removedCidrs.add(c);
      keptCidrs.addAll(pieces.map((p) => p.toString()));
    }
  }

  return CnDirectLists(
    cidrs: keptCidrs,
    domains: keptDomains,
    suffixes: keptSuffixes,
    regexes: regexes,
    removedCidrs: removedCidrs,
    removedDomains: removedDomains,
    removedSuffixes: removedSuffixes,
    rewrittenSuffixes: rewrittenSuffixes,
  );
}

/// 生成一条 RE2 正则：匹配 [suffix] 的后缀语义（[subdomainOnly] 为 false 时
/// 含它本身），但紧挨着 [suffix] 左边那一级标签落在 [excludedLabels] 里的
/// 域名（及其子域）不匹配。
///
/// 例：suffix=`cn`，excludedLabels={`google`, `g`} → 匹配 `baidu.cn`、
/// `www.gov.cn`、`cn`，不匹配 `google.cn`、`www.google.cn`、`g.cn`。
///
/// RE2 没有否定前瞻，所以"不是这几个标签之一"用前缀树展开成补集。产物里
/// 不会出现逗号——内核按逗号切分 `domains` 字段。
String suffixRegexExcluding({
  required String suffix,
  required bool subdomainOnly,
  required Set<String> excludedLabels,
}) {
  for (final label in excludedLabels) {
    if (!_labelPattern.hasMatch(label)) {
      // 被排除的域名比这条宽后缀深了不止一级（如 a.b.cn 对 cn）。补集正则
      // 只按"紧邻后缀的那一级标签"展开，这种情况得人工处理，不能静默放过。
      throw StateError(
        '排除域名 $label.$suffix 比后缀 $suffix 深了不止一级，'
        '当前生成器只支持按紧邻后缀的那一级标签排除',
      );
    }
  }
  final root = _TrieNode();
  for (final label in excludedLabels) {
    var node = root;
    for (final ch in label.split('')) {
      node = node.children.putIfAbsent(ch, _TrieNode.new);
    }
    node.terminal = true;
  }
  final label = _labelNotIn(root, allowEmpty: false);
  final escapedSuffix = suffix.replaceAll('.', r'\.');
  return subdomainOnly
      ? '^(?:.+\\.)?$label\\.$escapedSuffix\$'
      : '^(?:(?:.+\\.)?$label\\.)?$escapedSuffix\$';
}

class _TrieNode {
  final children = <String, _TrieNode>{};
  bool terminal = false;
}

/// 从 [node] 往后，匹配所有"拼上已走过的前缀后不在排除集合里"的标签剩余
/// 部分。[allowEmpty] 表示剩余部分可以为空（已走过的前缀本身不是被排除的
/// 标签，且不是根——标签不能为空）。
String _labelNotIn(_TrieNode node, {required bool allowEmpty}) {
  final keys = node.children.keys.toList()..sort();
  final alternatives = <String>[
    // 下一个字符不在任何被排除标签的这条路径上 → 之后随便是什么都安全。
    '[^.${keys.map((k) => k == '-' ? r'\-' : k).join()}][^.]*',
    for (final k in keys)
      '$k${_labelNotIn(node.children[k]!, allowEmpty: !node.children[k]!.terminal)}',
  ];
  final body = alternatives.length == 1 && !allowEmpty
      ? alternatives.single
      : '(?:${alternatives.join('|')})';
  return allowEmpty ? '$body?' : body;
}

/// 一个 IPv4/IPv6 网段。
class _Cidr {
  _Cidr(this.address, this.prefix, this.bits);

  final BigInt address;
  final int prefix;
  final int bits;

  static _Cidr parse(String text) {
    final parts = text.split('/');
    final ip = parts.length == 2 ? InternetAddress.tryParse(parts[0]) : null;
    final prefix = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (ip == null || prefix == null) {
      throw FormatException('CIDR 格式不对：$text');
    }
    final bytes = ip.rawAddress;
    final bits = bytes.length * 8;
    if (prefix < 0 || prefix > bits) {
      throw FormatException('CIDR 前缀长度越界：$text');
    }
    var value = BigInt.zero;
    for (final b in bytes) {
      value = (value << 8) | BigInt.from(b);
    }
    return _Cidr(_mask(value, prefix, bits), prefix, bits);
  }

  static BigInt _mask(BigInt value, int prefix, int bits) {
    final hostBits = bits - prefix;
    return (value >> hostBits) << hostBits;
  }

  bool contains(_Cidr other) =>
      bits == other.bits &&
      prefix <= other.prefix &&
      _mask(other.address, prefix, bits) == address;

  /// this 减去 [other] 之后剩下的网段（不相交时原样返回）。
  List<_Cidr> subtract(_Cidr other) {
    if (other.contains(this)) return const [];
    if (!contains(other)) return [this];
    // 沿着 other 往上走，每一级的"兄弟"网段都是要保留的部分。
    final result = <_Cidr>[];
    for (var len = prefix + 1; len <= other.prefix; len++) {
      final onPath = _mask(other.address, len, bits);
      final flip = BigInt.one << (bits - len);
      result.add(_Cidr(onPath ^ flip, len, bits));
    }
    result.sort((a, b) => a.address.compareTo(b.address));
    return result;
  }

  @override
  String toString() {
    final bytes = Uint8List(bits ~/ 8);
    var v = address;
    for (var i = bytes.length - 1; i >= 0; i--) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return '${InternetAddress.fromRawAddress(bytes).address}/$prefix';
  }
}

/// 测试用：判断 [ip] 是否落在 [cidrs] 的任一网段里。
bool cidrListContainsIp(List<String> cidrs, String ip) {
  final host = _Cidr.parse(ip.contains(':') ? '$ip/128' : '$ip/32');
  return cidrs.any((c) => _Cidr.parse(c).contains(host));
}
