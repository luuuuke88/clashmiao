import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/features/home/widget/speed_cat_connection_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(BoxStatus status, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(child: SpeedCatConnectionMark(status: status)),
      ),
    ),
  );
}

void main() {
  testWidgets('四种连接状态都使用分层猫咪 Logo', (tester) async {
    for (final status in <BoxStatus>[
      const BoxStopped(),
      const BoxStarting(),
      const BoxStarted(),
      const BoxStopping(),
    ]) {
      await tester.pumpWidget(_host(status));

      expect(
        find.byKey(const ValueKey('connection-cat-layer')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('connection-bolt-layer')),
        findsOneWidget,
      );
    }
  });

  testWidgets('连接中闪电独立上抬放大并出现蓝色光圈', (tester) async {
    await tester.pumpWidget(_host(const BoxStarting()));
    await tester.pump(const Duration(milliseconds: 220));

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('connection-bolt-transform')),
    );
    expect(transform.transform.getTranslation().y, lessThan(-6));
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1.15));
    expect(find.byKey(const ValueKey('connection-ripple-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsOneWidget);
  });

  testWidgets('激活动画结束后不保留涟漪', (tester) async {
    await tester.pumpWidget(_host(const BoxStarting()));
    await tester.pump(const Duration(milliseconds: 610));

    expect(find.byKey(const ValueKey('connection-ripple-0')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsNothing);
  });

  testWidgets('激活时闪电光效在峰值后回落到稳定亮度', (tester) async {
    await tester.pumpWidget(_host(const BoxStarting()));
    await tester.pump(const Duration(milliseconds: 220));

    final peakOpacity = tester
        .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
        .opacity;
    expect(peakOpacity, greaterThan(0.3));

    await tester.pump(const Duration(milliseconds: 400));
    final settledOpacity = tester
        .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
        .opacity;
    expect(settledOpacity, closeTo(0.12, 0.01));
    expect(settledOpacity, lessThan(peakOpacity));
  });

  testWidgets('已连接保留蓝色呼吸光', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted()));

    expect(find.byKey(const ValueKey('connection-blue-halo')), findsOneWidget);
  });

  testWidgets('已连接光圈平滑地呼吸回落', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted()));

    await tester.pump(const Duration(milliseconds: 600));
    final risingDiameter = tester
        .getSize(find.byKey(const ValueKey('connection-blue-halo')))
        .width;

    await tester.pump(const Duration(milliseconds: 600));
    final peakDiameter = tester
        .getSize(find.byKey(const ValueKey('connection-blue-halo')))
        .width;

    await tester.pump(const Duration(milliseconds: 600));
    final fallingDiameter = tester
        .getSize(find.byKey(const ValueKey('connection-blue-halo')))
        .width;

    expect(peakDiameter, greaterThan(risingDiameter));
    expect(fallingDiameter, lessThan(peakDiameter));
    expect(fallingDiameter, closeTo(risingDiameter, 0.01));
  });

  testWidgets('减少动态效果时保留静态分层 Logo', (tester) async {
    await tester.pumpWidget(
      _host(const BoxStarting(), disableAnimations: true),
    );
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byKey(const ValueKey('connection-cat-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-bolt-layer')), findsOneWidget);

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('connection-bolt-transform')),
    );
    expect(transform.transform.getTranslation().y, greaterThanOrEqualTo(-2));
  });
}
