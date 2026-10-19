import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clashmiao/core/storage/async_lock.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 一次提交的结局。
enum CommitStatus {
  /// 已写入。
  committed,

  /// plan 判定无需改动（没有任何写入）。
  unchanged,

  /// plan 判定输入已过期（订阅被删/被改/被换代），结果被丢弃。
  stale,

  /// 提交过程中 I/O 失败，已尽力还原。
  failed,
}

class CommitResult<T> {
  const CommitResult._(this.status, this.value, this.error);

  const CommitResult.committed(T? value)
    : this._(CommitStatus.committed, value, null);
  const CommitResult.unchanged(T? value)
    : this._(CommitStatus.unchanged, value, null);
  const CommitResult.stale() : this._(CommitStatus.stale, null, null);
  const CommitResult.failed(Object error)
    : this._(CommitStatus.failed, null, error);

  final CommitStatus status;
  final T? value;
  final Object? error;

  bool get isCommitted => status == CommitStatus.committed;
  bool get isStale => status == CommitStatus.stale;
  bool get isFailed => status == CommitStatus.failed;
}

/// schema 高于当前代码支持的版本（用户降级运行）时，订阅存储拒绝写入。
class StoreReadOnlyException implements Exception {
  const StoreReadOnlyException(this.schema);

  final int schema;

  @override
  String toString() =>
      'StoreReadOnlyException: 数据版本 $schema 高于本应用支持的 '
      '$kCurrentStorageSchema，请升级应用后再修改订阅';
}

/// 锁内给 plan 的只读视图。
class ProfileListView {
  const ProfileListView({
    required this.profiles,
    required this.activeId,
    required this.storedActiveId,
  });

  /// 合法条目，`active` 已按 [activeId] 填充。
  final List<ProfileEntity> profiles;

  /// 生效的激活 id：存储值指向存在的条目就用它；指向不存在的条目则退到第一条；
  /// 没存过（或列表为空）为 null。
  final String? activeId;

  /// 激活键里实际存的原始值。
  final String? storedActiveId;

  ProfileEntity? find(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}

/// 已在锁外写好的暂存配置文件，提交时在锁内 rename 成 `profileId` 的正式文件。
class StagedConfig {
  const StagedConfig(this.profileId, this.file);

  final String profileId;
  final File file;
}

/// 一次提交要做的全部变更。由同步、无副作用的计算产出。
class Plan<T> {
  const Plan({
    this.value,
    this.profiles,
    this.activeId = const Patch<String>.unset(),
    this.staged = const [],
    this.removedProfileIds = const [],
    this.deleteKeys = const [],
  }) : isStale = false;

  /// 无需改动，直接把 [value] 当结果。
  const Plan.unchanged([this.value])
    : profiles = null,
      activeId = const Patch<String>.unset(),
      staged = const [],
      removedProfileIds = const [],
      deleteKeys = const [],
      isStale = false;

  /// 输入已过期，丢弃。
  const Plan.stale()
    : value = null,
      profiles = null,
      activeId = const Patch<String>.unset(),
      staged = const [],
      removedProfileIds = const [],
      deleteKeys = const [],
      isStale = true;

  /// 提交成功后作为 [CommitResult.value] 返回。
  final T? value;

  /// 新的完整订阅列表；null 表示列表不动。
  final List<ProfileEntity>? profiles;

  /// 激活 id 的变更（unset 不动 / set 改为某 id / clear 置空）。
  final Patch<String> activeId;

  /// 待安装的配置文件。
  final List<StagedConfig> staged;

  /// 被移除的订阅：Store 负责删它们的配置文件与 `proxy_selection_*` /
  /// `proxy_delays_*` 附属键。
  final List<String> removedProfileIds;

  /// 额外要删除的偏好键。
  final List<String> deleteKeys;

  final bool isStale;

