import 'package:flutter/foundation.dart';

/// 一处**已知**的、暂不修复的 RenderFlex 溢出：用创建者链前缀（具体的
/// RenderFlex 位置）、溢出边与溢出量范围精确描述，而不是按「链里提到某个
/// widget 名」笼统放行。
class KnownOverflow {
  const KnownOverflow({
    required this.name,
    required this.creatorPrefix,
    required this.side,
    required this.maxAmount,
  });

  final String name;

  /// 框架报告的 `debugCreator` 链（从溢出的 RenderFlex 向外）的前缀，逐项相等。
  final List<String> creatorPrefix;

  /// 框架报告的溢出边：`right` / `bottom` ……
  final String side;

  /// 合理溢出量的上限（逻辑像素）；超过说明布局变了、不再是同一个已知问题。
  final double maxAmount;

  bool matches(OverflowReport report) {
    if (report.side != side) return false;
    if (report.amount <= 0 || report.amount > maxAmount) return false;
    if (report.chain.length < creatorPrefix.length) return false;
    for (var i = 0; i < creatorPrefix.length; i++) {
      if (report.chain[i] != creatorPrefix[i]) return false;
    }
    return true;
  }
}

/// 一次溢出报告：溢出量、框架报告的溢出边、溢出 RenderFlex 的创建者链。
class OverflowReport {
  const OverflowReport(this.amount, this.side, this.chain);

  final double amount;
  final String side;
  final List<String> chain;

  static OverflowReport? tryParse(FlutterErrorDetails details) {
    final match = RegExp(
      r'overflowed by ([\d.]+) pixels on the (\w+)',
    ).firstMatch(details.exceptionAsString());
    if (match == null) return null;
    final text = (details.informationCollector?.call() ?? const [])
        .map((n) => n.toStringDeep())
        .join('\n');
    final creator = RegExp(
      r'(?:debugCreator|creator):\s*(.+)',
    ).firstMatch(text)?.group(1);
    final chain = creator == null
        ? const <String>[]
        : creator.split('←').map((e) => e.trim()).toList();
    return OverflowReport(
      double.parse(match.group(1)!),
      match.group(2)!,
      chain,
    );
  }
}

/// 首页连接区里两处已知溢出（连接区正在被重写，本期不得触碰；重写之后删掉）。
///
/// - 连接按钮：猫 + 圆盘缩放盒里的竖向 Column 在文字放大时越过底边；
/// - 模式分段控件：横向 Row 在窄屏 / 大字号 / 长翻译下越过右缘。
const connectionButtonOverflow = KnownOverflow(
  name: 'connectionButton',
  creatorPrefix: [
    'Column',
    'SizedBox',
    'Center',
    'Listener',
    '_GestureSemantics',
    'RawGestureDetector',
    'GestureDetector',
    'ConnectionButton',
  ],
  side: 'bottom',
  maxAmount: 60,
);

const modeSelectorOverflow = KnownOverflow(
  name: 'modeSelector',
  creatorPrefix: [
    'Row',
    'Padding',
    'DecoratedBox',
    'ConstrainedBox',
    'Container',
    '_ModeSelector',
  ],
  side: 'right',
  maxAmount: 400,
);

/// 在 [body] 期间安装 `FlutterError.onError`：只放行 [expected] 里列出的已知
/// 溢出，且**每一项最多放行一次**；其余一切（未知溢出、同一已知项的第二次出现、
/// 位置 / 边 / 量级对不上的溢出、任何其它错误）原样交给框架，让测试失败。
/// 返回值是实际放行的已知项名称（按出现顺序），调用方应断言它与预期**逐项
/// 一致、各一次**。
Future<List<String>> runAllowingKnownOverflows(
  List<KnownOverflow> expected,
  Future<void> Function() body,
) async {
  final previous = FlutterError.onError;
  final pending = [...expected];
  final seen = <String>[];
  FlutterError.onError = (details) {
    final report = OverflowReport.tryParse(details);
    if (report != null) {
      final index = pending.indexWhere((k) => k.matches(report));
      if (index >= 0) {
        seen.add(pending.removeAt(index).name);
        return;
      }
    }
    previous?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return seen;
}
