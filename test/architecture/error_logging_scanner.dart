// 失败日志守卫的扫描器：`lib/features/**`、`lib/app/**` 的错误路径（catch 块、
// `onError:` / `error:` 回调）里不许用 `debugPrint` 记错误——它只进开发控制台，
// 不会落进用户可导出的 app.log。错误路径一律用 `logAppFailure` /
// `logAppFailureOnce`（core/logger/app_logger.dart）。
//
// 非错误路径上的 `debugPrint`（流程诊断、调试夹具）不受影响。
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// 一条违规：错误路径里的 `debugPrint`。
class DebugPrintOnErrorPath {
  const DebugPrintOnErrorPath(this.path, this.line, this.snippet);

  final String path;
  final int line;
  final String snippet;

  @override
  String toString() => '$path:$line · 错误路径只 debugPrint · $snippet';
}

List<DebugPrintOnErrorPath> scanErrorPathDebugPrints(
  String path,
  String source,
) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final visitor = _Visitor();
  result.unit.accept(visitor);
  return [
    for (final node in visitor.hits)
      DebugPrintOnErrorPath(
        path,
        result.lineInfo.getLocation(node.offset).lineNumber,
        _snippet(node),
      ),
  ];
}

String _snippet(AstNode node) {
  final s = node.toSource();
  return s.length > 100 ? '${s.substring(0, 100)}…' : s;
}

class _Visitor extends RecursiveAstVisitor<void> {
  final hits = <MethodInvocation>[];
  var _depth = 0;

  @override
  void visitCatchClause(CatchClause node) {
    _depth++;
    super.visitCatchClause(node);
    _depth--;
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    final label = node.name.lexeme;
    if ((label == 'error' || label == 'onError') &&
        node.argumentExpression is FunctionExpression) {
      _depth++;
      super.visitNamedArgument(node);
      _depth--;
      return;
    }
    super.visitNamedArgument(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_depth > 0 &&
        node.target == null &&
        node.methodName.name == 'debugPrint') {
      hits.add(node);
    }
    super.visitMethodInvocation(node);
  }
}
