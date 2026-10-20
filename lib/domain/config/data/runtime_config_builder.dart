import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:clashmiao/domain/config/model/profile_nodes.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter/foundation.dart';

/// Connect 时组装 runtime sing-box config：只处理 inbounds / mux 与信息条目
/// 标记这些会真正生效的部分。
///
/// 输入 = 订阅 profile（已被 ProfileRepository normalize 成 sing-box JSON）。
/// 输出 = workingDir/runtime-config.json，由 native start 加载。
///
/// `dns` / `route` 块**不在这里处理**：内核配置构建器对订阅自带的这两块一律
/// 丢弃重建，DNS 与智能 / 全局分流只由 `getDefaultConfigOptions` 的选项决定
/// （`remote-dns-address` / `direct-dns-address`、`isSmart` 带来的直连规则）。
/// 往 profile 里写 dns / route 对运行不起任何作用。
class RuntimeConfigBuilder {
  RuntimeConfigBuilder();

  static const _runtimeFileName = 'runtime-config.json';

  /// 读 [baseProfile]，写到 [workingDir]/[outputFileName]（默认
  /// `runtime-config.json`）并返回该 File。
  ///
  /// 连接生命周期（子项目 B）里先写临时文件 `runtime-prep-<token>.json`，算出
  /// revision 后再定稿为 `runtime-<revision>.json`，所以文件名由调用方决定。
  ///
  /// [remoteDnsAddress] 只为兼容调用方保留（连接启动器仍然传它）：它与
  /// `getDefaultConfigOptions` 的 `remote-dns-address` 同源，由内核配置构建器
  /// 消费；这里不再往配置里写 dns，所以传不传、传什么，输出都相同。
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

/// 节点（出站或端点）tag 带这个标记时，内核把主选择组的默认值设成**该节点的
/// 真实 tag**（而不是自动选择组）。
const String _kDefaultMarker = '§default§';

/// 运行时配置 [cfg]（[RuntimeConfigBuilder.build] 写出的 JSON）对应的「运行时
/// 选择组默认值」：选择组 tag → 内核启动时它选中的出站。用户在某个订阅下没有
/// 手选记录时，切到该订阅要把选择组还原成这个值，不能留着上一个订阅的选择。
///
/// 规则（与内核选择组启动时的行为一致）：
/// - 配置里每个 selector：写了 `default` 就用它；没写则是 `outbounds` 第一项；
/// - 内核配置构建器会丢弃订阅自带的 selector / urltest，重建主选择组
///   [kRuntimeMainSelectorTag]，成员为 [kRuntimeAutoGroupTag] 加全部节点（叶子
///   视图：含 `endpoints` 里的 WireGuard 端点，不含带隐藏标记的节点与订阅信息
///   条目），默认是 [kRuntimeAutoGroupTag]；成员里有 tag 带 `§default§` 标记的
///   （出站或端点，取第一个），默认就是**那个节点的真实 tag**；
/// - 写明的默认值不是成员时，内核启动该组直接报错、不回退第一项：这种组的默认
///   值视为**未知**，不出现在结果里（调用方据此不做还原）。
///
/// 只描述 selector；urltest / 自动选择组没有可还原的默认值，调用方不碰它们。
/// 结果里可能含运行时并不存在的 tag（订阅自带、被内核丢弃的 selector），调用方
/// 只对运行时真实存在的分组生效。
Map<String, String> runtimeSelectorDefaults(Map<String, dynamic> cfg) {
  final result = <String, String>{};
  // 分组遍历用完整集合（selector 只会出现在 outbounds，但成员引用的端点 tag
  // 同样合法）；成员资格用叶子视图。
  for (final e in profileEntities(cfg)) {
    if (e.type != 'selector' || e.tag.isEmpty) continue;
    final members = [
      for (final m in (e.raw['outbounds'] as List?) ?? const [])
        if (m is String) m,
    ];
    final picked = _defaultOrFirst(e.raw['default'], members);
    if (picked != null) result[e.tag] = picked;
  }
  final memberTags = [
    for (final n in profileLeafNodes(cfg))
      if (n.tag.isNotEmpty && !hasHideMarker(n.tag)) n.tag,
  ];
  // 与 [RuntimeConfigBuilder.build] 同一口径：信息条目会被打上隐藏标记，不是
  // 主选择组成员。传进来的已经是构建后的配置时这里不会再排除任何东西。
  final infoTags = subscriptionInfoExclusionsForConfig(cfg);
  memberTags.removeWhere(infoTags.contains);
  final mainMembers = [kRuntimeAutoGroupTag, ...memberTags];
  final marked = memberTags
      .where((t) => t.contains(_kDefaultMarker))
      .firstOrNull;
  final mainDefault = marked ?? kRuntimeAutoGroupTag;
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

/// 给 [cfg] 里的订阅信息条目（[subscriptionInfoExclusionsForConfig]；出站与
/// 端点都算）的 tag 追加隐藏
/// 标记 [kHideNodeMarker]，并把配置里引用旧 tag 的地方（出站的 `detour`、分组的
/// `outbounds` / `default`、路由规则的 `outbound`、`route.final`、DNS 服务器的
/// `detour`）一并改名，配置自洽。返回旧 tag → 新 tag。
///
/// 内核据此不把它们放进主选择组和自动选择组：不测速、不会被自动选中、线路
/// 列表里也没有。出站本身保留，订阅里别的出站拿它当前置代理时照常可用。
@visibleForTesting
Map<String, String> hideSubscriptionInfoOutbounds(Map<String, dynamic> cfg) {
  // 完整集合：出站 ∪ 端点。唯一性集合要含端点 tag，改名时分组成员、`default`、
  // 各实体的 `detour` 才能一并更新。
  final entities = profileEntities(cfg);
  final allTags = <String>{
    for (final e in entities)
      if (e.tag.isNotEmpty) e.tag,
  };
  final renames = <String, String>{};
  for (final tag in subscriptionInfoExclusionsForConfig(cfg)) {
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

  for (final e in entities) {
    final o = e.raw;
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
