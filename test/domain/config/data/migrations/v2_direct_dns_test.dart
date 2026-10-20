import 'dart:convert';

import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/data/migrations/v2_direct_dns.dart';
import 'package:clashmiao/domain/config/model/dns_defaults.dart';
import 'package:clashmiao/domain/profile/data/migrations/v1_profiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/crashable_prefs.dart';

const _key = kDirectDnsAddressPrefKey;
const _backup = kMigrationBackupV1DirectDnsKey;

Future<SharedPreferences> _seed(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(Map.of(initial));
  return SharedPreferences.getInstance();
}

Map<String, Object?> _snapshot(SharedPreferences p) => {
  for (final k in p.getKeys()) k: p.get(k),
};

Future<MigrationReport> _run(SharedPreferences prefs) =>
    StorageMigrator(migrations: [profilesV1Migration(), directDnsV2Migration()])
        .run(prefs);

/// 旧版本（schema 1）里地区选择顺带写下的直连 DNS，外加一个无关的网络设置。
Map<String, Object> _v1({Object? direct = '1.1.1.1'}) => {
  kStorageSchemaKey: 1,
  'clashmiao_mixed_port': 2090,
  'clashmiao_region': 'other',
  if (direct != null) _key: direct,
};

void main() {
  test('是第 2 步；偏好键与网络设置读取的是同一个键', () async {
    expect(directDnsV2Migration().toVersion, 2);
    final prefs = await _seed({_key: '9.9.9.9'});
    expect(NetworkSettingsNotifier(prefs).state.directDnsAddress, '9.9.9.9');
  });

  group('v1 → v2 夹具', () {
    test('旧版本自动写入的 1.1.1.1：删掉改回跟随默认值，原值备份，schema 推进到 2', () async {
      final prefs = await _seed(_v1());
      final report = await _run(prefs);

      expect(report.outcome, MigrationOutcome.migrated);
      expect(report.fromSchema, 1);
      expect(prefs.getInt(kStorageSchemaKey), 2);
      expect(prefs.containsKey(_key), isFalse);
      expect(jsonDecode(prefs.getString(_backup)!), {_key: '1.1.1.1'});
      expect(
        NetworkSettingsNotifier(prefs).state.directDnsAddress,
        kDefaultDirectDnsAddress,
      );
      expect(prefs.getInt('clashmiao_mixed_port'), 2090, reason: '别的设置不动');
      expect(prefs.getString('clashmiao_region'), 'other');
    });

    test('从 schema 0 一路迁上来同样生效', () async {
      final prefs = await _seed({_key: '1.1.1.1'});
      final report = await _run(prefs);
      expect(report.toSchema, 2);
      expect(prefs.containsKey(_key), isFalse);
    });

    for (final custom in [
      '8.8.8.8',
      '119.29.29.29',
      '223.5.5.5',
      ' 1.1.1.1',
      '1.1.1.1 ',
      'udp://1.1.1.1',
      'https://1.1.1.1/dns-query',
      'tls://1.1.1.1',
    ]) {
      test('用户自定义的值原样保留：「$custom」', () async {
        final prefs = await _seed(_v1(direct: custom));
        await _run(prefs);
        expect(prefs.getString(_key), custom);
        expect(prefs.containsKey(_backup), isFalse, reason: '没改就不造备份');
        expect(prefs.getInt(kStorageSchemaKey), 2);
      });
    }

    test('没存过这项：只推进 schema，不写别的键', () async {
      final inner = await _seed(_v1(direct: null));
      final prefs = CrashablePrefs(inner);
      await _run(prefs);
      expect(prefs.attempts, [kStorageSchemaKey]);
    });

    test('存了错误类型（不是字符串）：当作看不懂，原样保留', () async {
      final prefs = await _seed(_v1(direct: 42));
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.migrated);
      expect(prefs.get(_key), 42);
    });

    test('备份键已存在：不覆盖', () async {
      final prefs = await _seed({..._v1(), _backup: 'earlier'});
      await _run(prefs);
      expect(prefs.getString(_backup), 'earlier');
      expect(prefs.containsKey(_key), isFalse);
    });
  });

  group('可重跑', () {
    test('步骤本身跑两遍结果相同', () async {
      final prefs = await _seed(_v1());
      expect(await migrateDirectDnsToV2(prefs), isTrue);
      final once = _snapshot(prefs);
      expect(await migrateDirectDnsToV2(prefs), isTrue);
      expect(_snapshot(prefs), once);
    });

    test('跑完再跑：第二次是 upToDate，没有任何写入', () async {
      final inner = await _seed(_v1());
      await _run(inner);
      final prefs = CrashablePrefs(inner);
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.upToDate);
      expect(prefs.attempts, isEmpty);
    });

    test('在每一个写入点之后中断：schema 不推进，重跑得到与一次跑完相同的结果', () async {
      final refInner = await _seed(_v1());
      final counting = CrashablePrefs(refInner);
      await _run(counting);
      final total = counting.applied;
      expect(total, 3, reason: '备份、删除、schema');
      final expected = _snapshot(refInner);

      for (var n = 0; n < total; n++) {
        final inner = await _seed(_v1());
        final first = await _run(CrashablePrefs(inner, allowedWrites: n));
        expect(first.outcome, MigrationOutcome.failed, reason: 'n=$n');
        expect(inner.getInt(kStorageSchemaKey), 1, reason: 'n=$n');
        // 中间态读取照常：要么还是旧值，要么已跟随默认。
        expect(
          NetworkSettingsNotifier(inner).state.directDnsAddress,
          anyOf('1.1.1.1', kDefaultDirectDnsAddress),
        );

        final second = await _run(inner);
        expect(second.outcome, MigrationOutcome.migrated, reason: 'n=$n 重跑');
        expect(_snapshot(inner), expected, reason: 'n=$n：重跑后与一次跑完一致');
      }
    });
  });
}
