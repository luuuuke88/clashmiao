import 'dart:io';

import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 恢复失败的原因。
enum RestoreFailureKind {
  /// 存储由更新版本写过（只读模式），不能导入。
  readOnly,

  /// 恢复前快照没能保存：什么都没改动。
  snapshotFailed,

  /// 上次恢复被中断，且这次没能先回到那次恢复之前的状态：什么都没改动。
  unresolvedPrevious,

  /// 应用中途失败，已用快照回到恢复前的状态。
  rolledBack,

  /// 应用中途失败，用快照回滚也没成功：标记保留，下次启动会再试一次。
  notRolledBack,

  /// 另一次恢复正在进行（恢复流程互斥，不排队）：什么都没改。
  busy,
}

class RestoreFailure implements Exception {
  const RestoreFailure(this.kind, {this.cause, this.snapshotPath});

  final RestoreFailureKind kind;
  final Object? cause;
  final String? snapshotPath;

  @override
  String toString() =>
      'RestoreFailure(${kind.name}, cause: $cause, snapshot: $snapshotPath)';
}

/// 启动时发现恢复标记后的处理结果。
enum RecoveryOutcome {
  /// 没有标记：上次没有中断的恢复。
  none,

  /// 已用快照回到恢复前的状态，标记已清除。
  recovered,

  /// 快照缺失 / 损坏，无法回滚；标记已清除（再试没有意义）。
  unrecoverable,

  /// 回滚过程中失败；标记保留，下次启动再试。
  failed,

  /// 另一次恢复正在进行，这次没有检查（不会去回滚别人进行中的恢复）。
  busy,
}

/// 备份的导出、校验后的恢复与恢复前快照。
///
/// 恢复流程（spec §10.4）：①调用方已用 [prepare] 完整校验；②[restore] 把当前
/// 状态用导出函数写到 `backups/pre-restore-<时间戳>.json` 并写标记键；③应用
/// （整表替换订阅、配置文件、偏好）；④成功清标记，失败用同一快照、同一应用流程
/// 回滚；⑤进程中途被杀，下次启动 [recoverInterrupted] 发现标记就用快照回滚。
class BackupEngine {
  BackupEngine({
    required this.store,
    required this.prefs,
    required this.backupsDir,
    this.extraValidators = const {},
    DateTime Function()? now,
    this.keepSnapshots = 3,
    Future<String> Function(File file)? readConfigFile,
  }) : _now = now ?? DateTime.now,
       _readConfigFile = readConfigFile ?? ((file) => file.readAsString());

  /// 读订阅配置文件的入口（测试注入读取故障用）。
  final Future<String> Function(File file) _readConfigFile;

  /// 与 [store] 绑定的进程内状态：恢复互斥与「恢复线索待处理」。
  /// 挂在 Store 上而不是引擎实例上——页面每次导入都新建引擎，互斥必须跨实例。
  static final Expando<_RestoreState> _states = Expando<_RestoreState>();
  _RestoreState get _state => _states[store] ??= _RestoreState();

  final ProfileStore store;
  final SharedPreferences prefs;
  final Directory backupsDir;

  /// 注册表之外的值域校验（网络设置那一套），见 [PrefRegistry.validate]。
  final Map<String, PrefValidator> extraValidators;
  final DateTime Function() _now;

  /// 成功后保留的恢复前快照份数。
  final int keepSnapshots;

  static const snapshotPrefix = 'pre-restore-';

  // ───────────────────────── 导出 ─────────────────────────

