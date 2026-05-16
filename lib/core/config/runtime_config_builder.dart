import 'dart:convert';
import 'dart:io';

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

    if (remoteDnsAddress != null && remoteDnsAddress.isNotEmpty) {
      _overrideRemoteDnsAddress(cfg, remoteDnsAddress);
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
      }
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
