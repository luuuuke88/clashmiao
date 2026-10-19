// 连接启动产物的准备：每个 on 请求一份独立的运行时配置文件与内联 options。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §5「ConnectionLauncher」与计划补充 P4 ①：
// - 先写 `runtime-config-prep-<token>.json`（此时还不知道 seq，也不知道意图是否
//   仍然有效）；
// - 状态机确认意图仍有效、分配 seq 之后，改名为 `runtime-config-<seq>.json`；
// - `configRevision` = 对（options JSON + 运行时配置内容）的稳定哈希：相同配置
//   得到相同 revision、协调器不会重载；
// - 清理旧文件只保留最新两份与最近被受理的请求所引用的文件，绝不动协调器快照
//   / 持久化 spec 仍可能引用的那一份。

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

  /// 最近被协调器受理的请求所引用的运行时配置文件（新的在后）。它们可能仍被
  /// 内核实例或持久化的 LaunchSpec 引用，清理时绝不能删。
  final List<String> _accepted = [];

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
    return LaunchSpec(
      runtimeConfigPath: target,
      optionsJson: spec.optionsJson,
      profileName: spec.profileName,
      configRevision: spec.configRevision,
    );
  }

  /// 协调器受理了引用 [spec] 的请求：记下它，并清理旧文件。
  Future<void> accepted(int id, LaunchSpec spec) async {
    _accepted.remove(spec.runtimeConfigPath);
    _accepted.add(spec.runtimeConfigPath);
    if (_accepted.length > 2) _accepted.removeRange(0, _accepted.length - 2);
    _files.remove(id);
    try {
      await _cleanup(File(spec.runtimeConfigPath).parent);
    } catch (e) {
      debugPrint('清理旧运行时配置失败（忽略）: $e');
    }
  }

  /// 意图终结且没有被受理：删除还留在磁盘上的 prep / 已绑定文件。
  Future<void> discard(int id) async {
    final path = _files.remove(id);
    if (path == null) return;
    if (_accepted.contains(path)) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('删除未使用的运行时配置失败（忽略）: $e');
    }
  }

  static final RegExp _seqFile = RegExp(r'^runtime-config-(\d+)\.json$');
  static final RegExp _prepFile = RegExp(r'^runtime-config-prep-.+\.json$');

  /// 保留：最新两份（按修改时间）、最近被受理请求引用的文件、仍在准备/发送中的
  /// 意图的文件；其余 `runtime-config-<seq>.json` 删除。孤立的 prep 文件（上次
  /// 进程被杀留下的）只在超过一小时后删除，避免误伤别的在途准备。
  Future<void> _cleanup(Directory dir) async {
    final inUse = {..._accepted, ..._files.values};
    final seqFiles = <({File file, DateTime modified})>[];
    final now = DateTime.now();
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (_prepFile.hasMatch(name)) {
        if (inUse.contains(entity.path)) continue;
        final modified = await entity.lastModified();
        if (now.difference(modified) > const Duration(hours: 1)) {
          await entity.delete();
        }
      } else if (_seqFile.hasMatch(name)) {
        seqFiles.add((file: entity, modified: await entity.lastModified()));
      }
    }
    seqFiles.sort((a, b) => b.modified.compareTo(a.modified));
    final keep = {for (final f in seqFiles.take(2)) f.file.path};
    for (final f in seqFiles) {
      if (keep.contains(f.file.path) || inUse.contains(f.file.path)) continue;
      await f.file.delete();
    }
  }
}

final connectionLauncherProvider = Provider<ConnectionLauncher>((ref) {
  return ConnectionLauncher(ref);
});
