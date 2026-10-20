import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../support/restore_harness.dart';

Map<String, dynamic> _profile(String id) => {
  'id': id,
  'name': 'backup-$id',
  'url': 'https://example.com/$id',
  'lastUpdate': null,
  'updateInterval': 1,
  'subInfo': null,
  'customUserAgent': null,
  'rev': 1,
};

/// 备份：a、b、c 都带配置。本机原本只有 a 带配置，b 在列表里但没有配置文件——
/// 所以恢复到快照时 b.json 属于「只删配置」，a.json 属于「替换」，c 整条被删。
final _backup = jsonEncode({
  'version': 2,
  'profiles': [_profile('a'), _profile('b'), _profile('c')],
  'activeProfileId': 'c',
  'profileConfigs': {
    'a': sampleConfig('backup-a'),
    'b': sampleConfig('backup-b'),
    'c': sampleConfig('backup-c'),
  },
  'preferences': {'clashmiao_mixed_port': 3000},
});

/// 不变式（spec §10.4，修复轮 4 裁定）：恢复标记与内存线索只有在磁盘上的配置文件
/// 集合**证明**与快照一致时才能清除——证明 = 再也没有之后会增删可见 `<id>.json`
/// 的残留（`.undo` 可能被还原、`.del` 是没删完的删除；`.staging` 只会被删）。
///
/// 逐个枚举残留种类 × 故障点：故障一直在时恢复怎么结局都行，但只要标记被清了，
/// 磁盘上就不能有 `.undo` / `.del`，可见配置必须已经与导入前一致；故障消失后
/// 重试收敛；再重启仍精确一致。
void main() {
  late RestoreHarness h;
  tearDown(() async => h.dispose());

  /// 被杀的恢复现场里再种下的残留（模拟更早一次没清干净的进程留下的）。
  final kinds = <String, void Function(String dir)>{
    '.staging': (dir) {
      File(p.join(dir, 'a.cafe.staging')).writeAsStringSync('half-written');
    },
    '.undo（替换：a 的旧文件已移走、新文件没装上）': (dir) {
      File(p.join(dir, 'a.json')).deleteSync();
      File(
        p.join(dir, 'a.json.cafe.undo'),
      ).writeAsStringSync(sampleConfig('stale-a'));
    },
    '.undo（只删配置：b 仍在列表，b.json 移走后没能改名 .del / 删除）': (dir) {
      File(p.join(dir, 'b.json')).renameSync(p.join(dir, 'b.json.cafe.undo'));
    },
    '.del（只删配置：b.json 已改名 .del、没删掉）': (dir) {
      File(p.join(dir, 'b.json')).renameSync(p.join(dir, 'b.json.cafe.del'));
    },
  };

  const faults = ['rename', 'delete', 'restore-rename'];

  for (final kind in kinds.entries) {
    for (final fault in faults) {
      test('${kind.key} × $fault 失败', () async {
        h = await RestoreHarness.create(
          initialPrefs: {'clashmiao_mixed_port': 2080},
        );
        await h.seed('a', active: true, config: sampleConfig('local-a'));
        await h.seed('b');
        File(h.store.configFilePath('b')).deleteSync();
        final before = await h.state();
        final beforeConfigs = Map<String, Object?>.from(
          before['files']! as Map,
        );
        expect(h.strayFiles(), isEmpty);

        // ── 恢复在「全部应用完、标记还没清」时被杀 ──
        final killed = Completer<void>();
        final never = Completer<void>();
        h.prefs.beforeWrite = (op, key) async {
          if (op == 'remove' && key == kRestoreMarkerKey) {
            if (!killed.isCompleted) killed.complete();
            await never.future;
          }
        };
        unawaited(
          h.engine
              .restore(h.engine.prepare(_backup))
              .then<void>((_) {}, onError: (_) {}),
        );
        await killed.future;
        h.prefs.beforeWrite = null;
        kind.value(h.store.profilesDirPath);

        // ── 新进程，文件操作带持续故障 ──
        var faulty = true;
        final store = ProfileStore(
          prefs: h.real,
          configDir: h.tmp,
          deleteFile: (f) async {
            if (faulty && fault == 'delete') {
              throw FileSystemException('注入', f.path);
            }
            await f.delete();
          },
          renameFile: (f, to) async {
            final restore = f.path.endsWith('.undo') && to.endsWith('.json');
            if (faulty &&
                ((fault == 'rename' && to.endsWith('.del')) ||
                    (fault == 'restore-rename' && restore))) {
              throw FileSystemException('注入', f.path);
            }
            return f.rename(to);
          },
        );
        final engine = BackupEngine(
          store: store,
          prefs: h.real,
          backupsDir: h.backupsDir,
        );

        List<String> resurrectingOrRemoving() => [
          for (final n in h.strayFiles())
            if (n.endsWith('.undo') || n.endsWith('.del')) n,
        ];
        Map<String, Object?> visibleConfigs() => {
          for (final e in h.allProfileFiles().entries)
            if (e.key.endsWith('.json')) e.key: e.value,
        };

        void expectInvariant(RecoveryOutcome outcome) {
          expect(outcome, isNot(RecoveryOutcome.unrecoverable));
          final markerKept = h.real.containsKey(kRestoreMarkerKey);
          if (!markerKept) {
            expect(outcome, isNot(RecoveryOutcome.failed));
            expect(
              resurrectingOrRemoving(),
              isEmpty,
              reason: '标记已清，却还有会改变可见配置集合的残留',
            );
            expect(visibleConfigs(), beforeConfigs);
            expect(engine.hasRecoveryClue, isFalse);
          }
          if (resurrectingOrRemoving().isNotEmpty) {
            expect(outcome, RecoveryOutcome.failed);
            expect(markerKept, isTrue);
            expect(engine.hasRecoveryClue, isTrue);
          }
        }

        // 故障一直在：试两次，每次都守住不变式。
        final first = await engine.recoverInterrupted();
        expectInvariant(first);
        final second = await engine.recoverInterrupted();
        expectInvariant(second);

        // 故障消失：同一进程里重试收敛。
        faulty = false;
        final retry = await engine.recoverInterrupted();
        expect(
          retry,
          second == RecoveryOutcome.failed
              ? RecoveryOutcome.recovered
              : RecoveryOutcome.none,
        );
        expectInvariant(retry);
        expect(h.real.containsKey(kRestoreMarkerKey), isFalse);

        // 再重启：启动清理（含暂存）做完、什么都不复活，状态与导入前完全一致。
        final restarted = h.restartedStore();
        expect((await restarted.cleanupResidue()).isComplete, isTrue);
        expect(h.strayFiles(), isEmpty);
        expect(await h.state(via: h.restartedStore()), before);
        expect(
          await BackupEngine(
            store: restarted,
            prefs: h.real,
            backupsDir: h.backupsDir,
          ).recoverInterrupted(),
          RecoveryOutcome.none,
        );
      });
    }
  }

  test('替换留下的 .undo 删不掉（提交只把它当无害孤儿、不报告）：最后的核对拦住，不清标记', () async {
    h = await RestoreHarness.create(
      initialPrefs: {'clashmiao_mixed_port': 2080},
    );
    await h.seed('a', active: true, config: sampleConfig('local-a'));
    final before = await h.state();
    final killed = Completer<void>();
    final never = Completer<void>();
    h.prefs.beforeWrite = (op, key) async {
      if (op == 'remove' && key == kRestoreMarkerKey) {
        if (!killed.isCompleted) killed.complete();
        await never.future;
      }
    };
    final onlyA = jsonEncode({
      'version': 2,
      'profiles': [_profile('a')],
      'activeProfileId': 'a',
      'profileConfigs': {'a': sampleConfig('backup-a')},
      'preferences': {'clashmiao_mixed_port': 3000},
    });
    unawaited(
      h.engine
          .restore(h.engine.prepare(onlyA))
          .then<void>((_) {}, onError: (_) {}),
    );
    await killed.future;
    h.prefs.beforeWrite = null;

    var faulty = true;
    final engine = BackupEngine(
      store: ProfileStore(
        prefs: h.real,
        configDir: h.tmp,
        deleteFile: (f) async =>
            faulty ? throw FileSystemException('注入', f.path) : f.delete(),
      ),
      prefs: h.real,
      backupsDir: h.backupsDir,
    );
    // 回到快照只需把 a.json 换回 local-a：没有「只删配置」，提交不会报告任何东西，
    // 被换下的旧文件留成 `.undo`。
    expect(await engine.recoverInterrupted(), RecoveryOutcome.failed);
    expect(h.real.containsKey(kRestoreMarkerKey), isTrue);
    expect(h.strayFiles().where((n) => n.endsWith('.undo')), isNotEmpty);

    faulty = false;
    expect(await engine.recoverInterrupted(), RecoveryOutcome.recovered);
    expect(h.strayFiles(), isEmpty);
    expect(await h.state(via: h.restartedStore()), before);
  });
}
