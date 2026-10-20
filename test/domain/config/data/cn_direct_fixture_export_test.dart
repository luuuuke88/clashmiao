import 'dart:convert';

import 'package:clashmiao/domain/config/data/cn_direct_rules.dart';
import 'package:clashmiao/domain/config/data/default_config_options.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_file.dart';

/// 智能分流下 Dart 注入的 `rules` 全量（7.5k CIDR + 域名）入库成
/// `kernel/testdata/rules/cn-direct.json`，Go 的路由测试用它验证「全量清单能过
/// CheckConfig 与真启动」。这里保证入库的文件与 `getDefaultConfigOptions(isSmart:
/// true)` 的实际输出完全一致——清单数据（`cn_direct_rules.dart`）一变、夹具没
/// 更新，这条测试就失败。
const _path = 'kernel/testdata/rules/cn-direct.json';

const _comment =
    '由 lib/domain/config/data/cn_direct_rules.dart 导出，与 getDefaultConfigOptions '
    '在智能分流下注入的 rules 完全一致；cn_direct_fixture_export_test.dart 负责保持同步'
    '（UPDATE_GOLDEN=1 重写）。';

void main() {
  test('cn-direct.json 与智能分流注入的 rules 逐字节一致', () {
    final options = getDefaultConfigOptions(
      isSmart: true,
      settings: const NetworkSettings(),
    );
    final rules = options['rules'] as List;
    expectGoldenFile(
      _path,
      '${jsonEncode({'_comment': _comment, 'rules': rules})}\n',
    );
  });

  test('形态：一条 IP 规则 + 一条域名规则，都是 bypass，数据量是全量清单', () {
    final rules =
        (getDefaultConfigOptions(
                  isSmart: true,
                  settings: const NetworkSettings(),
                )['rules']
                as List)
            .cast<Map<String, dynamic>>();
    expect(rules, hasLength(2));
    expect(rules.map((r) => r['outbound']), ['bypass', 'bypass']);
    expect(rules[0].keys, {'ip', 'outbound'});
    expect(rules[1].keys, {'domains', 'outbound'});
    expect((rules[0]['ip'] as String).split(','), cnDirectCidrRanges);
    final domains = (rules[1]['domains'] as String).split(',');
    expect(
      domains.length,
      cnDirectDomains.length +
          cnDirectDomainSuffixes.length +
          cnDirectDomainRegexes.length,
    );
    expect(cnDirectCidrRanges.length, greaterThan(5000));
  });
}
