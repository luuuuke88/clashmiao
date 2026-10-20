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
  // 识别订阅里「官网 / 剩余流量 / 到期」这类信息条目的关键词（数据，不是文案）。
  'lib/domain/config/model/subscription_info_node.dart': {
    '官网',
    '官方',
    '网址',
    '订阅',
    '剩余',
    '到期',
    '过期',
    '有效期',
    '套餐',
    '重置',
    '流量',
    '：',
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

/// 内部异常载体：构造参数里的文本**只进日志 / 诊断**，界面按类型或错误码映射成
/// 本地化文案，绝不原样展示。只有确认过展示路径的类型才能登记，每条写明依据。
///
/// 不按名字后缀放行：`DeepLinkImportFailure.message` 由 shell_page 直接 toast，
/// 是用户文案通道，**不能**登记（下面有测试锁住）。
const Map<String, String> kInternalCarrierTypes = {
  'KernelFailure':
      '内核快照里的失败；界面经 ConnectionFailure.fromKernel → '
      'connection_error_classifier 按 code 映射文案，message 只进日志',
  '_Fault': 'EmulatedKernelPort 内部，落成 KernelFailure（同上）',
  'PlatformFailure': 'connection_error_classifier 一律映射为 t.failure.unexpected',
  'UnexpectedFailure': '同上',
  'SelectFailed':
      '手选失败结果；proxies_page 只把 code/message 写日志，toast 用 t.proxies.switchFailed',
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
        internalCarrierTypes: kInternalCarrierTypes.keys.toSet(),
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
          '修法：异常原文只进 logAppFailure（应用日志）；给用户看的文案用 t.xxx'
          '（10 种语言）。确认只进日志的内部异常类型登记到 kInternalCarrierTypes；'
          '确实不该翻译的字面量（品牌、语言自称、解析用关键词）登记到 '
          'kAllowedCjkLiterals 并写明原因。',
    );
  });

  test('白名单没有过期条目：登记的文件都存在', () {
    for (final path in [...kAllowedCjkLiterals.keys, ...kRawErrorExemptFiles]) {
      expect(File(path).existsSync(), isTrue, reason: '$path 已不存在，删掉这条');
    }
  });

  test('内部载体没有过期条目：登记的类型都在 lib/ 里声明', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !_generated(f.path))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final type in kInternalCarrierTypes.keys) {
      expect(
        RegExp('class ${RegExp.escape(type)}\\b').hasMatch(sources),
        isTrue,
        reason: '$type 已不存在，删掉这条',
      );
    }
  });

  test('展示给用户的结果类型不能登记成内部载体', () {
    // DeepLinkImportFailure.message 直接进 toast（shell_page）。
    expect(kInternalCarrierTypes, isNot(contains('DeepLinkImportFailure')));
    for (final type in kInternalCarrierTypes.keys) {
      expect(type, isNot(endsWith('Result')), reason: type);
    }
  });

  group('扫描器自测（合成源码）', () {
    List<String> rules(String src, {Set<String>? allow = const {}}) =>
        scanUserStrings(
          'x.dart',
          src,
          allowedCjk: allow,
          internalCarrierTypes: kInternalCarrierTypes.keys.toSet(),
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
    logAppFailure('where', e, st);
    logAppFailure('where \$e', e);
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

    // 审核结论：按后缀（Failure / Error / Exception…）整体放行会漏掉承载用户文案
    // 的类型。没登记的构造，参数照常检查。
    test('展示给用户的 Failure 结果：异常原文与写死中文都违规', () {
      expect(
        rules('''
void f() { try {} catch (e) { state = DeepLinkImportFailure('\$e'); } }
'''),
        [ruleRawError],
      );
      expect(
        rules('''
void f() { try {} catch (e) { state = DeepLinkImportFailure('导入失败: \$e'); } }
'''),
        [ruleRawError, ruleCjkLiteral],
      );
      expect(
        rules("void f() { state = const DeepLinkImportFailure('导入失败'); }"),
        [ruleCjkLiteral],
      );
      expect(
        rules("void f() { state = SomeNewFailure('出错了'); }"),
        [ruleCjkLiteral],
        reason: '名字以 Failure 结尾不再自动放行',
      );
      expect(
        rules('''
void f() { try {} catch (e) { report(FooError('\$e')); } }
'''),
        [ruleRawError],
        reason: '未登记的 Error 构造（不在 throw 里）同样检查',
      );
    });

    test('登记过的内部载体：放行', () {
      expect(
        rules('''
void f() {
  try {} catch (e) { return SelectFailed('unknown', '\$e'); }
  _fail(const _Fault(code, '核心库未加载'));
  _failure = KernelFailure(code: c, message: '停止超时', attempt: 1);
}
'''),
        isEmpty,
      );
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
