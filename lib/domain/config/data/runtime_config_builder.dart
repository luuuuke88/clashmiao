import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:clashmiao/domain/config/model/dns_defaults.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter/foundation.dart';

/// Connect 时组装 runtime sing-box config：只处理 inbounds/dns/mux 这些
/// 会真正生效的部分。
///
/// 输入 = 订阅 profile（已被 ProfileRepository normalize 成 sing-box JSON）。
/// 输出 = workingDir/runtime-config.json，由 native start 加载。
///
/// 智能 / 全局分流**不在这里处理**——这个 sing-box fork 的
/// `config.BuildConfig()`（libcore/config/config.go:383）会无条件丢弃/重建
/// profile 自带的整个 `route` 块，不管 `enable-full-config`/
/// `execute-config-as-is` 传的是什么。这里以前往 profile 的 `route` 块注入 cn
/// 分流规则的做法（真机验证过）从未真正生效——智能/全局分流实际行为完全
/// 一样。真正生效的分流机制在 `getDefaultConfigOptions` 的 `isSmart` 参数
/// （对应 fork 真正认的 `configOptions.rules` 口子），见该函数文档。
class RuntimeConfigBuilder {
  RuntimeConfigBuilder();

  static const _runtimeFileName = 'runtime-config.json';

  /// 读 [baseProfile]，写到 [workingDir]/[outputFileName]（默认
  /// `runtime-config.json`）并返回该 File。
  ///
  /// 连接生命周期（子项目 B）里先写临时文件 `runtime-prep-<token>.json`，算出
  /// revision 后再定稿为 `runtime-<revision>.json`，所以文件名由调用方决定。
  ///
  /// [remoteDnsAddress] 会覆盖 profile 里 `dns.servers[tag=remote]` 的 address。
  /// import 阶段写进 profile 的 fallback 值（profile_repository._ensureMinimal...）
  /// 无法跟随 NetworkSettings 变更，所以每次 connect 都在这里现拼。
  ///
  Future<File> build({
    required File baseProfile,
    required Directory workingDir,
    String? remoteDnsAddress,
    AdvancedConfig? advancedConfig,
    String outputFileName = _runtimeFileName,
  }) async {
    final raw = await baseProfile.readAsString();
    final cfg = jsonDecode(raw) as Map<String, dynamic>;

    // mixed inbound 永远剥（所有平台）：
    //   核心在 enable-full-config 路径下，不管 profile 写没写都会自己 append 一个
    //   mixed:MixedPort（默认 2080），profile 自带 mixed 必然撞端口
    //   → sing-box 启动直接 `listen tcp 127.0.0.1:2080: bind: address already in use`。
    //
    // tun inbound 也永远剥（所有平台、所有服务模式）：
    //   tun 只由启动参数 `enable-tun` 交给内核配置构建器创建——它会自己 append
    //   一个 tag 为 tun-in 的 tun inbound（地址 / MTU / 栈 / 严格路由取自网络设置）。
    //   订阅里再留一个，运行配置就有两个 tun inbound：VPN 每次启动都调两次
    //   VpnService.Builder.establish()，第二次把第一个 VPN 接口替换掉，两套 tun
    //   协议栈抢同一个地址 172.19.0.1；被替换接口的拆除与新协议栈的 TCP 转发监听
    //   赛跑，输了的那次启动 tun 转发监听不存在，所有经 tun 的 TCP 约 2 ms 内被拒
    //   （真机验收 BUG-B）。Android「仅线路」不起 tun（纯代理 Service 不是
    //   VpnService，留着它内核启动即失败）；桌面没开 TUN 时同理。
    _stripConflictingInbounds(cfg, stripTun: true);

    // 订阅信息条目（「官网地址：…」「剩余流量：…」）不能进自动选择组。主选择
    // 组 / 自动选择组的成员是内核配置构建器决定的，它只认 tag 里的隐藏标记，
    // 所以在这里给信息条目打上标记。规则见 subscription_info_node.dart。
    hideSubscriptionInfoOutbounds(cfg);

    final effectiveDns = (advancedConfig?.remoteDnsOverride?.isNotEmpty == true)
        ? advancedConfig!.remoteDnsOverride!
        : remoteDnsAddress;

    // DNS 链自足兜底。订阅导入有三条路径（单 URI / 多节点订阅 / sing-box JSON
    // 直通），只有单 URI 路径在 import 时补过 dns.servers；后两条产出的 profile
    // 可能完全没有 dns 块，导致 sing-box 的 DNS 阶段无可用解析后端。
    _ensureDnsSelfSufficient(cfg, effectiveDns);

    if (effectiveDns != null && effectiveDns.isNotEmpty) {
      _overrideRemoteDnsAddress(cfg, effectiveDns);
    }

    if (advancedConfig?.muxEnabled == true) {
      _injectMux(cfg, advancedConfig!);
    }

    final out = File('${workingDir.path}/$outputFileName');
    await out.writeAsString(jsonEncode(cfg), flush: true);
    if (kDebugMode) {
      debugPrint(
        '[RuntimeConfigBuilder] wrote ${out.path} '
        '(${(await out.length()) ~/ 1024} KB)',
      );
    }
    return out;
  }

