import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('弹层再长也要给页面标题留出顶部空间', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAiUiModal<void>(
                  context: context,
                  // 内容比屏幕高得多（真实场景就是十几种语言那一列）：
                  // 不封顶的话弹层会一路顶到屏幕最上面。
                  builder: (_) => AiUiModalWrapper(
                    child: Column(
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 56, child: Text('$i')),
                      ),
                    ),
                  ),
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

    final sheetTop = tester.getRect(find.byType(AiUiModalWrapper)).top;
    expect(sheetTop, greaterThanOrEqualTo(90.0), reason: '弹层顶得太高就会盖住页面标题');
  });

  testWidgets('直接用 showModalBottomSheet 弹出时同样封顶（设置页就是这么调的）', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => AiUiModalWrapper(
                    child: Column(
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 56, child: Text('$i')),
                      ),
                    ),
                  ),
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

    expect(
      tester.getRect(find.byType(AiUiModalWrapper)).top,
      greaterThanOrEqualTo(90.0),
      reason: '封顶必须写在 wrapper 里，否则绕过 showAiUiModal 的调用点全都漏掉',
    );
  });

  testWidgets('routeProvidesSurface：加上系统拖拽柄之后整张弹层仍不越过顶部留白', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => AiUiModalWrapper(
                    routeProvidesSurface: true,
                    child: Column(
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 56, child: Text('$i')),
                      ),
                    ),
                  ),
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

    expect(
      tester.getRect(find.byType(BottomSheet)).top,
      greaterThanOrEqualTo(90.0),
      reason: '含拖拽柄的整张弹层不能盖住页面标题',
    );
  });

  testWidgets('毛玻璃弹层的底铺到导航栏下面，内容仍停在导航栏之上（edge-to-edge）', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    // 手势导航条：系统在底部留 48 的安全区。
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAiUiModal<void>(
                  context: context,
                  builder: (_) => const AiUiModalWrapper(
                    child: SizedBox(height: 120, child: Text('last')),
                  ),
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

    final surface = tester.getRect(
      find.descendant(
        of: find.byType(AiUiModalWrapper),
        matching: find.byType(BackdropFilter),
      ),
    );
    expect(
      surface.bottom,
      900.0,
      reason: '弹层底色要一直铺到屏幕底边，否则导航栏那一条会露出下面的页面，像断了一截',
    );
    expect(
      tester.getRect(find.text('last')).bottom,
      lessThanOrEqualTo(900.0 - 48),
      reason: '内容不能被手势导航条压住',
    );
  });
}
