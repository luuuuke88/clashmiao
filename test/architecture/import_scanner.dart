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

/// `package:clashmiao/x/y.dart` → `x/y.dart`；非项目内 URI 返回 `null`。
String? projectPath(String uri) => uri.startsWith(_projectPrefix)
    ? uri.substring(_projectPrefix.length)
    : null;