  bool get hasChanges =>
      profiles != null ||
      !activeId.isUnset ||
      staged.isNotEmpty ||
      removedProfileIds.isNotEmpty ||
      deleteKeys.isNotEmpty;
}

/// 订阅的进程级存储：所有读改写都经过同一把锁，且一律基于锁内最新数据。
///
/// 为什么需要它：旧实现里 `update()` 在网络请求之前读取列表、之后写回旧快照，
/// 期间发生的新增 / 删除 / 切换 / 编辑都会被覆盖或复活。这里的约定是：
/// - 任何写入都走 [commit]：plan 是**同步**函数，拿到锁内最新视图，返回一份
///   [Plan]；Store 自己在锁内完成异步落盘，调用者无法在计算与写入之间插入 await；
/// - 网络等慢操作放在锁外，落地前由 plan 用 `(id, inc, rev, url, ua)` 校验输入
///   是否仍然成立，不成立就丢弃（stale）；
/// - 读取 [read] 永不抛出，坏数据隔离而不是拖垮整张列表。
class ProfileStore {
  ProfileStore({
    required this.prefs,
    required this.configDir,
    String Function()? incGenerator,
    String Function()? opIdGenerator,
  }) : _newInc = incGenerator ?? _randomHex16,
       _newOpId = opIdGenerator ?? _randomHex8;

  final SharedPreferences prefs;

  /// 应用文档目录；订阅配置文件在其下的 `profiles/`。
  final Directory configDir;

  static const profilesKey = 'clashmiao_profiles';
  static const activeProfileKey = 'clashmiao_active_profile';
  static const quarantineKey = 'clashmiao_profiles_quarantine';
  static const corruptKey = 'clashmiao_profiles_corrupt';

  /// 隔离区最多保留的条目数。
  static const quarantineLimit = 50;

  static const _selectionPrefix = 'proxy_selection_';
  static const _delaysPrefix = 'proxy_delays_';

  /// 订阅名下「手选节点」键。
  static String selectionKey(String id) => '$_selectionPrefix$id';

  /// 订阅名下「延迟缓存」键。
  static String delaysKey(String id) => '$_delaysPrefix$id';

  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// 订阅 id 是否合法。它会拼进文件路径，所以必须排除 `/`、`..` 等。
  static bool isValidId(String id) => _idPattern.hasMatch(id);

  /// 某订阅名下的附属偏好键（手选节点、延迟缓存）。
  static List<String> auxKeysFor(String id) => [
    selectionKey(id),
    delaysKey(id),
  ];

  final String Function() _newInc;
  final String Function() _newOpId;
  final AsyncLock _lock = AsyncLock();
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Map<String, Future<Object?>> _inFlight = {};

  String? _parsedRaw;
  _ParsedList _parsed = const _ParsedList.empty();
  bool _parsedValid = false;

  /// 每次提交成功后广播一次；UI 层据此刷新。
  Stream<void> get changes => _changes.stream;

  /// 生成新的对象代际。
  String newInc() => _newInc();

  Future<void> dispose() => _changes.close();

  // ───────────────────────── 读取（同步、永不抛出） ─────────────────────────

  /// 当前全部合法订阅，`active` 已填充。
  List<ProfileEntity> read() => view().profiles;

  /// 生效的激活订阅 id；见 [ProfileListView.activeId]。
  String? readActiveId() => view().activeId;

  ProfileEntity? find(String id) => view().find(id);

  bool exists(String id) => find(id) != null;

  /// 当前一致视图。
  ProfileListView view() {
    try {
      final parsed = _parse();
      final stored = _readString(activeProfileKey);
      String? effective;
      if (parsed.entities.isNotEmpty) {
        if (stored != null && parsed.entities.any((e) => e.id == stored)) {
          effective = stored;
        } else if (stored != null) {
          effective = parsed.entities.first.id;
        }
      }
      return ProfileListView(
        profiles: List.unmodifiable([
          for (final e in parsed.entities)
            e.copyWith(active: e.id == effective),
        ]),
        activeId: effective,
        storedActiveId: stored,
      );
    } catch (e, st) {
      debugPrint('[ProfileStore] read 异常，按空列表处理: $e\n$st');
      return const ProfileListView(
        profiles: [],
        activeId: null,
        storedActiveId: null,
      );
    }
  }

