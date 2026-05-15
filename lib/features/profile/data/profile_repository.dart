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

    // 补齐 native parse 输出的"裸 outbounds"结构：
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
    final tagsSet = <String>{
      for (final o in outbounds)
        if (o is Map && o['tag'] is String) o['tag'] as String,
    };

    var changed = false;
    final hasDirect = outbounds.any((o) => o is Map && o['type'] == 'direct');
    if (!hasDirect) {
      outbounds.add({'type': 'direct', 'tag': 'direct'});
      tagsSet.add('direct');
      changed = true;
    }

    final hasSelector = outbounds.any(
      (o) => o is Map && o['type'] == 'selector',
    );
    if (!hasSelector) {
      // proxy 候选 = 所有非 direct / 非 dns / 非 block 的 outbound tag
      final proxyTags = outbounds
          .where(
            (o) =>
                o is Map &&
                o['tag'] is String &&
                o['type'] != 'direct' &&
                o['type'] != 'dns' &&
                o['type'] != 'block',
          )
          .map((o) => (o as Map)['tag'] as String)
          .toList();
      if (proxyTags.isNotEmpty) {
        outbounds.insert(0, {
          'type': 'selector',
          'tag': 'proxy',
          'outbounds': proxyTags,
          'default': proxyTags.first,
        });
        changed = true;
      }
    }

    final route = (cfg['route'] is Map<String, dynamic>)
        ? cfg['route'] as Map<String, dynamic>
        : <String, dynamic>{};
    if (route['final'] == null) {
      // 优先 proxy selector；没有就用第一个非 direct 的
      route['final'] = tagsSet.contains('proxy')
          ? 'proxy'
          : outbounds.firstWhere(
              (o) => o is Map && o['type'] != 'direct',
              orElse: () => {'tag': 'direct'},
            )['tag'];
      cfg['route'] = route;
      changed = true;
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
      //   remote → 远程 DNS（走代理）
      //   direct → 直连 DNS（用来解析 remote 自己的域名 + 国内域名）
      //   local  → 系统 DNS（用来解析 direct 自己的域名 fallback）
      // 不写 detour 让 sing-box 走路由表（route.final / route.rules）。
      // 简化：remote/direct 都用纯 IP，省去 address_resolver 链。
      // local 备用走系统 DNS（不经代理）。
      dnsServers.addAll([
        {'tag': 'remote', 'address': 'udp://1.1.1.1'},
        {'tag': 'direct', 'address': 'udp://1.1.1.1', 'detour': 'direct'},
        {'tag': 'local', 'address': 'local', 'detour': 'direct'},
      ]);
      dns['servers'] = dnsServers;
      dns['final'] = dns['final'] ?? 'remote';
      cfg['dns'] = dns;
      changed = true;
    }

    final inbounds = (cfg['inbounds'] as List?)?.cast<dynamic>() ?? [];
    if (inbounds.isEmpty) {
      // tun + mixed 一并补。tun 配置抄上游 fork 的 default，最稳：
      // - inet4 用 /28 不用 /30（auto_route 兼容性更好）
      // - endpoint_independent_nat: true（关键：sing-box outbound 才能正确 NAT）
      // - sniff: 让 TUN 解析 SNI/HTTP host，路由能按域名分流
      //
      // 桌面端这两条都会被 RuntimeConfigBuilder strip 掉，由 fork 自动 append。
      inbounds.add({
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
      });
      inbounds.add({
        'type': 'mixed',
        'tag': 'mixed-in',
        'listen': '127.0.0.1',
        'listen_port': 2080,
        'sniff': true,
        'sniff_override_destination': true,
      });
      cfg['inbounds'] = inbounds;
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

  /// 添加订阅（下载并解析）
  /// [customName] 用户自定义名称，不传则从响应头自动解析
  Future<ProfileEntity> addByUrl(String url, {String? customName}) async {
    final response = await dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 400,
        headers: {'User-Agent': 'ClashMiao/0.1.0 (sing-box)'},
      ),
    );

    // 解析响应头
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = values;
    });

    var profile = ProfileParser.parse(url, headers);

    // 优先使用用户自定义名称
    if (customName != null && customName.trim().isNotEmpty) {
      profile = profile.copyWith(name: customName.trim());
    }

    // 归一化：先把原始响应写到 tempFile（输入），让 native parse 读它、
    // 解析（Clash YAML / base64 / sing-box JSON）后**写到** configFile（输出）。
    final configFile = File(configFilePath(profile.id));
    await configFile.parent.create(recursive: true);
    await _normalizeAndWrite(rawBody: response.data ?? '', output: configFile);

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
        headers: {'User-Agent': 'ClashMiao/0.1.0 (sing-box)'},
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
    await _normalizeAndWrite(rawBody: response.data ?? '', output: configFile);

    final updated = current.copyWith(
      lastUpdate: DateTime.now(),
      subInfo: subInfo ?? current.subInfo,
    );
    profiles[index] = updated;
    await _saveAll(profiles);

    return updated;
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
  /// 直接写出原文——保留 inbounds / dns / route / rule_set 等完整字段，
  /// 让 fork 的 `enable-full-config: true` 路径能拿到完整 profile。
  ///
  /// **否则**：调 native `parse(configPath, tempPath)`（Clash YAML / vless 链接 → sing-box JSON），
  /// 但 parse 后的输出只剩 outbounds，需要 RuntimeConfigBuilder 在 connect 时补全。
  Future<void> _normalizeAndWrite({
    required String rawBody,
    required File output,
  }) async {
    final trimmed = rawBody.trimLeft();
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
        if (decoded.containsKey('outbounds')) {
          await output.writeAsString(rawBody);
          debugPrint('[Profile] raw 已是 sing-box JSON，跳过 native parse');
          return;
        }
      } catch (_) {
        // 不是合法 JSON 就 fallthrough 到 native parse
      }
    }

    if (boxService is StubBoxService) {
      await output.writeAsString(rawBody);
      return;
    }
    final tempFile = File('${output.path}.tmp');
    try {
      await tempFile.writeAsString(rawBody);
      final err = await boxService.validateConfig(output.path, tempFile.path);
      if (err != null && err.isNotEmpty) {
        debugPrint('[Profile] validateConfig 失败，回退到原始内容: $err');
        await output.writeAsString(rawBody);
        return;
      }
      if (!await output.exists()) {
        debugPrint('[Profile] validateConfig 成功但未写出 output，回退');
        await output.writeAsString(rawBody);
      }
    } catch (e, st) {
      debugPrint('[Profile] _normalizeAndWrite 抛异常: $e\n$st');
      await output.writeAsString(rawBody);
    } finally {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  /// 配置文件路径
  String configFilePath(String profileId) {
    return p.join(configDir.path, 'profiles', '$profileId.json');
  }
}
