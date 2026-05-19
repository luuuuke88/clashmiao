import 'dart:convert';
import 'package:clashmiao/features/settings/model/backup_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BackupBundle round-trips through JSON correctly', () {
    const original = BackupBundle(
      version: BackupBundle.currentVersion,
      profiles: [
        {'id': 'abc', 'name': 'test', 'url': 'https://example.com'},
      ],
      activeProfileId: 'abc',
      settings: {},
      createdAt: 1000000,
    );

    final json = jsonEncode(original.toJson());
    final decoded = BackupBundle.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

    expect(decoded.version, BackupBundle.currentVersion);
    expect(decoded.profiles.length, 1);
    expect(decoded.profiles.first['id'], 'abc');
    expect(decoded.activeProfileId, 'abc');
    expect(decoded.createdAt, 1000000);
  });

  test('BackupBundle.fromJson rejects unknown version', () {
    expect(
      () => BackupBundle.fromJson({
        'version': '99.0',
        'profiles': [],
        'settings': {},
        'createdAt': 0,
      }),
      throwsException,
    );
  });
}
