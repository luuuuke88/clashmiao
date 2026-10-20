// 离线代理组解析：不依赖内核是否在运行。
//
// 运行时配置由内核的配置构建器生成，它会丢掉订阅里自带的 selector / urltest
// 分组、重建自己的主选择组与自动选择组——订阅配置文件里的分组 tag（例如
// `proxy`）在运行时根本不存在。所以能编译的平台上，离线分组取自「把订阅配置
// 编译成运行时配置」的结果，tag 与连接后内核报出的实时分组一致：离线时看到的
// 选中项、存储里的手选、连接后的实时分组说的是同一组 tag。编译不可用或失败时
// 才退回直接解析订阅配置（只用于展示，内核操作一律只对实时分组发起）。

import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:clashmiao/domain/routing/data/config_parser.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============ 离线代理解析 ============

/// 把订阅配置文件编译成运行时配置文本；`null` = 当前平台不用这条路径。
///
/// 只在 Android 上启用：编译走 Pigeon（异步、在原生 IO 线程）。桌面端的 FFI
/// 编译会阻塞 UI isolate，iOS 未验证，二者维持直接解析订阅配置。
final runtimeConfigCompilerProvider =
    Provider<Future<String?> Function(String path)?>((ref) {
      if (!Platform.isAndroid) return null;
      final service = ref.watch(boxServiceProvider);
      return service.generateFullConfig;
    });

/// 离线分组：优先取运行时形态（[compile] 编译后的配置），失败或为空时退回
/// 直接解析 [configPath]。
@visibleForTesting
Future<List<OutboundGroup>> loadOfflineGroups(
  String configPath, {
  Future<String?> Function(String path)? compile,
}) async {
  if (compile != null) {
    try {
      final compiled = await compile(configPath);
      if (compiled != null && compiled.isNotEmpty) {
        final groups = ConfigParser.parseConfig(compiled);
        if (groups.isNotEmpty) return groups;
      }
    } catch (e) {
      debugPrint('离线分组：编译运行时配置失败，退回解析订阅配置: $e');
    }
  }
  return ConfigParser.parseFile(configPath);
}

/// 从配置文件解析代理组（不依赖核心库）
final offlineProxyGroupsProvider = FutureProvider<List<OutboundGroup>>((
  ref,
) async {
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROXY_FIXTURE')) {
    return const [
      OutboundGroup(
        tag: 'proxy',
        type: 'selector',
        selected: '香港 01 | SS',
        items: [
          OutboundProxy(tag: 'Auto', type: 'urltest', delay: 86),
          OutboundProxy(tag: '香港 01 | SS', type: 'shadowsocks', delay: 128),
          OutboundProxy(tag: '日本 Tokyo 02', type: 'vmess', delay: 241),
          OutboundProxy(tag: 'US Los Angeles 03', type: 'vless', delay: 618),
          OutboundProxy(tag: 'Singapore 04', type: 'trojan'),
        ],
      ),
    ];
  }

  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return [];

  final repo = await ref.read(profileRepositoryProvider.future);
  final configPath = repo.configFilePath(profile.id);
  final file = File(configPath);
  if (!await file.exists()) return [];
  return loadOfflineGroups(
    configPath,
    compile: ref.read(runtimeConfigCompilerProvider),
  );
});

/// 当前订阅配置的信息条目排除集（`subscriptionInfoExclusionsForConfig`，按整份
/// 配置的全部候选叶子节点算，与运行时配置构建器同一口径）。线路页用它过滤
/// 离线分组。读不到或解析不了时为空集（不排除任何东西）。
final offlineInfoExclusionsProvider = FutureProvider<Set<String>>((ref) async {
  final profile = await ref.watch(activeProfileProvider.future);
  if (profile == null) return const {};
  try {
    final repo = await ref.read(profileRepositoryProvider.future);
    final file = File(repo.configFilePath(profile.id));
    if (!await file.exists()) return const {};
    final cfg = jsonDecode(await file.readAsString());
    if (cfg is! Map<String, dynamic>) return const {};
    return subscriptionInfoExclusionsForConfig(cfg);
  } catch (e) {
    debugPrint('离线信息条目排除集：读取订阅配置失败: $e');
    return const {};
  }
});
