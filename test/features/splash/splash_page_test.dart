import 'package:clashmiao/features/splash/widget/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required VoidCallback onFinished,
  bool disableAnimations = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: SplashPage(onFinished: onFinished),
  ),
);

void main() {
  testWidgets('开屏：猫先弹进来，再冒出招呼气泡和名字', (tester) async {
    var finished = 0;
    await tester.pumpWidget(_host(onFinished: () => finished++));

    // 取矩阵的 X 轴缩放，不用 getMaxScaleOnAxis——后者会把恒为 1 的 Z 轴算进去，
    // 缩小（<1）的情况一律读成 1.0，测不出"弹进来"。
    double catScale() => tester
        .widget<Transform>(find.byKey(const ValueKey('splash-cat-scale')))
        .transform
        .storage[0];

    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey('splash-cat')), findsOneWidget);
    final earlyScale = catScale();
    expect(earlyScale, lessThan(1.0), reason: '一开始要比最终尺寸小，才有"弹进来"');

    await tester.pump(const Duration(milliseconds: 660));
    expect(catScale(), greaterThan(earlyScale), reason: '猫要弹起来，不是一上来就定死');
    expect(find.text('Hi 喵~'), findsOneWidget);
    expect(find.text('ClashMiao'), findsOneWidget);

    // 动画放完必须放行，否则用户被永久挡在开屏页
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('系统开了"减弱动态效果"：不放动画也不干等，立刻放行', (tester) async {
    var finished = 0;
    await tester.pumpWidget(
      _host(onFinished: () => finished++, disableAnimations: true),
    );
    await tester.pump();

    expect(finished, 1, reason: '减弱动态效果时不该让用户干等一秒半');
  });
}
