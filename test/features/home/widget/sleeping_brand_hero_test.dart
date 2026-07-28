import 'package:clashmiao/features/home/widget/sleeping_brand_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool disableAnimations}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SleepingBrandHero()),
  ),
);

Offset _zOffset(WidgetTester tester, int index) =>
    tester.getTopLeft(find.byKey(ValueKey('sleep-zzz-$index')));

void main() {
  testWidgets('睡觉的猫：三个 z 都在，而且彼此错开（不是叠在同一个点上）', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.pump();

    final positions = [
      _zOffset(tester, 0),
      _zOffset(tester, 1),
      _zOffset(tester, 2),
    ];
    expect(positions.toSet().length, 3);
  });

  testWidgets('睡觉的猫：动画在跑——同一个 z 隔一段时间会飘到新位置', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.pump();
    final before = _zOffset(tester, 0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(_zOffset(tester, 0), isNot(before));

    // 常驻循环动画，测试结束前必须让 widget 下树，否则 pending timer 泄漏。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('系统开了"减弱动态效果"时彻底不动：z 停在原位，也不再排帧', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.pump();
    final before = _zOffset(tester, 0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(_zOffset(tester, 0), before);

    // 没有待处理帧才能 settle——这条同时证明了减弱动态效果下不会一直排帧。
    await tester.pumpAndSettle();
  });
}
