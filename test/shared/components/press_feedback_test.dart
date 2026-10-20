import 'package:clashmiao/shared/components/press_feedback.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onTap,
  VoidCallback? onLongPress,
  bool disableAnimations = false,
  double pressedScale = PressFeedback.defaultPressedScale,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Center(
            child: PressFeedback(
              onTap: onTap,
              onLongPress: onLongPress,
              pressedScale: pressedScale,
              child: const ColoredBox(
                color: Colors.blue,
                key: ValueKey('target'),
                child: SizedBox(width: 120, height: 60),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

double _scale(WidgetTester tester) {
  final transforms = find.descendant(
    of: find.byType(PressFeedback),
    matching: find.byType(Transform),
  );
  return tester.widget<Transform>(transforms.first).transform.entry(0, 0);
}

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byType(PressFeedback),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

void main() {
  testWidgets('按下缩小并变淡，松手回弹，点击照常触发', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    expect(_scale(tester), 1);
    expect(_opacity(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    // 点按识别在按下后过了 kPressTimeout 才通知 onTapDown。
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    expect(_scale(tester), PressFeedback.defaultPressedScale);
    expect(_opacity(tester), PressFeedback.pressedOpacity);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_scale(tester), 1);
    expect(_opacity(tester), 1);
  });

  testWidgets('按下后拖出去：反馈收回、不触发点击', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    expect(_scale(tester), PressFeedback.defaultPressedScale);

    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_scale(tester), 1);
    expect(_opacity(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('pressedScale 可调（图标按钮缩得更多）', (tester) async {
    await _pump(
      tester,
      onTap: () {},
      pressedScale: PressFeedback.iconPressedScale,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    expect(_scale(tester), PressFeedback.iconPressedScale);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('减少动画：不缩放，只瞬时变淡', (tester) async {
    await _pump(tester, onTap: () {}, disableAnimations: true);
    expect(_scale(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    // 时长为零：一帧之内就到位。
    await tester.pump();
    expect(_opacity(tester), PressFeedback.pressedOpacity);
    expect(_scale(tester), 1, reason: '减少动画不缩放');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets('没有回调时视为禁用：按下没有反馈', (tester) async {
    await _pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    expect(_scale(tester), 1);
    expect(_opacity(tester), 1);
    await gesture.up();
  });

  testWidgets('只有长按回调时同样有按下反馈', (tester) async {
    var longPresses = 0;
    await _pump(tester, onLongPress: () => longPresses++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200)); // 走完 150 ms 的缓动
    expect(_scale(tester), PressFeedback.defaultPressedScale);
    await tester.pump(kLongPressTimeout);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(longPresses, 1);
    expect(_scale(tester), 1);
  });
}
