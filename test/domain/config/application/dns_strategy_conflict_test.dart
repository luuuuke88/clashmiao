import 'package:clashmiao/domain/config/application/dns_strategy_conflict.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<NetworkSettingsNotifier> _notifier(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  return NetworkSettingsNotifier(await SharedPreferences.getInstance());
}

void main() {
  group('冲突判定', () {
    test('IPv6 禁用 + 仅 IPv6 冲突；仅限 IPv6 + 仅 IPv4 冲突', () {
      expect(
        dnsStrategyConflictKind('ipv4_only', 'ipv6_only'),
        DnsStrategyConflictKind.ipv6Disabled,
      );
      expect(
        dnsStrategyConflictKind('ipv6_only', 'ipv4_only'),
        DnsStrategyConflictKind.ipv6Only,
      );
    });

    test('其余组合都不冲突，空策略（自动）永不冲突', () {
      const modes = ['ipv4_only', 'prefer_ipv4', 'prefer_ipv6', 'ipv6_only'];
      const strategies = [
        '',
        'prefer_ipv6',
        'prefer_ipv4',
        'ipv4_only',
        'ipv6_only',
      ];
      final conflicting = <String>{};
      for (final m in modes) {
        for (final s in strategies) {
          if (dnsStrategyConflictKind(m, s) != null) conflicting.add('$m+$s');
        }
      }
      expect(conflicting, {'ipv4_only+ipv6_only', 'ipv6_only+ipv4_only'});
    });
  });

  group('设置入口拦截', () {
    test('IPv6 禁用时把任一策略改成仅 IPv6：抛异常，值与存储都不变', () async {
      for (final setter in <String>['remote', 'direct']) {
        final n = await _notifier({});
        final call = setter == 'remote'
            ? n.setRemoteDnsDomainStrategy
            : n.setDirectDnsDomainStrategy;
        await expectLater(
          call('ipv6_only'),
          throwsA(
            isA<DnsStrategyConflictException>().having(
              (e) => e.conflict.kind,
              'kind',
              DnsStrategyConflictKind.ipv6Disabled,
            ),
          ),
        );
        expect(n.state.remoteDnsDomainStrategy, '');
        expect(n.state.directDnsDomainStrategy, '');
        expect(
          n.prefs.getString('clashmiao_${setter}_dns_domain_strategy'),
          isNull,
        );
      }
    });

    test('策略是仅 IPv6 时把 IPv6 模式改成禁用：被拦下', () async {
      final n = await _notifier({
        'clashmiao_ipv6_mode': 'prefer_ipv4',
        'clashmiao_remote_dns_domain_strategy': 'ipv6_only',
      });
      await expectLater(
        n.setIpv6Mode('ipv4_only'),
        throwsA(isA<DnsStrategyConflictException>()),
      );
      expect(n.state.ipv6Mode, 'prefer_ipv4');
    });

    test('仅限 IPv6 + 仅 IPv4 这个对称死局同样被拦', () async {
      final n = await _notifier({'clashmiao_ipv6_mode': 'ipv6_only'});
      await expectLater(
        n.setDirectDnsDomainStrategy('ipv4_only'),
        throwsA(
          isA<DnsStrategyConflictException>().having(
            (e) => (e.conflict.field, e.conflict.kind),
            'conflict',
            (DnsStrategyField.direct, DnsStrategyConflictKind.ipv6Only),
          ),
        ),
      );
    });

    test('不冲突的修改照常生效；先改 IPv6 再改策略的正常顺序可用', () async {
      final n = await _notifier({});
      await n.setIpv6Mode('prefer_ipv6');
      await n.setRemoteDnsDomainStrategy('ipv6_only');
      expect(n.state.remoteDnsDomainStrategy, 'ipv6_only');
      expect(n.state.ipv6Mode, 'prefer_ipv6');
    });
  });

  group('已存设置里的冲突：归一并留下提示，不静默', () {
    test('读入时重置冲突的策略、写回存储、留下持久化提示', () async {
      final n = await _notifier({
        'clashmiao_ipv6_mode': 'ipv4_only',
        'clashmiao_remote_dns_domain_strategy': 'ipv6_only',
        'clashmiao_direct_dns_domain_strategy': 'prefer_ipv4',
      });
      await pumpEventQueue();

      expect(n.state.remoteDnsDomainStrategy, '');
      expect(n.state.directDnsDomainStrategy, 'prefer_ipv4', reason: '不冲突的不动');
      expect(n.prefs.getString('clashmiao_remote_dns_domain_strategy'), '');
      expect(n.normalizationNotice, [
        const DnsStrategyConflict(
          DnsStrategyField.remote,
          DnsStrategyConflictKind.ipv6Disabled,
        ),
      ]);

      // 重启（重建 notifier）后提示仍在，直到用户确认。
      final again = NetworkSettingsNotifier(n.prefs);
      expect(again.normalizationNotice, isNotEmpty);
      await again.dismissNormalizationNotice();
      expect(NetworkSettingsNotifier(n.prefs).normalizationNotice, isEmpty);
    });

    test('没有冲突就没有提示', () async {
      final n = await _notifier({'clashmiao_ipv6_mode': 'prefer_ipv4'});
      await pumpEventQueue();
      expect(n.normalizationNotice, isEmpty);
    });

    test('用户随后明确改了相关设置：旧提示作废', () async {
      final n = await _notifier({
        'clashmiao_remote_dns_domain_strategy': 'ipv6_only',
      });
      await pumpEventQueue();
      expect(n.normalizationNotice, isNotEmpty);
      await n.setIpv6Mode('prefer_ipv4');
      expect(n.normalizationNotice, isEmpty);
    });

    test('恢复默认清掉提示', () async {
      final n = await _notifier({
        'clashmiao_remote_dns_domain_strategy': 'ipv6_only',
      });
      await pumpEventQueue();
      await n.reset();
      expect(n.normalizationNotice, isEmpty);
    });
  });

  group('配置导入', () {
    test('导入的 JSON 本身自相矛盾：策略重置为自动并在结果里报告', () async {
      final n = await _notifier({});
      final result = await n.importJson(
        '{"ipv6Mode":"ipv4_only","remoteDnsDomainStrategy":"ipv6_only",'
        '"directDnsDomainStrategy":"ipv6_only"}',
      );
      expect(n.state.ipv6Mode, 'ipv4_only');
      expect(n.state.remoteDnsDomainStrategy, '');
      expect(n.state.directDnsDomainStrategy, '');
      expect(result.normalizedConflicts.map((c) => c.field), [
        DnsStrategyField.remote,
        DnsStrategyField.direct,
      ]);
      expect(n.normalizationNotice, hasLength(2));
    });

    test('导入只带 IPv6 模式，与本机已存的策略冲突：同样归一并报告', () async {
      final n = await _notifier({
        'clashmiao_ipv6_mode': 'prefer_ipv4',
        'clashmiao_direct_dns_domain_strategy': 'ipv6_only',
      });
      final result = await n.importJson('{"ipv6Mode":"ipv4_only"}');
      expect(n.state.directDnsDomainStrategy, '');
      expect(result.normalizedConflicts, hasLength(1));
    });

    test('导入不冲突：无归一、无提示；导入逐项写入的中间态不会被误拦', () async {
      final n = await _notifier({
        'clashmiao_ipv6_mode': 'ipv4_only',
        'clashmiao_remote_dns_domain_strategy': 'ipv4_only',
      });
      // 顺序上 ipv6Mode 先写：此刻本机策略是 ipv4_only，若逐项拦截会误判。
      final result = await n.importJson(
        '{"ipv6Mode":"ipv6_only","remoteDnsDomainStrategy":"ipv6_only"}',
      );
      expect(result.skippedKeys, isEmpty);
      expect(result.normalizedConflicts, isEmpty);
      expect(n.state.ipv6Mode, 'ipv6_only');
      expect(n.state.remoteDnsDomainStrategy, 'ipv6_only');
    });
  });
}
