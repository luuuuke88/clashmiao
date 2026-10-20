import 'dart:io';

import 'package:clashmiao/shared/components/system_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(ThemeMode mode, {Widget child = const SizedBox()}) => MaterialApp(
  themeMode: mode,
  theme: ThemeData.light(),
  darkTheme: ThemeData.dark(),
  builder: (context, child) => SystemUiScope(child: child!),
  home: Scaffold(body: child),
);

SystemUiOverlayStyle _regionStyle(WidgetTester tester) {
  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find.descendant(
      of: find.byType(SystemUiScope),
      matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    ),
  );
  return region.value;
}

void main() {
  group('系统栏样式', () {
    for (final brightness in Brightness.values) {
      test('${brightness.name}：状态栏 / 导航栏全透明、不加对比度遮罩', () {
        final style = appSystemUiOverlayStyle(brightness);
        expect(style.statusBarColor, Colors.transparent);
        expect(style.systemNavigationBarColor, Colors.transparent);
        expect(style.systemNavigationBarDividerColor, Colors.transparent);
        expect(
          style.systemNavigationBarContrastEnforced,
          isFalse,
          reason: '三键导航在栏透明时会垫半透明遮罩，那就是色带',
        );
      });
    }

    test('图标明暗与背景相反：浅色主题深图标，深色主题浅图标', () {
      final light = appSystemUiOverlayStyle(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      final dark = appSystemUiOverlayStyle(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
    });
  });

  group('SystemUiScope', () {
    testWidgets('随主题明暗给出兜底样式，切换主题后跟着变', (tester) async {
      await tester.pumpWidget(_app(ThemeMode.dark));
      expect(
        _regionStyle(tester).systemNavigationBarIconBrightness,
        Brightness.light,
      );
      await tester.pumpWidget(_app(ThemeMode.light));
      await tester.pumpAndSettle();
      expect(
        _regionStyle(tester).systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(_regionStyle(tester).systemNavigationBarColor, Colors.transparent);
    });

    testWidgets('Android 上启用 edge-to-edge', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_app(ThemeMode.dark));
      // 变量必须在用例结束前复位，框架在 tearDown 之前就校验它。
      debugDefaultTargetPlatformOverride = null;
      expect(
        calls.where(
          (c) =>
              c.method == 'SystemChrome.setEnabledSystemUIMode' &&
              c.arguments == 'SystemUiMode.edgeToEdge',
        ),
        isNotEmpty,
      );
    });
  });

  test('系统栏颜色只在 system_ui.dart 里定义，别处不得写死实色导航栏', () {
    final offenders = <String>[];
    for (final root in ['lib/features', 'lib/shared', 'lib/app']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path == 'lib/shared/components/system_ui.dart') continue;
        if (entity.readAsStringSync().contains('systemNavigationBarColor')) {
          offenders.add(path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
