import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/features/profile/model/advanced_config.dart';
import 'package:flutter/foundation.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Connect 时根据 mode 现场组装 runtime sing-box config。
///
/// 输入 = 订阅 profile（已被 ProfileRepository normalize 成 sing-box JSON）。
/// 输出 = workingDir/runtime-config.json，由 native start 加载。
///
/// 智能模式：注入 local rule-set + 把中国 IP/域名走 direct outbound。
/// 全局模式：删掉 profile 自带的所有 rule-set 引用，让兜底 default outbound 接管。
class RuntimeConfigBuilder {
  RuntimeConfigBuilder();

  static const _ruleSetGeoip = 'geoip-cn';
  static const _ruleSetGeosite = 'geosite-cn';
  static const _runtimeFileName = 'runtime-config.json';

  /// 读 [baseProfile]，根据 [isSmart] 决定要不要注入 cn 分流，
  /// 写到 [workingDir]/runtime-config.json 并返回该 File。
  ///
  /// [remoteDnsAddress] 会覆盖 profile 里 `dns.servers[tag=remote]` 的 address。
  /// import 阶段写进 profile 的 fallback 值（profile_repository._ensureMinimal...）
  /// 无法跟随 NetworkSettings 变更，所以每次 connect 都在这里现拼。
  Future<File> build({
    required File baseProfile,
    required bool isSmart,
    required Directory workingDir,
    String? remoteDnsAddress,
    AdvancedConfig? advancedConfig,
  }) async {
    final raw = await baseProfile.readAsString();
    final cfg = jsonDecode(raw) as Map<String, dynamic>;

    // mixed inbound 永远剥（所有平台）：
    //   上游 fork 在 enable-full-config 路径下不管 profile 写没写都会自己 append 一个
    //   mixed:MixedPort（默认 2080），profile 自带 mixed 必然撞端口
    //   → sing-box 启动直接 `listen tcp 127.0.0.1:2080: bind: address already in use`。
    //
    // tun inbound：
    //   - 桌面端剥 —— 用户进程没 root 建不了 tun，service 会 "operation not permitted"。
    //   - Android 不能剥 —— Settings.needVPNService() 靠扫 profile 里的 tun inbound 决定
    //     要不要起 VpnService。剥了直接走 NORMAL mode（无 TUN，无系统级路由）。
    _stripConflictingInbounds(cfg, stripTun: _isDesktop);

    // 永远先剥离 profile 自带的 rule-set 引用：
    //   - route.rule_set: 全清
    //   - route.rules / dns.rules: 删任何 rule_set: [...] 的项
    // 这样无论智能 / 全局，profile 自带的 上游 geo CDN url 引用都不会去 fetch。
    _stripRuleSetReferences(cfg);

    final effectiveDns = (advancedConfig?.remoteDnsOverride?.isNotEmpty == true)
        ? advancedConfig!.remoteDnsOverride!
        : remoteDnsAddress;

    // DNS 链自足兜底。订阅导入有三条路径（单 URI / 多节点订阅 / sing-box JSON
    // 直通），只有单 URI 路径在 import 时补过 dns.servers；后两条产出的 profile
    // 可能完全没有 dns 块。而下面 _injectSmartCnRouting 会无条件插一条
    // `server: 'local'` 的 dns rule —— 若 servers 里没有 local，sing-box 的 DNS
    // 阶段无可用解析后端，表现为连上了但所有域名 DNS 超时。
    // 在 connect 的唯一咽喉（这里）统一补齐，三条路径一次覆盖。
    _ensureDnsSelfSufficient(cfg, effectiveDns);

    if (effectiveDns != null && effectiveDns.isNotEmpty) {
      _overrideRemoteDnsAddress(cfg, effectiveDns);
    }

    if (advancedConfig?.muxEnabled == true) {
      _injectMux(cfg, advancedConfig!);
    }

    if (isSmart) {
      _injectSmartCnRouting(cfg, workingDir);
    }
    // 全局模式：profile.outbounds 自带的兜底 default 接管所有流量。

    final out = File('${workingDir.path}/$_runtimeFileName');
    await out.writeAsString(jsonEncode(cfg), flush: true);
    if (kDebugMode) {
      debugPrint(
        '[RuntimeConfigBuilder] wrote ${out.path} '
        '(${(await out.length()) ~/ 1024} KB, smart=$isSmart)',
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

  void _stripRuleSetReferences(Map<String, dynamic> cfg) {
    final route = cfg['route'];
    if (route is Map<String, dynamic>) {
      route['rule_set'] = <Map<String, dynamic>>[];
      _filterRulesWithRuleSet(route['rules']);
    }
    final dns = cfg['dns'];
    if (dns is Map<String, dynamic>) {
      _filterRulesWithRuleSet(dns['rules']);
    }
  }

  void _filterRulesWithRuleSet(Object? rules) {
    if (rules is! List) return;
    rules.removeWhere((r) {
      if (r is! Map) return false;
      final ref = r['rule_set'];
      if (ref is List && ref.isNotEmpty) return true;
      if (ref is String && ref.isNotEmpty) return true;
      return false;
    });
  }

  /// 保证 runtime config 的 dns 块自足：remote（出口查询）/ direct / local
  /// 三个 server 必须齐。tag 已存在的不动（尊重 profile 自带配置），缺的补上。
  ///
  /// remote 用 DoH（TCP，对不支持 UDP 转发的节点也能工作）且带
  /// `detour: 'direct'` 的 address_resolver 自举不需要 —— 默认地址是裸 IP；
  /// 若用户覆盖成域名 DoH，sing-box 需要先解析该域名，因此给 remote 挂
  /// `address_resolver: 'direct'` 保证自举。
  void _ensureDnsSelfSufficient(Map<String, dynamic> cfg, String? remoteAddr) {
    final dns = (cfg['dns'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final servers = ((dns['servers'] ??= <dynamic>[]) as List).cast<dynamic>();
    final tags = servers
        .whereType<Map>()
        .map((s) => s['tag'])
        .whereType<String>()
        .toSet();

    if (!tags.contains('direct')) {
      servers.add({'tag': 'direct', 'address': '1.1.1.1', 'detour': 'direct'});
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

  void _injectSmartCnRouting(Map<String, dynamic> cfg, Directory workingDir) {
    // 1. 注入 local rule-set 引用。
    //    用绝对路径：Android 上 sing-box 的 CWD 是 external files dir
    //    (/storage/.../Android/data/.../files/)，跟 Flutter 的 app_flutter/
    //    (rule-set 实际位置) 不在同一处。相对 './geoip-cn.srs' 永远找不到，
    //    rule-set 静默失败 → 所有规则不命中 → 智能模式表现得跟全局一样。
    final geoipPath = '${workingDir.path}/$_ruleSetGeoip.srs';
    final geositePath = '${workingDir.path}/$_ruleSetGeosite.srs';
    final route =
        (cfg['route'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    route['rule_set'] = <Map<String, dynamic>>[
      {
        'tag': _ruleSetGeoip,
        'type': 'local',
        'format': 'binary',
        'path': geoipPath,
      },
      {
        'tag': _ruleSetGeosite,
        'type': 'local',
        'format': 'binary',
        'path': geositePath,
      },
    ];

    // 2. route.rules 第一条：中国 IP / 域名走 direct
    final routeRules =
        (route['rules'] ??= <Map<String, dynamic>>[]) as List<dynamic>;
    routeRules.insert(0, <String, dynamic>{
      'rule_set': <String>[_ruleSetGeoip, _ruleSetGeosite],
      'outbound': 'direct',
    });

    // 3. dns.rules 第一条：中国域名走 local DNS（profile 里如果有 tag=local 的 server）
    final dns = (cfg['dns'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final dnsRules =
        (dns['rules'] ??= <Map<String, dynamic>>[]) as List<dynamic>;
    dnsRules.insert(0, <String, dynamic>{
      'rule_set': <String>[_ruleSetGeosite],
      'server': 'local',
    });
  }
}
