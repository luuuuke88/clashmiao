import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 翻译完整性门禁。
///
/// 背景：体检时发现 10 个语言合计缺 766 个 key（es/id/tr 各缺 30% 左右），
/// 非中文用户会大面积看到英文兜底。运行时兜底不崩溃，所以这个问题可以长期
/// 无声无息地存在、越积越多——直到有人真的用那个语言打开 App。
///
/// 这个测试把"补齐"这件事变成不可逆的：以后任何人加了新的 en key 而没有
/// 同步补上其它语言，CI 直接红。
///
/// `play.*` 不在门禁范围：那是 Play 商店 listing 文案（App 内零引用），
/// 商店的多语言 listing 在 Play Console 单独管理，不该由这里约束。
const _storeListingPrefix = 'play.';

Set<String> _leafKeys(Map<String, dynamic> map, [String prefix = '']) {
  final out = <String>{};
  map.forEach((k, v) {
    if (k.startsWith('@')) return; // slang 的元数据键
    final path = prefix.isEmpty ? k : '$prefix.$k';
    if (v is Map<String, dynamic>) {
      out.addAll(_leafKeys(v, path));
    } else {
      out.add(path);
    }
  });
  return out;
}

Set<String> _keysOf(String locale) {
  final file = File('assets/translations/strings_$locale.i18n.json');
  expect(file.existsSync(), isTrue, reason: '找不到 ${file.path}');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return _leafKeys(json);
}

void main() {
  group('翻译完整性', () {
    late Set<String> baseline;

    setUpAll(() {
      baseline = _keysOf(
        'en',
      ).where((k) => !k.startsWith(_storeListingPrefix)).toSet();
    });

    test('en 基准非空（防止解析出错让下面的断言平凡通过）', () {
      expect(baseline.length, greaterThan(300));
    });

    for (final locale in const [
      'ar',
      'ckb-KUR',
      'es',
      'fa',
      'id',
      'pt-BR',
      'ru',
      'tr',
      'zh-CN',
      'zh-TW',
    ]) {
      test('$locale 覆盖全部 en key', () {
        final missing = (baseline..toSet()).difference(_keysOf(locale))
          ..removeWhere((k) => k.startsWith(_storeListingPrefix));
        expect(
          missing,
          isEmpty,
          reason:
              '$locale 缺 ${missing.length} 个 key。加了新的 en 文案就要同步补齐所有语言，'
              '否则这些界面对该语言用户会显示成英文。缺失清单：'
              '${missing.take(20).toList()}',
        );
      });
    }

    test('各语言不含 en 里不存在的孤儿 key（改名/删除后应同步清理）', () {
      final all = _keysOf('en');
      for (final locale in const ['zh-CN', 'es', 'ru']) {
        final orphans = _keysOf(locale).difference(all);
        expect(
          orphans,
          isEmpty,
          reason: '$locale 有 en 里已不存在的 key：${orphans.take(10).toList()}',
        );
      }
    });
  });
}
