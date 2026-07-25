import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/features/profile/model/advanced_config.dart';
import 'package:flutter/foundation.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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

  /// 读 [baseProfile]，写到 [workingDir]/runtime-config.json 并返回该 File。
  ///
  /// [remoteDnsAddress] 会覆盖 profile 里 `dns.servers[tag=remote]` 的 address。
  /// import 阶段写进 profile 的 fallback 值（profile_repository._ensureMinimal...）
  /// 无法跟随 NetworkSettings 变更，所以每次 connect 都在这里现拼。
  Future<File> build({
    required File baseProfile,
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

    final out = File('${workingDir.path}/$_runtimeFileName');
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
}
