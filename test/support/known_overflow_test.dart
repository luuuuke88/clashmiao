import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'known_overflow.dart';

/// 已知溢出的放行规则本身必须是严的：位置、边、量级任何一项对不上都不放行，
/// 同一已知项第二次出现也不放行。
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

  test('位置、边、量级都对得上才匹配', () {
    expect(
      connectionButtonOverflow.matches(
        const OverflowReport(28, 'bottom', conn),
      ),
      isTrue,
    );
  });

  test('边不对 / 量级超限 / 零溢出 / 位置不对 都不匹配', () {
    expect(
      connectionButtonOverflow.matches(const OverflowReport(28, 'right', conn)),
      isFalse,
    );
    expect(
      connectionButtonOverflow.matches(
        const OverflowReport(61, 'bottom', conn),
      ),
      isFalse,
    );
    expect(
      connectionButtonOverflow.matches(const OverflowReport(0, 'bottom', conn)),
      isFalse,
    );
    // 仅「链里提到 ConnectionButton」不够：开头的 RenderFlex 位置必须一致。
    expect(
      connectionButtonOverflow.matches(
        const OverflowReport(28, 'bottom', [
          'Row',
          'Padding',
          'ConnectionButton',
        ]),
      ),
      isFalse,
    );
    expect(
      connectionButtonOverflow.matches(const OverflowReport(28, 'bottom', [])),
      isFalse,
    );
    expect(
      modeSelectorOverflow.matches(const OverflowReport(22, 'right', conn)),
      isFalse,
    );
  });

  Widget overflowing() => const Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 50,
        child: Row(children: [SizedBox(width: 80, height: 10)]),
      ),
    ),
  );

  testWidgets('不在预期里的溢出原样交给框架（测试失败），而不是被吞掉', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final outer = FlutterError.onError;
    // 把「交给框架」的出口换成收集器，才能在这里断言它被调用。
    FlutterError.onError = errors.add;
    final seen = await runAllowingKnownOverflows(const [], () async {
      await tester.pumpWidget(overflowing());
    });
    FlutterError.onError = outer;
    expect(seen, isEmpty);
    expect(errors, hasLength(1));
    expect(errors.single.exceptionAsString(), contains('overflowed by 30'));
    tester.takeException();
  });
}
