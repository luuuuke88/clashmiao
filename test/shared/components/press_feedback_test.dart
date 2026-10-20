import 'package:clashmiao/shared/components/press_feedback.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
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

/// PressFeedback 自己那一层 `Semantics(button: true)` 对应的语义节点。
Finder _buttonSemantics() => find.descendant(
  of: find.byType(PressFeedback),
  matching: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.button == true,
  ),
);

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

  testWidgets('减少动画：不缩放，只瞬时变淡（手势识别后一帧就到位）', (tester) async {
    await _pump(tester, onTap: () {}, disableAnimations: true);
    expect(_scale(tester), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    // 只推进到 onTapDown 触发的那一帧，再多一帧；不再多等 200 ms——普通动画
    // 150 ms 走不完，错误地保留普通淡入时长时这里会红。
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump();
    expect(_opacity(tester), PressFeedback.pressedOpacity);
    expect(_scale(tester), 1, reason: '减少动画不缩放');

    await gesture.up();
    await tester.pump();
    expect(_opacity(tester), 1, reason: '松手同样一帧收回');
  });

  testWidgets('按住期间被禁用：反馈立即收回，松手不触发点击', (tester) async {
    var taps = 0;
    await _pump(tester, onTap: () => taps++);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('target'))),
    );
    await tester.pump(kPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), PressFeedback.pressedOpacity);

    await _pump(tester); // 回调没了 = 禁用
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacity(tester), 1);
    expect(_scale(tester), 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
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

  group('键盘与焦点', () {
    Finder ring() => find.byKey(const ValueKey('press-feedback-focus-ring'));

    testWidgets('Tab 聚焦后 Enter / Space 触发点击', (tester) async {
      var taps = 0;
      await _pump(tester, onTap: () => taps++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('只有长按回调时，键盘激活走长按', (tester) async {
      var longPresses = 0;
      await _pump(tester, onLongPress: () => longPresses++);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(longPresses, 1);
    });

    testWidgets('键盘聚焦时画焦点描边，颜色取主题主色；触屏 / 失焦时没有', (tester) async {
      await _pump(tester, onTap: () {});
      expect(ring(), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), findsOneWidget);
      final box = tester.widget<DecoratedBox>(ring());
      final border = (box.decoration as BoxDecoration).border! as Border;
      final context = tester.element(find.byType(PressFeedback));
      expect(border.top.color, Theme.of(context).colorScheme.primary);
      expect(border.top.width, PressFeedback.focusRingWidth);

      // 描边画在内容外面，不改变内容尺寸。
      expect(
        tester.getSize(find.byKey(const ValueKey('target'))),
        const Size(120, 60),
      );

      FocusManager.instance.primaryFocus?.unfocus(); // 焦点移出
      await tester.pump();
      await tester.pump();
      expect(ring(), findsNothing);
    });

    testWidgets('焦点描边随主题主色变化', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(primary: Color(0xFFFF8800)),
          ),
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                onTap: () {},
                child: const SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final box = tester.widget<DecoratedBox>(ring());
      expect(
        ((box.decoration as BoxDecoration).border! as Border).top.color,
        const Color(0xFFFF8800),
      );
    });

    testWidgets('禁用：不可聚焦，键盘不触发，也没有描边', (tester) async {
      await _pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.byKey(const ValueKey('target')))).hasFocus,
        isFalse,
      );
    });

    testWidgets('聚焦时被禁用：描边立即消失', (tester) async {
      await _pump(tester, onTap: () {});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), findsOneWidget);
      await _pump(tester);
      await tester.pump();
      expect(ring(), findsNothing);
    });
  });

  group('语义', () {
    testWidgets('是按钮、可用，点按与长按动作可由读屏触发', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      var longPresses = 0;
      await _pump(
        tester,
        onTap: () => taps++,
        onLongPress: () => longPresses++,
      );
      final node = tester.getSemantics(_buttonSemantics());
      expect(
        node,
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );

      final button = find.semantics.byFlag(SemanticsFlag.isButton);
      tester.semantics.tap(button);
      tester.semantics.longPress(button);
      await tester.pump();
      expect(taps, 1);
      expect(longPresses, 1);
      handle.dispose();
    });

    testWidgets('禁用：仍是按钮，但 enabled 为否、没有点按动作', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(
        tester.getSemantics(_buttonSemantics()),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
          hasLongPressAction: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('excludeFromSemantics：不提供按钮语义', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                excludeFromSemantics: true,
                onTap: () {},
                child: const SizedBox(width: 80, height: 40, child: Text('x')),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('x')),
        isSemantics(isButton: false, hasTapAction: false),
      );
      handle.dispose();
    });
  });
}