  /// 在 Store 锁内取一份一致快照：列表、激活 id、配置文件内容与偏好是同一时刻的。
  /// 只含 `include` 键；机密、运行时键与订阅的本机 `inc` 不导出。
  ///
  /// [includeAux] 为 true 时额外带上各订阅的附属偏好（手选节点、延迟缓存）——只有
  /// 恢复前快照这么做；用户导出的备份不含它们。
  Future<BackupBundle> exportBundle({bool includeAux = false}) {
    return store.readConsistent((view) async {
      final profiles = <Map<String, dynamic>>[];
      final configs = <String, String>{};
      for (final profile in view.profiles) {
        profiles.add(_exportProfile(profile));
        // 「文件不存在」与「读取失败」是两回事：前者就是没有配置；后者说明本机
        // 有一份读不出来的数据，绝不能当作没有——否则快照缺了它，随后的
        // 破坏性应用一旦失败就无从还原。读取失败整个导出 / 快照中止。
        try {
          configs[profile.id] = await _readConfigFile(
            File(store.configFilePath(profile.id)),
          );
        } on PathNotFoundException {
          // 确实没有这个配置文件：快照里也记为「没有」。
        }
      }
      // 快照要记下 profiles/ 里**全部**既有的配置文件，包括不属于任何列表订阅的
      // （被隔离的订阅、遗留的孤儿）：回滚只能删「这次恢复新装进来」的文件。
      final orphans = includeAux
          ? await _readOrphanConfigs({for (final p in view.profiles) p.id})
          : const <String, String>{};
      return BackupBundle(
        schema: store.schema,
        createdAt: _now().millisecondsSinceEpoch,
        profiles: profiles,
        activeProfileId: view.activeId,
        profileConfigs: configs,
        preferences: _exportPreferences(),
        auxPreferences: includeAux
            ? _exportAux([for (final p in view.profiles) p.id])
            : const {},
        orphanConfigs: orphans,
      );
    });
  }

  /// `profiles/` 里合法 `<id>.json` 中不属于 [listed] 的文件内容。读取失败照样抛
  /// （和订阅配置同一条规则：读不出来的东西不能当作没有）。
  Future<Map<String, String>> _readOrphanConfigs(Set<String> listed) async {
    final out = <String, String>{};
    final dir = Directory(store.profilesDirPath);
    if (!await dir.exists()) return out;
    for (final entry in await dir.list(followLinks: false).toList()) {
      if (entry is! File) continue;
      final id = _configIdOf(entry.path);
      if (id == null || listed.contains(id)) continue;
      try {
        out[id] = await _readConfigFile(entry);
      } on PathNotFoundException {
        // 列举之后被删掉了：等同于不存在。
      }
    }
    return out;
  }

  /// `<id>.json` → id；不是合法订阅配置文件名则 null。
  static String? _configIdOf(String path) {
    final name = p.basename(path);
    if (!name.endsWith('.json')) return null;
    final id = name.substring(0, name.length - '.json'.length);
    return ProfileStore.isValidId(id) ? id : null;
  }

  Map<String, String> _exportAux(List<String> ids) {
    final out = <String, String>{};
    for (final id in ids) {
      for (final key in ProfileStore.auxKeysFor(id)) {
        try {
          final value = prefs.get(key);
          if (value is String) out[key] = value;
        } catch (_) {}
      }
    }
    return out;
  }

  static Map<String, dynamic> _exportProfile(ProfileEntity profile) {
    final json = Map<String, dynamic>.from(profile.toJson());
    json.remove('inc');
    json.remove('active');
    return json;
  }

  Map<String, Object> _exportPreferences() {
    final out = <String, Object>{};
    for (final spec in PrefRegistry.included) {
      final Object? value;
      try {
        if (!prefs.containsKey(spec.key)) continue;
        value = prefs.get(spec.key);
      } catch (_) {
        continue;
      }
      if (value == null || !PrefRegistry.matchesType(spec.type, value)) {
        continue;
      }
      out[spec.key] = value is List ? List<String>.from(value) : value;
    }
    return out;
  }

  // ───────────────────────── 导入：校验 ─────────────────────────

  /// 解析并完整校验备份内容，**不写任何东西**。
  RestorePlan prepare(String raw) => BackupCodec.parse(
    raw,
    currentSchema: kCurrentStorageSchema,
    extraValidators: extraValidators,
  );

