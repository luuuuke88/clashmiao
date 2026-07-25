import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/model/advanced_config.dart';
import 'package:clashmiao/shared/components/experimental_feature_notice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('hasExperimentalFeatures (纯字段判断，无 UI 依赖)', () {
    test('全部默认值 → 不是实验性配置', () {
      expect(
        hasExperimentalFeatures(settings: const NetworkSettings()),
        isFalse,
      );
    });

    test('enableTlsFragment 开启 → 实验性', () {
      final settings = const NetworkSettings().copyWith(
        enableTlsFragment: true,
      );
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('enableTlsPadding 开启 → 实验性', () {
      final settings = const NetworkSettings().copyWith(enableTlsPadding: true);
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('enableWarp 开启 → 实验性', () {
      final settings = const NetworkSettings().copyWith(enableWarp: true);
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('bypassLan 开启 → 实验性', () {
      final settings = const NetworkSettings().copyWith(bypassLan: true);
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('allowConnectionFromLan 开启 → 实验性', () {
      final settings = const NetworkSettings().copyWith(
        allowConnectionFromLan: true,
      );
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('桌面端开启 TUN → 实验性（测试进程跑在桌面 OS 上，isDesktop 恒真）', () {
      final settings = const NetworkSettings().copyWith(enableTun: true);
      expect(hasExperimentalFeatures(settings: settings), isTrue);
    });

    test('per-profile advancedConfig.fragmentEnabled → 实验性', () {
      expect(
        hasExperimentalFeatures(
          settings: const NetworkSettings(),
          advancedConfig: const AdvancedConfig(fragmentEnabled: true),
        ),
        isTrue,
      );
    });

    test('per-profile advancedConfig.muxEnabled → 实验性', () {
      expect(
        hasExperimentalFeatures(
          settings: const NetworkSettings(),
          advancedConfig: const AdvancedConfig(muxEnabled: true),
        ),
        isTrue,
      );
    });

    test('advancedConfig 为 null 且其它字段默认 → 不是实验性配置', () {
      expect(
        hasExperimentalFeatures(
          settings: const NetworkSettings(),
          advancedConfig: null,
        ),
        isFalse,
      );
    });
  });

  group('ExperimentalFeatureNoticeDialog 弹窗 UI', () {
    Future<ProviderContainer> pumpOpenButton(
      WidgetTester tester, {
      Map<String, Object> prefsValues = const {},
      required void Function(bool? result) onResult,
    }) async {
      SharedPreferences.setMockInitialValues({
        'locale': 'zhCn',
        ...prefsValues,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Center(
                    child: TextButton(
                      onPressed: () async {
                        final result =
                            await showExperimentalFeatureNoticeDialog(context);
                        onResult(result);
                      },
                      child: const Text('open-experimental-notice'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

      return container;
    }

    testWidgets('展示标题、说明文字与"不再提示"开关', (tester) async {
      bool? result;
      await pumpOpenButton(tester, onResult: (r) => result = r);

      await tester.tap(find.text('open-experimental-notice'));
      await tester.pumpAndSettle();

      expect(find.byType(ExperimentalFeatureNoticeDialog), findsOneWidget);
      expect(find.textContaining('实验性'), findsWidgets);
      expect(find.byType(Checkbox), findsOneWidget);

      await tester.tap(find.text('仍然连接'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('点击取消按钮返回 false', (tester) async {
      bool? result;
      await pumpOpenButton(tester, onResult: (r) => result = r);

      await tester.tap(find.text('open-experimental-notice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('勾选"不再提示"会持久化到 SharedPreferences', (tester) async {
      await pumpOpenButton(tester, onResult: (_) {});

      await tester.tap(find.text('open-experimental-notice'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      await tester.tap(find.text('仍然连接'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kExperimentalNoticeDismissedKey), isTrue);
    });
  });

  group('maybeConfirmExperimentalFeatures（门禁入口，widget 内用于读取当前配置）', () {
    testWidgets('无实验性字段时直接放行，不弹窗', (tester) async {
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith((_) async => null),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);

      bool? proceed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return TextButton(
                    onPressed: () async {
                      proceed = await maybeConfirmExperimentalFeatures(
                        context: context,
                        ref: ref,
                      );
                    },
                    child: const Text('tap'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(proceed, isTrue);
      expect(find.byType(ExperimentalFeatureNoticeDialog), findsNothing);
    });

    testWidgets('已勾选"不再提示"时直接放行，即使配置命中实验性字段', (tester) async {
      SharedPreferences.setMockInitialValues({
        'locale': 'zhCn',
        'clashmiao_bypass_lan': true,
        kExperimentalNoticeDismissedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          activeProfileProvider.overrideWith((_) async => null),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(activeProfileProvider.future);

      bool? proceed;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return TextButton(
                    onPressed: () async {
                      proceed = await maybeConfirmExperimentalFeatures(
                        context: context,
                        ref: ref,
                      );
                    },
                    child: const Text('tap'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(proceed, isTrue);
      expect(find.byType(ExperimentalFeatureNoticeDialog), findsNothing);
    });
  });
}
