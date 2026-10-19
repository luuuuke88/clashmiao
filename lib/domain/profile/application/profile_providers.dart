// 订阅（Profile）相关的 provider：仓库、订阅列表、当前激活订阅，以及调试用的假数据。

import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ============ Profile Providers ============

final profileRepositoryProvider = FutureProvider<ProfileRepository>((
  ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final appDir = await getApplicationDocumentsDirectory();

  // 核心 bug 修复：此前这里硬编码 `findProxy = (_) => 'DIRECT'`，订阅刷新
  // 永远直连、绝不经过本地隧道。如果订阅源本身是那种必须经隧道才能访问的
  // 服务器（比如被墙的域名，只有连上 VPN 后才能访问），订阅刷新会在隧道
  // 明明健康可用的情况下必定失败。改成 `preferTunnel: true`：优先尝试
  // 通过本地 sing-box 的 mixed 代理端口发出请求，连接失败（sing-box 未启动 /
  // mixed 端口未监听）时自动降级直连——两种场景都能覆盖，不再是"永远直连"
  // 这一种。TLS 证书仍使用系统默认校验；生产环境不能接受任意证书。
  final mixedPort = ref.read(networkSettingsProvider).mixedPort;
  final dio = createAppHttpClient(preferTunnel: true, mixedPort: mixedPort);

  final boxService = ref.watch(boxServiceProvider);

  return ProfileRepository(
    dio: dio,
    configDir: Directory(appDir.path),
    prefs: prefs,
    boxService: boxService,
  );
});

/// 所有订阅列表
final profileListProvider = FutureProvider<List<ProfileEntity>>((ref) async {
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_EMPTY_PROFILES')) {
    return const [];
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROFILE_LIST')) {
    return _debugProfileList;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_NO_ACTIVE_PROFILE')) {
    return _debugNoActiveProfileList;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_PROFILE')) {
    return [_debugHomeProfile];
  }

  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getAll();
});

/// 当前激活订阅
final activeProfileProvider = FutureProvider<ProfileEntity?>((ref) async {
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_EMPTY_PROFILES')) {
    return null;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_PROFILE_LIST')) {
    return _debugProfileList.first;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_NO_ACTIVE_PROFILE')) {
    return null;
  }
  if (kDebugMode &&
      const bool.fromEnvironment('CLASHMIAO_DEBUG_HOME_PROFILE')) {
    return _debugHomeProfile;
  }

  final repo = await ref.watch(profileRepositoryProvider.future);
  return repo.getActive();
});

final _debugHomeProfile = ProfileEntity(
  id: 'debug-home-profile',
  name: 'ClashMiao Pro',
  url: 'https://example.com/debug-sub',
  active: true,
  subInfo: SubscriptionInfo(
    upload: 2 * 1024 * 1024 * 1024,
    download: 28 * 1024 * 1024 * 1024,
    total: 120 * 1024 * 1024 * 1024,
    expire: DateTime(2026, 12, 31),
  ),
);

final _debugProfileList = [
  _debugHomeProfile,
  ProfileEntity(
    id: 'debug-profile-no-subinfo',
    name: '无订阅信息',
    url: 'https://example.com/no-sub',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 10),
  ),
  ProfileEntity(
    id: 'debug-local-profile',
    name: '本地导入',
    url: 'content://local-debug-config',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 20),
  ),
];

final _debugNoActiveProfileList = [
  ProfileEntity(
    id: 'debug-no-active-remote',
    name: 'ClashMiao Pro',
    url: 'https://example.com/debug-sub',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 20),
  ),
  ProfileEntity(
    id: 'debug-no-active-local',
    name: '本地导入',
    url: 'content://local-debug-config',
    active: false,
    lastUpdate: DateTime(2026, 6, 12, 1, 30),
  ),
];