  void _stripConflictingInbounds(
    Map<String, dynamic> cfg, {
    required bool stripTun,
  }) {
    final inbounds = (cfg['inbounds'] as List?)?.cast<dynamic>() ?? [];
    inbounds.removeWhere((i) {
      if (i is! Map) return false;
      if (i['type'] == 'mixed') return true;
      if (stripTun && i['type'] == 'tun') return true;
      return false;
    });
    cfg['inbounds'] = inbounds;
  }

  /// 保证 runtime config 的 dns 块自足：remote（出口查询）/ direct / local
  /// 三个 server 必须齐。tag 已存在的不动（尊重 profile 自带配置），缺的补上。
  ///
  /// 注意：Android / 桌面现用的内核配置构建器会丢弃这里的整个 dns 块、自己重建
  /// （直连 DNS 取 `direct-dns-address`，见 default_config_options.dart），这里
  /// 只保证文件本身自洽；默认地址与设置的默认值保持一致。
  ///
  /// remote 用 DoH（TCP，对不支持 UDP 转发的节点也能工作）且带
  /// `detour: 'direct'` 的 address_resolver 自举不需要 —— 默认地址是裸 IP；
  /// 若用户覆盖成域名 DoH，sing-box 需要先解析该域名，因此给 remote 挂
  /// `address_resolver: 'direct'` 保证自举。
  void _ensureDnsSelfSufficient(Map<String, dynamic> cfg, String? remoteAddr) {
    final dns = (cfg['dns'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final servers = ((dns['servers'] ??= <dynamic>[]) as List).cast<dynamic>();
    final tags = servers
        .whereType<Map<dynamic, dynamic>>()
        .map((s) => s['tag'])
        .whereType<String>()
        .toSet();

    if (!tags.contains('direct')) {
      servers.add({
        'tag': 'direct',
        'address': kDefaultDirectDnsAddress,
        'detour': 'direct',
      });
    }
    if (!tags.contains('local')) {
      servers.add({'tag': 'local', 'address': 'local', 'detour': 'direct'});
    }
    if (!tags.contains('remote')) {
      servers.add({
        'tag': 'remote',
        'address': (remoteAddr != null && remoteAddr.isNotEmpty)
            ? remoteAddr
            : 'https://1.1.1.1/dns-query',
        'address_resolver': 'direct',
      });
    }
    dns['servers'] = servers;
    dns['final'] = dns['final'] ?? 'remote';
  }

  /// 覆盖 profile.dns.servers 里 `tag=remote` 那条的 address。
  /// 没 dns / 没 servers 就直接 return（fork 兜底会自己 append）。
  void _overrideRemoteDnsAddress(Map<String, dynamic> cfg, String address) {
    final dns = cfg['dns'];
    if (dns is! Map<String, dynamic>) return;
    final servers = dns['servers'];
    if (servers is! List) return;
    for (final s in servers) {
      if (s is Map && s['tag'] == 'remote') {
        s['address'] = address;
        // 域名形式的 DoH（如 https://dns.google/dns-query）需要先解析域名
        // 才能发查询；没有 resolver 会死锁在自举。裸 IP 带上也无害。
        s['address_resolver'] ??= 'direct';
      }
    }
  }

  /// 把 per-profile 的 Mux 设置注入到支持 multiplex 的代理 outbound。
  /// 只对 sing-box 原生支持 multiplex 的协议生效；profile 自带 multiplex
  /// 配置的 outbound 不覆盖（尊重订阅方的显式配置）。
  static const _muxCapableTypes = {'shadowsocks', 'vmess', 'vless', 'trojan'};

  void _injectMux(Map<String, dynamic> cfg, AdvancedConfig adv) {
    final outbounds = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];
    for (final o in outbounds) {
      if (o is! Map) continue;
      if (!_muxCapableTypes.contains(o['type'])) continue;
      if (o.containsKey('multiplex')) continue;
      o['multiplex'] = {
        'enabled': true,
        'protocol': adv.muxProtocol,
        'max_streams': adv.muxConcurrency,
      };
    }
  }
}

/// 内核配置构建器重建的主选择组 tag（订阅里的 selector / urltest 一律被丢弃，
/// 换成这一组加自动选择组 [kRuntimeAutoGroupTag]）。
const String kRuntimeMainSelectorTag = 'select';

/// 内核配置构建器重建的自动选择（urltest）组 tag。
const String kRuntimeAutoGroupTag = 'auto';

/// 节点 tag 带这个标记时，内核把主选择组的默认值设成它（而不是自动选择组）。
const String _kDefaultMarker = '§default§';

/// 不会成为主选择组成员的出站类型（内核构建主选择组时跳过）。
const Set<String> _kNonMemberTypes = {
  'direct',
  'block',
  'dns',
  'selector',
  'urltest',
  'custom',
};

/// 运行时配置 [cfg]（[RuntimeConfigBuilder.build] 写出的 JSON）对应的「运行时
/// 选择组默认值」：选择组 tag → 内核启动时它选中的出站。用户在某个订阅下没有
/// 手选记录时，切到该订阅要把选择组还原成这个值，不能留着上一个订阅的选择。
///
/// 规则（与内核选择组启动时的行为一致）：
/// - 配置里每个 selector：写了 `default` 就用它；没写则是 `outbounds` 第一项；
/// - 内核配置构建器会丢弃订阅自带的 selector / urltest，重建主选择组
///   [kRuntimeMainSelectorTag]，成员为 [kRuntimeAutoGroupTag] 加全部节点（不含
///   带隐藏标记的节点与订阅信息条目），默认
///   是 [kRuntimeAutoGroupTag]（节点 tag 带 `§default§` 标记时是该标记字面值）；
/// - 写明的默认值不是成员时，内核启动该组直接报错、不回退第一项：这种组的默认
///   值视为**未知**，不出现在结果里（调用方据此不做还原）。
///
/// 只描述 selector；urltest / 自动选择组没有可还原的默认值，调用方不碰它们。
/// 结果里可能含运行时并不存在的 tag（订阅自带、被内核丢弃的 selector），调用方
/// 只对运行时真实存在的分组生效。
Map<String, String> runtimeSelectorDefaults(Map<String, dynamic> cfg) {
  final outbounds = (cfg['outbounds'] as List?) ?? const [];
  final result = <String, String>{};
  final memberTags = <String>[];
  for (final o in outbounds) {
    if (o is! Map) continue;
    final tag = o['tag'];
    final type = o['type'];
    if (tag is! String || type is! String) continue;
    if (type == 'selector') {
      final members = [
        for (final m in (o['outbounds'] as List?) ?? const [])
          if (m is String) m,
      ];
      final picked = _defaultOrFirst(o['default'], members);
      if (picked != null) result[tag] = picked;
    }
    if (!_kNonMemberTypes.contains(type) && !hasHideMarker(tag)) {
      memberTags.add(tag);
    }
  }
  // 与 [RuntimeConfigBuilder.build] 同一口径：信息条目会被打上隐藏标记，不是
  // 主选择组成员。传进来的已经是构建后的配置时这里不会再排除任何东西。
  final infoTags = subscriptionInfoTagsToExclude(memberTags);
  memberTags.removeWhere(infoTags.contains);
  final mainMembers = [kRuntimeAutoGroupTag, ...memberTags];
  final mainDefault = memberTags.any((t) => t.contains(_kDefaultMarker))
      ? _kDefaultMarker
      : kRuntimeAutoGroupTag;
  // 主选择组由内核重建，订阅里同名的旧 selector 已被丢弃：它的默认值不能代表
  // 重建后的主组，推导不出时必须是「未知」，不能留着旧条目。
  final main = _defaultOrFirst(mainDefault, mainMembers);
  if (main != null) {
    result[kRuntimeMainSelectorTag] = main;
  } else {
    result.remove(kRuntimeMainSelectorTag);
  }
  return result;
}

/// 选择组启动时选中的出站：写明了默认值（非空）就必须是成员，否则未知；
/// 没写则是第一项。
String? _defaultOrFirst(Object? preferred, List<String> members) {
  if (preferred is String && preferred.isNotEmpty) {
    return members.contains(preferred) ? preferred : null;
  }
  return members.isEmpty ? null : members.first;
}

/// 给 [cfg] 里的订阅信息条目（[subscriptionInfoTagsToExclude]）的 tag 追加隐藏
/// 标记 [kHideNodeMarker]，并把配置里引用旧 tag 的地方（出站的 `detour`、分组的
/// `outbounds` / `default`、路由规则的 `outbound`、`route.final`、DNS 服务器的
/// `detour`）一并改名，配置自洽。返回旧 tag → 新 tag。
///
/// 内核据此不把它们放进主选择组和自动选择组：不测速、不会被自动选中、线路
/// 列表里也没有。出站本身保留，订阅里别的出站拿它当前置代理时照常可用。
@visibleForTesting
Map<String, String> hideSubscriptionInfoOutbounds(Map<String, dynamic> cfg) {
  final outbounds = (cfg['outbounds'] as List?) ?? const [];
  final allTags = <String>{};
  final leafTags = <String>[];
  for (final o in outbounds) {
    if (o is! Map) continue;
    final tag = o['tag'];
    if (tag is! String) continue;
    allTags.add(tag);
    final type = o['type'];
    if (type is String && !_kNonMemberTypes.contains(type)) leafTags.add(tag);
  }
  final renames = <String, String>{};
  for (final tag in subscriptionInfoTagsToExclude(leafTags)) {
    var renamed = '$tag $kHideNodeMarker';
    while (allTags.contains(renamed)) {
      renamed = '$renamed$kHideNodeMarker';
    }
    allTags.add(renamed);
    renames[tag] = renamed;
  }
  if (renames.isEmpty) return renames;

  Object? rename(Object? value) =>
      value is String ? (renames[value] ?? value) : value;
  void renameKey(Map<dynamic, dynamic> m, String key) {
    if (m.containsKey(key)) m[key] = rename(m[key]);
  }

  for (final o in outbounds) {
    if (o is! Map) continue;
    renameKey(o, 'tag');
    renameKey(o, 'detour');
    renameKey(o, 'default');
    final members = o['outbounds'];
    if (members is List) {
      for (var i = 0; i < members.length; i++) {
        members[i] = rename(members[i]);
      }
    }
  }
  final route = cfg['route'];
  if (route is Map) {
    renameKey(route, 'final');
    for (final r in (route['rules'] as List?) ?? const []) {
      if (r is Map) renameKey(r, 'outbound');
    }
  }
  final dns = cfg['dns'];
  if (dns is Map) {
    for (final s in (dns['servers'] as List?) ?? const []) {
      if (s is Map) renameKey(s, 'detour');
    }
  }
  return renames;
}