  /// 应用 [plan] 后会被移除的本机订阅（本机有、备份里没有）。供确认对话框展示。
  List<ProfileEntity> removedBy(RestorePlan plan) {
    final keep = {for (final p in plan.profiles) p.id};
    return [
      for (final profile in store.read())
        if (!keep.contains(profile.id)) profile,
    ];
  }

  // ───────────────────────── 导入：应用 ─────────────────────────

  /// 同一时刻只允许一个恢复流程（恢复检查 → 快照 → 应用 → 回滚）。已有恢复
  /// 在进行时直接拒绝（[RestoreFailureKind.busy]），不排队。[body] 里的工作
  /// 属于这次恢复；只有拿到锁的一方才有资格暂停 / 恢复定时刷新。
  Future<T> runExclusive<T>(Future<T> Function() body) async {
    final state = _state;
    if (state.busy) throw const RestoreFailure(RestoreFailureKind.busy);
    state.busy = true;
    try {
      return await body();
    } finally {
      state.busy = false;
    }
  }

  /// 应用已校验的 [plan]。失败时抛 [RestoreFailure]，且（`rolledBack` / 其它
  /// 「什么都没改」的情形下）本机状态与调用前一致。自带互斥。
  Future<RestoreReport> restore(RestorePlan plan) =>
      runExclusive(() => restoreHoldingLock(plan));

  /// [restore] 的本体，调用者必须已经在 [runExclusive] 里。
  Future<RestoreReport> restoreHoldingLock(RestorePlan plan) async {
    if (store.isReadOnly) {
      throw RestoreFailure(
        RestoreFailureKind.readOnly,
        cause: StoreReadOnlyException(store.schema),
      );
    }
    final removed = removedBy(plan).length;

    // 上次恢复若被中断（或回滚没完成），先回到那次恢复之前，再开始新的一次。
    final previous = await recoverHoldingLock();
    if (previous == RecoveryOutcome.failed) {
      throw const RestoreFailure(RestoreFailureKind.unresolvedPrevious);
    }

    final snapshot = await _writeSnapshot();
    try {
      await _apply(plan);
      await _clearMarker();
    } catch (e, st) {
      debugPrint('[backup] 恢复应用失败，用快照回滚: $e\n$st');
      try {
        await _rollbackTo(snapshot);
      } catch (e2, st2) {
        debugPrint('[backup] 快照回滚失败（标记保留，下次再试）: $e2\n$st2');
        // 恢复线索在内存里也记一份：磁盘标记可能没清掉也可能已经没了，
        // 这个进程里下一次导入必须先把这件事了结，不能直接覆盖线索。
        _state.pendingSnapshot = snapshot.path;
        await _reassertMarker(snapshot.path);
        throw RestoreFailure(
          RestoreFailureKind.notRolledBack,
          cause: e,
          snapshotPath: snapshot.path,
        );
      }
      throw RestoreFailure(
        RestoreFailureKind.rolledBack,
        cause: e,
        snapshotPath: snapshot.path,
      );
    }
    await _pruneSnapshots();
    return RestoreReport(
      profilesImported: plan.profiles.length,
      profilesDropped: plan.profilesDropped,
      profilesRemoved: removed,
      prefsImported: plan.prefs.length,
      prefsSkipped: plan.skippedPrefKeys.length,
      refreshQueued: plan.needsFetch.length,
      warpDisabled: plan.warpDisabled,
      snapshotPath: snapshot.path,
      skippedPrefKeys: plan.skippedPrefKeys,
    );
  }

