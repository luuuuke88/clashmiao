import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 文案守卫：中文译文里相邻重复的汉字几乎都是笔误（真机验收 BUG-D「噪音延延迟」）。
/// 合法的叠字 / 跨词相邻重复逐条登记在 [_allowed]，写明出处。
const _allowed = <String>{
  '喵喵', // 应用名「Clash喵喵」
  '试试', // 「试试换一个节点」
  '試試', // 同上（繁体）
  '連線線路', // 「透過 WARP 連線線路」：連線 + 線路，跨词相邻
};

final _cjkPair = RegExp(r'([一-鿿])\1');

Iterable<(String, String)> _strings(Object? node, [String path = '']) sync* {
  if (node is Map) {
    for (final entry in node.entries) {
      yield* _strings(entry.value, '$path.${entry.key}');
    }
  } else if (node is String) {
    yield (path, node);
  }
}

void main() {
  test('中文译文没有相邻重复的汉字（登记的合法叠字除外）', () {
    final offenders = <String>[];
    final files = Directory(
      'assets/translations',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.i18n.json'));
    for (final file in files) {
      final json = jsonDecode(file.readAsStringSync());
      for (final (path, value) in _strings(json)) {
        var masked = value;
        for (final ok in _allowed) {
          masked = masked.replaceAll(ok, '');
        }
        if (_cjkPair.hasMatch(masked)) {
          offenders.add('${file.uri.pathSegments.last} $path: $value');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
