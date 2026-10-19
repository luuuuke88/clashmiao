// 连接启动产物的准备：每个 on 请求一份内联 options 与运行时配置文件。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §5「ConnectionLauncher」：
// - `configRevision` = 对（options JSON + 运行时配置内容）的稳定哈希：相同配置
//   得到相同 revision、协调器不会重载；
// - 运行时配置文件**按 revision 命名**：`runtime-<revision>.json`。相同 revision
//   的请求复用同一份文件——先写 `runtime-prep-<token>.json`，仅当目标不存在或
//   内容不同时才用改名（原子）覆盖，内容相同则丢弃临时文件，所以读取方永远看
//   不到半份文件，也不会出现「相同 revision 删掉自己的文件」；
// - 删除只依据**权威快照与本进程已知的引用**，绝不依据修改时间或文件年龄：
//   受保护 = 快照 `activeConfigRevision` 的文件（原生运行 / 持久化引用的就是它）
//   ∪ 尚未终结（准备中 / 发送中 / 回执未处理）的请求的文件 ∪ 本进程最近准备
//   的 3 个不同 revision。受保护集合之外的才删；本进程收到首个权威快照之前
//   什么都不删（冷启动时原生的持久化引用只能从快照得知）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/model/directories.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/data/default_config_options.dart';
import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 准备启动产物失败；[failure] 是界面应展示的原因。
class LaunchPreparationException implements Exception {
  const LaunchPreparationException(this.failure);

  final ConnectionFailure failure;

  @override
  String toString() => 'LaunchPreparationException($failure)';
}

/// FNV-1a 64 位哈希（自写，不引入依赖）。返回的是 64 位补码值，可能为负。
@visibleForTesting
int fnv1a64(Iterable<int> bytes, {int seed = _fnvOffsetBasis}) {
  var h = seed;
  for (final b in bytes) {
    h ^= b & 0xff;
    h *= _fnvPrime; // Dart VM 的 int 乘法按 2^64 回绕
  }
  return h;
}

// 0xcbf29ce484222325：Dart VM 的 int 是 64 位补码，十六进制字面量按补码解释。
const int _fnvOffsetBasis = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;

/// 配置 revision：对（options JSON + 分隔符 + 运行时配置内容）的稳定哈希，
/// 取低 63 位保证非负（Pigeon / JSON 里作为 Long 往返不会遇到符号问题）。
int computeConfigRevision(String optionsJson, List<int> runtimeConfigBytes) {
  var h = fnv1a64(utf8.encode(optionsJson));
  h = fnv1a64(const [0], seed: h);
  h = fnv1a64(runtimeConfigBytes, seed: h);
  return h & 0x7fffffffffffffff;
}

/// 本进程最近准备的不同 revision 里，受保护的个数。
const kRecentRevisionsProtected = 3;

typedef WorkingDirectoryResolver = Future<Directory> Function();

/// 运行时配置文件名（按 revision）。
String runtimeConfigFileName(int revision) => 'runtime-$revision.json';

class ConnectionLauncher {
  ConnectionLauncher(
    this._ref, {
    WorkingDirectoryResolver? workingDirectory,
    String Function()? tokenGenerator,
  }) : _workingDirectory = workingDirectory ?? resolveSingBoxWorkingDirectory,
       _token = tokenGenerator ?? _defaultToken;

  final Ref _ref;
  final WorkingDirectoryResolver _workingDirectory;
  final String Function() _token;

