import 'package:clashmiao/shared/components/adaptive_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AdaptiveIcon] 平台自适应图标封装的测试。
///
/// 用 `debugDefaultTargetPlatformOverride` 而不是真机/模拟器来 mock 平台——
/// [resolveAdaptiveIcon]/[AdaptiveIcon] 内部读的是 [defaultTargetPlatform]
/// （而不是 `dart:io` 的 `Platform.isIOS`），这样纯 `flutter test` 就能覆盖
/// Android / iOS 两条分支。
void main() {
  group('resolveAdaptiveIcon', () {
    test('iOS 平台返回 apple 图标', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final icon = resolveAdaptiveIcon(
        apple: Icons.more_horiz,
        other: Icons.more_vert,
      );

      expect(icon, Icons.more_horiz);
    });

    test('Android 平台返回 other 图标', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final icon = resolveAdaptiveIcon(
        apple: Icons.more_horiz,
        other: Icons.more_vert,
      );

      expect(icon, Icons.more_vert);
    });

    test('macOS 平台也返回 apple 图标（跟 iOS 同一套桌面/移动 Apple 生态）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final icon = resolveAdaptiveIcon(
        apple: Icons.more_horiz,
        other: Icons.more_vert,
      );

      expect(icon, Icons.more_horiz);
    });
  });

  group('AdaptiveIcon widget', () {
    testWidgets('mock 平台为 iOS 时渲染 apple 图标', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: AdaptiveIcon(
              apple: Icons.more_horiz,
              other: Icons.more_vert,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // flutter_test 在测试结束时会断言所有 foundation debug 变量都已复位，
      // 这个检查在 testWidgets 的测试体本身返回之前就跑，`tearDown`/
      // `addTearDown` 都来不及生效，所以必须在测试体末尾手动复位。
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('mock 平台为 Android 时渲染 other 图标', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: AdaptiveIcon(
              apple: Icons.more_horiz,
              other: Icons.more_vert,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('透传 size / color 给底层 Icon', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: AdaptiveIcon(
              apple: Icons.more_horiz,
              other: Icons.more_vert,
              size: 32,
              color: Colors.red,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 32);
      expect(icon.color, Colors.red);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
