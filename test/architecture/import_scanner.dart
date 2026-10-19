// 架构测试的 import 扫描器。
//
// 刻意不依赖 flutter_test：规则逻辑与扫描逻辑都是纯 Dart，
// 这样 layering_rules_test 可以用合成数据直接验证规则本身。
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// 项目自身的 package 名；`lib/` 下文件一律以 `package:clashmiao/` 互相引用
/// （由 `always_use_package_imports` 保证，见 R2）。
const _projectPrefix = 'package:clashmiao/';

/// 提取源码里全部 import / export 的 URI（含条件导入的每个分支）。
///
/// 用官方解析器而不是正则：同一行多条指令、单双引号混用、字符串或注释里的
/// 伪指令、跨行的 show/hide/as/deferred 写法，正则逐个都踩过坑，
/// 交给解析器就不会漏判或误判。
/// `part` / `part of` / `library` 不是依赖边，不返回。
List<String> extractDirectiveUris(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final uris = <String>[];

  void add(String? uri) {
    if (uri != null) uris.add(uri);
  }

  for (final directive in unit.directives) {
    if (directive is ImportDirective) {
      add(directive.uri.stringValue);
      for (final c in directive.configurations) {
        add(c.uri.stringValue);
      }
    } else if (directive is ExportDirective) {
      add(directive.uri.stringValue);
      for (final c in directive.configurations) {
        add(c.uri.stringValue);
      }
    }
  }
  return uris;
}

final _schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');

/// 带 scheme（`dart:io`、`package:x/...`、`file:`）的 URI 不是「相对 URI」。
bool _hasScheme(String uri) => _schemePattern.hasMatch(uri);

/// 项目内相对 URI 不规范、或解析后越出 `lib/` 时返回原因，否则返回 `null`。
/// 带 scheme 的 URI（`dart:`、其他 package）不在此列，返回 `null`。
///
/// 为什么不照 Dart 解析器的语义去「尽量还原」：反斜杠、`%2e%2e` 之类的转义写法、
/// 多余的 `..`，analyzer 与 Dart 工具链可能各有各的解读，规则检查器一旦和它们
/// 解读不一致就是漏洞。所以一律失败即关闭——凡不是规范写法的相对 URI，
/// 都当违规处理，让作者改成 `package:clashmiao/` 导入。
/// 规范写法 = 只由 `/` 分隔的 `name` / `.` / `..` 段，无转义、无 query/fragment、无空段，
/// 且 `..` 不会越出 `lib/`。
String? nonCanonicalRelativeUriReason(String uri, {required String from}) {
  if (_hasScheme(uri)) return null;
  if (uri.contains(RegExp(r'[\\%?#]'))) {
    return '含反斜杠、百分号转义或 query/fragment';
  }
  final segs = uri.split('/');
  if (segs.any((s) => s.isEmpty)) return '路径含空段或为绝对路径';
  var depth = from.split('/').length - 1; // 导入方所在目录相对 lib/ 的层数
  for (final seg in segs) {
    if (seg == '.') continue;
    if (seg == '..') {
      if (depth == 0) return '解析后越出 lib/';
      depth--;
    } else {
      depth++;
    }
  }
  return null;
}

/// 把 URI 解析成 `lib/` 内的相对路径；不是项目内文件返回 `null`。
///
/// - `package:clashmiao/x/y.dart` → `x/y.dart`；
/// - 规范的相对 URI（`../a.dart`、`./b.dart`）按 [from]（导入方自己的 `lib/` 内
///   相对路径）解析并规整 `.` / `..`。`always_use_package_imports` 只管 import 的
///   主 URI，export 与条件导入分支里的相对写法它拦不住，所以这里必须自己解析；
/// - 非规范或越出 `lib/` 的相对 URI、没给 [from] 的相对 URI → `null`。
///   注意 `null` 不等于「干净」：规则层会先用 [nonCanonicalRelativeUriReason]
///   把这类 URI 报为违规，不会静默跳过；
/// - `dart:`、其他 package、`file:` 等带 scheme 的 URI → `null`。
String? projectPath(String uri, {String? from}) {
  if (uri.startsWith(_projectPrefix)) {
    return uri.substring(_projectPrefix.length);
  }
  if (_hasScheme(uri) || from == null) return null;
  if (nonCanonicalRelativeUriReason(uri, from: from) != null) return null;

  final segments = from.split('/')..removeLast(); // 导入方所在目录
  for (final seg in uri.split('/')) {
    if (seg == '.') continue;
    if (seg == '..') {
      segments.removeLast();
    } else {
      segments.add(seg);
    }
  }
  return segments.join('/');
}
