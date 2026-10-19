import 'dart:io';

import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _portProbe = [-1, 0, 80, 1023, 1024, 2080, 65535, 65536];

Iterable<File> _libSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) =>
          f.path.endsWith('.dart') &&
          !f.path.endsWith('.g.dart') &&
          !f.path.contains('/gen/'),
    );

void main() {
  group('登记表本身', () {
    test('键不重复', () {
      final keys = PrefRegistry.specs.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('机密只有 WARP 凭证四项，且全部是字符串', () {
      final secrets = PrefRegistry.specs.where(
        (s) => s.backup == BackupPolicy.secret,
      );
      expect(
        secrets.map((s) => s.key),
        unorderedEquals([
          'clashmiao_warp_license_key',
          'clashmiao_warp_account_id',
          'clashmiao_warp_access_token',
          'clashmiao_warp_wireguard_config',
        ]),
      );
      expect(secrets.every((s) => s.type == PrefType.string), isTrue);
    });

    test('存储结构键、恢复标记、运行时键、原生拥有的键都不进备份', () {
      for (final key in [
        'clashmiao_profiles',
        'clashmiao_active_profile',
        'clashmiao_profiles_quarantine',
        'clashmiao_profiles_corrupt',
        'clashmiao_storage_schema',
        'clashmiao_migration_backup_v0',
        kRestoreMarkerKey,
        'clashmiao_system_proxy_dirty',
        'clashmiao_store_review_requested',
        'clashmiao_analytics_enabled', // 同意与否每台设备各自决定
        'update_last_check_ms',
        'update_latest_tag',
        'service-mode',
        'debug_mode',
        'disable_memory_limit',
        'system_proxy_enabled',
        'started_by_user',
        'active_config_path',
        'active_profile_name',
      ]) {
        final spec = PrefRegistry.lookup(key);
        expect(spec, isNotNull, reason: key);
        expect(spec!.isIncluded, isFalse, reason: key);
      }
    });

    test('每订阅一份的动态键按前缀排除', () {
      expect(PrefRegistry.isExcludedPrefixKey('proxy_selection_abc'), isTrue);
      expect(PrefRegistry.isExcludedPrefixKey('proxy_delays_abc'), isTrue);
      expect(PrefRegistry.isExcludedPrefixKey('theme_mode'), isFalse);
      expect(
        PrefRegistry.validate('proxy_selection_abc', '{}'),
        PrefCheck.unknownKey,
        reason: '动态键不是登记项，导入时当作未知键拒绝',
      );
    });

    test('原生共享键必须带默认值', () {
      for (final spec in PrefRegistry.nativeShared) {
        expect(spec.defaultValue, isNotNull, reason: spec.key);
        expect(
          PrefRegistry.matchesType(spec.type, spec.defaultValue),
          isTrue,
          reason: '${spec.key} 的默认值类型要与登记类型一致',
        );
      }
    });
  });

  group('防漂移：代码里用到的偏好键必须登记', () {
    test('网络设置的每个 `_k…` 键都已登记，且登记表里的网络键没有多余', () {
      final source = File(
        'lib/domain/config/application/network_settings.dart',
      ).readAsStringSync();
      final declared = RegExp(
        r"const _k\w+ = '(clashmiao_[a-z0-9_]+)';",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
      expect(declared.length, greaterThan(40));
      for (final key in declared) {
        expect(PrefRegistry.lookup(key), isNotNull, reason: '$key 未登记');
      }
      // 反向：源码里不存在的网络键（拼错 / 已删除）不能留在登记表里。
      const nonNetwork = {
        'clashmiao_proxy_mode',
        'clashmiao_analytics_enabled',
        'clashmiao_auto_ip_check',
        'clashmiao_haptic_feedback',
        'clashmiao_silent_start',
        'clashmiao_experimental_notice_dismissed',
        'clashmiao_profiles',
        'clashmiao_active_profile',
        'clashmiao_profiles_quarantine',
        'clashmiao_profiles_corrupt',
        'clashmiao_storage_schema',
        'clashmiao_migration_backup_v0',
        'clashmiao_restore_in_progress',
        'clashmiao_system_proxy_dirty',
        'clashmiao_store_review_requested',
      };
      final registered = PrefRegistry.specs
          .map((s) => s.key)
          .where((k) => k.startsWith('clashmiao_'))
          .toSet();
      expect(registered.difference(declared).difference(nonNetwork), isEmpty);
    });

    test('全部 lib 源码里的 `clashmiao_*` 字面量都已登记（新增偏好键必须同时登记）', () {
      final literal = RegExp(r'''['"](clashmiao_[a-z0-9_]+)['"]''');
      final missing = <String>{};
      for (final file in _libSources()) {
        for (final m in literal.allMatches(file.readAsStringSync())) {
          final key = m.group(1)!;
          if (PrefRegistry.lookup(key) == null) {
            missing.add('$key（${file.path}）');
          }
        }
      }
      expect(missing, isEmpty, reason: '这些键没有登记到 PrefRegistry');
    });

    test('其它不带 clashmiao_ 前缀的键（直接传给 prefs 存取的字面量）也都已登记', () {
      // 只看「偏好对象」的存取（`prefs.` / `_prefs.` / `….requireValue.`），
      // 免得把 `json.remove('inc')` 之类的 Map 操作当成偏好键。
      final access = RegExp(
        r'''(?:\b_?prefs\??|requireValue|valueOrNull\)?\??)\s*\.\s*(?:get|set|remove|containsKey)(?:Bool|Int|String|StringList|Double)?\(\s*['"]([a-z0-9_\-]+)['"]''',
      );
      final missing = <String>{};
      for (final file in _libSources()) {
        final text = file.readAsStringSync();
        if (!text.contains('SharedPreferences') &&
            !text.contains('sharedPreferencesProvider')) {
          continue;
        }
        for (final m in access.allMatches(text)) {
          final key = m.group(1)!;
          if (PrefRegistry.lookup(key) == null) {
            missing.add('$key（${file.path}）');
          }
        }
      }
      expect(missing, isEmpty);
    });
  });

  group('值域与枚举', () {
    test('登记表里的枚举集合与代码里的枚举保持一致', () {
      for (final mode in AppThemeMode.values) {
        expect(
          PrefRegistry.validate('theme_mode', mode.name),
          PrefCheck.ok,
          reason: 'theme ${mode.name}',
        );
      }
      for (final locale in AppLocale.values) {
        expect(
          PrefRegistry.validate('locale', locale.name),
          PrefCheck.ok,
          reason: 'locale ${locale.name}',
        );
      }
      for (final sort in ProxiesSort.values) {
        expect(
          PrefRegistry.validate('proxies_sort_mode', sort.name),
          PrefCheck.ok,
          reason: 'sort ${sort.name}',
        );
      }
      expect(
        PrefRegistry.validate('theme_mode', 'black'),
        PrefCheck.outOfRange,
      );
    });

    test('类型检查：类型不对、null、混合列表', () {
      expect(
        PrefRegistry.validate('clashmiao_block_ads', 1),
        PrefCheck.wrongType,
      );
      expect(
        PrefRegistry.validate('clashmiao_mixed_port', '2080'),
        PrefCheck.wrongType,
      );
      expect(
        PrefRegistry.validate('clashmiao_mixed_port', null),
        PrefCheck.wrongType,
      );
      expect(
        PrefRegistry.validate('per_app_proxy_include_list', ['a', 2]),
        PrefCheck.wrongType,
      );
      expect(
        PrefRegistry.validate('per_app_proxy_include_list', ['a']),
        PrefCheck.ok,
      );
    });

    test('未登记 / 机密 / 运行时键：区分「未知」与「不进备份」', () {
      expect(PrefRegistry.validate('nope', 1), PrefCheck.unknownKey);
      expect(
        PrefRegistry.validate('clashmiao_warp_access_token', 'x'),
        PrefCheck.notBackedUp,
      );
      expect(
        PrefRegistry.validate('started_by_user', true),
        PrefCheck.notBackedUp,
      );
    });

    test('备份导入的值域校验与 NetworkSettingsNotifier 的 setter 逐值一致', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      Future<bool> accepts(Future<void> Function() call) async {
        try {
          await call();
          return true;
        } on ArgumentError {
          return false;
        }
      }

      final ints = <String, (Future<void> Function(int), List<int>)>{
        'clashmiao_mixed_port': (notifier.setMixedPort, _portProbe),
        'clashmiao_clash_api_port': (notifier.setClashApiPort, _portProbe),
        'clashmiao_tproxy_port': (notifier.setTproxyPort, _portProbe),
        'clashmiao_local_dns_port': (notifier.setLocalDnsPort, _portProbe),
        'clashmiao_warp_port': (notifier.setWarpPort, _portProbe),
        'clashmiao_mtu': (notifier.setMtu, [-1, 0, 1, 1500, 9000]),
        'clashmiao_url_test_interval_seconds': (
          notifier.setUrlTestIntervalSeconds,
          [0, 59, 60, 600, 3600, 3601],
        ),
      };
      for (final entry in ints.entries) {
        for (final value in entry.value.$2) {
          expect(
            networkPrefValidators[entry.key]!(value),
            await accepts(() => entry.value.$1(value)),
            reason: '${entry.key} = $value',
          );
        }
      }

      final strings = <String, (Future<void> Function(String), List<String>)>{
        'clashmiao_region': (notifier.setRegion, ['cn', 'other', 'xx', '']),
        'clashmiao_log_level': (notifier.setLogLevel, ['warn', 'trace', 'x']),
        'clashmiao_ipv6_mode': (
          notifier.setIpv6Mode,
          ['ipv4_only', 'ipv6_only', 'both'],
        ),
        'clashmiao_remote_dns_domain_strategy': (
          notifier.setRemoteDnsDomainStrategy,
          ['', 'prefer_ipv4', 'bogus'],
        ),
        'clashmiao_direct_dns_domain_strategy': (
          notifier.setDirectDnsDomainStrategy,
          ['', 'ipv6_only', 'bogus'],
        ),
        'clashmiao_tun_implementation': (
          notifier.setTunImplementation,
          ['mixed', 'gvisor', 'tap'],
        ),
        'clashmiao_warp_detour_mode': (
          notifier.setWarpDetourMode,
          ['proxyOverWarp', 'warpOverProxy', 'x'],
        ),
        'clashmiao_tls_fragment_size': (
          notifier.setTlsFragmentSize,
          ['10-30', '', '   '],
        ),
        'clashmiao_tls_fragment_sleep': (
          notifier.setTlsFragmentSleep,
          ['50-200', '', ' '],
        ),
        'clashmiao_tls_padding_size': (
          notifier.setTlsPaddingSize,
          ['100-200', '', ' '],
        ),
      };
      for (final entry in strings.entries) {
        for (final value in entry.value.$2) {
          expect(
            networkPrefValidators[entry.key]!(value),
            await accepts(() => entry.value.$1(value)),
            reason: '${entry.key} = "$value"',
          );
        }
      }
      // 上面两张表覆盖了校验器登记的全部键。
      expect({
        ...ints.keys,
        ...strings.keys,
      }, networkPrefValidators.keys.toSet());
    });

    test('网络设置值域与 setter 是同一套判据（通过 / 拒绝两边一致）', () {
      final validators = networkPrefValidators;
      expect(validators['clashmiao_mixed_port']!(1024), isTrue);
      expect(validators['clashmiao_mixed_port']!(1023), isFalse);
      expect(validators['clashmiao_mixed_port']!(65536), isFalse);
      expect(validators['clashmiao_mixed_port']!('1024'), isFalse);
      expect(validators['clashmiao_mtu']!(1), isTrue);
      expect(validators['clashmiao_mtu']!(0), isFalse);
      expect(validators['clashmiao_url_test_interval_seconds']!(60), isTrue);
      expect(validators['clashmiao_url_test_interval_seconds']!(3601), isFalse);
      expect(validators['clashmiao_tls_fragment_size']!('10-30'), isTrue);
      expect(validators['clashmiao_tls_fragment_size']!(' '), isFalse);
      expect(validators['clashmiao_region']!('cn'), isTrue);
      expect(validators['clashmiao_region']!('xx'), isFalse);
      expect(validators['clashmiao_remote_dns_domain_strategy']!(''), isTrue);
      // 所有带校验器的键都已登记为 include（不会对机密 / 排除键白费校验）。
      for (final key in validators.keys) {
        expect(PrefRegistry.lookup(key)?.isIncluded, isTrue, reason: key);
      }
    });
  });
}
