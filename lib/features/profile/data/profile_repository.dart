import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/features/profile/data/profile_parser.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 订阅仓库 - 管理订阅的增删改查和配置文件下载
class ProfileRepository {
  ProfileRepository({
    required this.dio,
    required this.configDir,
    required this.prefs,
    required this.boxService,
  });

  final Dio dio;

  /// 配置文件存储目录
  final Directory configDir;

  final SharedPreferences prefs;

  /// 用于把订阅原始内容（Clash YAML / vless 链接列表 / sing-box JSON）
  /// 归一化成 sing-box JSON。native 的 `parse` 入口会原地覆盖文件。
  final BoxService boxService;

  static const _profilesKey = 'clashmiao_profiles';
  static const _activeProfileKey = 'clashmiao_active_profile';
  static Map<String, String>? _userAgentHeaders(String? customUserAgent) {
    if (customUserAgent == null || customUserAgent.trim().isEmpty) return null;

    return {'User-Agent': customUserAgent.trim()};
  }

  /// 获取所有订阅
  List<ProfileEntity> getAll() {
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => ProfileEntity.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 保存所有订阅
  Future<void> _saveAll(List<ProfileEntity> profiles) async {
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((e) => e.toJson()).toList()),
    );
  }

  /// 获取当前激活的订阅
  ProfileEntity? getActive() {
    final activeId = prefs.getString(_activeProfileKey);
    if (activeId == null) return null;
    final profiles = getAll();
    try {
      return profiles.firstWhere((p) => p.id == activeId);
    } catch (_) {
      return profiles.isNotEmpty ? profiles.first : null;
    }
  }

  /// 设置激活的订阅
  Future<void> setActive(String profileId) async {
    await prefs.setString(_activeProfileKey, profileId);
    final profiles = getAll();
    final updated = profiles.map((p) {
      return p.copyWith(active: p.id == profileId);
    }).toList();
    await _saveAll(updated);
  }

  /// 直接导入单节点 / 内嵌订阅内容（ss:// vless:// trojan:// hysteria2:// vmess://
  /// 等代理 URI，或者一段已经是 Clash YAML / sing-box JSON 的文本）。
  ///
  /// 不走 HTTP 获取，把内容当订阅 body 直接喂给 native parse。
  /// 适用：剪贴板粘贴的单节点 URI、本地手动备份的配置内容。
  Future<ProfileEntity> addByContent(
    String content, {
    required String name,
  }) async {
    final id = const Uuid().v4();
    final configFile = File(configFilePath(id));
    await configFile.parent.create(recursive: true);
    await _normalizeAndWrite(rawBody: content, output: configFile);

    // 补齐 parse/raw JSON 输出中的配置结构：
    // ss:// / vless:// 单 URI 解析出来通常只有一个代理 outbound，没有 direct、
    // 没有 selector group、没有 route.final。RuntimeConfigBuilder 智能模式
    // 注入的 `outbound: 'direct'` 规则会找不到 direct outbound，整条路由失效，
    // 流量绕过 TUN 走系统默认链路。
    if (await configFile.exists()) {
      await _ensureMinimalProfileStructure(configFile);
    }

    final isFirst = getAll().isEmpty;
    final entity = ProfileEntity(
      id: id,
      // 不存完整 URI 到 url（可能含敏感凭据 / 密码）
      name: name.trim().isEmpty ? '本地导入' : name.trim(),
      url: 'content://${_truncate(content, 24)}',
      active: isFirst,
      lastUpdate: DateTime.now(),
    );

    final profiles = getAll();
    profiles.add(entity);
    await _saveAll(profiles);
    if (isFirst) await setActive(id);
    return entity;
  }

  /// 给 native parse 出的精简 profile 补齐：
  /// - outbounds: 缺 direct 加 direct；缺 selector 自动包装出 `proxy` selector
  /// - route.final: 缺则指向 proxy（或第一个非 direct outbound）
  /// - inbounds: 缺则补 tun + mixed（移动端用 tun，桌面端 RuntimeConfigBuilder
  ///   会 strip 掉，最后 fork 自己接管）
  /// 已有这些字段则保留不动。
  Future<void> _ensureMinimalProfileStructure(File file) async {
    final raw = await file.readAsString();
    final Map<String, dynamic> cfg;
    try {
      cfg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // 不是 JSON（StubBoxService fallback 写的原文），不动
      return;
    }

    final outbounds = (cfg['outbounds'] as List?)?.cast<dynamic>() ?? [];

    var changed = false;
    final hasDirect = outbounds.any((o) => o is Map && o['type'] == 'direct');
    if (!hasDirect) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
      changed = true;
    }

    const groupTypes = {'selector', 'urltest', 'url_test'};
    final removedUrlTestTags = <String>{};
    outbounds.removeWhere((o) {
      if (o is! Map || !{'urltest', 'url_test'}.contains(o['type'])) {
        return false;
      }
      final tag = o['tag'];
      if (tag is String) removedUrlTestTags.add(tag);
      return true;
    });
    if (removedUrlTestTags.isNotEmpty) {
      changed = true;
    }

    final tagsSet = <String>{
      for (final o in outbounds)
        if (o is Map && o['tag'] is String) o['tag'] as String,
    };
    final tagTypes = <String, String>{
      for (final o in outbounds)
        if (o is Map && o['tag'] is String && o['type'] is String)
          o['tag'] as String: o['type'] as String,
    };
    bool isLeafProxyTag(String tag) {
      final type = tagTypes[tag];
      return type != null &&
          type != 'direct' &&
          type != 'dns' &&
          type != 'block' &&
          !groupTypes.contains(type);
    }

    final proxyTags = outbounds
        .where(
          (o) =>
              o is Map &&
              o['tag'] is String &&
              o['type'] != 'direct' &&
              o['type'] != 'dns' &&
              o['type'] != 'block' &&
              !groupTypes.contains(o['type']),
        )
        .map((o) => (o as Map)['tag'] as String)
        .toList();
    String? preferredDefaultFor(List<String> tags) {
      if (tags.isEmpty) return null;
      return tags.firstWhere(
        (tag) => !_isLikelyInformationalProxyTag(tag),
        orElse: () => tags.first,
      );
    }

    bool shouldReplaceDefault(Object? current, List<String> tags) {
      if (current is! String || !tags.contains(current)) return true;
      final preferred = preferredDefaultFor(tags);
      return preferred != null &&
          preferred != current &&
          _isLikelyInformationalProxyTag(current);
    }

    Map<dynamic, dynamic>? proxySelector;
    for (final outbound in outbounds) {
      if (outbound is! Map || !groupTypes.contains(outbound['type'])) {
        continue;
      }
      final current =
          (outbound['outbounds'] as List?)
              ?.whereType<String>()
              .where(tagsSet.contains)
              .toList() ??
          <String>[];
      final currentLeafTags = current.where(isLeafProxyTag).toList();
      if (outbound['type'] == 'selector' && outbound['tag'] == 'proxy') {
        proxySelector = outbound;
      }
      if (currentLeafTags.length != current.length &&
          outbound['type'] == 'selector') {
        outbound['outbounds'] = currentLeafTags;
        final currentDefault = outbound['default'];
        if (shouldReplaceDefault(currentDefault, currentLeafTags)) {
          outbound['default'] = preferredDefaultFor(currentLeafTags);
        }
        changed = true;
      }
      if (currentLeafTags.isEmpty && proxyTags.isNotEmpty) {
        outbound['outbounds'] = proxyTags;
        if (shouldReplaceDefault(outbound['default'], proxyTags)) {
          outbound['default'] = preferredDefaultFor(proxyTags);
        }
        changed = true;
      }
    }

    if (proxySelector != null && proxyTags.isNotEmpty) {
      final current =
          (proxySelector['outbounds'] as List?)
              ?.whereType<String>()
              .where(isLeafProxyTag)
              .toList() ??
          <String>[];
      final currentDefault = proxySelector['default'];
      if (!listEquals(current, proxyTags) ||
          shouldReplaceDefault(currentDefault, proxyTags)) {
        proxySelector['outbounds'] = proxyTags;
        proxySelector['default'] =
            shouldReplaceDefault(currentDefault, proxyTags)
            ? preferredDefaultFor(proxyTags)
            : currentDefault;
        changed = true;
      }
    }

    if (proxyTags.isNotEmpty) {
      Map<dynamic, dynamic>? existingProxy;
      for (final outbound in outbounds) {
        if (outbound is Map &&
            outbound['tag'] == 'proxy' &&
            outbound['type'] == 'selector') {
          existingProxy = outbound;
          break;
        }
      }
      if (existingProxy != null) {
        final current =
            (existingProxy['outbounds'] as List?)
                ?.whereType<String>()
                .where(isLeafProxyTag)
                .toList() ??
            <String>[];
        final currentDefault = existingProxy['default'];
        if (!listEquals(current, proxyTags) ||
            shouldReplaceDefault(currentDefault, proxyTags)) {
          existingProxy['outbounds'] = proxyTags;
          existingProxy['default'] =
              shouldReplaceDefault(currentDefault, proxyTags)
              ? preferredDefaultFor(proxyTags)
              : currentDefault;
          changed = true;
        }
      } else {
        outbounds.insert(0, {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': proxyTags,
          'default': preferredDefaultFor(proxyTags),
        });
        tagsSet.add('proxy');
        tagTypes['proxy'] = 'selector';
        changed = true;
      }
    }

    String? normalizeOutboundReference(dynamic value) {
      if (value is! String) return null;
      final type = tagTypes[value];
      final shouldUseProxy =
          removedUrlTestTags.contains(value) ||
          !tagsSet.contains(value) ||
          type == 'urltest' ||
          type == 'url_test' ||
          (type == 'selector' && value != 'proxy');
      if (!shouldUseProxy) return value;
      if (proxyTags.isNotEmpty && tagsSet.contains('proxy')) return 'proxy';
      if (tagsSet.contains('direct')) return 'direct';
      return null;
    }

    final route = (cfg['route'] is Map<String, dynamic>)
        ? cfg['route'] as Map<String, dynamic>
        : <String, dynamic>{};
    final finalTag = route['final'];
    final finalType = finalTag is String ? tagTypes[finalTag] : null;
    final shouldRouteViaProxy =
        proxyTags.isNotEmpty &&
        tagsSet.contains('proxy') &&
        finalTag != 'proxy';
    if (shouldRouteViaProxy ||
        finalTag is! String ||
        !tagsSet.contains(finalTag) ||
        finalType == 'urltest' ||
        finalType == 'url_test') {
      // 优先 proxy selector；没有就用第一个非 direct 的。
      //
      // 先落到有类型的局部变量再取 'tag'，不要把 `firstWhere(...)['tag']` 串成
      // 一行：`firstWhere` 在 `List<dynamic>` 上返回 dynamic，直接下标就是一次
      // dynamic 调用——类型对不上时不会在这里报错，而是在几层之后以一个跟现场
      // 无关的 NoSuchMethodError 冒出来。
      final Object? fallbackOutbound = outbounds.firstWhere(
        (o) => o is Map && o['type'] != 'direct',
        orElse: () => {'tag': 'direct'},
      );
      route['final'] = tagsSet.contains('proxy')
          ? 'proxy'
          : (fallbackOutbound is Map ? fallbackOutbound['tag'] : 'direct');
      cfg['route'] = route;
      changed = true;
    }
    final routeRules = route['rules'];
    if (routeRules is List) {
      for (final rule in routeRules) {
        if (rule is! Map) continue;
        final current = rule['outbound'];
        final normalized = normalizeOutboundReference(current);
        if (normalized != null && normalized != current) {
          rule['outbound'] = normalized;
          changed = true;
        }
      }
    }
    final routeRuleSet = route['rule_set'];
    if (routeRuleSet is List) {
      for (final ruleSet in routeRuleSet) {
        if (ruleSet is! Map) continue;
        final current = ruleSet['download_detour'];
        final normalized = normalizeOutboundReference(current);
        if (normalized != null && normalized != current) {
          ruleSet['download_detour'] = normalized;
          changed = true;
        }
      }
    }

    // dns.servers 缺失会让 RuntimeConfigBuilder 注入的 `server: "local"` 引用
    // 不到任何 server → sing-box DNS 阶段没有解析后端 → Chrome 上 DNS_PROBE_
    // FINISHED_NO_INTERNET。补上标准两 server：local（系统）+ remote（走代理）。
    final dns = (cfg['dns'] is Map<String, dynamic>)
        ? cfg['dns'] as Map<String, dynamic>
        : <String, dynamic>{};
    final dnsServers = (dns['servers'] as List?)?.cast<dynamic>() ?? [];
    if (dnsServers.isEmpty) {
      // 3 层 DNS server 链（参考 sing-box 推荐套路）：
      //   remote → 远程 DNS（走代理）。用 DoH 而不是 udp://1.1.1.1，因为很多 SS /
      //            Trojan 节点不转发 UDP，udp DNS 永远超时。RuntimeConfigBuilder
      //            每次 connect 会按用户 NetworkSettings.remoteDnsAddress 覆盖。
      //   direct → 直连 DNS（用来解析 remote 自己的域名 + 国内域名）
      //   local  → 系统 DNS（用来解析 direct 自己的域名 fallback）
      dnsServers.addAll([
        {'tag': 'remote', 'address': 'https://1.1.1.1/dns-query'},
        {'tag': 'direct', 'address': '1.1.1.1', 'detour': 'direct'},
        {'tag': 'local', 'address': 'local', 'detour': 'direct'},
      ]);
      dns['servers'] = dnsServers;
      dns['final'] = dns['final'] ?? 'remote';
      cfg['dns'] = dns;
      changed = true;
    }
    for (final server in dnsServers) {
      if (server is! Map) continue;
      final current = server['detour'];
      final normalized = normalizeOutboundReference(current);
      if (normalized != null && normalized != current) {
        server['detour'] = normalized;
        changed = true;
      }
    }

    // tun + mixed 一并使用 App 自己验证过的 schema。服务端 raw sing-box JSON
    // 可能带 `address`、`users` 等当前 mobile core 不接受的字段。
    //
    // 桌面端这两条都会被 RuntimeConfigBuilder strip 掉，由 fork 自动 append。
    final standardInbounds = <Map<String, dynamic>>[
      {
        'type': 'tun',
        'tag': 'tun-in',
        'stack': 'mixed',
        'mtu': 9000,
        'auto_route': true,
        'strict_route': true,
        'endpoint_independent_nat': true,
        'inet4_address': ['172.19.0.1/28'],
        'inet6_address': ['fdfe:dcba:9876::1/126'],
        'sniff': true,
        'sniff_override_destination': true,
      },
      {
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 2080,
        'sniff': true,
        'sniff_override_destination': true,
      },
    ];
    if (jsonEncode(cfg['inbounds'] ?? []) != jsonEncode(standardInbounds)) {
      cfg['inbounds'] = standardInbounds;
      changed = true;
    }

    if (changed) {
      cfg['outbounds'] = outbounds;
      await file.writeAsString(jsonEncode(cfg));
    }
  }

  static String _truncate(String s, int n) {
    final stripped = s.trim().replaceAll(RegExp(r'\s+'), '');
    return stripped.length <= n ? stripped : '${stripped.substring(0, n)}...';
  }

  static bool _isLikelyInformationalProxyTag(String tag) {
    final lower = tag.toLowerCase();
    return lower.contains('官网') ||
        lower.contains('官方') ||
        lower.contains('网址') ||
        lower.contains('订阅') ||
        lower.contains('套餐') ||
        lower.contains('流量') ||
        lower.contains('剩余') ||
        lower.contains('到期') ||
        lower.contains('过期') ||
        lower.contains('expire') ||
        lower.contains('traffic') ||
        lower.contains('website') ||
        lower.contains('official');
  }

  /// 添加订阅（下载并解析）
  /// [customName] 用户自定义名称，不传则从响应头自动解析
  ///
  /// 去重：同一 URL（trim 后比较）重复添加不会产生第二条记录——
  /// 找到已有的那条，直接复用 [update] 触发一次真实的重新拉取（并按需
  /// 更新名称），不新建 profile / 不新建配置文件。
  Future<ProfileEntity> addByUrl(String url, {String? customName}) async {
    final normalizedUrl = url.trim();
    ProfileEntity? existing;
    for (final p in getAll()) {
      if (p.url.trim() == normalizedUrl) {
        existing = p;
        break;
      }
    }
    if (existing != null) {
      if (customName != null && customName.trim().isNotEmpty) {
        await editProfile(existing.id, newName: customName.trim());
      }
      return update(existing.id);
    }

    final response = await dio.get<String>(
      normalizedUrl,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        headers: _userAgentHeaders(null),
      ),
    );

    // 解析响应头
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values;
    });

    var profile = ProfileParser.parse(normalizedUrl, headers);

    // 优先使用用户自定义名称
    if (customName != null && customName.trim().isNotEmpty) {
      profile = profile.copyWith(name: customName.trim());
    }

    // 归一化：先把原始响应写到 tempFile（输入），让 native parse 读它、
    // 解析（Clash YAML / base64 / sing-box JSON）后**写到** configFile（输出）。
    final configFile = File(configFilePath(profile.id));
    await configFile.parent.create(recursive: true);
    final needsStructureRepair = await _normalizeAndWrite(
      rawBody: response.data ?? '',
      output: configFile,
    );
    if (needsStructureRepair) {
      await _ensureMinimalProfileStructure(configFile);
    }

    // 添加到列表
    final profiles = getAll();
    final isFirst = profiles.isEmpty;
    final entity = profile.copyWith(active: isFirst);
    profiles.add(entity);
    await _saveAll(profiles);

    if (isFirst) {
      await setActive(entity.id);
    }

    return entity;
  }

  /// 更新指定订阅
  Future<ProfileEntity> update(String profileId) async {
    final profiles = getAll();
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) throw Exception('Profile not found/订阅不存在');

    final current = profiles[index];
    final response = await dio.get<String>(
      current.url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        headers: _userAgentHeaders(current.customUserAgent),
      ),
    );

    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values;
    });

    // 更新订阅信息
    final parsed = ProfileParser.parse(current.url, headers);
    final subInfo = parsed.subInfo;

    // 重新归一化（参见 addByUrl 注释）
    final configFile = File(configFilePath(profileId));
    final needsStructureRepair = await _normalizeAndWrite(
      rawBody: response.data ?? '',
      output: configFile,
    );
    if (needsStructureRepair) {
      await _ensureMinimalProfileStructure(configFile);
    }

    final updated = current.copyWith(
      lastUpdate: DateTime.now(),
      subInfo: subInfo ?? current.subInfo,
    );
    profiles[index] = updated;
    await _saveAll(profiles);

    return updated;
  }

  /// 替换整个订阅实体（按 id 匹配）
  Future<void> updateProfile(ProfileEntity entity) async {
    final profiles = getAll();
    final index = profiles.indexWhere((p) => p.id == entity.id);
    if (index < 0) return;
    profiles[index] = entity;
    await _saveAll(profiles);
  }

  /// 编辑订阅信息（名称、URL）
  Future<void> editProfile(
    String profileId, {
    String? newName,
    String? newUrl,
  }) async {
    final profiles = getAll();
    final index = profiles.indexWhere((p) => p.id == profileId);
    if (index < 0) return;
    final current = profiles[index];
    profiles[index] = current.copyWith(
      name: (newName != null && newName.trim().isNotEmpty)
          ? newName.trim()
          : current.name,
      url: (newUrl != null && newUrl.trim().isNotEmpty)
          ? newUrl.trim()
          : current.url,
    );
    await _saveAll(profiles);
  }

  /// 插入或更新订阅（按 id 匹配；备份恢复时使用）
  Future<void> upsert(Map<String, dynamic> json) async {
    final entity = ProfileEntity.fromJson(json);
    final profiles = getAll();
    final idx = profiles.indexWhere((p) => p.id == entity.id);
    if (idx >= 0) {
      profiles[idx] = entity;
    } else {
      profiles.add(entity);
    }
    await _saveAll(profiles);
  }

  /// 删除订阅
  Future<void> delete(String profileId) async {
    final profiles = getAll();
    profiles.removeWhere((p) => p.id == profileId);
    await _saveAll(profiles);

    // 删除配置文件
    final configFile = File(configFilePath(profileId));
    if (await configFile.exists()) {
      await configFile.delete();
    }

    // 如果删掉的是激活的，切换到第一个
    final activeId = prefs.getString(_activeProfileKey);
    if (activeId == profileId && profiles.isNotEmpty) {
      await setActive(profiles.first.id);
    }
  }

  /// 更新全部订阅
  Future<void> updateAll() async {
    final profiles = getAll();
    for (final profile in profiles) {
      try {
        await update(profile.id);
      } catch (_) {
        // 单个更新失败不影响其他
      }
    }
  }

  /// 把订阅原始 body 归一化成 sing-box JSON 并写到 [output]。
  ///
  /// **优先**：如果 raw 是合法 sing-box JSON（`{` 开头，能 jsonDecode 出 outbounds），
  /// 先直接写出原文——保留 inbounds / dns / route / rule_set 等完整字段，
  /// 再走结构修复，避免订阅自带的多级 selector / urltest 让 UI 和运行态退回
  /// 不稳定分组。
  ///
  /// **否则**：调 native `parse(configPath, tempPath)`（Clash YAML / vless 链接 → sing-box JSON），
  /// 但 parse 后的输出只剩 outbounds，需要 RuntimeConfigBuilder 在 connect 时补全。
  Future<bool> _normalizeAndWrite({
    required String rawBody,
    required File output,
  }) async {
    await output.parent.create(recursive: true);
    final normalized = File('${output.path}.next');
    final trimmed = rawBody.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        final outbounds = decoded['outbounds'];
        if (outbounds is List && outbounds.isNotEmpty) {
          await _replaceAtomically(normalized, output, rawBody);
          debugPrint('[Profile] raw 已是 sing-box JSON，跳过 native parse');
          return true;
        }
      } catch (_) {
        // 不是合法 JSON 就 fallthrough 到 native parse
      }
    }

    if (boxService is StubBoxService) {
      await _replaceAtomically(normalized, output, rawBody);
      return false;
    }
    final tempFile = File('${output.path}.tmp');
    try {
      if (await normalized.exists()) await normalized.delete();
      await tempFile.writeAsString(rawBody);
      debugPrint('[Profile] native validateConfig start');
      final err = await boxService
          .validateConfig(normalized.path, tempFile.path)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const ProfileValidationException('配置解析超时'),
          );
      debugPrint('[Profile] native validateConfig done');
      if (err != null && err.isNotEmpty) {
        throw ProfileValidationException(err);
      }
      if (!await normalized.exists()) {
        throw const ProfileValidationException(
          'validateConfig did not write output',
        );
      }
      await _commitNormalized(normalized, output);
      return true;
    } catch (e, st) {
      debugPrint('[Profile] _normalizeAndWrite 抛异常: $e\n$st');
      if (e is ProfileValidationException) rethrow;
      throw ProfileValidationException(e.toString());
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (await normalized.exists()) {
        try {
          await normalized.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _replaceAtomically(
    File staging,
    File output,
    String content,
  ) async {
    await staging.writeAsString(content);
    await _commitNormalized(staging, output);
  }

  Future<void> _commitNormalized(File staging, File output) async {
    await staging.rename(output.path);
  }

  /// 配置文件路径
  String configFilePath(String profileId) {
    return p.join(configDir.path, 'profiles', '$profileId.json');
  }
}

class ProfileValidationException implements Exception {
  const ProfileValidationException(this.message);

  final String message;

  @override
  String toString() => 'ProfileValidationException: $message';
}
