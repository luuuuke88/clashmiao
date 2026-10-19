import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'allowlist.dart';
import 'import_scanner.dart';
import 'layering_rules.dart';

/// 扫描 `lib/` 下全部 `.dart`（含 `*.g.dart`，R4：生成物按所在目录归层、不豁免），
/// 返回「`lib/` 内相对路径 → 该文件全部 import/export URI」。
Map<String, List<String>> scanLib() {
  final lib = Directory('lib');
  expect(lib.existsSync(), isTrue, reason: '必须在 clashmiao-client 根目录下运行测试');
  final result = <String, List<String>>{};
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final rel = f.path
        .substring(lib.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    result[rel] = extractDirectiveUris(f.readAsStringSync());
  }
  return result;
}

/// 失败时把全部违规一次打印出来，而不是改一条跑一次。
String render(Iterable<Object> items) => '\n${items.join('\n')}\n';

void main() {
  late final Map<String, List<String>> uris;

  setUpAll(() => uris = scanLib());

  test('扫描到了足够多的文件（防止路径写错导致空扫描而「全绿」）', () {
    expect(uris.length, greaterThan(100));
  });

  test('层间依赖合规（core ← shared ← domain ← features ← app，domain 内部有序）', () {
    final violations = checkLayering(uris, allowlist: kAllowlist);
    expect(violations, isEmpty, reason: render(violations));
  });

  test(
    'R1：domain 模型不传递依赖 Flutter / Riverpod / dart:io / dart:ui / data / application',
    () {
      final violations = checkModelPurity(uris);
      expect(violations, isEmpty, reason: render(violations));
    },
  );

  test('白名单没有过期条目', () {
    final stale = staleEntries(uris, kAllowlist);
    expect(
      stale,
      isEmpty,
      reason: '以下白名单条目对应的依赖已经消除，请从 allowlist.dart 删除：${render(stale)}',
    );
  });

  test('白名单合法：条数不超上限，且只含 features → features', () {
    final problems = checkAllowlist(kAllowlist, ceiling: kAllowlistCeiling);
    expect(problems, isEmpty, reason: render(problems));
  });
}
