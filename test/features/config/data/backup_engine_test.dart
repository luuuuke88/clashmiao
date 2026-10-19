import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../support/gate_adapter.dart';
import '../../../support/restore_harness.dart';

const _markerKey = kRestoreMarkerKey;

/// 本机原有的数据：两条订阅（a 激活）、各自的手选节点、一批偏好——
/// 含机密、运行时键、WARP 开关。
Future<RestoreHarness> _seededHarness({
  Map<String, Object> extraPrefs = const {},
  int keepSnapshots = 3,
}) async {
  final h = await RestoreHarness.create(
    keepSnapshots: keepSnapshots,
    initialPrefs: {
      'clashmiao_mixed_port': 2080,
      'clashmiao_block_ads': false,
      'clashmiao_analytics_enabled': false,
      'clashmiao_enable_warp': true,
      'clashmiao_warp_access_token': 'local-token',
      'clashmiao_warp_license_key': 'local-license',
      'started_by_user': true,
      'update_latest_tag': 'v9',
      'theme_mode': 'dark',
      'per_app_proxy_mode': 'include',
      'per_app_proxy_include_list': ['com.local.a'],
      'proxy_selection_a': '{"proxy":"node-a"}',
      'proxy_delays_a': '{"node-a":10}',
      'proxy_selection_b': '{"proxy":"node-b"}',
      ...extraPrefs,
    },
  );
  await h.seed('a', active: true, config: sampleConfig('local-a'));
  await h.seed('b', config: sampleConfig('local-b'));
  return h;
}

Map<String, dynamic> _profile(String id, {String? name, String? url}) => {
  'id': id,
  'name': name ?? 'backup-$id',
  'url': url ?? 'https://example.com/$id',
  'lastUpdate': null,
  'updateInterval': 1,
  'subInfo': null,
  'customUserAgent': null,
  'rev': 1,
};

/// 备份里：b（新内容、新名字）、c；激活 c；偏好里 region 是本机没有的键。
String _backup({Map<String, Object>? prefs}) => jsonEncode({
  'version': 2,
  'schema': 1,
  'createdAt': 1,
  'profiles': [_profile('b', name: 'from-backup'), _profile('c')],
  'activeProfileId': 'c',
  'profileConfigs': {
    'b': sampleConfig('backup-b'),
    'c': sampleConfig('backup-c'),
  },
  'preferences':
      prefs ??
      {
        'clashmiao_mixed_port': 3000,
        'clashmiao_block_ads': true,
        'clashmiao_region': 'cn',
        'clashmiao_enable_warp': true,
        'theme_mode': 'light',
        'clashmiao_warp_access_token': 'attacker-token',
        'clashmiao_analytics_enabled': true,
      },
});

