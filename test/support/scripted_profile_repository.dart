import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 按剧本抛异常的仓库：只用来验证「界面怎么对待仓库抛出的各类异常」
/// （作废 stale、存储只读、普通失败）。抛出的异常与真实仓库在对应交错下
/// 抛出的一致——真实交错由 `profile_stale_callers_test.dart` 等仓库层测试覆盖。
class ScriptedProfileRepository extends ProfileRepository {
  ScriptedProfileRepository({required super.prefs})
    : super(
        dio: Dio(),
        configDir: Directory('/tmp/unused-scripted-profile-repo'),
        boxService: const StubBoxService(),
      );

  Object? updateError;

  /// 非空时，[update] 先等它完成（用来把刷新「卡在半路」，再在页面销毁后放行）。
  Completer<void>? updateGate;
  Object? updateAllError;
  Object? setActiveError;
  Object? editError;
  Object? deleteError;
  Object? addError;
  int updateCalls = 0;

  @override
  Future<ProfileEntity> update(String profileId) async {
    updateCalls++;
    await updateGate?.future;
    final error = updateError;
    if (error != null) throw error;
    return getAll().firstWhere((p) => p.id == profileId);
  }

  @override
  Future<ProfileEntity> addByUrl(String url, {String? customName}) async {
    final error = addError;
    if (error != null) throw error;
    return ProfileEntity(id: 'added', name: customName ?? 'added', url: url);
  }

  @override
  Future<ProfileEntity> addByContent(
    String content, {
    required String name,
  }) async {
    final error = addError;
    if (error != null) throw error;
    return ProfileEntity(id: 'added', name: name, url: 'content://x');
  }

  @override
  Future<void> updateAll() async {
    final error = updateAllError;
    if (error != null) throw error;
  }

  @override
  Future<void> setActive(String profileId) async {
    final error = setActiveError;
    if (error != null) throw error;
  }

  @override
  Future<void> editProfile(
    String profileId, {
    String? newName,
    String? newUrl,
    ProfilePatch? patch,
  }) async {
    final error = editError;
    if (error != null) throw error;
  }

  @override
  Future<void> delete(String profileId) async {
    final error = deleteError;
    if (error != null) throw error;
  }
}

/// 把 [profiles] 种进偏好，返回对应的脚本仓库。
Future<ScriptedProfileRepository> scriptedRepository(
  SharedPreferences prefs,
) async => ScriptedProfileRepository(prefs: prefs);
