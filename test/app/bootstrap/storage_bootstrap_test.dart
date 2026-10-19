import 'package:clashmiao/app/bootstrap/storage_bootstrap.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

void main() {
  const v0 = {
    ProfileStore.profilesKey:
        '[{"id":"a","name":"n","url":"http://x/a","active":true}]',
  };

  test('启动屏障：先做恢复标记检查，再迁移', () async {
    final prefs = await _prefs(v0);
    int? schemaSeenByCheck = -1;
    await prepareStorage(
      prefs,
      checkRestoreMarker: (p) async {
        schemaSeenByCheck = p.getInt(kStorageSchemaKey);
      },
    );
    expect(schemaSeenByCheck, isNull, reason: '检查发生时还没迁移');
    expect(prefs.getInt(kStorageSchemaKey), kCurrentStorageSchema);
    expect(prefs.getString(ProfileStore.activeProfileKey), 'a');
  });

  test('恢复标记检查抛错：不挡住启动，迁移照常进行', () async {
    final prefs = await _prefs(v0);
    await prepareStorage(
      prefs,
      checkRestoreMarker: (_) async => throw StateError('boom'),
    );
    expect(prefs.getInt(kStorageSchemaKey), kCurrentStorageSchema);
  });

  test('没有接入恢复检查时（C1-3 之前）也能正常迁移', () async {
    final prefs = await _prefs(v0);
    final report = await prepareStorage(prefs);
    expect(report.toSchema, kCurrentStorageSchema);
  });

  test('高 schema：不动数据，不抛', () async {
    final prefs = await _prefs({...v0, kStorageSchemaKey: 99});
    await prepareStorage(prefs);
    expect(prefs.getInt(kStorageSchemaKey), 99);
    expect(prefs.containsKey(ProfileStore.activeProfileKey), isFalse);
  });
}
