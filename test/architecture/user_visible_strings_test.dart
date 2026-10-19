import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'user_strings_scanner.dart';

/// 允许出现 CJK 字面量的地方：文件 → 允许的完整字面量；`null` = 整个文件豁免。
/// 只登记**不该翻译**的内容，每条写明原因。界面文案一律走 i18n。
const Map<String, Set<String>?> kAllowedCjkLiterals = {
  // 品牌名：任务切换器 / 窗口标题，各语言一致。
  'lib/app/app.dart': {'喵速'},
  // 品牌吉祥物的问候语，属于开屏插画的一部分。
  'lib/features/splash/presentation/splash_page.dart': {'Hi 喵~'},
  // 第三方许可证原文，必须逐字保留。
  'lib/core/licenses/bundled_licenses.dart': null,
  // 语言的自称（语言选择列表里每种语言用它自己的文字显示）。
  'lib/core/localization/locale_extensions.dart': {'中文 (中国)', '中文 (台湾)'},
  'lib/features/settings/presentation/settings_page.dart': {'简体中文', '繁體中文'},
  // 从节点名里识别地区的关键词表（数据，不是文案）。
  'lib/domain/routing/model/node_display.dart': null,
  // 识别订阅里「官网 / 剩余流量 / 到期」这类信息伪节点的关键词（数据）。
  'lib/domain/profile/data/profile_repository.dart': {
    '官网',
    '官方',
    '网址',
    '订阅',
    '套餐',
    '流量',
    '剩余',
    '到期',
    '过期',
  },
  // 仅调试构建、由 dart-define 打开的界面夹具：模拟用户自己的订阅 / 节点名。
  'lib/domain/profile/application/profile_providers.dart': {'无订阅信息', '本地导入'},
  'lib/domain/routing/application/offline_proxy_groups_provider.dart': {
    '香港 01 | SS',
    '日本 Tokyo 02',
  },
  'lib/features/proxy/presentation/proxies_page.dart': {'香港 01 | SS'},
  'lib/features/profile/presentation/profiles_page.dart': {'测试配置'},
};

/// 日志通道本身：格式化日志记录时必然输出异常原文，豁免规则 1。
const Set<String> kRawErrorExemptFiles = {'lib/core/logger/app_logger.dart'};

/// 生成代码（i18n、freezed、json）不扫。
bool _generated(String path) =>
    path.contains('/gen/') ||
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart');

List<StringViolation> _scanLib() {
  final violations = <StringViolation>[];
  final files =
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !_generated(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final path = f.path.replaceAll(r'\', '/');
    violations.addAll(
      scanUserStrings(
        path,
        f.readAsStringSync(),
        allowedCjk: kAllowedCjkLiterals.containsKey(path)
            ? kAllowedCjkLiterals[path]
            : const {},
        checkRawError: !kRawErrorExemptFiles.contains(path),
      ),
    );
  }
  return violations;
}

void main() {
  test('lib/ 没有把异常原文拼进文案，也没有写死的中文文案', () {
    final violations = _scanLib();
    expect(
      violations,
      isEmpty,
      reason:
          '${violations.join('\n')}\n\n'
          '修法：异常原文只进 debugPrint；给用户看的文案用 t.xxx（10 种语言）。'
          '确实不该翻译的字面量（品牌、语言自称、解析用关键词）登记到 '
          'kAllowedCjkLiterals 并写明原因。',
    );
  });

  test('白名单没有过期条目：登记的文件都存在', () {
    for (final path in [...kAllowedCjkLiterals.keys, ...kRawErrorExemptFiles]) {
      expect(File(path).existsSync(), isTrue, reason: '$path 已不存在，删掉这条');
    }
  });

  group('扫描器自测（合成源码）', () {
    List<String> rules(String src, {Set<String>? allow = const {}}) =>
        scanUserStrings(
          'x.dart',
          src,
          allowedCjk: allow,
        ).map((v) => v.rule).toList();

    test('catch 到的异常插值进 toast：违规', () {
      expect(
        rules('''
void f() { try {} catch (e) { toast('failed: \$e'); } }
'''),
        [ruleRawError],
      );
      expect(
        rules('''
void f() { try {} catch (err) { toast('x \${err.message}'); } }
'''),
        [ruleRawError],
      );
      expect(
        rules('''
void f() { try {} catch (e) { toast(e.toString()); } }
'''),
        [ruleRawError],
      );
    });

    test('error 回调参数与 AsyncValue.error 插值：违规', () {
      expect(
        rules('''
Widget f(a) => a.when(error: (e, _) => Text('oops: \$e'));
'''),
        [ruleRawError],
      );
      expect(
        rules('''
Widget f(a) => Text('oops: \${a.error}');
'''),
        [ruleRawError],
      );
    });

    test('技术通道里的异常原文：放行', () {
      expect(
        rules('''
void f() {
  try {} catch (e) {
    debugPrint('failed: \$e');
    _log.warning('x \$e');
    throw StateError('wrapped \$e');
  }
  try {} catch (e) { return UnexpectedFailure('\$e'); }
  try {} catch (e) { return SelectFailed('x', '\$e'); }
}
class A { String toString() => 'A(\$error)'; final error = 1; }
'''),
        isEmpty,
      );
    });

    test('写死的中文：违规；日志、throw、白名单里的：放行', () {
      expect(rules("void f() { toast('导入失败'); }"), [ruleCjkLiteral]);
      expect(rules("void f() { toast('已导入 \$n 项'); }"), [ruleCjkLiteral]);
      expect(
        rules("""
void f() {
  debugPrint('调试信息');
  throw Exception('内部错误');
  assert(true, '断言说明');
}
"""),
        isEmpty,
      );
      expect(
        rules("const title = '喵速';", allow: {'喵速'}),
        isEmpty,
        reason: '白名单按完整字面量匹配',
      );
      expect(
        rules("const title = '喵速'; const other = '别的';", allow: {'喵速'}),
        [ruleCjkLiteral],
        reason: '同一文件里没登记的字面量照样报',
      );
      expect(rules("const t = '香港';", allow: null), isEmpty);
    });

    test('名字里碰巧含 log 的对象不算日志通道', () {
      expect(
        rules('''
void f() { try {} catch (e) { dialog.show('x \$e'); } }
'''),
        [ruleRawError],
      );
    });

    test('注释里的中文不算', () {
      expect(rules('// 中文注释\n/// 文档注释\nvoid f() {}'), isEmpty);
    });
  });
}
