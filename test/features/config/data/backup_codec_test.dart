import 'dart:convert';

import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/restore_harness.dart';

Map<String, dynamic> _profile(String id, {String? url, String? name}) => {
  'id': id,
  'name': name ?? 'n-$id',
  'url': url ?? 'https://example.com/$id',
  'lastUpdate': null,
  'updateInterval': 1,
  'subInfo': null,
  'customUserAgent': null,
  'rev': 3,
};

String _v2({
  List<Object?>? profiles,
  Object? active,
  Object? configs,
  Object? prefs,
  int schema = 1,
  Object? version = 2,
}) => jsonEncode({
  'version': version,
  'schema': schema,
  'createdAt': 1,
  'profiles': profiles ?? [_profile('a')],
  'activeProfileId': active,
  'profileConfigs': configs ?? {'a': sampleConfig('a')},
  'preferences': prefs ?? <String, Object>{},
});

RestorePlan _parse(String raw, {bool trusted = false}) => BackupCodec.parse(
  raw,
  currentSchema: kCurrentStorageSchema,
  extraValidators: networkPrefValidators,
  newInc: _counter(),
  trusted: trusted,
);

String Function() _counter() {
  var n = 0;
  return () => 'inc${n++}';
}

void main() {
  group('版本与整体形状', () {
    test('导入 v2：订阅、激活、配置、偏好齐全，且换发新的本机代际', () {
      final plan = _parse(
        _v2(
          profiles: [_profile('a'), _profile('b')],
          active: 'b',
          configs: {'a': sampleConfig('a'), 'b': sampleConfig('b')},
          prefs: {'clashmiao_mixed_port': 3000, 'theme_mode': 'dark'},
        ),
      );
      expect([for (final p in plan.profiles) p.id], ['a', 'b']);
      expect(plan.activeId, 'b');
      expect(plan.configs.keys, {'a', 'b'});
      expect(plan.prefs, {'clashmiao_mixed_port': 3000, 'theme_mode': 'dark'});
      expect(plan.profiles.map((p) => p.inc), ['inc0', 'inc1']);
      expect(plan.profiles.every((p) => !p.active), isTrue);
      expect(plan.profiles.first.rev, 3, reason: 'rev 随备份保留，代际靠 inc');
      expect(plan.profilesDropped, 0);
      expect(plan.skippedPrefKeys, isEmpty);
      expect(plan.needsFetch, isEmpty);
    });

    test('备份里即使带了 inc 也不采用（一律重新生成）', () {
      final p = _profile('a')..['inc'] = 'attacker-chosen';
      final plan = _parse(_v2(profiles: [p]));
      expect(plan.profiles.single.inc, 'inc0');
    });

    test('导入旧的 1.0（嵌套 settings）', () {
      final raw = jsonEncode({
        'version': '1.0',
        'createdAt': 1,
        'profiles': [
          {..._profile('a'), 'active': true},
        ],
        'activeProfileId': 'a',
        'settings': {
          'profileConfigs': {'a': sampleConfig('a')},
          'preferences': {
            'clashmiao_block_ads': true,
            // 旧导出会带的机密 / 运行时键：现在一律忽略。
            'clashmiao_warp_access_token': 'secret',
            'started_by_user': true,
            'update_latest_tag': 'v1',
          },
        },
      });
      final plan = _parse(raw);
      expect(plan.profiles.single.id, 'a');
      expect(plan.activeId, 'a');
      expect(plan.configs.keys, {'a'});
      expect(plan.prefs, {'clashmiao_block_ads': true});
      expect(
        plan.skippedPrefKeys,
        unorderedEquals([
          'clashmiao_warp_access_token',
          'started_by_user',
          'update_latest_tag',
        ]),
      );
    });

    test('不认识的版本、不是对象、不是 JSON、profiles 形状不对都被拒', () {
      void expectKind(String raw, BackupErrorKind kind) {
        expect(
          () => _parse(raw),
          throwsA(
            isA<BackupFormatException>().having((e) => e.kind, 'kind', kind),
          ),
        );
      }

      expectKind(_v2(version: 99), BackupErrorKind.unsupportedVersion);
      expectKind(_v2(version: '1.5'), BackupErrorKind.unsupportedVersion);
      expectKind('not json', BackupErrorKind.invalidFile);
      expectKind('[1,2]', BackupErrorKind.invalidFile);
      expectKind(
        jsonEncode({'version': 2, 'profiles': 'x'}),
        BackupErrorKind.invalidFile,
      );
    });

    test('schema 高于本机支持的版本被拒（提示升级）', () {
      expect(
        () => _parse(_v2(schema: kCurrentStorageSchema + 1)),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.kind,
            'kind',
            BackupErrorKind.newerSchema,
          ),
        ),
      );
    });
  });

  group('订阅校验（路径安全、单条隔离）', () {
    test('../x、含斜杠、过长、空 id 被拒；其余条目照常导入', () {
      final bad = ['../x', 'a/b', r'a\b', '..', '', 'x' * 65, '.hidden', 'a b'];
      final plan = _parse(
        _v2(
          profiles: [for (final id in bad) _profile(id), _profile('ok')],
          configs: {
            for (final id in bad) id: sampleConfig(id),
            'ok': sampleConfig('ok'),
          },
        ),
      );
      expect([for (final p in plan.profiles) p.id], ['ok']);
      expect(plan.configs.keys, {'ok'}, reason: '恶意 id 的配置内容不会被采用');
      expect(plan.profilesDropped, bad.length);
    });

    test('重复 id 只留第一条；非对象 / 缺字段的条目被丢弃并计数', () {
      final plan = _parse(
        _v2(
          profiles: [
            _profile('a', name: 'first'),
            _profile('a', name: 'second'),
            'garbage',
            {'id': 'nourl'},
            _profile('b'),
          ],
          configs: {'a': sampleConfig('a'), 'b': sampleConfig('b')},
        ),
      );
      expect([for (final p in plan.profiles) p.id], ['a', 'b']);
      expect(plan.profiles.first.name, 'first');
      expect(plan.profilesDropped, 3);
    });

    test('profileConfigs 里不属于最终订阅集合的键被忽略', () {
      final plan = _parse(
        _v2(
          configs: {
            'a': sampleConfig('a'),
            '../evil': sampleConfig('evil'),
            'ghost': sampleConfig('ghost'),
          },
        ),
      );
      expect(plan.configs.keys, {'a'});
    });

    test('配置不是「含 outbounds 数组的对象」就不被采用', () {
      final cases = <Object?>[
        '',
        '   ',
        'not json',
        '[]',
        '"str"',
        '42',
        '{}',
        '{"outbounds": "x"}',
        '{"outbounds": {}}',
        123,
        null,
      ];
      for (final bad in cases) {
        final plan = _parse(
          _v2(profiles: [_profile('a')], configs: {'a': bad}),
        );
        expect(plan.configs, isEmpty, reason: '$bad');
        // 远程订阅：配置不可用 → 保留订阅，导入后后台补拉。
        expect(plan.profiles.single.id, 'a', reason: '$bad');
        expect(plan.needsFetch, ['a'], reason: '$bad');
      }
    });

    test('远程订阅缺配置 → 排队补拉；本地订阅缺配置 → 丢弃并计数', () {
      final plan = _parse(
        _v2(
          profiles: [
            _profile('remote'),
            _profile('local', url: 'content://pasted'),
            _profile('weird', url: ''),
            _profile('full', url: 'content://ok'),
          ],
          configs: {'full': sampleConfig('full')},
        ),
      );
      expect([for (final p in plan.profiles) p.id], ['remote', 'full']);
      expect(plan.needsFetch, ['remote']);
      expect(plan.profilesDropped, 2);
    });

    test('激活 id 必须指向最终集合：被丢弃或不存在时取第一条，空列表置空', () {
      // 激活的是被丢弃的本地订阅 → 第一条。
      var plan = _parse(
        _v2(
          profiles: [
            _profile('local', url: 'content://x'),
            _profile('b'),
          ],
          active: 'local',
          configs: {'b': sampleConfig('b')},
        ),
      );
      expect(plan.activeId, 'b');
      // 指向不存在的 id。
      plan = _parse(_v2(active: 'nope'));
      expect(plan.activeId, 'a');
      // 路径穿越形式的激活 id。
      plan = _parse(_v2(active: '../a'));
      expect(plan.activeId, 'a');
      // 空列表。
      plan = _parse(_v2(profiles: [], configs: {}));
      expect(plan.profiles, isEmpty);
      expect(plan.activeId, isNull);
    });

    test('备份里有订阅但没有一条可用 → 整体被拒，不会把本机订阅清空', () {
      expect(
        () => _parse(
          _v2(
            profiles: [
              _profile('../x'),
              _profile('local', url: 'content://x'),
            ],
            configs: {},
          ),
        ),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.kind,
            'kind',
            BackupErrorKind.noUsableProfiles,
          ),
        ),
      );
    });
  });

  group('偏好校验', () {
    test('机密、运行时、未登记的键一律不导入', () {
      final plan = _parse(
        _v2(
          prefs: {
            'clashmiao_warp_license_key': 'k',
            'clashmiao_warp_account_id': 'id',
            'clashmiao_warp_access_token': 't',
            'clashmiao_warp_wireguard_config': 'c',
            'clashmiao_profiles': '[]',
            'clashmiao_active_profile': 'a',
            'clashmiao_storage_schema': 99,
            'clashmiao_restore_in_progress': '/etc/passwd',
            'clashmiao_system_proxy_dirty': true,
            'service-mode': 'proxy',
            'proxy_selection_a': '{}',
            'totally_unknown': 1,
            'clashmiao_log_level': 'info',
          },
        ),
      );
      expect(plan.prefs, {'clashmiao_log_level': 'info'});
      expect(plan.skippedPrefKeys, hasLength(12));
    });

    test('类型不对 / null / 嵌套值：跳过并报告，其余照常', () {
      final plan = _parse(
        _v2(
          prefs: {
            'clashmiao_mixed_port': '3000', // 字符串
            'clashmiao_block_ads': 1, // 数字
            'theme_mode': null,
            'per_app_proxy_include_list': ['a', 1], // 混合列表
            'per_app_proxy_exclude_list': 'nope',
            'clashmiao_region': 'cn',
          },
        ),
      );
      expect(plan.prefs, {'clashmiao_region': 'cn'});
      expect(plan.skippedPrefKeys, hasLength(5));
    });

    test('非法端口 / 枚举 / 范围：跳过（保留本机值）并报告', () {
      final plan = _parse(
        _v2(
          prefs: {
            'clashmiao_mixed_port': 80, // < 1024
            'clashmiao_clash_api_port': 70000,
            'clashmiao_tproxy_port': 0,
            'clashmiao_local_dns_port': -1,
            'clashmiao_warp_port': 1023,
            'clashmiao_mtu': 0,
            'clashmiao_url_test_interval_seconds': 30,
            'clashmiao_region': 'mars',
            'clashmiao_log_level': 'verbose',
            'clashmiao_ipv6_mode': 'both',
            'clashmiao_tun_implementation': 'x',
            'clashmiao_warp_detour_mode': 'sideways',
            'clashmiao_remote_dns_domain_strategy': 'bad',
            'clashmiao_tls_fragment_size': '   ',
            'clashmiao_proxy_mode': 2,
            'theme_mode': 'neon',
            'locale': 'klingon',
            'proxies_sort_mode': 'random',
            'per_app_proxy_mode': 'all',
          },
        ),
      );
      expect(plan.prefs, isEmpty);
      expect(plan.skippedPrefKeys, hasLength(19));
    });

    test('合法边界值被接受', () {
      final plan = _parse(
        _v2(
          prefs: {
            'clashmiao_mixed_port': 1024,
            'clashmiao_clash_api_port': 65535,
            'clashmiao_mtu': 1,
            'clashmiao_url_test_interval_seconds': 60,
            'clashmiao_remote_dns_domain_strategy': '',
            'clashmiao_proxy_mode': 0,
            'theme_mode': 'light',
            'locale': 'zh', // 旧版本写过的值
            'proxies_sort_mode': 'delay',
            'per_app_proxy_mode': 'exclude',
            'per_app_proxy_include_list': ['com.a', 'com.b'],
            'dynamic_notification': false,
          },
        ),
      );
      expect(plan.skippedPrefKeys, isEmpty);
      expect(plan.prefs['per_app_proxy_include_list'], ['com.a', 'com.b']);
      expect(plan.prefs, hasLength(12));
    });

    test('enableWarp=true 导入为 false，并在报告里标出', () {
      final plan = _parse(
        _v2(
          prefs: {
            'clashmiao_enable_warp': true,
            'clashmiao_warp_consent_given': true,
          },
        ),
      );
      expect(plan.prefs['clashmiao_enable_warp'], false);
      expect(plan.prefs['clashmiao_warp_consent_given'], true);
      expect(plan.warpDisabled, isTrue);
    });

    test('enableWarp=false 原样导入，不触发提示', () {
      final plan = _parse(_v2(prefs: {'clashmiao_enable_warp': false}));
      expect(plan.prefs['clashmiao_enable_warp'], false);
      expect(plan.warpDisabled, isFalse);
    });
  });

  group('信任模式（用恢复前快照回到原状）', () {
    test('不压 enableWarp、不查值域、本地订阅缺配置也保留、不排队补拉', () {
      final plan = _parse(
        _v2(
          profiles: [
            _profile('remote'),
            _profile('local', url: 'content://x'),
          ],
          configs: {},
          prefs: {
            'clashmiao_enable_warp': true,
            'clashmiao_mixed_port': 80, // 本机原值即便越界也要原样还原
            'clashmiao_warp_access_token': 'x',
            'unknown': 1,
          },
        ),
        trusted: true,
      );
      expect([for (final p in plan.profiles) p.id], ['remote', 'local']);
      expect(plan.needsFetch, isEmpty);
      expect(plan.prefs, {
        'clashmiao_enable_warp': true,
        'clashmiao_mixed_port': 80,
      });
      expect(plan.warpDisabled, isFalse);
      expect(plan.exactPrefs, isTrue);
    });

    test('信任模式也不放过路径穿越 id，附属偏好只认最终集合内的键', () {
      final raw = jsonEncode({
        'version': 2,
        'schema': 1,
        'profiles': [_profile('a'), _profile('../x')],
        'profileConfigs': {'a': 'cfg', '../x': 'evil'},
        'preferences': <String, Object>{},
        'auxPreferences': {
          'proxy_selection_a': '{"g":"n"}',
          'proxy_delays_a': '{}',
          'proxy_selection_ghost': '{}',
          'clashmiao_mixed_port': '3000',
          'proxy_selection_../x': '{}',
        },
      });
      final plan = _parse(raw, trusted: true);
      expect([for (final p in plan.profiles) p.id], ['a']);
      expect(plan.configs.keys, {'a'});
      expect(plan.auxPrefs.keys, {'proxy_selection_a', 'proxy_delays_a'});
    });

    test('非信任模式不采用 auxPreferences', () {
      final raw = jsonEncode({
        'version': 2,
        'profiles': [_profile('a')],
        'profileConfigs': {'a': sampleConfig('a')},
        'preferences': <String, Object>{},
        'auxPreferences': {'proxy_selection_a': '{}'},
      });
      expect(_parse(raw).auxPrefs, isEmpty);
    });
  });
}
