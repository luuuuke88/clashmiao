import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 建一个真实的 [ProfileStore]，并把 [profiles] 种进偏好（激活第一条，除非指定）。
///
/// 订阅附属数据（手选节点、延迟缓存）的写入现在要经 `ProfileStore.writeAux`
/// 校验「这条订阅确实存在」，所以依赖它们的 notifier 测试必须有一个种好订阅的
/// Store，而不能只 override `activeProfileProvider`。
Future<ProfileStore> seededProfileStore(
  SharedPreferences prefs,
  List<ProfileEntity> profiles, {
  String? activeId,
  Directory? configDir,
}) async {
  await prefs.setString(
    ProfileStore.profilesKey,
    jsonEncode([for (final e in profiles) e.toJson()]),
  );
  final active = activeId ?? (profiles.isEmpty ? null : profiles.first.id);
  if (active != null) {
    await prefs.setString(ProfileStore.activeProfileKey, active);
  }
  return ProfileStore(
    prefs: prefs,
    configDir:
        configDir ?? Directory.systemTemp.createTempSync('seeded_store_'),
  );
}
