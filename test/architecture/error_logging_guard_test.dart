import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'error_logging_scanner.dart';

/// 界面层（`lib/features/**`、`lib/app/**`）的失败必须落进用户可导出的 app.log：
/// 错误路径里只 `debugPrint` 的写法会让排障时拿不到任何记录。
const _roots = ['lib/features', 'lib/app'];

bool _generated(String path) =>
    path.contains('/gen/') ||
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart');

void main() {
  test('界面层错误路径不只 debugPrint：失败一律走 logAppFailure', () {
    final violations = <DebugPrintOnErrorPath>[];
    for (final root in _roots) {
      final files =
          Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart') && !_generated(f.path))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        violations.addAll(
          scanErrorPathDebugPrints(
            f.path.replaceAll(r'\', '/'),
            f.readAsStringSync(),
          ),
        );
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '${violations.join('\n')}\n\n'
          '修法：catch / onError / error 回调里改用 logAppFailure（会重复触发的'
          '分支用 logAppFailureOnce），异常与堆栈会写进 app.log。',
    );
  });

  group('扫描器自测（合成源码）', () {
    int hits(String src) => scanErrorPathDebugPrints('x.dart', src).length;

    test('catch 里 debugPrint：违规', () {
      expect(hits("void f() { try {} catch (e) { debugPrint('x \$e'); } }"), 1);
      expect(
        hits(
          "void f() { try {} on StateError catch (e) { debugPrint('x'); } }",
        ),
        1,
      );
    });

    test('onError / error 回调里 debugPrint：违规', () {
      expect(
        hits(
          "void f(s) { s.listen((_) {}, onError: (e) => debugPrint('\$e')); }",
        ),
        1,
      );
      expect(
        hits(
          "Widget f(a) => a.when(error: (e, _) { debugPrint('\$e'); return x; });",
        ),
        1,
      );
    });

    test('logAppFailure 与非错误路径的 debugPrint：放行', () {
      expect(
        hits('''
void f() {
  debugPrint('流程诊断');
  try {} catch (e, st) { logAppFailure('where', e, st); }
}
'''),
        0,
      );
    });
  });
}
