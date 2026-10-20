import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/data/backup_service.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:clashmiao/features/config/presentation/backup_messages.dart';
import 'package:flutter_test/flutter_test.dart';

PreparedImport _prepared(List<ProfileEntity> willRemove) => PreparedImport(
  plan: const RestorePlan(
    profiles: [],
    activeId: null,
    configs: {},
    needsFetch: [],
    prefs: {},
    skippedPrefKeys: [],
    profilesDropped: 0,
    warpDisabled: false,
    exactPrefs: false,
  ),
  willRemove: willRemove,
);

RestoreReport _report({
  int imported = 2,
  int dropped = 0,
  int prefs = 5,
  int skipped = 0,
  int queued = 0,
  bool warp = false,
}) => RestoreReport(
  profilesImported: imported,
  profilesDropped: dropped,
  profilesRemoved: 0,
  prefsImported: prefs,
  prefsSkipped: skipped,
  refreshQueued: queued,
  warpDisabled: warp,
  snapshotPath: '/x/pre-restore-1.json',
);

void main() {
  final en = AppLocale.en.buildSync();
  final zh = AppLocale.zhCn.buildSync();

  group('确认对话框', () {
    test('本机有不在备份里的订阅时，明确说会被移除并给出数量', () {
      final text = BackupMessages.confirm(
        en,
        _prepared([
          const ProfileEntity(id: 'a', name: 'A', url: 'u'),
          const ProfileEntity(id: 'b', name: 'B', url: 'u'),
        ]),
      );
      expect(text, contains(en.settings.backup.importConfirmMsg));
      expect(text, contains('2 subscription(s)'));
      expect(text, contains('removed'));
      expect(
        BackupMessages.confirm(
          zh,
          _prepared([const ProfileEntity(id: 'a', name: 'A', url: 'u')]),
        ),
        contains('1 个订阅'),
      );
    });

    test('没有会被移除的订阅时不出现这句', () {
      final text = BackupMessages.confirm(en, _prepared([]));
      expect(text, en.settings.backup.importConfirmMsg);
    });
  });

  group('结果报告', () {
    test('只有有话可说的部分才出现', () {
      expect(
        BackupMessages.report(en, _report()),
        'Imported 2 subscription(s) and 5 setting(s).',
      );
      final full = BackupMessages.report(
        en,
        _report(dropped: 1, skipped: 3, queued: 2, warp: true),
      );
      expect(full.split('\n'), hasLength(5));
      expect(full, contains('1 subscription(s) in the backup were skipped'));
      expect(full, contains('3 setting(s) were skipped'));
      expect(full, contains('WARP'));
      expect(full, contains('2 subscription(s) will be downloaded'));
    });

    test('简体中文', () {
      expect(
        BackupMessages.report(zh, _report(warp: true)),
        '已导入 2 个订阅、5 项设置。\n导入时已关闭 WARP，请在本机重新启用。',
      );
    });
  });

  group('失败原因', () {
    test('备份文件问题：每种原因一句话，且互不相同', () {
      final messages = {
        for (final kind in BackupErrorKind.values)
          kind: BackupMessages.error(en, BackupFormatException(kind)),
      };
      expect(messages.values.toSet(), hasLength(BackupErrorKind.values.length));
      expect(messages[BackupErrorKind.newerSchema], contains('upgrade'));
    });

    test('恢复失败：每种结局一句话；回滚没完成时带上快照路径', () {
      final messages = {
        for (final kind in RestoreFailureKind.values)
          kind: BackupMessages.error(
            en,
            RestoreFailure(kind, snapshotPath: '/snap/pre-restore-1.json'),
          ),
      };
      expect(
        messages.values.toSet(),
        hasLength(RestoreFailureKind.values.length),
      );
      expect(
        messages[RestoreFailureKind.notRolledBack],
        contains('/snap/pre-restore-1.json'),
      );
      expect(messages[RestoreFailureKind.rolledBack], contains('restored'));
      expect(
        messages[RestoreFailureKind.readOnly],
        en.failure.profiles.readOnlyUpgrade,
      );
    });

    test('其它异常落到通用提示，不把异常文本直接丢给用户', () {
      expect(
        BackupMessages.error(en, StateError('internal detail')),
        en.settings.backup.errFailed,
      );
      expect(
        BackupMessages.error(en, const StoreReadOnlyException(9)),
        en.failure.profiles.readOnlyUpgrade,
      );
    });
  });

  group('各语言文案齐全且占位符一致', () {
    final files = Directory('assets/translations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.i18n.json'))
        .toList();

    Map<String, dynamic> backupSection(File f) =>
        ((jsonDecode(f.readAsStringSync()) as Map)['settings'] as Map)['backup']
            as Map<String, dynamic>;
    Set<String> placeholders(String s) => {
      for (final m in RegExp(r'\$\{(\w+)\}').allMatches(s)) m.group(1)!,
    };

    test('11 个翻译文件都有 settings.backup', () {
      expect(files, hasLength(11));
    });

    for (final file in files) {
      test(file.uri.pathSegments.last, () {
        final base = backupSection(
          files.firstWhere((f) => f.path.endsWith('strings_en.i18n.json')),
        );
        final section = backupSection(file);
        expect(section.keys.toSet(), base.keys.toSet());
        for (final key in base.keys) {
          final value = section[key] as String;
          expect(value.trim(), isNotEmpty, reason: key);
          expect(
            placeholders(value),
            placeholders(base[key] as String),
            reason: '$key 的占位符与英文不一致',
          );
        }
      });
    }
  });
}
