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

/// 把 URI 解析成 `lib/` 内的相对路径；不是项目内文件返回 `null`。
///
/// - `package:clashmiao/x/y.dart` → `x/y.dart`；
/// - 相对 URI（`../a.dart`、`./b.dart`）按 [from]（导入方自己的 `lib/` 内相对路径）
///   解析并规整 `.` / `..`。`always_use_package_imports` 只管 import 的主 URI，
///   export 与条件导入分支里的相对写法它拦不住，所以这里必须自己解析，
///   否则这些依赖边会被静默漏掉；
/// - 解析后跳出 `lib/` 的相对 URI、没给 [from] 的相对 URI → `null`；
/// - `dart:`、其他 package、`file:` 等带 scheme 的 URI → `null`。
String? projectPath(String uri, {String? from}) {
  if (uri.startsWith(_projectPrefix)) {
    return uri.substring(_projectPrefix.length);
  }
  // 带 scheme（`dart:io`、`package:x/...`）或绝对路径：不是项目内的相对引用。
  if (uri.startsWith('/') ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(uri)) {
    return null;
  }
  if (from == null) return null;

  final segments = from.split('/')..removeLast(); // 导入方所在目录
  for (final seg in uri.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (segments.isEmpty) return null; // 跳出 lib/
      segments.removeLast();
    } else {
      segments.add(seg);
    }
  }
  return segments.join('/');
}
