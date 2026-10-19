// 连接启动产物的准备：每个 on 请求一份独立的运行时配置文件与内联 options。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §5「ConnectionLauncher」与计划补充 P4 ①：
// - 先写 `runtime-config-prep-<token>.json`（此时还不知道 seq，也不知道意图是否
//   仍然有效）；
// - 状态机确认意图仍有效、分配 seq 之后，改名为 `runtime-config-<seq>.json`；
// - `configRevision` = 对（options JSON + 运行时配置内容）的稳定哈希：相同配置
//   得到相同 revision、协调器不会重载；
// - 清理旧文件的规则是「拿不准就留」：运行中的 spec、仍在执行（尚未被协调器
//   处理）的 spec、持久化引用的 spec（最新一份已处理的）一律保护；能证明无引用
//   的中间产物（更新的 spec 已确认运行、相同 revision 的请求被协调器无操作
//   合并、被更新的请求取代且并非运行中的）才释放；
// - 留存有上限（[kMaxRetainedRuntimeFiles]）：回收之后仍超限且无法证明可释放
//   时，新的准备请求以 [RuntimeFilesExhausted] 失败，不再继续写文件。

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

/// 除「运行中」与「最新一份」之外，最多允许留存的运行时配置文件数。
const kMaxRetainedRuntimeFiles = 4;

