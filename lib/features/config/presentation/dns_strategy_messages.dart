import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/domain/config/application/dns_strategy_conflict.dart';

/// IPv6 模式与 DNS 域名策略冲突相关的用户可见文案（纯函数，便于单测）。
class DnsStrategyMessages {
  const DnsStrategyMessages._();

  static String _fieldLabel(Translations t, DnsStrategyField field) =>
      switch (field) {
        DnsStrategyField.remote => t.config.remoteDnsDomainStrategy,
        DnsStrategyField.direct => t.config.directDnsDomainStrategy,
      };

  /// 这次修改被拦下的说明。
  static String blocked(Translations t, DnsStrategyConflict c) {
    final field = _fieldLabel(t, c.field);
    return switch (c.kind) {
      DnsStrategyConflictKind.ipv6Disabled =>
        t.config.dnsStrategyBlockedIpv6Off(field: field),
      DnsStrategyConflictKind.ipv6Only => t.config.dnsStrategyBlockedIpv6Only(
        field: field,
      ),
    };
  }

  /// 已存设置 / 导入 / 恢复里的冲突被重置为自动之后的说明（每项一行）。
  static String reset(Translations t, List<DnsStrategyConflict> conflicts) => [
    for (final c in conflicts)
      t.config.dnsStrategyReset(field: _fieldLabel(t, c.field)),
  ].join('\n');
}
