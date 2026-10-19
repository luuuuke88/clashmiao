import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_overflow.dart';

/// 已知溢出的放行规则本身必须是严的：位置、边、溢出量（相对本场景基线，带小
/// 容差）任何一项对不上都不放行，同一已知项第二次出现也不放行。
void main() {
  const conn = [
    'Column',
    'SizedBox',
    'Center',
    'Listener',
    '_GestureSemantics',
    'RawGestureDetector',
    'GestureDetector',
    'ConnectionButton',
    'FittedBox',
  ];
  final known = connectionButtonOverflow.at(28);

  test('位置、边、量级（基线 ± 容差）都对得上才匹配', () {
    expect(known.matches(const OverflowReport(28, 'bottom', conn)), isTrue);
    // 容差：max(1 px, 基线 2%)。
    expect(known.matches(const OverflowReport(28.9, 'bottom', conn)), isTrue);
    expect(known.matches(const OverflowReport(27.1, 'bottom', conn)), isTrue);
  });

  test('溢出量超出基线容差（变大或变小）都不匹配', () {
    expect(known.matches(const OverflowReport(29.5, 'bottom', conn)), isFalse);
    expect(known.matches(const OverflowReport(26.5, 'bottom', conn)), isFalse);
    expect(known.matches(const OverflowReport(399, 'bottom', conn)), isFalse);
    expect(known.matches(const OverflowReport(0, 'bottom', conn)), isFalse);
    // 基线大时容差按 2% 放宽，但仍是有界的。
    final wide = modeSelectorOverflow.at(308);
    const mode = [
      'Row',
      'Padding',
      'DecoratedBox',
      'ConstrainedBox',
      'Container',
      '_ModeSelector',
    ];
    expect(wide.matches(const OverflowReport(312, 'right', mode)), isTrue);
    expect(wide.matches(const OverflowReport(330, 'right', mode)), isFalse);
  });

  test('边不对 / 位置不对 都不匹配', () {
    expect(known.matches(const OverflowReport(28, 'right', conn)), isFalse);
    // 仅「链里提到 ConnectionButton」不够：开头的 RenderFlex 位置必须一致。
    expect(
      known.matches(
        const OverflowReport(28, 'bottom', [
          'Row',
          'Padding',
          'ConnectionButton',
        ]),
      ),
      isFalse,
    );
    expect(known.matches(const OverflowReport(28, 'bottom', [])), isFalse);
    expect(
      modeSelectorOverflow
          .at(22)
          .matches(const OverflowReport(22, 'right', conn)),
      isFalse,
    );
  });

  // 合成一个真实溢出：Align > SizedBox(50) > Row(子项 [width])，溢出 width-50。
  Widget overflowing(double width, {int copies = 1}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        for (var i = 0; i < copies; i++)
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 50,
              child: Row(children: [SizedBox(width: width, height: 10)]),
            ),
          ),
      ],
    ),
  );

  // 合成场景用的「已知项」：创建者位置是 Row ← SizedBox ← Align，右溢出 30。
  const synthetic = KnownOverflow(
    name: 'synthetic',
    creatorPrefix: ['Row', 'SizedBox', 'Align'],
    side: 'right',
    baseline: 30,
  );

  Future<(List<String>, List<FlutterErrorDetails>)> run(
    WidgetTester tester,
    Widget widget,
  ) async {
    final forwarded = <FlutterErrorDetails>[];
    final outer = FlutterError.onError;
    // 把「交给框架」的出口换成收集器，才能在这里断言它被调用。
    FlutterError.onError = forwarded.add;
    final seen = await runAllowingKnownOverflows(const [synthetic], () async {
      await tester.pumpWidget(widget);
    });
    FlutterError.onError = outer;
    return (seen, forwarded);
  }

  testWidgets('量级恰在基线内：放行一次，没有任何东西交给框架', (tester) async {
    final (seen, forwarded) = await run(tester, overflowing(80));
    expect(seen, ['synthetic']);
    expect(forwarded, isEmpty);
  });

  testWidgets('负例：溢出量超过本场景基线 → 不放行，原样交给框架', (tester) async {
    final (seen, forwarded) = await run(tester, overflowing(120));
    expect(seen, isEmpty);
    expect(forwarded, hasLength(1));
    expect(forwarded.single.exceptionAsString(), contains('overflowed by 70'));
  });

  testWidgets('负例：同一已知项重复报告 → 第一次放行，第二次交给框架', (tester) async {
    final (seen, forwarded) = await run(tester, overflowing(80, copies: 2));
    expect(seen, ['synthetic']);
    expect(forwarded, hasLength(1));
    expect(forwarded.single.exceptionAsString(), contains('overflowed by 30'));
  });

  testWidgets('不在预期里的溢出原样交给框架（测试失败），而不是被吞掉', (tester) async {
    final forwarded = <FlutterErrorDetails>[];
    final outer = FlutterError.onError;
    FlutterError.onError = forwarded.add;
    final seen = await runAllowingKnownOverflows(const [], () async {
      await tester.pumpWidget(overflowing(80));
    });
    FlutterError.onError = outer;
    expect(seen, isEmpty);
    expect(forwarded, hasLength(1));
  });
}