  /// 把 [plan] 写进本机：配置文件暂存 → **一次** Store 提交（同一临界区里完成列表 /
  /// 激活替换、配置文件安装、不在计划里的订阅及其附属键的删除，以及——精确模式下——
  /// 清掉这次恢复新装进来的文件）→ 偏好。回滚时用的是同一个流程。
  ///
  /// 精确模式（回滚 / 启动恢复）的文件规则：计划里的 [RestorePlan.configs]（快照记下的
  /// 全部既有文件，含隔离 / 孤儿）原样装回；`profiles/` 里其余的 `<id>.json` 都不是
  /// 恢复前就有的，才删。列举目录发生在提交的 plan 里（锁内），所以普通仓库提交
  /// 无法插在「替换列表」与「清文件」之间。
  Future<void> _apply(RestorePlan plan) async {
    final staged = <StagedConfig>[];
    try {
      for (final entry in plan.configs.entries) {
        final file = await store.createStagingFile(entry.key);
        staged.add(StagedConfig(entry.key, file));
        await file.writeAsString(entry.value, flush: true);
      }
      final newIds = {for (final profile in plan.profiles) profile.id};
      final result = await store.commit<void>((view) {
        // 不在新列表里的当前订阅：连文件带附属键删掉。若它的 id 恰好有要装回的
        // 文件（恢复前它是游离文件），文件交给 staged 覆盖，只清它的附属键。
        final removedProfiles = <String>[];
        final staleAux = <String>[];
        for (final profile in view.profiles) {
          if (newIds.contains(profile.id)) continue;
          if (plan.configs.containsKey(profile.id)) {
            staleAux.addAll(ProfileStore.auxKeysFor(profile.id));
          } else {
            removedProfiles.add(profile.id);
          }
        }
        final removedConfigs = <String>[];
        if (plan.exactPrefs) {
          final dir = Directory(store.profilesDirPath);
          if (dir.existsSync()) {
            for (final entry in dir.listSync(followLinks: false)) {
              if (entry is! File) continue;
              final id = _configIdOf(entry.path);
              if (id == null ||
                  plan.configs.containsKey(id) ||
                  removedProfiles.contains(id)) {
                continue;
              }
              removedConfigs.add(id);
            }
          }
        }
        return Plan<void>(
          profiles: plan.profiles,
          activeId: plan.activeId == null
              ? const Patch<String>.clear()
              : Patch<String>.set(plan.activeId!),
          staged: staged,
          removedProfileIds: removedProfiles,
          removedConfigIds: removedConfigs,
          deleteKeys: staleAux,
        );
      });
      if (!result.isCommitted) {
        throw StateError('订阅提交未成功: ${result.status.name} ${result.error}');
      }
      if (result.incompleteCleanup.isNotEmpty) {
        // 列表已换，但要删的配置文件没删干净。不能报告成功 / 清标记：留着恢复线索，
        // 之后重试（启动清理会删完 `.del`，不会复活）。
        throw StateError('配置文件删除未完成: ${result.incompleteCleanup}');
      }
    } catch (_) {
      for (final s in staged) {
        await _deleteQuietly(s.file);
      }
      rethrow;
    }
    await _writePrefs(plan);
  }

  Future<void> _writePrefs(RestorePlan plan) async {
    for (final entry in plan.prefs.entries) {
      final value = entry.value;
      final bool ok;
      switch (value) {
        case bool v:
          ok = await prefs.setBool(entry.key, v);
        case int v:
          ok = await prefs.setInt(entry.key, v);
        case String v:
          ok = await prefs.setString(entry.key, v);
        case List<String> v:
          ok = await prefs.setStringList(entry.key, v);
        default:
          throw StateError('不支持的偏好值类型: ${entry.key}');
      }
      if (!ok) throw StateError('偏好写入失败: ${entry.key}');
    }
    for (final entry in plan.auxPrefs.entries) {
      if (!await prefs.setString(entry.key, entry.value)) {
        throw StateError('偏好写入失败: ${entry.key}');
      }
    }
    if (plan.exactPrefs) {
      for (final key in prefs.getKeys().toList()) {
        final spec = PrefRegistry.lookup(key);
        if (spec == null || !spec.isIncluded || plan.prefs.containsKey(key)) {
          continue;
        }
        if (!await prefs.remove(key)) {
          throw StateError('偏好删除失败: $key');
        }
      }
    }
  }

