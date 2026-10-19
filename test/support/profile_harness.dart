import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'flaky_prefs.dart';
import 'gate_adapter.dart';
import 'temp_dirs.dart';

/// 订阅存储测试的统一装置：真实文件系统 + 真实 [ProfileStore] / [ProfileRepository]，
/// 网络换成可卡住请求的 [GateAdapter]，偏好可选包一层会失败的 [FlakyPrefs]。
class ProfileHarness {
  ProfileHarness._({
    required this.tmpDir,
    required this.prefs,
    required this.flaky,
    required this.adapter,
    required this.repo,
  });

  final Directory tmpDir;
  final SharedPreferences prefs;
  final FlakyPrefs? flaky;
  final GateAdapter adapter;
  final ProfileRepository repo;

  ProfileStore get store => repo.store;

  static Future<ProfileHarness> create({
    bool flaky = false,
    Map<String, Object> initialPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(Map.of(initialPrefs));
    final real = await SharedPreferences.getInstance();
    final wrapped = flaky ? FlakyPrefs(real) : null;
    final prefs = wrapped ?? real;
    final tmpDir = await Directory.systemTemp.createTemp('profile_harness_');
    final adapter = GateAdapter();
    final repo = ProfileRepository(
      dio: Dio()..httpClientAdapter = adapter,
      configDir: tmpDir,
      prefs: prefs,
      boxService: const StubBoxService(),
    );
    return ProfileHarness._(
      tmpDir: tmpDir,
      prefs: prefs,
      flaky: wrapped,
      adapter: adapter,
      repo: repo,
    );
  }

  Future<void> dispose() => deleteTempDirBestEffort(tmpDir);

  Directory get profilesDir => Directory(p.join(tmpDir.path, 'profiles'));

  File configFile(String id) => File(repo.configFilePath(id));

  /// profiles 目录里除正式 `<id>.json` 之外的文件（暂存 / undo / 临时残留）。
  List<String> strayFiles() {
    if (!profilesDir.existsSync()) return const [];
    return [
      for (final f in profilesDir.listSync())
        if (f is File && !p.basename(f.path).endsWith('.json'))
          p.basename(f.path),
    ]..sort();
  }

  List<String> get ids => [for (final e in repo.getAll()) e.id];

  String? get rawList => prefs.getString(ProfileStore.profilesKey);

  List<Map<String, dynamic>> get storedJson {
    final raw = rawList;
    if (raw == null) return const [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  /// 把订阅 JSON 直接种进偏好（模拟旧版本 / 别处写入的数据）。
  Future<void> seedRaw(Object? list, {String? activeId}) async {
    await prefs.setString(
      ProfileStore.profilesKey,
      list is String ? list : jsonEncode(list),
    );
    if (activeId != null) {
      await prefs.setString(ProfileStore.activeProfileKey, activeId);
    }
  }
}
