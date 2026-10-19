// 离线代理组解析：直接读订阅配置文件，不依赖核心库是否在运行。

import 'dart:io';

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/routing/data/config_parser.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ============ 离线代理解析 ============

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
  return ConfigParser.parseFile(configPath);
});
