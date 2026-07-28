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

({double scale, double opacity}) _rippleFrame(WidgetTester tester, String key) {
  final ripple = find.byKey(ValueKey(key));
  final transform = tester.widget<Transform>(
    find.descendant(of: ripple, matching: find.byType(Transform)),
  );
  final opacity = tester.widget<Opacity>(
    find.descendant(of: ripple, matching: find.byType(Opacity)),
  );
  return (
    scale: transform.transform.getMaxScaleOnAxis(),
    opacity: opacity.opacity,
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

  testWidgets('从已连接进入停止中时闪电回到默认状态', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted()));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.pumpWidget(_host(const BoxStopping()));
    await tester.pump(const Duration(milliseconds: 220));

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('connection-bolt-transform')),
    );
    final glow = tester.widget<Opacity>(
      find.byKey(const ValueKey('connection-bolt-glow')),
    );
    expect(transform.transform.getTranslation().y, closeTo(0, 0.001));
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(glow.opacity, closeTo(0.04, 0.001));
    expect(find.byKey(const ValueKey('connection-blue-halo')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-0')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsNothing);
  });

  testWidgets('减少动态效果时停止中使用默认静态帧', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted(), disableAnimations: true));
    await tester.pumpWidget(
      _host(const BoxStopping(), disableAnimations: true),
    );
    await tester.pump(const Duration(milliseconds: 220));

    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('connection-bolt-transform')),
    );
    final glow = tester.widget<Opacity>(
      find.byKey(const ValueKey('connection-bolt-glow')),
    );
    expect(transform.transform.getTranslation().y, closeTo(0, 0.001));
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(glow.opacity, closeTo(0.04, 0.001));
    expect(find.byKey(const ValueKey('connection-blue-halo')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-0')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsNothing);
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
  });

  testWidgets('两个涟漪分别等待 120ms 和 250ms 后出现', (tester) async {
    await tester.pumpWidget(_host(const BoxStarting()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('connection-ripple-0')), findsNothing);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsNothing);

    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byKey(const ValueKey('connection-ripple-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsNothing);

    await tester.pump(const Duration(milliseconds: 130));
    expect(find.byKey(const ValueKey('connection-ripple-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-ripple-1')), findsOneWidget);
  });

  testWidgets('涟漪出现后单调扩张并淡出', (tester) async {
    await tester.pumpWidget(_host(const BoxStarting()));
    await tester.pump(const Duration(milliseconds: 260));

    final ripple0Earlier = _rippleFrame(tester, 'connection-ripple-0');
    final ripple1Earlier = _rippleFrame(tester, 'connection-ripple-1');

    await tester.pump(const Duration(milliseconds: 140));
    final ripple0Later = _rippleFrame(tester, 'connection-ripple-0');
    final ripple1Later = _rippleFrame(tester, 'connection-ripple-1');

    expect(ripple0Later.scale, greaterThan(ripple0Earlier.scale));
    expect(ripple0Later.opacity, lessThan(ripple0Earlier.opacity));
    expect(ripple1Later.scale, greaterThan(ripple1Earlier.scale));
    expect(ripple1Later.opacity, lessThan(ripple1Earlier.opacity));
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

  testWidgets('已连接时闪电保持点亮，而且亮度在呼吸（不是连上就熄火）', (tester) async {
    await tester.pumpWidget(_host(const BoxStopped()));
    final idleGlow = tester
        .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
        .opacity;

    await tester.pumpWidget(_host(const BoxStarted()));
    await tester.pump(const Duration(milliseconds: 300));
    final litGlow = tester
        .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
        .opacity;

    await tester.pump(const Duration(milliseconds: 600));
    final laterGlow = tester
        .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
        .opacity;

    expect(litGlow, greaterThan(idleGlow), reason: '连上之后闪电要比待机时亮');
    expect(laterGlow, isNot(closeTo(litGlow, 0.001)), reason: '亮度要一亮一暗地闪');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('光晕跟着 Logo 尺寸放大——大按钮上才可能扩散到猫脸外面', (tester) async {
    Future<double> haloWidthAt(double size) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpeedCatConnectionMark(
                status: const BoxStarted(),
                size: size,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester
          .getSize(find.byKey(const ValueKey('connection-blue-halo')))
          .width;
    }

    final small = await haloWidthAt(112);
    final large = await haloWidthAt(214);

    expect(large, greaterThan(small * 1.5));
    expect(large, greaterThan(190), reason: '要盖过首页那颗 190 的底盘才叫"绕在 Logo 外圈"');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('已连接时闪电持续冒电火花，而且不规则地窜（不是规律呼吸）', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey('connection-spark-0')),
      findsOneWidget,
      reason: '连上之后闪电周围要一直有电弧窜出来',
    );

    // 连着三帧取辉光亮度：电流的抖动不该是单调升或单调降。
    final samples = <double>[];
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 45));
      samples.add(
        tester
            .widget<Opacity>(find.byKey(const ValueKey('connection-bolt-glow')))
            .opacity,
      );
    }
    expect(samples.toSet().length, 3, reason: '每帧都该变，否则不是"滋滋"是"呼吸"');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('已连接时闪电内部有一道流动的电流高光', (tester) async {
    await tester.pumpWidget(_host(const BoxStarted()));
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const ValueKey('connection-bolt-current')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('未连接和减少动态效果时都不冒电火花', (tester) async {
    await tester.pumpWidget(_host(const BoxStopped()));
    await tester.pump();
    expect(find.byKey(const ValueKey('connection-spark-0')), findsNothing);

    await tester.pumpWidget(_host(const BoxStarted(), disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('connection-spark-0')), findsNothing);
    expect(find.byKey(const ValueKey('connection-bolt-current')), findsNothing);
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
