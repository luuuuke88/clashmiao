import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 弹出一张弹层，并把它所在的路由抓出来看转场参数。
Future<ModalRoute<void>> _openAndCaptureRoute(
  WidgetTester tester, {
  required bool disableAnimations,
}) async {
  ModalRoute<void>? route;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAiUiModal<void>(
                context: context,
                builder: (sheetContext) {
                  route = ModalRoute.of(sheetContext) as ModalRoute<void>?;
                  return const AiUiModalWrapper(child: Text('sheet'));
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return route!;
}

void main() {
  testWidgets('showAiUiModal 与快速设置同一套转场：入场 250 / 退场 200 ms', (tester) async {
    final route = await _openAndCaptureRoute(tester, disableAnimations: false);
    expect(route.transitionDuration, Motion.medium);
    expect(route.reverseTransitionDuration, Motion.sheetExit);
  });

  testWidgets('减少动画：弹层路由没有转场时长', (tester) async {
    final route = await _openAndCaptureRoute(tester, disableAnimations: true);
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
  });
}
