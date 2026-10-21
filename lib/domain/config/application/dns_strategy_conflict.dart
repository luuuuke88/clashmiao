/// IPv6 路由模式与 DNS 域名策略之间「不可能同时成立」的组合。
///
/// - IPv6 路由禁用（`ipv4_only`）而 DNS 域名策略是 `ipv6_only`：解析只会问 AAAA，
///   而出站走不了 IPv6——所有域名都解析不出可用地址（健康检查 `cp.cloudflare.com`
///   也因此降级）。
/// - IPv6 路由仅限 IPv6（`ipv6_only`）而 DNS 域名策略是 `ipv4_only`：对称的死局。
///
/// 内核对这类组合不报错（每个值单独都合法），所以由应用层在设置入口、已存设置、
/// 配置导入与备份恢复四处统一拦截。口径只在这里定义一次。
library;

/// 哪一项 DNS 域名策略。
enum DnsStrategyField { remote, direct }

/// 冲突的方向。
enum DnsStrategyConflictKind {
  /// IPv6 禁用，策略却是仅 IPv6。
  ipv6Disabled,

  /// IPv6 仅限，策略却是仅 IPv4。
  ipv6Only,
}

/// 某一项 DNS 域名策略与 IPv6 模式冲突。
class DnsStrategyConflict {
  const DnsStrategyConflict(this.field, this.kind);

  final DnsStrategyField field;
  final DnsStrategyConflictKind kind;

  @override
  bool operator ==(Object other) =>
      other is DnsStrategyConflict &&
      other.field == field &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(field, kind);

  @override
  String toString() => 'DnsStrategyConflict(${field.name}, ${kind.name})';
}

/// [ipv6Mode] 与 [strategy] 是否冲突；不冲突返回 null。空策略（自动）永不冲突。
DnsStrategyConflictKind? dnsStrategyConflictKind(
  String ipv6Mode,
  String strategy,
) {
  if (ipv6Mode == 'ipv4_only' && strategy == 'ipv6_only') {
    return DnsStrategyConflictKind.ipv6Disabled;
  }
  if (ipv6Mode == 'ipv6_only' && strategy == 'ipv4_only') {
    return DnsStrategyConflictKind.ipv6Only;
  }
  return null;
}

/// 一组设置里的全部冲突（远程在前、直连在后）。
List<DnsStrategyConflict> dnsStrategyConflicts({
  required String ipv6Mode,
  required String remoteStrategy,
  required String directStrategy,
}) => [
  for (final (field, strategy) in [
    (DnsStrategyField.remote, remoteStrategy),
    (DnsStrategyField.direct, directStrategy),
  ])
    if (dnsStrategyConflictKind(ipv6Mode, strategy) case final kind?)
      DnsStrategyConflict(field, kind),
];

/// 设置入口被拦下的异常：这次修改会造成冲突，没有写入任何东西。
class DnsStrategyConflictException implements Exception {
  const DnsStrategyConflictException(this.conflict);

  final DnsStrategyConflict conflict;

  @override
  String toString() => 'DnsStrategyConflictException($conflict)';
}
