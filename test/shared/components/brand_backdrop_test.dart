import 'package:clashmiao/shared/components/brand_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewport = Size(430, 860);

Future<void> _pumpBackdrop(WidgetTester tester) async {
  tester.view.physicalSize = _viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: BrandBackdrop())),
  );
  await tester.pump();
}

void main() {
  testWidgets('晕染四角都有：顶部一层、底部一层', (tester) async {
    await _pumpBackdrop(tester);

    for (final key in const [
      'brand-wash-top-left',
      'brand-wash-top-right',
      'brand-wash-bottom-left',
      'brand-wash-bottom-right',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: '缺了 $key');
    }
  });

  testWidgets('底部那层要盖住胶囊导航所在的那条带（否则浅色胶囊压在纯白上分不出边界）', (tester) async {
    await _pumpBackdrop(tester);

    // 胶囊高 68、离底 12，所以它占据的是页面最下面这 80px。
    const navBandTop = 860.0 - 80;
    for (final key in const [
      'brand-wash-bottom-left',
      'brand-wash-bottom-right',
    ]) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.top, lessThan(navBandTop), reason: '$key 没够到导航那条带');
      expect(rect.bottom, greaterThan(860.0), reason: '$key 应该一直漫到页尾');
    }
  });
}