typedef WorkingDirectoryResolver = Future<Directory> Function();

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

  /// 每个未终结意图当前的运行时配置文件路径（prep 名或已绑定 seq 的名字）。
  final Map<int, String> _files = {};

  /// 意图 [id] 最近一次绑定 seq（发送）时内核已知的 attempt：之后 attempt 增长
  /// 才说明有新实例启动。**发送元数据保持不变直到 [sendFinished]**（回执路径
  /// 走完）——意图提前终结（快照先于回执）不会让它消失；缺失（从未得知内核
  /// attempt）一律视为「无法确认」，绝不据此推断发生过新启动。
  final Map<int, int> _attemptAtSend = {};

  /// 被协调器受理的请求所引用的运行时配置文件，按受理顺序。它们可能是运行中
  /// 实例、正在执行的请求或持久化 spec 的引用，是否可以释放由 [_released] 判断。
  final List<_AcceptedSpec> _accepted = [];

  /// 最近观察到的内核快照；尚未观察到为 null（此时一律保守保留）。
  KernelSnapshot? _kernel;

  /// 串行化清理，避免两次清理并发删除/扫描。
  Future<void> _cleanupChain = Future<void>.value();

  /// 没有任何记录引用的 seq 文件（请求已终结但可能仍在协调器手里）至少保留这
  /// 么久：协调器收到请求后几秒内就会读取 spec，两分钟足够保守。
  static const untrackedGrace = Duration(minutes: 2);

  /// 没有记录引用的 seq 文件中，最新的这几份始终保留（上次进程留下的、可能仍
  /// 是运行中或持久化引用的那份）。
  static const _untrackedKeepNewest = 2;

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
      await _enforceQuota(workingDir);
      final prepName = 'runtime-config-prep-${_token()}.json';
      final runtimeConfig = await RuntimeConfigBuilder().build(
        baseProfile: File(repo.configFilePath(active.id)),
        workingDir: workingDir,
        remoteDnsAddress: settings.remoteDnsAddress,
        advancedConfig: active.advancedConfig,
        outputFileName: prepName,
      );
      final bytes = await runtimeConfig.readAsBytes();
      _files[id] = runtimeConfig.path;
      return LaunchSpec(
        runtimeConfigPath: runtimeConfig.path,
        optionsJson: optionsJson,
        profileName: active.name,
        configRevision: computeConfigRevision(optionsJson, bytes),
      );
    } on LaunchPreparationException {
      rethrow;
    } catch (e) {
      throw LaunchPreparationException(UnexpectedFailure('$e'));
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

  /// 状态机分配了 [seq] 之后，把 prep 文件改名为 `runtime-config-<seq>.json`。
  /// 同一意图因 stale / wrongEpoch 被重发时会用新的 seq 再调一次，所以这里按
  /// 「当前路径 → 新名字」处理，已经是目标名字则不动。
  Future<LaunchSpec> bindSeq(int id, LaunchSpec spec, int seq) async {
    final current = _files[id] ?? spec.runtimeConfigPath;
    final target = '${File(current).parent.path}/runtime-config-$seq.json';
    if (current != target) {
      await File(current).rename(target);
      _files[id] = target;
    }
    final attempt = _kernel?.attempt;
    if (attempt != null) {
      _attemptAtSend[id] = attempt;
    } else {
      _attemptAtSend.remove(id);
    }
    return LaunchSpec(
      runtimeConfigPath: target,
      optionsJson: spec.optionsJson,
      profileName: spec.profileName,
      configRevision: spec.configRevision,
    );
  }

  /// 协调器受理了（[epoch] 纪元内序号 [seq] 的）引用 [spec] 的请求：记下它，
  /// 并按规则清理旧文件。
  Future<void> accepted(
    int id,
    LaunchSpec spec, {
    required String epoch,
    required int seq,
  }) async {
    _accepted.removeWhere((a) => a.path == spec.runtimeConfigPath);
    final entry = _AcceptedSpec(
      path: spec.runtimeConfigPath,
      revision: spec.configRevision,
      epoch: epoch,
      seq: seq,
      attemptAtSend: _attemptAtSend[id],
    );
    _accepted.add(entry);
    _files.remove(id);
    _resolve(entry);
    await _scheduleCleanup(File(spec.runtimeConfigPath).parent);
  }

  /// 意图 [id] 的发送路径（含回执处理）已全部走完：发送元数据可以丢弃了。
  void sendFinished(int id) => _attemptAtSend.remove(id);

  /// 控制器每收到一份内核快照就调用：运行中的 spec、已执行到哪一步都来自它。
  /// 与文件释放相关的状态变化时触发一次清理。
  Future<void> observe(KernelSnapshot snapshot) async {
    final before = _signature();
    _kernel = snapshot;
    for (final a in _accepted) {
      _resolve(a);
    }
    if (_accepted.isEmpty || _signature() == before) return;
    await _scheduleCleanup(File(_accepted.last.path).parent);
  }

  /// 清理相关状态的指纹：确认运行的、最新已处理的、可释放的各是哪些。
  String _signature() =>
      '${_confirmed()?.path}|${_newestApplied()?.path}|'
      '${_accepted.where(_released).map((a) => a.path).join(',')}';

  /// 用快照给 [a] 定性（只定一次）：协调器已处理到它、内核已启动时，
  /// - attempt 在发送之后增长且 revision 一致 → 它启动了新实例（[_AcceptedSpec.started]）；
  /// - attempt 未变且 revision 一致 → 相同 revision 的请求被协调器无操作合并
  ///   （[_AcceptedSpec.noop]），它的文件从未被运行实例引用。
  /// 缺发送元数据时无法判定，保持未定性（保留）。
  void _resolve(_AcceptedSpec a) {
    final k = _kernel;
    final sent = a.attemptAtSend;
    if (a.resolved || sent == null || k == null) return;
    if (k.epoch != a.epoch || k.appliedSeq < a.seq) return;
    if (k.status != KernelStatus.started) return;
    if (k.activeConfigRevision != a.revision) return;
    if (k.attempt > sent) {
      a.started = true;
      a.resolved = true;
    } else if (k.attempt == sent) {
      a.noop = true;
      a.resolved = true;
    }
  }

  /// 最新的、已确认「正在运行」的 spec：它启动了当前仍在运行的实例。
  _AcceptedSpec? _confirmed() {
    final k = _kernel;
    if (k == null || k.status != KernelStatus.started) return null;
    _AcceptedSpec? best;
    for (final a in _accepted) {
      if (!a.started || a.epoch != k.epoch) continue;
      if (a.revision != k.activeConfigRevision) continue;
      if (best == null || a.seq > best.seq) best = a;
    }
    return best;
  }

  /// 当前纪元里协调器已处理的最新一份（持久化引用的那份）。
  _AcceptedSpec? _newestApplied() {
    final k = _kernel;
    if (k == null) return null;
    _AcceptedSpec? best;
    for (final a in _accepted) {
      if (a.epoch != k.epoch || a.seq > k.appliedSeq) continue;
      if (best == null || a.seq > best.seq) best = a;
    }
    return best;
  }

  /// 意图终结：删除还没绑定 seq 的 prep 文件（没有任何人引用）。
  ///
  /// **已经绑定 seq 的文件不在这里删**：请求可能已经交给协调器（回执在路上，或
  /// 协调器已受理但随后被更新的请求取代），协调器此刻可能正要读取它——删了会让
  /// 一次本来成功的启动在读取配置时失败。它们之后按清理规则（更新的 spec 确认
  /// 运行且超过宽限期）回收。
  Future<void> discard(int id) async {
    final path = _files.remove(id);
    if (path == null) return;
    if (!_prepFile.hasMatch(File(path).uri.pathSegments.last)) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('删除未使用的运行时配置失败（忽略）: $e');
    }
  }

  static final RegExp _seqFile = RegExp(r'^runtime-config-(\d+)\.json$');
  static final RegExp _prepFile = RegExp(r'^runtime-config-prep-.+\.json$');

  Future<void> _scheduleCleanup(Directory dir) {
    final run = _cleanupChain.then((_) async {
      try {
        await _cleanup(dir);
      } catch (e) {
        debugPrint('清理旧运行时配置失败（忽略）: $e');
      }
    });
    _cleanupChain = run;
    return run;
  }

  /// [a] 现在可以释放吗？只有**能证明**无引用才可以，拿不准就留：
  /// - 别的纪元的记录：当前纪元已有确认运行的 spec 才算被替换；
  /// - 当前纪元里序号还没被协调器处理到的（仍在执行 / 可能被持久化）不放；
  /// - 最新一份已处理的（持久化引用）、确认运行的那份不放；
  /// - 比确认运行的更旧的：新实例已经在跑，放；
  /// - 相同 revision 被协调器无操作合并的：从未被运行实例引用，放；
  /// - 已被更新的已处理请求取代、且并非当前运行 revision 的：放；
  /// - 其余（revision 与运行中的相同却无法证明没被引用）：留。
  bool _released(_AcceptedSpec a) {
    final k = _kernel;
    if (k == null) return false;
    final confirmed = _confirmed();
    if (a.epoch != k.epoch) return confirmed != null;
    if (a.seq > k.appliedSeq) return false;
    if (identical(a, _newestApplied()) || identical(a, confirmed)) return false;
    if (confirmed != null && a.seq < confirmed.seq) return true;
    if (a.noop) return true;
    final running =
        k.status == KernelStatus.started &&
        k.activeConfigRevision == a.revision;
    return !running;
  }

  /// 没有任何记录引用的 seq 文件，哪些可以删：保留最新 [_untrackedKeepNewest]
  /// 份与宽限期内的；其余只有在已有确认运行的 spec 时才删（拿不准就留）。
  Future<List<File>> _untrackedSeqFiles(Directory dir) async {
    final tracked = {for (final a in _accepted) a.path};
    final inFlight = {..._files.values};
    final found = <({File file, DateTime modified})>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_seqFile.hasMatch(entity.uri.pathSegments.last)) continue;
      if (tracked.contains(entity.path) || inFlight.contains(entity.path)) {
        continue;
      }
      found.add((file: entity, modified: await entity.lastModified()));
    }
    found.sort((a, b) => b.modified.compareTo(a.modified));
    return [for (final f in found) f.file];
  }

  /// 删除可以释放的文件。绝不删：仍在准备/发送中的意图的文件、受保护的记录。
  /// 孤立的 prep 文件（上次进程被杀留下的）只在超过一小时后删除，避免误伤别的
  /// 在途准备。
  Future<void> _cleanup(Directory dir) async {
    final inFlight = {..._files.values};
    final now = DateTime.now();

    for (final a in [
      for (final a in _accepted)
        if (_released(a)) a,
    ]) {
      if (inFlight.contains(a.path)) continue;
      try {
        final f = File(a.path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('删除旧运行时配置失败（忽略）: $e');
        continue;
      }
      _accepted.remove(a);
    }

    // 孤立 prep 文件。
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_prepFile.hasMatch(entity.uri.pathSegments.last)) continue;
      if (inFlight.contains(entity.path)) continue;
      final modified = await entity.lastModified();
      if (now.difference(modified) > const Duration(hours: 1)) {
        await entity.delete();
      }
    }

    // 没有记录引用的 seq 文件：最新几份留着，宽限期内的留着。
    final untracked = await _untrackedSeqFiles(dir);
    for (final f in untracked.skip(_untrackedKeepNewest)) {
      final modified = await f.lastModified();
      if (now.difference(modified) < untrackedGrace) continue;
      try {
        await f.delete();
      } catch (e) {
        debugPrint('删除遗留运行时配置失败（忽略）: $e');
      }
    }
    if (_confirmed() != null) {
      for (final f in untracked.take(_untrackedKeepNewest)) {
        final modified = await f.lastModified();
        if (now.difference(modified) < untrackedGrace) continue;
        try {
          await f.delete();
        } catch (e) {
          debugPrint('删除遗留运行时配置失败（忽略）: $e');
        }
      }
    }
  }

  /// 留存配额：除「确认运行的」「最新已处理的」和在途的之外，仍留存的运行时
  /// 配置文件数 ≥ [kMaxRetainedRuntimeFiles] 时，先尝试回收；回收后仍超限就
  /// 以 [RuntimeFilesExhausted] 拒绝这次准备，不再继续写文件。
  Future<void> _enforceQuota(Directory dir) async {
    if (await _retainedExtras(dir) < kMaxRetainedRuntimeFiles) return;
    await _scheduleCleanup(dir);
    if (await _retainedExtras(dir) >= kMaxRetainedRuntimeFiles) {
      throw const LaunchPreparationException(RuntimeFilesExhausted());
    }
  }

  Future<int> _retainedExtras(Directory dir) async {
    final protected = {
      _confirmed()?.path,
      _newestApplied()?.path,
      ..._files.values,
    };
    var n = _accepted.where((a) => !protected.contains(a.path)).length;
    final untracked = await _untrackedSeqFiles(dir);
    n += untracked.skip(_untrackedKeepNewest).length;
    return n;
  }
}

/// 一次被协调器受理的请求所引用的运行时配置文件。
class _AcceptedSpec {
  _AcceptedSpec({
    required this.path,
    required this.revision,
    required this.epoch,
    required this.seq,
    required this.attemptAtSend,
  });

  final String path;
  final int revision;
  final String epoch;
  final int seq;

  /// 发送时内核已知的 attempt；null = 未知（无法确认是否启动过新实例）。
  final int? attemptAtSend;

  /// 已经被 [ConnectionLauncher._resolve] 定性（启动了新实例 / 无操作合并）。
  bool resolved = false;

  /// 启动了当前这一代实例。
  bool started = false;

  /// 相同 revision，被协调器无操作合并。
  bool noop = false;
}

final connectionLauncherProvider = Provider<ConnectionLauncher>((ref) {
  return ConnectionLauncher(ref);
});
