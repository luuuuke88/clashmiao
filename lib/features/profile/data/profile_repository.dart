import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/features/profile/data/profile_parser.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 订阅仓库 - 管理订阅的增删改查和配置文件下载
class ProfileRepository {
  ProfileRepository({
    required this.dio,
    required this.configDir,
    required this.prefs,
  });

  final Dio dio;

  /// 配置文件存储目录
  final Directory configDir;

  final SharedPreferences prefs;

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

    // 保存配置文件到本地
    final configFile = File(configFilePath(profile.id));
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(response.data ?? '');

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

    // 保存新配置
    final configFile = File(configFilePath(profileId));
    await configFile.writeAsString(response.data ?? '');

    final updated = current.copyWith(
      lastUpdate: DateTime.now(),
      subInfo: subInfo ?? current.subInfo,
    );
    profiles[index] = updated;
    await _saveAll(profiles);

    return updated;
  }

  /// 编辑订阅信息（名称、URL）
  Future<void> editProfile(String profileId,
      {String? newName, String? newUrl}) async {
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

  /// 配置文件路径
  String configFilePath(String profileId) {
    return p.join(configDir.path, 'profiles', '$profileId.json');
  }
}