  /// 已隔离的原始条目（最近至多 [quarantineLimit] 条）。
  List<Object?> readQuarantine() {
    final raw = _readString(quarantineKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? List<Object?>.unmodifiable(decoded) : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 当前存储 schema；缺失或类型不符按 0。
  int get schema {
    try {
      return prefs.getInt(kStorageSchemaKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// schema 高于当前代码支持的版本：只读。
  bool get isReadOnly => schema > kCurrentStorageSchema;

  String? _readString(String key) {
    try {
      return prefs.getString(key);
    } catch (_) {
      return null; // 类型不符（别处写成了非字符串）：当作没有。
    }
  }

  _ParsedList _parse() {
    final raw = _readString(profilesKey);
    if (_parsedValid && raw == _parsedRaw) return _parsed;
    final parsed = _parseRaw(raw);
    _parsedRaw = raw;
    _parsed = parsed;
    _parsedValid = true;
    return parsed;
  }

  static _ParsedList _parseRaw(String? raw) {
    if (raw == null || raw.isEmpty) return const _ParsedList.empty();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return _ParsedList(const [], const [], corruptRaw: raw);
    }
    if (decoded is! List) {
      return _ParsedList(const [], const [], corruptRaw: raw);
    }
    final entities = <ProfileEntity>[];
    final quarantined = <Object?>[];
    final seen = <String>{};
    for (final item in decoded) {
      try {
        if (item is! Map<String, dynamic>) throw const FormatException('非对象');
        final entity = ProfileEntity.fromJson(item);
        if (!isValidId(entity.id)) throw const FormatException('非法 id');
        if (!seen.add(entity.id)) throw const FormatException('重复 id');
        entities.add(entity);
      } catch (_) {
        quarantined.add(item);
      }
    }
    return _ParsedList(entities, quarantined);
  }

  // ───────────────────────── 路径 ─────────────────────────

  String get profilesDirPath => p.join(configDir.path, 'profiles');

  /// 订阅配置文件路径。非法 id 抛 [ArgumentError]：id 会拼进路径，
  /// 绝不能让 `../x` 之类逃出 profiles 目录。
  String configFilePath(String profileId) {
    if (!isValidId(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', '订阅 id 不合法');
    }
    return p.join(profilesDirPath, '$profileId.json');
  }

  /// 为 [profileId] 创建一个唯一的暂存文件路径（父目录保证存在，文件本身不创建）。
  /// 暂存文件由调用者在锁外写入，随后通过 [StagedConfig] 交给 [commit]。
  Future<File> createStagingFile(String profileId) async {
    final formal = configFilePath(profileId);
    final dir = Directory(p.dirname(formal));
    await dir.create(recursive: true);
    return File(p.join(dir.path, '$profileId.${_newOpId()}.staging'));
  }

  // ───────────────────────── 提交 ─────────────────────────

  /// 串行提交一次变更。
  ///
  /// [plan] 在锁内、基于最新视图同步计算，返回 [Plan]；之后 Store 在锁内按固定
  /// 顺序落盘：①暂存配置文件 rename 为正式文件（被替换的旧文件先改名 `.undo`）、
  /// 被移除订阅的配置文件改名 `.undo`；②写列表键与激活键并检查返回值；
  /// ③成功则清理 `.undo`、附属键并广播 [changes]；任一步失败则还原文件与偏好并
  /// 返回 [CommitResult.failed]。
  ///
  /// 进程恰好死在 ① 与 ② 之间的后果见 [cleanupResidue]。
  ///
  /// schema 高于当前版本时抛 [StoreReadOnlyException]。
  Future<CommitResult<T>> commit<T>(
    Plan<T> Function(ProfileListView view) plan,
  ) {
    return _lock.synchronized<CommitResult<T>>(() async {
      final current = schema;
      if (current > kCurrentStorageSchema) {
        throw StoreReadOnlyException(current);
      }
      final snapshot = view();
      final decided = plan(snapshot);
      if (decided.isStale) return CommitResult<T>.stale();
      if (!decided.hasChanges) return CommitResult<T>.unchanged(decided.value);
      return _apply(decided);
    });
  }

  Future<CommitResult<T>> _apply<T>(Plan<T> plan) async {
    final profiles = plan.profiles;
    // 输入校验：id 会拼进路径、也是唯一键，错了宁可整次拒绝。
    try {
      if (profiles != null) {
        final seen = <String>{};
        for (final profile in profiles) {
          if (!isValidId(profile.id) || !seen.add(profile.id)) {
            throw ArgumentError.value(profile.id, 'profile.id', '非法或重复');
          }
        }
      }
      for (final staged in plan.staged) {
        configFilePath(staged.profileId);
      }
      for (final id in plan.removedProfileIds) {
        configFilePath(id);
      }
      final newActive = plan.activeId;
      if (newActive.isSet && !isValidId(newActive.value)) {
        throw ArgumentError.value(newActive.value, 'activeId', '非法');
      }
    } catch (e) {
      return CommitResult<T>.failed(e);
    }

    final prevList = _readString(profilesKey);
    final prevActive = _readString(activeProfileKey);
    final parsedBefore = _parse();
    final undo = <_Undo>[];
    var touchedPrefs = false;
    try {
      // 隔离区与损坏原文：只有主列表要被重写时才会丢掉它们，所以在此之前先落盘。
      if (profiles != null) await _persistSafetyNet(parsedBefore);

      for (final staged in plan.staged) {
        final formal = File(configFilePath(staged.profileId));
        final entry = _Undo(formal, File('${formal.path}.${_newOpId()}.undo'));
        undo.add(entry);
        if (await formal.exists()) {
          await formal.rename(entry.undo.path);
          entry.movedOld = true;
        }
        await staged.file.rename(formal.path);
        entry.installed = true;
      }
      for (final id in plan.removedProfileIds) {
        final formal = File(configFilePath(id));
        if (!await formal.exists()) continue;
        final entry = _Undo(formal, File('${formal.path}.${_newOpId()}.undo'));
        undo.add(entry);
        await formal.rename(entry.undo.path);
        entry.movedOld = true;
      }

      touchedPrefs = true;
      final writes = <Future<bool>>[];
      if (profiles != null) {
        writes.add(
          prefs.setString(
            profilesKey,
            jsonEncode([for (final e in profiles) e.toJson()]),
          ),
        );
      }
      final newActive = plan.activeId;
      if (newActive.isSet) {
        writes.add(prefs.setString(activeProfileKey, newActive.value));
      } else if (newActive.isClear) {
        writes.add(prefs.remove(activeProfileKey));
      }
      final results = await Future.wait(writes);
      if (results.any((ok) => !ok)) {
        throw const FileSystemException('偏好写入返回失败');
      }
    } catch (e, st) {
      debugPrint('[ProfileStore] 提交失败，还原: $e\n$st');
      await _rollback(
        undo: undo,
        restorePrefs: touchedPrefs,
        prevList: prevList,
        prevActive: prevActive,
        listChanged: profiles != null,
        activeChanged: !plan.activeId.isUnset,
      );
      return CommitResult<T>.failed(e);
    }

    // 成功后的收尾：失败只留下无害的孤儿，不再回滚已写入的列表。
    for (final entry in undo) {
      await _deleteQuietly(entry.undo);
    }
    final aux = <String>{
      for (final id in plan.removedProfileIds) ...auxKeysFor(id),
      ...plan.deleteKeys,
    };
    for (final key in aux) {
      try {
        await prefs.remove(key);
      } catch (e) {
        debugPrint('[ProfileStore] 删除附属键失败 $key: $e');
      }
    }
    if (!_changes.isClosed) _changes.add(null);
    return CommitResult<T>.committed(plan.value);
  }

  Future<void> _rollback({
    required List<_Undo> undo,
    required bool restorePrefs,
    required String? prevList,
    required String? prevActive,
    required bool listChanged,
    required bool activeChanged,
  }) async {
    if (restorePrefs) {
      try {
        if (listChanged) await _restoreString(profilesKey, prevList);
        if (activeChanged) await _restoreString(activeProfileKey, prevActive);
      } catch (e) {
        debugPrint('[ProfileStore] 还原偏好失败: $e');
      }
    }
    for (final entry in undo.reversed) {
      try {
        if (entry.installed) await _deleteQuietly(entry.formal);
        if (entry.movedOld && await entry.undo.exists()) {
          await entry.undo.rename(entry.formal.path);
        }
      } catch (e) {
        debugPrint('[ProfileStore] 还原文件失败 ${entry.formal.path}: $e');
      }
    }
  }

  Future<void> _restoreString(String key, String? value) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  /// 主列表将被重写之前，把「会被丢掉的东西」存进独立键：整体损坏的原文，
  /// 以及解析失败 / id 非法 / 重复的条目。写入失败只记日志，不拖累正常操作。
  Future<void> _persistSafetyNet(_ParsedList parsed) async {
    try {
      final corrupt = parsed.corruptRaw;
      if (corrupt != null) {
        await prefs.setString(corruptKey, corrupt);
      }
      if (parsed.quarantined.isNotEmpty) {
        final merged = <String, Object?>{};
        for (final item in readQuarantine()) {
          merged[jsonEncode(item)] = item;
        }
        for (final item in parsed.quarantined) {
          final key = jsonEncode(item);
          merged.remove(key); // 重新追加到末尾，保持「最近」在后
          merged[key] = item;
        }
        var items = merged.values.toList();
        if (items.length > quarantineLimit) {
          items = items.sublist(items.length - quarantineLimit);
        }
        await prefs.setString(quarantineKey, jsonEncode(items));
      }
    } catch (e) {
      debugPrint('[ProfileStore] 写隔离区失败（忽略）: $e');
    }
  }

  // ───────────────────────── 附属数据 ─────────────────────────

  /// 写订阅名下的附属偏好键（手选节点 / 延迟缓存）。
  ///
  /// 写入者在创建时记下 `(id, inc)`；这里在锁内校验订阅仍存在且代际一致，
  /// 不一致（已删除或已换代）则丢弃，避免旧 notifier 复活孤儿键。
  /// 返回是否真的写入；永不抛出。[value] 为 null 表示删除该键。
  Future<bool> writeAux(String id, String inc, String key, String? value) {
    return _lock.synchronized<bool>(() async {
      try {
        if (!isValidId(id) || !auxKeysFor(id).contains(key)) return false;
        final entity = view().find(id);
        if (entity == null || entity.inc != inc) return false;
        return value == null
            ? await prefs.remove(key)
            : await prefs.setString(key, value);
      } catch (e) {
        debugPrint('[ProfileStore] writeAux 失败 $key: $e');
        return false;
      }
    });
  }

  // ───────────────────────── 去重 ─────────────────────────

  /// 相同 [key] 的并发调用共享同一个 Future；结束（成功、失败、stale 皆可）
  /// 即从表中移除。键不同则互不共享。
  Future<T> dedupe<T>(String key, Future<T> Function() run) {
    final existing = _inFlight[key];
    if (existing != null) return existing as Future<T>;
    final future = Future<T>.sync(run);
    late final Future<T> tracked;
    tracked = future.whenComplete(() {
      if (identical(_inFlight[key], tracked)) _inFlight.remove(key);
    });
    _inFlight[key] = tracked;
    return tracked;
  }

  @visibleForTesting
  int get inFlightCount => _inFlight.length;

  // ───────────────────────── 启动清理 ─────────────────────────

  /// 启动时清理上次进程遗留的暂存文件。必须在任何业务读写之前调用。
  ///
  /// - `.staging`（及其 `.next` / `.tmp` 衍生物）：未提交的暂存，直接删除；
  /// - `.undo`：若正式文件存在则保留正式文件、删 `.undo`——这是刷新时进程死在
  ///   「文件已替换」与「列表已写入」之间的良性窗口（较新的同源配置配较旧元数据）；
  ///   正式文件缺失且该订阅仍在列表里 → 还原 `.undo`；订阅已不在列表 → 删除。
  Future<void> cleanupResidue() {
    return _lock.synchronized<void>(() async {
      try {
        final dir = Directory(profilesDirPath);
        if (!await dir.exists()) return;
        final ids = {for (final e in view().profiles) e.id};
        // 先取完整清单再逐个处理：边遍历边删 / 改名，目录枚举可能漏项。
        final entries = await dir.list(followLinks: false).toList();
        for (final entity in entries) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          try {
            if (name.endsWith('.staging') ||
                name.contains('.staging.') ||
                name.endsWith('.json.next') ||
                name.endsWith('.json.tmp')) {
              await entity.delete();
            } else if (name.endsWith('.undo')) {
              final id = name.split('.').first;
              if (!isValidId(id)) {
                await entity.delete();
                continue;
              }
              final formal = File(configFilePath(id));
              if (!await formal.exists() && ids.contains(id)) {
                await entity.rename(formal.path);
              } else {
                await entity.delete();
              }
            }
          } catch (e) {
            debugPrint('[ProfileStore] 清理残留失败 $name: $e');
          }
        }
      } catch (e) {
        debugPrint('[ProfileStore] 清理残留失败: $e');
      }
    });
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _randomHex8() => _randomHex(8);

  static String _randomHex16() => _randomHex(16);

  static final Random _random = Random.secure();

  static String _randomHex(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(_random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}

class _ParsedList {
  const _ParsedList(this.entities, this.quarantined, {this.corruptRaw});

  const _ParsedList.empty()
    : entities = const [],
      quarantined = const [],
      corruptRaw = null;

  final List<ProfileEntity> entities;
  final List<Object?> quarantined;
  final String? corruptRaw;
}

class _Undo {
  _Undo(this.formal, this.undo);

  final File formal;
  final File undo;
  bool movedOld = false;
  bool installed = false;
}