void main() {
  late RestoreHarness h;
  tearDown(() async => h.dispose());

  group('导出', () {
    test('只导出 include 键：机密、运行时、未登记的键、订阅 inc 都不在里面', () async {
      h = await _seededHarness(extraPrefs: {'totally_unknown': 'x'});
      final bundle = await h.engine.exportBundle();

      expect(
        bundle.preferences.keys,
        unorderedEquals([
          'clashmiao_mixed_port',
          'clashmiao_block_ads',
          'clashmiao_enable_warp',
          'theme_mode',
          'per_app_proxy_mode',
          'per_app_proxy_include_list',
        ]),
      );
      final text = BackupCodec.encode(bundle);
      expect(text, isNot(contains('local-token')));
      expect(text, isNot(contains('local-license')));
      expect(text, isNot(contains('analytics')), reason: '同意与否是每台设备各自的决定');
      expect(text, isNot(contains('started_by_user')));
      expect(text, isNot(contains('update_latest_tag')));
      expect(text, isNot(contains('proxy_selection_')));
      expect(text, isNot(contains('"inc"')));
      expect(text, isNot(contains('"active"')));

      expect(bundle.activeProfileId, 'a');
      expect([for (final j in bundle.profiles) j['id']], ['a', 'b']);
      expect(bundle.profileConfigs.keys, {'a', 'b'});
      expect(bundle.schema, kCurrentStorageSchema);
      expect((jsonDecode(text) as Map<String, dynamic>)['version'], 2);
    });

    test('导出再导入（信任之外的常规校验）能还原出同样的订阅与偏好', () async {
      h = await _seededHarness();
      final bundle = await h.engine.exportBundle();
      final plan = h.engine.prepare(BackupCodec.encode(bundle));
      expect([for (final e in plan.profiles) e.id], ['a', 'b']);
      expect(plan.activeId, 'a');
      expect(plan.configs['a'], sampleConfig('local-a'));
      // enable_warp=true 在常规导入里被压成 false，其余偏好原样。
      expect(plan.prefs['clashmiao_mixed_port'], 2080);
      expect(plan.prefs['clashmiao_enable_warp'], false);
      expect(plan.warpDisabled, isTrue);
      expect(plan.skippedPrefKeys, isEmpty);
    });

    test('附属偏好只有快照才带（includeAux），用户导出的备份没有', () async {
      h = await _seededHarness();
      expect((await h.engine.exportBundle()).auxPreferences, isEmpty);
      final aux = (await h.engine.exportBundle(
        includeAux: true,
      )).auxPreferences;
      expect(aux.keys, {
        'proxy_selection_a',
        'proxy_delays_a',
        'proxy_selection_b',
      });
    });

    test('导出是一致快照：与进行中的提交串行，看不到「文件已换、列表未写」的中间态', () async {
      h = await _seededHarness();
      final listWriteReached = Completer<void>();
      final releaseListWrite = Completer<void>();
      h.prefs.beforeWrite = (op, key) async {
        if (key == ProfileStore.profilesKey) {
          listWriteReached.complete();
          await releaseListWrite.future;
        }
      };

      // 一次把 a 的配置换成新内容并改名的提交：配置文件先 rename 到位，
      // 然后在写列表键这一步被卡住。
      final staging = await h.store.createStagingFile('a');
      await staging.writeAsString(sampleConfig('NEW-a'));
      final commit = h.store.commit<void>((view) {
        final a = view.find('a')!;
        return Plan<void>(
          profiles: [
            for (final e in view.profiles)
              e.id == 'a' ? a.copyWith(name: 'renamed', rev: a.rev + 1) : e,
          ],
          staged: [StagedConfig('a', staging)],
        );
      });
      await listWriteReached.future;
      expect(
        File(h.store.configFilePath('a')).readAsStringSync(),
        sampleConfig('NEW-a'),
        reason: '前提：文件已经换了，列表还没写',
      );

      var exported = false;
      final export = h.engine.exportBundle().then((b) {
        exported = true;
        return b;
      });
      await pumpEventQueue();
      expect(exported, isFalse, reason: '导出必须等提交结束，不能读到中间态');

      h.prefs.beforeWrite = null;
      releaseListWrite.complete();
      await commit;
      final bundle = await export;
      final a = bundle.profiles.firstWhere((j) => j['id'] == 'a');
      expect(a['name'], 'renamed');
      expect(bundle.profileConfigs['a'], sampleConfig('NEW-a'));
    });
  });

  group('恢复（成功路径）', () {
    test('整表替换：备份里的订阅与配置、激活、偏好落地；不在备份中的本机订阅及附属键被移除', () async {
      h = await _seededHarness();
      final plan = h.engine.prepare(_backup());
      expect([for (final e in h.engine.removedBy(plan)) e.id], ['a']);

      final report = await h.engine.restore(plan);

      expect(h.ids, ['b', 'c']);
      expect(h.store.readActiveId(), 'c');
      expect(File(h.store.configFilePath('a')).existsSync(), isFalse);
      expect(
        File(h.store.configFilePath('b')).readAsStringSync(),
        sampleConfig('backup-b'),
      );
      expect(
        File(h.store.configFilePath('c')).readAsStringSync(),
        sampleConfig('backup-c'),
      );
      expect(h.store.find('b')!.name, 'from-backup');
      // a 的附属键随订阅被删；b 的保留。
      expect(h.real.containsKey('proxy_selection_a'), isFalse);
      expect(h.real.containsKey('proxy_delays_a'), isFalse);
      expect(h.real.getString('proxy_selection_b'), '{"proxy":"node-b"}');

      // 偏好：备份里合法的键覆盖本机；机密永远不被备份覆盖；WARP 压成 false。
      expect(h.real.getInt('clashmiao_mixed_port'), 3000);
      expect(h.real.getBool('clashmiao_block_ads'), true);
      expect(h.real.getString('clashmiao_region'), 'cn');
      expect(h.real.getString('theme_mode'), 'light');
      expect(h.real.getBool('clashmiao_enable_warp'), false);
      expect(h.real.getString('clashmiao_warp_access_token'), 'local-token');
      expect(h.real.getString('clashmiao_warp_license_key'), 'local-license');
      expect(h.real.getBool('started_by_user'), true);
      // 备份里没带的 include 键保持本机值（导入不是整体清空偏好）。
      expect(h.real.getString('per_app_proxy_mode'), 'include');

      // 标记已清，快照保留。
      expect(h.real.containsKey(_markerKey), isFalse);
      expect(h.snapshots(), hasLength(1));
      expect(report.snapshotPath, h.snapshots().single.path);
      expect(report.profilesImported, 2);
      expect(report.profilesRemoved, 1);
      expect(report.profilesDropped, 0);
      expect(report.prefsImported, 5);
      expect(
        report.prefsSkipped,
        2,
        reason: '备份里的 WARP 令牌（机密）与 analytics（每设备各自决定）被忽略',
      );
      expect(
        h.real.getBool('clashmiao_analytics_enabled'),
        false,
        reason: '导入不得替用户改数据分析同意',
      );
      expect(report.warpDisabled, isTrue);
      expect(report.refreshQueued, 0);
      expect(h.strayFiles(), isEmpty);
    });

    test('导入的订阅换发了新的本机代际，旧代际的写入者被拒', () async {
      h = await _seededHarness();
      final oldIncOfB = h.store.find('b')!.inc;
      await h.engine.restore(h.engine.prepare(_backup()));
      final newIncOfB = h.store.find('b')!.inc;
      expect(newIncOfB, isNot(oldIncOfB));
      expect(newIncOfB, isNotEmpty);
      expect(
        await h.store.writeAux('b', oldIncOfB, 'proxy_selection_b', '{}'),
        isFalse,
      );
      expect(
        await h.store.writeAux('b', newIncOfB, 'proxy_selection_b', '{}'),
        isTrue,
      );
    });

    test('刷新进行中恢复了同一个 id：旧刷新的结果不落地（代际已换）', () async {
      h = await _seededHarness();
      final gate = GateAdapter();
      final repo = ProfileRepository(
        dio: Dio()..httpClientAdapter = gate,
        configDir: h.tmp,
        prefs: h.prefs,
        boxService: const StubBoxService(),
        store: h.store,
      );
      final hold = gate.hold('https://example.com/b');
      final refresh = repo.update('b');
      // 先接住异常，免得它在放行前被判成「未处理」。
      final outcome = refresh.then<Object?>((v) => v, onError: (Object e) => e);
      await gate.waitForRequests(1);

      await h.engine.restore(h.engine.prepare(_backup()));
      hold.complete();

      expect(await outcome, isA<ProfileUpdateStaleException>());
      expect(
        File(h.store.configFilePath('b')).readAsStringSync(),
        sampleConfig('backup-b'),
        reason: '旧刷新下载的内容不能覆盖刚恢复的配置',
      );
      expect(h.store.find('b')!.name, 'from-backup');
      expect(h.strayFiles(), isEmpty);
    });

    test('远程订阅缺配置：记入补拉清单，本机原有的同 id 配置文件保留', () async {
      h = await _seededHarness();
      final raw = jsonEncode({
        'version': 2,
        'profiles': [_profile('b')],
        'profileConfigs': <String, String>{},
        'preferences': <String, Object>{},
      });
      final plan = h.engine.prepare(raw);
      final report = await h.engine.restore(plan);
      expect(report.refreshQueued, 1);
      expect(plan.needsFetch, ['b']);
      expect(
        File(h.store.configFilePath('b')).readAsStringSync(),
        sampleConfig('local-b'),
      );
    });

    test('备份是空订阅列表：本机订阅全部移除，激活清空', () async {
      h = await _seededHarness();
      final raw = jsonEncode({
        'version': 2,
        'profiles': <Object>[],
        'preferences': <String, Object>{},
      });
      await h.engine.restore(h.engine.prepare(raw));
      expect(h.ids, isEmpty);
      expect(h.store.readActiveId(), isNull);
      expect(h.real.containsKey(ProfileStore.activeProfileKey), isFalse);
    });

    test('只保留最近 3 份恢复前快照（最新的留下，旧的删掉）', () async {
      h = await _seededHarness();
      final paths = <String>[];
      for (var i = 0; i < 5; i++) {
        final report = await h.engine.restore(h.engine.prepare(_backup()));
        paths.add(report.snapshotPath);
      }
      expect(paths.toSet(), hasLength(5), reason: '每次都是新文件');
      expect(h.snapshots().map((f) => f.path), paths.sublist(2));
      for (final old in paths.sublist(0, 2)) {
        expect(File(old).existsSync(), isFalse);
      }
    });

    test('存储只读（schema 高于本机）时拒绝导入，什么都不动', () async {
      h = await _seededHarness();
      // 降级运行：数据由更新版本写过。
      await h.real.setInt(kStorageSchemaKey, kCurrentStorageSchema + 1);
      final before = await h.state();
      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.readOnly,
          ),
        ),
      );
      expect(await h.state(), before);
      expect(h.snapshots(), isEmpty);
    });
  });

  group('精确还原配置文件集合', () {
    test('订阅原本没有配置文件：导入装进来的文件在回滚后被清掉（逐个文件比较）', () async {
      h = await _seededHarness();
      File(h.store.configFilePath('b')).deleteSync(); // b 在列表里，但没有配置文件
      final before = await h.state();
      expect(before['files'], isNot(contains('b.json')));
      var armed = true;
      h.prefs.failWhen = (op, key) {
        if (armed && op == 'set' && key == 'clashmiao_mixed_port') {
          armed = false;
          return true;
        }
        return false;
      };

      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.rolledBack,
          ),
        ),
      );

      expect(File(h.store.configFilePath('b')).existsSync(), isFalse);
      expect(File(h.store.configFilePath('c')).existsSync(), isFalse);
      expect(await h.state(via: h.restartedStore()), before);
    });

    test('进程被杀（c.json 已装进来、列表还没写）：重启恢复后文件集合与导入前完全一致', () async {
      h = await _seededHarness();
      File(h.store.configFilePath('b')).deleteSync();
      final before = await h.state();
      final killed = Completer<void>();
      final never = Completer<void>();
      var firstMarkerWrite = true;
      h.prefs.beforeWrite = (op, key) async {
        if (key == _markerKey && op == 'set' && firstMarkerWrite) {
          firstMarkerWrite = false;
          return;
        }
        if (op == 'set' && key == ProfileStore.profilesKey) {
          if (!killed.isCompleted) killed.complete();
          await never.future;
        }
      };
      unawaited(
        h.engine
            .restore(h.engine.prepare(_backup()))
            .then<void>((_) {}, onError: (_) {}),
      );
      await killed.future;
      // 被杀的现场：b.json、c.json 都已装进来，而列表还是旧的。
      expect(File(h.store.configFilePath('c')).existsSync(), isTrue);
      expect(File(h.store.configFilePath('b')).existsSync(), isTrue);

      final restarted = BackupEngine(
        store: h.restartedStore(),
        prefs: h.real,
        backupsDir: h.backupsDir,
      );
      expect(await restarted.recoverInterrupted(), RecoveryOutcome.recovered);
      expect(await h.state(via: h.restartedStore()), before);
    });
  });

  group('快照读取失败 → 中止导入', () {
    BackupEngine engineReading(Future<String> Function(File file) reader) =>
        BackupEngine(
          store: h.store,
          prefs: h.prefs,
          backupsDir: h.backupsDir,
          readConfigFile: reader,
        );

    test('已存在的配置文件读不出来：导入在任何破坏性步骤之前中止，导出同样失败', () async {
      h = await _seededHarness();
      final before = await h.state();
      final engine = engineReading((file) async {
        if (p.basename(file.path) == 'b.json') {
          throw const FileSystemException('permission denied');
        }
        return file.readAsString();
      });

      await expectLater(
        engine.restore(engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.snapshotFailed,
          ),
        ),
      );
      expect(await h.state(via: h.restartedStore()), before);
      expect(h.real.containsKey(_markerKey), isFalse);
      expect(h.snapshots(), isEmpty);
      expect(
        File(h.store.configFilePath('b')).readAsStringSync(),
        sampleConfig('local-b'),
        reason: '读不出来的原配置一个字节都没动',
      );
      await expectLater(
        engine.exportBundle(),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('文件确实不存在（PathNotFound）与读取失败是两回事：前者照常快照', () async {
      h = await _seededHarness();
      File(h.store.configFilePath('b')).deleteSync();
      final bundle = await h.engine.exportBundle();
      expect(bundle.profileConfigs.keys, {'a'});
      expect([for (final j in bundle.profiles) j['id']], ['a', 'b']);
    });
  });

  group('恢复流程互斥', () {
    test('一次恢复进行中，另一次（哪怕是新建的引擎实例）被拒绝，且不碰它的标记与快照', () async {
      h = await _seededHarness();
      final reached = Completer<void>();
      final release = Completer<void>();
      h.prefs.beforeWrite = (op, key) async {
        if (op == 'set' && key == 'clashmiao_mixed_port') {
          if (!reached.isCompleted) reached.complete();
          await release.future;
        }
      };
      final first = h.engine.restore(h.engine.prepare(_backup()));
      await reached.future;
      final snapshotsMidway = h.snapshots().map((f) => f.path).toList();
      final markerMidway = h.real.getString(_markerKey);
      expect(markerMidway, snapshotsMidway.single);

      // 页面每次导入都新建引擎：互斥必须跨实例。
      final other = BackupEngine(
        store: h.store,
        prefs: h.prefs,
        backupsDir: h.backupsDir,
      );
      await expectLater(
        other.restore(other.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.busy,
          ),
        ),
      );
      expect(
        await other.recoverInterrupted(),
        RecoveryOutcome.busy,
        reason: '不能把别人进行中的恢复当成「被中断的恢复」去回滚',
      );
      expect(h.real.getString(_markerKey), markerMidway);
      expect(h.snapshots().map((f) => f.path), snapshotsMidway);

      h.prefs.beforeWrite = null;
      release.complete();
      final report = await first;
      expect(report.profilesImported, 2);
      expect(h.ids, ['b', 'c']);
      expect(h.real.containsKey(_markerKey), isFalse);

      // 第一次结束后互斥释放：再导入一次可以正常进行。
      await other.restore(other.prepare(_backup()));
      expect(h.ids, ['b', 'c']);
    });
  });

  group('恢复线索（标记）失败路径', () {
    test('清标记失败 + 回滚也失败：缓存里的标记没了，但本进程仍记着「恢复待处理」，新导入被挡住', () async {
      h = await _seededHarness();
      final before = await h.state();
      var snapshotMarkerWritten = false;
      h.prefs.failWhen = (op, key) => op == 'remove' && key == _markerKey;
      h.prefs.beforeWrite = (op, key) async {
        if (op == 'set' && key == _markerKey) {
          if (!snapshotMarkerWritten) {
            snapshotMarkerWritten = true; // 写快照标记那一次放行
            return;
          }
          throw StateError('platform channel gone'); // 之后补写标记也失败
        }
      };

      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.notRolledBack,
          ),
        ),
      );
      expect(
        h.real.containsKey(_markerKey),
        isFalse,
        reason: '前提：平台缓存里的标记确实没了，只剩内存里的记录',
      );
      final stuck = await h.state();
      expect(h.snapshots(), hasLength(1));

      // 新建的引擎实例（页面每次都新建）也要被挡住：线索挂在 Store 上。
      final other = BackupEngine(
        store: h.store,
        prefs: h.prefs,
        backupsDir: h.backupsDir,
      );
      await expectLater(
        other.restore(other.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.unresolvedPrevious,
          ),
        ),
      );
      expect(await other.recoverInterrupted(), RecoveryOutcome.failed);
      expect(await h.state(), stuck, reason: '被挡住的导入什么都不能改');
      expect(h.snapshots(), hasLength(1), reason: '也不能覆盖恢复线索（不写新快照）');

      // 问题消失：先自动了结上一次，再正常导入。
      h.prefs.failWhen = null;
      h.prefs.beforeWrite = null;
      final report = await other.restore(other.prepare(_backup()));
      expect(report.profilesImported, 2);
      expect(h.ids, ['b', 'c']);
      expect(h.real.containsKey(_markerKey), isFalse);
      expect(await other.recoverInterrupted(), RecoveryOutcome.none);
      // 了结上一次时回到的就是导入前的状态（订阅 a、b 的配置再被这次导入替换，
      // 这里只验证线索已清、没有残留）。
      expect(h.strayFiles(), isEmpty);
      expect(before['active'], 'a');
    });
  });

  group('恢复前快照', () {
    test('快照写在标记之前、内容就是导入前状态；快照带附属偏好', () async {
      h = await _seededHarness();
      final markerAtPref = Completer<String?>();
      h.prefs.beforeWrite = (op, key) async {
        if (key == 'clashmiao_mixed_port' && !markerAtPref.isCompleted) {
          markerAtPref.complete(h.real.getString(_markerKey));
        }
      };
      await h.engine.restore(h.engine.prepare(_backup()));
      // 应用偏好时标记已经在了，并且指向快照文件。
      final marker = await markerAtPref.future;
      expect(marker, h.snapshots().single.path);
      final snap = jsonDecode(h.snapshots().single.readAsStringSync()) as Map;
      expect((snap['profiles'] as List).map((e) => (e as Map)['id']), [
        'a',
        'b',
      ]);
      expect(snap['activeProfileId'], 'a');
      expect(
        (snap['auxPreferences'] as Map).keys,
        containsAll(['proxy_selection_a', 'proxy_delays_a']),
      );
    });

    test('快照目录建不了：什么都没改，没有标记', () async {
      h = await _seededHarness();
      // 在 backups 的位置放一个文件，目录就建不出来。
      File(h.backupsDir.path).writeAsStringSync('blocker');
      final before = await h.state();
      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.snapshotFailed,
          ),
        ),
      );
      expect(await h.state(), before);
      expect(h.real.containsKey(_markerKey), isFalse);
    });

    test('标记写不进去：快照文件被撤销，什么都没改', () async {
      h = await _seededHarness();
      h.prefs.failWhen = (op, key) => key == _markerKey;
      final before = await h.state();
      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.snapshotFailed,
          ),
        ),
      );
      h.prefs.failWhen = null;
      // 平台先改内存缓存再返回 false：失败路径自己必须把缓存里的标记撤销，
      // 不能留下一个指向已删快照的标记。
      expect(h.real.containsKey(_markerKey), isFalse);
      expect(await h.state(), before);
      expect(h.snapshots(), isEmpty);
    });
  });

  group('中途失败 → 用快照回到恢复前状态', () {
    /// 让第一次命中的写入失败（之后恢复正常，回滚写入不受影响）。
    void failOnce(RestoreHarness h, bool Function(String op, String key) when) {
      var armed = true;
      h.prefs.failWhen = (op, key) {
        if (armed && when(op, key)) {
          armed = false;
          return true;
        }
        return false;
      };
    }

    final failurePoints = <String, bool Function(String, String)>{
      '写第一个偏好失败': (op, key) => op == 'set' && key == 'clashmiao_mixed_port',
      '写到偏好中途失败（此前已写入本机没有的键）': (op, key) => op == 'set' && key == 'theme_mode',
      '写订阅列表键失败': (op, key) => op == 'set' && key == ProfileStore.profilesKey,
      '写激活键失败': (op, key) =>
          op == 'set' && key == ProfileStore.activeProfileKey,
      '清除恢复标记失败（成功的恢复不能留着标记）': (op, key) => op == 'remove' && key == _markerKey,
    };

    for (final entry in failurePoints.entries) {
      test(entry.key, () async {
        h = await _seededHarness();
        final before = await h.state();
        failOnce(h, entry.value);

        await expectLater(
          h.engine.restore(h.engine.prepare(_backup())),
          throwsA(
            isA<RestoreFailure>().having(
              (e) => e.kind,
              'kind',
              RestoreFailureKind.rolledBack,
            ),
          ),
        );

        // 订阅、激活、配置文件、全部偏好（含机密、WARP 开关、本机没有的键）、
        // 残留文件：与导入前逐项一致。
        expect(await h.state(), before);
        expect(h.real.containsKey('clashmiao_region'), isFalse);
        expect(h.real.getBool('clashmiao_enable_warp'), true);
        expect(h.real.containsKey(_markerKey), isFalse);
        expect(h.real.getString('proxy_selection_a'), '{"proxy":"node-a"}');
      });
    }

    test('回滚也失败：标记保留、报告 notRolledBack；下次启动自动回到恢复前', () async {
      h = await _seededHarness();
      final before = await h.state();
      // 偏好写入一直失败：导入失败，回滚（同样要写偏好）也失败。
      h.prefs.failWhen = (op, key) => key == 'clashmiao_mixed_port';

      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.notRolledBack,
          ),
        ),
      );
      expect(h.real.containsKey(_markerKey), isTrue, reason: '标记保留，下次启动再试');
      expect(h.ids, ['a', 'b'], reason: '订阅部分已经被回滚，只剩偏好没写成');

      // 「重启」：问题消失，启动屏障发现标记。
      h.prefs.failWhen = null;
      expect(await h.engine.recoverInterrupted(), RecoveryOutcome.recovered);
      expect(await h.state(), before);
    });

    test('上次回滚没完成时再次导入：先回到上次之前，仍失败则拒绝并不动任何东西', () async {
      h = await _seededHarness();
      h.prefs.failWhen = (op, key) => key == 'clashmiao_mixed_port';
      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(isA<RestoreFailure>()),
      );
      final stuck = await h.state();

      await expectLater(
        h.engine.restore(h.engine.prepare(_backup())),
        throwsA(
          isA<RestoreFailure>().having(
            (e) => e.kind,
            'kind',
            RestoreFailureKind.unresolvedPrevious,
          ),
        ),
      );
      expect(await h.state(), stuck);

      // 问题消失后再导入：先自动恢复上次，再正常导入。
      h.prefs.failWhen = null;
      final report = await h.engine.restore(h.engine.prepare(_backup()));
      expect(h.ids, ['b', 'c']);
      expect(h.real.containsKey(_markerKey), isFalse);
      expect(report.profilesImported, 2);
    });
  });

  group('进程被杀 → 下次启动回到恢复前', () {
    // 在应用的某一步把写入卡住（Future 永不返回）= 进程恰在那一刻被杀。
    // 然后用另一个引擎实例（新进程）检查标记并恢复。
    final killPoints = <String, bool Function(String, String)>{
      '订阅提交时（配置文件已换、列表未写）': (op, key) =>
          op == 'set' && key == ProfileStore.profilesKey,
      '偏好写到一半': (op, key) => op == 'set' && key == 'theme_mode',
      '全部应用完、标记还没清': (op, key) => op == 'remove' && key == _markerKey,
    };

    for (final entry in killPoints.entries) {
      test(entry.key, () async {
        h = await _seededHarness();
        final before = await h.state();
        final killed = Completer<void>();
        final never = Completer<void>();
        var firstMarkerWrite = true;
        h.prefs.beforeWrite = (op, key) async {
          if (key == _markerKey && op == 'set' && firstMarkerWrite) {
            firstMarkerWrite = false;
            return; // 标记要先写进去
          }
          if (entry.value(op, key)) {
            if (!killed.isCompleted) killed.complete();
            await never.future; // 永远不返回：被杀
          }
        };
        unawaited(
          h.engine
              .restore(h.engine.prepare(_backup()))
              .then<void>((_) {}, onError: (_) {}),
        );
        await killed.future;
        expect(h.real.containsKey(_markerKey), isTrue);

        // 新进程：没有任何内存状态，只有磁盘上的偏好与文件。
        final restarted = BackupEngine(
          store: ProfileStore(prefs: h.real, configDir: h.tmp),
          prefs: h.real,
          backupsDir: h.backupsDir,
        );
        expect(await restarted.recoverInterrupted(), RecoveryOutcome.recovered);
        // 新进程视角：全新 Store、只看磁盘与偏好；配置文件集合逐个比较（含 .json）。
        expect(await h.state(via: h.restartedStore()), before);
        expect(h.real.containsKey(_markerKey), isFalse);
        expect(
          File(h.store.configFilePath('c')).existsSync(),
          isFalse,
          reason: '这次恢复装进来的 c.json 不在快照里，必须被清掉',
        );
      });
    }
  });

  group('启动恢复（标记检查）', () {
    test('没有标记：什么都不做', () async {
      h = await _seededHarness();
      final before = await h.state();
      expect(await h.engine.recoverInterrupted(), RecoveryOutcome.none);
      expect(await h.state(), before);
    });

    test('标记指向的快照不存在：无法回滚，标记被清掉（不无限重试）', () async {
      h = await _seededHarness();
      await h.real.setString(_markerKey, '/gone/pre-restore-x.json');
      expect(
        await h.engine.recoverInterrupted(),
        RecoveryOutcome.unrecoverable,
      );
      expect(h.real.containsKey(_markerKey), isFalse);
    });

    test('快照损坏：无法回滚，标记被清掉，本机数据不动', () async {
      h = await _seededHarness();
      final before = await h.state();
      await h.backupsDir.create(recursive: true);
      final snap = File(p.join(h.backupsDir.path, 'pre-restore-bad.json'))
        ..writeAsStringSync('{ not json');
      await h.real.setString(_markerKey, snap.path);
      expect(
        await h.engine.recoverInterrupted(),
        RecoveryOutcome.unrecoverable,
      );
      await h.real.remove(_markerKey);
      expect(await h.state(), before);
    });

    test('标记里的目录部分过期（容器路径变了）：按文件名在本机 backups 目录里找', () async {
      h = await _seededHarness();
      final before = await h.state();
      await h.engine.restore(h.engine.prepare(_backup()));
      final snap = h.snapshots().single;
      // 模拟一次「恢复被杀」：标记还在，且记录的是旧容器下的路径。
      await h.real.setString(
        _markerKey,
        '/old/container/backups/${p.basename(snap.path)}',
      );
      expect(await h.engine.recoverInterrupted(), RecoveryOutcome.recovered);
      expect(await h.state(), before);
    });

    test('标记里的路径不能把读取引到 backups 目录之外', () async {
      h = await _seededHarness();
      final outside = File(p.join(h.tmp.path, 'outside.json'))
        ..writeAsStringSync(_backup());
      final before = await h.state();
      await h.real.setString(_markerKey, '../outside.json');
      expect(
        await h.engine.recoverInterrupted(),
        RecoveryOutcome.unrecoverable,
      );
      await h.real.remove(_markerKey);
      expect(await h.state(), before);
      expect(outside.existsSync(), isTrue);
    });
  });
}

extension on RestoreHarness {
  List<String> get ids => [for (final e in store.read()) e.id];
}
