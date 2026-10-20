import 'package:clashmiao/shared/components/animated_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({Widget? mark, bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: AnimatedMark(child: mark)),
  ),
);

const _check = Icon(Icons.check, key: ValueKey('check'));
const _chevron = Icon(Icons.chevron_right, key: ValueKey('chevron'));

void main() {
  testWidgets('标记出现：先半透明，再完全不透明', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpWidget(_host(mark: _check));
    await tester.pump(const Duration(milliseconds: 60));
    final opacity = tester
        .widget<FadeTransition>(
          find.ancestor(
            of: find.byKey(const ValueKey('check')),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;
    expect(opacity, inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('check')), findsOneWidget);
  });

  testWidgets('两个图标互换：过渡期间新旧并存，结束后只剩新的', (tester) async {
    await tester.pumpWidget(_host(mark: _chevron));
    await tester.pumpWidget(_host(mark: _check));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('chevron')), findsOneWidget);
    expect(find.byKey(const ValueKey('check')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('chevron')), findsNothing);
    expect(find.byKey(const ValueKey('check')), findsOneWidget);
  });

  testWidgets('减少动画：瞬时切换', (tester) async {
    await tester.pumpWidget(_host(mark: _chevron, disableAnimations: true));
    await tester.pumpWidget(_host(mark: _check, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('chevron')), findsNothing);
    expect(find.byKey(const ValueKey('check')), findsOneWidget);
  });
}
