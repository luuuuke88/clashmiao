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