  static int _tokenCounter = 0;
  static String _defaultToken() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_tokenCounter++}';

  /// 尚未终结的意图对运行时配置文件的引用：从 [prepare] 完成起，到意图终结
  /// （[discard]）且发送路径走完（[sendFinished]）为止。
  final Map<int, _Hold> _holds = {};

  /// 本进程最近准备的不同 revision（新的在后，至多 [kRecentRevisionsProtected]）。
  final List<int> _recent = [];

  /// 正在构建中的临时文件（绝不能被清理删掉）。
  final Set<String> _prepInProgress = {};

  /// 最近观察到的内核快照；尚未观察到为 null——此时**什么都不删**。
  KernelSnapshot? _kernel;

  /// 串行化「定稿目标文件」与「清理」：清理按快照与引用计算受保护集合并据此
  /// 删除，期间不允许有别的请求同时定稿，否则刚复用 / 写好的文件可能被误删。
  Future<void> _ioChain = Future<void>.value();

  /// 排队中的定稿 / 清理全部完成（测试用）。
  @visibleForTesting
  Future<void> get idle async {
    Future<void> seen;
    do {
      seen = _ioChain;
      await seen;
    } while (!identical(seen, _ioChain));
  }

  Future<T> _serialized<T>(Future<T> Function() op) {
    final run = _ioChain.then((_) => op());
    _ioChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// 为意图 [id] 准备启动产物。失败抛 [LaunchPreparationException]。
  Future<LaunchSpec> prepare(int id) async {
    if (_ref.read(coreLibraryMissingProvider)) {
      throw const LaunchPreparationException(CoreUnavailable());
    }

    // 等仓库就绪，而不是报错：仓库未就绪只是启动期的短暂竞态。
    final ProfileRepository repo;
    try {
      repo = await _ref.read(profileRepositoryProvider.future);
    } catch (e) {
      throw LaunchPreparationException(UnexpectedFailure('$e'));
    }

    final ProfileEntity active = await _resolveActiveWithSelfHeal(repo);

    String? prepPath;
    try {
      final isGlobal = _ref.read(proxyModeProvider) == 0;
      final settings = _ref.read(networkSettingsProvider);
      final optionsJson = jsonEncode(
        getDefaultConfigOptions(
          executeConfigAsIs: isGlobal,
          isSmart: !isGlobal,
          settings: settings,
          advancedConfig: active.advancedConfig,
        ),
      );

      final workingDir = await _workingDirectory();
      final prepName = 'runtime-prep-${_token()}.json';
      prepPath = '${workingDir.path}/$prepName';
      _prepInProgress.add(prepPath);
      final built = await RuntimeConfigBuilder().build(
        baseProfile: File(repo.configFilePath(active.id)),
        workingDir: workingDir,
        remoteDnsAddress: settings.remoteDnsAddress,
        advancedConfig: active.advancedConfig,
        outputFileName: prepName,
      );
      final bytes = await built.readAsBytes();
      final revision = computeConfigRevision(optionsJson, bytes);
      final target = File(
        '${workingDir.path}/${runtimeConfigFileName(revision)}',
      );

      // 定稿：登记引用、复用或原子落盘，与清理串行。
      await _serialized(() async {
        _holds[id] = _Hold(revision);
        _touchRecent(revision);
        await _finalize(built, target, bytes);
      });
      return LaunchSpec(
        runtimeConfigPath: target.path,
        optionsJson: optionsJson,
        profileName: active.name,
        configRevision: revision,
      );
    } on LaunchPreparationException {
      rethrow;
    } catch (e) {
      throw LaunchPreparationException(UnexpectedFailure('$e'));
    } finally {
      if (prepPath != null) {
        _prepInProgress.remove(prepPath);
        try {
          final f = File(prepPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// 目标文件已存在且内容相同：直接复用（不写、不改名），临时文件由调用方删除；
  /// 否则用改名把临时文件原子地放到目标位置（覆盖时读取方要么看到旧的完整文件，
  /// 要么看到新的完整文件）。
  Future<void> _finalize(File temp, File target, List<int> bytes) async {
    if (await target.exists()) {
      final existing = await target.readAsBytes();
      if (_sameBytes(existing, bytes)) return;
    }
    await temp.rename(target.path);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _touchRecent(int revision) {
    _recent.remove(revision);
    _recent.add(revision);
    if (_recent.length > kRecentRevisionsProtected) {
      _recent.removeRange(0, _recent.length - kRecentRevisionsProtected);
    }
  }

  /// 配置文件存在性预检 + 缺失时的自愈刷新。
  ///
  /// 缺失是真实会发生的（订阅更新中途失败、备份恢复之后）。唯一的自救动作
  /// 就是重新拉一次订阅，那就替用户做。刷新期间激活订阅可能已经被并发修改
  /// （切换、删除、被刷新作废），所以刷新**无论成功、抛出（含 stale / 取消）
  /// 还是失败**，都要重新读取当前激活订阅，并用它当前的路径重做预检——绝不复用
  /// 刷新前的 `active` 与路径。
  Future<ProfileEntity> _resolveActiveWithSelfHeal(
    ProfileRepository repo,
  ) async {
    ProfileEntity? active;
    try {
      active = repo.getActive();
    } catch (e) {
      throw LaunchPreparationException(UnexpectedFailure('$e'));
    }
    if (active == null) {
      throw const LaunchPreparationException(NoActiveProfile());
    }
    if (await _configUsable(repo, active)) return active;

    debugPrint('配置文件不存在，尝试重新拉取订阅自愈: ${repo.configFilePath(active.id)}');
    try {
      await repo.update(active.id);
    } catch (e) {
      debugPrint('自愈重新拉取订阅失败: $e');
      final mapped = _mapSelfHealException(e);
      if (mapped != null) throw LaunchPreparationException(mapped);
    }

    // 重新读取当前激活订阅，再判断配置是否存在。
    final ProfileEntity? current;
    try {
      current = repo.getActive();
    } catch (e) {
      throw LaunchPreparationException(UnexpectedFailure('$e'));
    }
    if (current == null) {
      throw const LaunchPreparationException(NoActiveProfile());
    }
    if (!await _configUsable(repo, current)) {
      throw const LaunchPreparationException(ConfigMissing());
    }
    return current;
  }

  Future<bool> _configUsable(ProfileRepository repo, ProfileEntity p) async {
    final file = File(repo.configFilePath(p.id));
    return await file.exists() && await file.length() > 0;
  }

  /// 把自愈刷新抛出的异常映射为连接失败；返回 null 表示「照常重读当前激活订阅
  /// 再继续」（stale / 取消 / 网络失败都属于这一类）。
  ///
  /// TODO(C 合并): 在这里把 `StoreReadOnlyException` 映射为对应的失败（i18n
  /// 键 `failure.profiles.readOnlyUpgrade`）。本分支还看不到持久化子项目的
  /// 异常类型，所以暂时一律返回 null。
  ConnectionFailure? _mapSelfHealException(Object error) => null;

  /// 请求 [id] 开始走发送路径（绑定 seq 之后）。运行时配置文件按 revision 命名、
  /// 与 seq 无关，所以这里不再改名，只把「发送中」记下来：回执处理完之前这份
  /// 文件的引用不能释放。
  Future<LaunchSpec> bindSeq(int id, LaunchSpec spec, int seq) async {
    _holds[id]?.sending = true;
    return spec;
  }

  /// 意图 [id] 的发送路径（含回执处理）已全部走完。
  void sendFinished(int id) {
    final h = _holds[id];
    if (h == null) return;
    h.sending = false;
    _releaseIfDone(id);
  }

  /// 意图终结（成功、失败、被取代、被中断都算）。文件不在这里删：它可能仍被
  /// 协调器读取，也可能被相同 revision 的别的请求复用，是否可删只由清理按
  /// 受保护集合判断。
  Future<void> discard(int id) async {
    final h = _holds[id];
    if (h == null) return;
    h.terminal = true;
    _releaseIfDone(id);
  }

  void _releaseIfDone(int id) {
    final h = _holds[id];
    if (h == null || !h.terminal || h.sending) return;
    _holds.remove(id);
    if (_kernel != null) unawaited(_scheduleCleanup());
  }

  /// 控制器每收到一份权威内核快照就调用。首个快照到达前不删任何文件；运行中的
  /// revision 变化时（旧 revision 的文件可能不再受保护）触发清理。
  Future<void> observe(KernelSnapshot snapshot) async {
    final previous = _kernel;
    _kernel = snapshot;
    if (previous != null &&
        previous.activeConfigRevision == snapshot.activeConfigRevision) {
      return;
    }
    await _scheduleCleanup();
  }

  Future<void> _scheduleCleanup() => _serialized(_cleanup);

  static final RegExp _revisionFile = RegExp(r'^runtime-(\d+)\.json$');
  static final RegExp _prepFile = RegExp(r'^runtime-prep-.+\.json$');
  // 早期（每请求按 seq 命名）版本留下的文件，来历不明，按同一规则处理。
  static final RegExp _legacySeqFile = RegExp(r'^runtime-config-\d+\.json$');
  static final RegExp _legacyPrepFile = RegExp(
    r'^runtime-config-prep-.+\.json$',
  );

  /// 受保护的 revision：快照里运行 / 持久化引用的、尚未终结的请求的、本进程最近
  /// 准备的。
  Set<int> _protectedRevisions() => {
    ?_kernel?.activeConfigRevision,
    for (final h in _holds.values) h.revision,
    ..._recent,
  };

  /// 删除受保护集合之外的运行时配置文件。没有首个快照时什么都不做。
  Future<void> _cleanup() async {
    final kernel = _kernel;
    if (kernel == null) return;
    final Directory dir;
    try {
      dir = await _workingDirectory();
      if (!await dir.exists()) return;
    } catch (e) {
      debugPrint('清理运行时配置：无法定位目录（忽略）: $e');
      return;
    }
    final keep = _protectedRevisions();
    final activeRevision = kernel.activeConfigRevision;
    // 旧版按 seq 命名的文件无法与 revision 对应：只要内核还在运行、而新命名的
    // 运行中文件并不存在，说明运行中的可能正是某个旧文件，保守保留。
    final legacyMayBeRunning =
        activeRevision != null &&
        !await File(
          '${dir.path}/${runtimeConfigFileName(activeRevision)}',
        ).exists();

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        try {
          final m = _revisionFile.firstMatch(name);
          if (m != null) {
            final revision = int.tryParse(m.group(1)!);
            if (revision != null && keep.contains(revision)) continue;
            await entity.delete();
          } else if (_prepFile.hasMatch(name) ||
              _legacyPrepFile.hasMatch(name)) {
            if (_prepInProgress.contains(entity.path)) continue;
            await entity.delete();
          } else if (_legacySeqFile.hasMatch(name)) {
            if (legacyMayBeRunning) continue;
            await entity.delete();
          }
        } catch (e) {
          debugPrint('删除运行时配置失败（忽略）: $name $e');
        }
      }
    } catch (e) {
      debugPrint('清理运行时配置失败（忽略）: $e');
    }
  }
}

class _Hold {
  _Hold(this.revision);

  final int revision;
  bool terminal = false;
  bool sending = false;
}

final connectionLauncherProvider = Provider<ConnectionLauncher>((ref) {
  return ConnectionLauncher(ref);
});
