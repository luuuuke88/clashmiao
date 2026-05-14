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
  Future<File> build({
    required File baseProfile,
    required bool isSmart,
    required Directory workingDir,
  }) async {
    final raw = await baseProfile.readAsString();
    final cfg = jsonDecode(raw) as Map<String, dynamic>;

    // 桌面端剥离 profile 自带的 tun inbound — 用户进程没 root 建不了 tun，
    // 整个 service 会因 "operation not permitted" 启动失败。
    // 同时强制 mixed inbound 监听 127.0.0.1:2080（与 changeConfigOptions 的 MixedPort 一致）。
    if (_isDesktop) {
      _coerceDesktopInbounds(cfg);
    }

    // 永远先剥离 profile 自带的 rule-set 引用：
    //   - route.rule_set: 全清
    //   - route.rules / dns.rules: 删任何 rule_set: [...] 的项
    // 这样无论智能 / 全局，profile 自带的 上游 geo CDN url 引用都不会去 fetch。
    _stripRuleSetReferences(cfg);

    if (isSmart) {
      _injectSmartCnRouting(cfg);
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

  void _coerceDesktopInbounds(Map<String, dynamic> cfg) {
    // 桌面端剥离 tun + mixed inbound：
    //  - tun: 用户进程没 root 建不了
    //  - mixed: 上游 fork 在 enable-full-config 路径下仍然会 append 一个 mixed:MixedPort，
    //    如果 profile 也有 mixed 会端口冲突。让 fork 那条独占 2080。
    final inbounds = (cfg['inbounds'] as List?)?.cast<dynamic>() ?? [];
    inbounds.removeWhere(
      (i) => i is Map && (i['type'] == 'tun' || i['type'] == 'mixed'),
    );
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

  void _injectSmartCnRouting(Map<String, dynamic> cfg) {
    // 1. 注入 local rule-set 引用
    final route = (cfg['route'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    route['rule_set'] = <Map<String, dynamic>>[
      {
        'tag': _ruleSetGeoip,
        'type': 'local',
        'format': 'binary',
        'path': './$_ruleSetGeoip.srs',
      },
      {
        'tag': _ruleSetGeosite,
        'type': 'local',
        'format': 'binary',
        'path': './$_ruleSetGeosite.srs',
      },
    ];

    // 2. route.rules 第一条：中国 IP / 域名走 direct
    final routeRules = (route['rules'] ??= <Map<String, dynamic>>[])
        as List<dynamic>;
    routeRules.insert(0, <String, dynamic>{
      'rule_set': <String>[_ruleSetGeoip, _ruleSetGeosite],
      'outbound': 'direct',
    });

    // 3. dns.rules 第一条：中国域名走 local DNS（profile 里如果有 tag=local 的 server）
    final dns = (cfg['dns'] ??= <String, dynamic>{}) as Map<String, dynamic>;
    final dnsRules = (dns['rules'] ??= <Map<String, dynamic>>[])
        as List<dynamic>;
    dnsRules.insert(0, <String, dynamic>{
      'rule_set': <String>[_ruleSetGeosite],
      'server': 'local',
    });
  }
}
