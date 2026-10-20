import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// edge-to-edge 下手势条占底部一圈：弹层底色铺到屏幕底边，滚动内容能划过这一圈，
/// 滚到头时最后一项停在手势条上方，而不是在手势条上沿被硬切掉。
void main() {
  for (final routeProvidesSurface in [false, true]) {
    testWidgets(
      '弹层滚动区铺到屏幕底边，末尾留出手势条高度（routeProvidesSurface=$routeProvidesSurface）',
      (tester) async {
        const inset = 34.0;
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(padding: const EdgeInsets.only(bottom: inset)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AiUiModalWrapper(
                  routeProvidesSurface: routeProvidesSurface,
                  showHandle: false,
                  child: Column(
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(
                          height: 80,
                          child: Text('item $i', key: ValueKey('item-$i')),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scroll = find.byType(SingleChildScrollView);
        expect(
          tester.getBottomLeft(scroll).dy,
          closeTo(800, 1), // 毛玻璃表面有 0.5 dp 描边
          reason: '滚动区一直铺到屏幕底边（不在手势条上沿截断）',
        );

        await tester.drag(scroll, const Offset(0, -5000));
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(find.byKey(const ValueKey('item-29'))).dy,
          closeTo(800 - inset, 1),
          reason: '滚到头，最后一项停在手势条上方',
        );
      },
    );
  }
}
