// 用户可见文案的守卫扫描器（纯 Dart，用官方解析器，不用正则）。
//
// 两条规则：
// 1. 异常原文不进文案：catch 到的异常、`error:` / `onError:` 回调的错误参数、
//    以及 `xxx.error` 取值，不得被插值进字符串或 `.toString()`——技术细节只进
//    日志，用户看到的是类型化的本地化文案。
// 2. 不写死中文：`lib/` 里的 CJK 字符串字面量必须来自生成的 i18n；真正不该翻
//    译的（品牌、语言自称、解析节点名用的关键词表、调试夹具）逐条登记在白名单。
//
// 两条规则都豁免「技术通道」：日志调用（debugPrint / print / log / 日志对象
// 上的方法）、throw、assert、异常 / 失败类型的构造（名字以 Exception、
// Error、Failure、Failed、Fault 结尾——它们携带技术信息，展示时再映射成本地化
// 文案）、以及 `toString()` 的实现。
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// 一条违规。
class StringViolation {
  const StringViolation(this.path, this.line, this.rule, this.snippet);

  final String path;
  final int line;
  final String rule;
  final String snippet;

  @override
  String toString() => '$path:$line · $rule · $snippet';
}

const ruleRawError = '异常原文进了文案';
const ruleCjkLiteral = '写死的中文文案';

final _cjk = RegExp(r'[　-〿㐀-䶿一-鿿＀-￯]');

/// 扫描 [source]（路径 [path] 仅用于报告）。[allowedCjk] 是这个文件里允许出现
/// 的 CJK 字面量（完整字面量值）；`null` 表示整个文件豁免规则 2。
List<StringViolation> scanUserStrings(
  String path,
  String source, {
  Set<String>? allowedCjk = const {},
  bool checkCjk = true,
  bool checkRawError = true,
}) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _Visitor(
    path,
    result.lineInfo,
    allowedCjk: allowedCjk,
    checkCjk: checkCjk && allowedCjk != null,
    checkRawError: checkRawError,
  );
  result.unit.accept(visitor);
  return visitor.violations;
}

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(
    this.path,
    this.lineInfo, {
    required this.allowedCjk,
    required this.checkCjk,
    required this.checkRawError,
  });

  final String path;
  final LineInfo lineInfo;
  final Set<String>? allowedCjk;
  final bool checkCjk;
  final bool checkRawError;
  final violations = <StringViolation>[];

  /// 当前作用域里的错误变量名（catch 参数、error 回调参数）。
  final _errorNames = <String>[];

  void _report(AstNode node, String rule) {
    final line = lineInfo.getLocation(node.offset).lineNumber;
    var snippet = node.toSource();
    if (snippet.length > 100) snippet = '${snippet.substring(0, 100)}…';
    violations.add(StringViolation(path, line, rule, snippet));
  }

  @override
  void visitCatchClause(CatchClause node) {
    final name = node.exceptionParameter?.name.lexeme;
    if (name == null) return super.visitCatchClause(node);
    _errorNames.add(name);
    super.visitCatchClause(node);
    _errorNames.removeLast();
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    final label = node.name.label.name;
    final fn = node.expression;
    if ((label == 'error' || label == 'onError') && fn is FunctionExpression) {
      final first = fn.parameters?.parameters.firstOrNull?.name?.lexeme;
      if (first != null) {
        _errorNames.add(first);
        super.visitNamedExpression(node);
        _errorNames.removeLast();
        return;
      }
    }
    super.visitNamedExpression(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (!_inTechnicalSink(node)) {
      for (final el in node.elements) {
        if (checkRawError &&
            el is InterpolationExpression &&
            _isErrorValue(el.expression)) {
          _report(node, ruleRawError);
          break;
        }
      }
      if (checkCjk) {
        final text = node.elements
            .whereType<InterpolationString>()
            .map((s) => s.value)
            .join();
        if (_cjk.hasMatch(text) && !_allowed(node)) {
          _report(node, ruleCjkLiteral);
        }
      }
    }
    super.visitStringInterpolation(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (checkCjk &&
        _cjk.hasMatch(node.value) &&
        node.parent is! StringInterpolation &&
        !_inTechnicalSink(node) &&
        !_allowed(node)) {
      _report(node, ruleCjkLiteral);
    }
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (checkRawError &&
        node.methodName.name == 'toString' &&
        node.argumentList.arguments.isEmpty &&
        _isErrorValue(node.target) &&
        !_inTechnicalSink(node)) {
      _report(node, ruleRawError);
    }
    super.visitMethodInvocation(node);
  }

  bool _allowed(StringLiteral node) {
    final allow = allowedCjk;
    if (allow == null) return true;
    final value = node.stringValue;
    if (value != null && allow.contains(value)) return true;
    // 相邻字符串拼接：按整体值判断。
    final parent = node.parent;
    if (parent is AdjacentStrings) {
      final whole = parent.stringValue;
      if (whole != null && allow.contains(whole)) return true;
    }
    return false;
  }

  /// [e] 是错误值：错误变量本身，或以它为根的属性 / 方法链（`e.message`）、
  /// 或任意 `xxx.error` 取值（`AsyncValue.error`、状态里存的异常原文）。
  bool _isErrorValue(Expression? e) {
    if (e == null) return false;
    if (e is SimpleIdentifier) return _errorNames.contains(e.name);
    if (e is PrefixedIdentifier) {
      return _errorNames.contains(e.prefix.name) ||
          e.identifier.name == 'error';
    }
    if (e is PropertyAccess) {
      return e.propertyName.name == 'error' || _isErrorValue(e.target);
    }
    if (e is PostfixExpression) return _isErrorValue(e.operand);
    if (e is ParenthesizedExpression) return _isErrorValue(e.expression);
    if (e is MethodInvocation) return _isErrorValue(e.target);
    return false;
  }

  static const _logFunctions = {'debugPrint', 'print', 'log', 'debugLog'};
  // 日志对象：`_log.warning(...)`、`logger.e(...)`。只认这几个名字，免得
  // `dialog.show(...)` 之类被误当成日志通道。
  static final _loggerTarget = RegExp(
    r'^_?(log|logger|appLogger)$',
    caseSensitive: false,
  );
  static final _carrierType = RegExp(
    r'(Exception|Error|Failure|Failed|Fault)$',
  );

  bool _inTechnicalSink(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is ThrowExpression || p is Assertion || p is AssertInitializer) {
        return true;
      }
      if (p is MethodDeclaration && p.name.lexeme == 'toString') return true;
      if (p is InstanceCreationExpression &&
          _carrierType.hasMatch(p.constructorName.type.name2.lexeme)) {
        return true;
      }
      if (p is MethodInvocation) {
        final name = p.methodName.name;
        final target = p.target;
        if (target == null && _logFunctions.contains(name)) return true;
        // 不带 new 的构造调用解析成 MethodInvocation。
        if (target == null && _carrierType.hasMatch(name)) return true;
        if (target is SimpleIdentifier && _loggerTarget.hasMatch(target.name)) {
          return true;
        }
      }
    }
    return false;
  }
}