  // ───────────────────────── 快照与标记 ─────────────────────────

  /// 把当前状态写成快照文件并写标记键。任何一步失败都撤销已做的部分并抛
  /// [RestoreFailureKind.snapshotFailed]——此时尚未改动任何东西。
  Future<File> _writeSnapshot() async {
    File? file;
    try {
      final bundle = await exportBundle(includeAux: true);
      final text = BackupCodec.encode(bundle);
      await backupsDir.create(recursive: true);
      file = _uniqueSnapshotFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
      // 读回并按信任模式解析一遍：确认回滚时这份快照真的读得懂。
      BackupCodec.parse(
        await file.readAsString(),
        currentSchema: kCurrentStorageSchema,
        trusted: true,
      );
      if (!await prefs.setString(kRestoreMarkerKey, file.path)) {
        throw StateError('恢复标记写入失败');
      }
      return file;
    } catch (e, st) {
      debugPrint('[backup] 恢复前快照失败: $e\n$st');
      if (file != null) {
        await _deleteQuietly(file);
        await _deleteQuietly(File('${file.path}.tmp'));
      }
      // 写标记失败时平台已先改了内存缓存：撤销它，不留下指向已删快照的标记。
      await _forgetMarker();
      throw RestoreFailure(RestoreFailureKind.snapshotFailed, cause: e);
    }
  }

  File _uniqueSnapshotFile() {
    final t = _now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${t.millisecond.toString().padLeft(3, '0')}';
    var file = File(p.join(backupsDir.path, '$snapshotPrefix$stamp.json'));
    for (var n = 1; file.existsSync(); n++) {
      file = File(p.join(backupsDir.path, '$snapshotPrefix$stamp-$n.json'));
    }
    return file;
  }

  Future<void> _clearMarker() async {
    final ok = await prefs.remove(kRestoreMarkerKey);
    if (!ok || prefs.containsKey(kRestoreMarkerKey)) {
      // 标记清不掉就不能宣布成功：下次启动会拿快照把「成功的恢复」回滚掉。
      // 抛出让调用方走回滚路径，状态与标记保持一致。
      throw StateError('恢复标记清除失败');
    }
  }

  /// 回滚没完成时把标记补回去（清标记失败时平台缓存里它可能已经没了）。尽力而为：
  /// 补不回去也没关系，内存里的 [_RestoreState.pendingSnapshot] 仍会挡住新导入。
  Future<void> _reassertMarker(String path) async {
    try {
      await prefs.setString(kRestoreMarkerKey, path);
    } catch (e) {
      debugPrint('[backup] 补回恢复标记失败（内存里仍记着）: $e');
    }
  }

  Future<void> _rollbackTo(File snapshot) async {
    final plan = BackupCodec.parse(
      await snapshot.readAsString(),
      currentSchema: kCurrentStorageSchema,
      trusted: true,
    );
    await _apply(plan);
    await _clearMarker();
  }

  /// 只保留最近 [keepSnapshots] 份快照。
  Future<void> _pruneSnapshots() async {
    try {
      if (!await backupsDir.exists()) return;
      final files = [
        for (final e in await backupsDir.list(followLinks: false).toList())
          if (e is File &&
              p.basename(e.path).startsWith(snapshotPrefix) &&
              e.path.endsWith('.json'))
            e,
      ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final stale in files.skip(keepSnapshots)) {
        await _deleteQuietly(stale);
      }
    } catch (e) {
      debugPrint('[backup] 清理旧快照失败（忽略）: $e');
    }
  }

  // ───────────────────────── 启动恢复 ─────────────────────────

