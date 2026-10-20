import 'package:clashmiao/shared/navigation/animated_tab_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: Center(child: Text('taps=$taps')),
  );
}

Widget _host({required int index, bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedTabStack(
        index: index,
        children: const [
          _Counter(key: ValueKey('page0')),
          Center(child: Text('page1')),
        ],
      ),
    ),
  );
}

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byType(FadeTransition).first)
    .opacity
    .value;

void main() {
  testWidgets('首次构建不淡入', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    expect(_opacity(tester), 1);
  });

  testWidgets('切换 tab：新页面从透明淡入到不透明', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.pumpWidget(_host(index: 1));
    expect(_opacity(tester), 0);

    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester), inExclusiveRange(0, 1));

    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacity(tester), 1);
    expect(find.text('page1'), findsOneWidget);
  });

  testWidgets('减少动画：切换后立刻是终态', (tester) async {
    await tester.pumpWidget(_host(index: 0, disableAnimations: true));
    await tester.pumpWidget(_host(index: 1, disableAnimations: true));
    expect(_opacity(tester), 1);
  });

  testWidgets('淡入进行到一半打开减少动画：立刻收尾', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.pumpWidget(_host(index: 1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), lessThan(1));

    await tester.pumpWidget(_host(index: 1, disableAnimations: true));
    expect(_opacity(tester), 1);
  });

  testWidgets('切走再切回：各页保活，状态不丢', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.tap(find.text('taps=0'));
    await tester.pump();
    expect(find.text('taps=1'), findsOneWidget);

    await tester.pumpWidget(_host(index: 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_host(index: 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('taps=1'), findsOneWidget);
  });

  testWidgets('只有当前页的 Ticker 开着', (tester) async {
    await tester.pumpWidget(_host(index: 1));
    bool enabled(Key key) => TickerMode.valuesOf(
      tester.element(find.byKey(key, skipOffstage: false)),
    ).enabled;
    expect(enabled(const ValueKey('page0')), isFalse);
    await tester.pumpWidget(_host(index: 0));
    expect(enabled(const ValueKey('page0')), isTrue);
  });
}
