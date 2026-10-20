import 'dart:convert';

import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

BackupBundle _bundle({Map<String, String> aux = const {}}) => BackupBundle(
  schema: kCurrentStorageSchema,
  createdAt: 1000000,
  profiles: const [
    {'id': 'abc', 'name': 'test', 'url': 'https://example.com'},
  ],
  activeProfileId: 'abc',
  profileConfigs: const {
    'abc': '{"outbounds":[{"type":"shadowsocks","tag":"hk"}]}',
  },
  preferences: const {'clashmiao_mixed_port': 3000},
  auxPreferences: aux,
);

void main() {
  test('v2 的 JSON 形状：顶层是扁平结构，不再有嵌套的 settings', () {
    final json = _bundle().toJson();
    expect(json.keys, {
      'version',
      'schema',
      'createdAt',
      'profiles',
      'activeProfileId',
      'profileConfigs',
      'preferences',
    });
    expect(json['version'], 2);
    expect(json['schema'], kCurrentStorageSchema);
  });

  test('附属偏好只在非空（恢复前快照）时才出现在文件里', () {
    expect(_bundle().toJson().containsKey('auxPreferences'), isFalse);
    expect(
      _bundle(aux: {'proxy_selection_abc': '{}'}).toJson()['auxPreferences'],
      {'proxy_selection_abc': '{}'},
    );
  });

  test('写出的文件能被导入解析器读回', () {
    final plan = BackupCodec.parse(
      BackupCodec.encode(_bundle()),
      currentSchema: kCurrentStorageSchema,
    );
    expect(plan.profiles.single.id, 'abc');
    expect(plan.activeId, 'abc');
    expect(plan.configs.keys, ['abc']);
    expect(plan.prefs, {'clashmiao_mixed_port': 3000});
  });

  test('旧的 1.0 版本串只在导入时识别，导出永远是 2', () {
    expect(BackupBundle.legacyVersion, '1.0');
    final json =
        jsonDecode(BackupCodec.encode(_bundle())) as Map<String, dynamic>;
    expect(json['version'], 2);
  });
}