  /// 发现恢复标记（上次恢复被杀 / 回滚没完成）时，用标记指向的快照回到恢复前
  /// 的状态。永不抛出。另一次恢复正在进行时返回 [RecoveryOutcome.busy]，
  /// 不去碰它的标记与快照。
  Future<RecoveryOutcome> recoverInterrupted() async {
    final state = _state;
    if (state.busy) return RecoveryOutcome.busy;
    state.busy = true;
    try {
      return await recoverHoldingLock();
    } finally {
      state.busy = false;
    }
  }

  /// 是否有待处理的恢复线索（磁盘 / 缓存里的标记，或本进程记着的未了结恢复）。
  /// 廉价的同步检查：启动重试据此判断「没有要恢复的」时完全不必暂停与刷新。
  bool get hasRecoveryClue {
    if (_state.pendingSnapshot != null) return true;
    try {
      return prefs.containsKey(kRestoreMarkerKey);
    } catch (_) {
      return false;
    }
  }

  /// [recoverInterrupted] 的本体，调用者必须已经在 [runExclusive] 里（启动重试要在
  /// 同一次互斥里完成暂停 → 恢复 → 刷新）。永不抛出。
  Future<RecoveryOutcome> recoverHoldingLock() async {
    final Object? marker;
    try {
      marker = prefs.get(kRestoreMarkerKey);
    } catch (_) {
      return RecoveryOutcome.none;
    }
    // 磁盘 / 缓存里没有标记，但本进程里还记着一次没了结的恢复：以内存为准。
    final Object? clue = marker ?? _state.pendingSnapshot;
    if (clue == null) return RecoveryOutcome.none;

    // 只取文件名、在本机 backups 目录里找：路径里的目录部分可能已经过期
    // （iOS 容器路径会变），也不能让标记把读取引到别处。
    final name = clue is String ? p.basename(clue) : '';
    final file = File(p.join(backupsDir.path, name));
    try {
      if (name.isEmpty || !await file.exists()) {
        debugPrint('[backup] 恢复标记指向的快照不存在，无法回滚: $clue');
        await _forgetMarker();
        _state.pendingSnapshot = null;
        return RecoveryOutcome.unrecoverable;
      }
      final RestorePlan plan;
      try {
        plan = BackupCodec.parse(
          await file.readAsString(),
          currentSchema: kCurrentStorageSchema,
          trusted: true,
        );
      } catch (e) {
        debugPrint('[backup] 恢复快照损坏，无法回滚: $e');
        await _forgetMarker();
        _state.pendingSnapshot = null;
        return RecoveryOutcome.unrecoverable;
      }
      await store.cleanupResidue();
      final stuck = await store.pendingConfigDeletions();
      if (stuck.isNotEmpty) {
        throw StateError('上次遗留的配置文件删除仍未完成: $stuck');
      }
      await _apply(plan);
      await _clearMarker();
      _state.pendingSnapshot = null;
      debugPrint('[backup] 已用恢复前快照回到上次恢复之前的状态');
      return RecoveryOutcome.recovered;
    } catch (e, st) {
      debugPrint('[backup] 回滚失败，标记保留: $e\n$st');
      _state.pendingSnapshot = file.path;
      await _reassertMarker(file.path);
      return RecoveryOutcome.failed;
    }
  }

  Future<void> _forgetMarker() async {
    try {
      await prefs.remove(kRestoreMarkerKey);
    } catch (_) {}
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 挂在 [ProfileStore] 上的恢复状态（见 [BackupEngine._states]）。
class _RestoreState {
  /// 有恢复流程（或恢复检查）正在进行。
  bool busy = false;

  /// 上次恢复没了结时的快照路径（回滚失败后设置，回滚成功 / 无法回滚后清除）。
  /// 磁盘标记因平台缓存的先改后写语义可能丢失，这份内存记录是第二道保险。
  String? pendingSnapshot;
}
