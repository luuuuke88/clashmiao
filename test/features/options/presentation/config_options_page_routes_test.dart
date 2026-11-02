import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/options/presentation/config_options_page.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 记录一个 Navigator 上的路由事件（按发生顺序）。
class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('$name push ${route.runtimeType}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('$name pop ${route.runtimeType}');
}

/// 配置选项页放在一个嵌套 Navigator 里（根 Navigator 另有观察器），
/// 目标页用桩，只验证入口的行为：先收起操作面板，再压入目标页。
Future<({List<String> log, GlobalKey<NavigatorState> nestedKey})> _pump(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);

  final log = <String>[];
  final nestedKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: AppRouteScope(
        builders: {
          AppRoute.assets: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('资产页桩'),
              ),
            ),
          ),
          AppRoute.logs: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('日志页桩'),
              ),
            ),
          ),
        },
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            navigatorObservers: [_RecordingObserver('root', log)],
            home: Navigator(
              key: nestedKey,
              observers: [_RecordingObserver('nested', log)],
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const ConfigOptionsPage(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (log: log, nestedKey: nestedKey);
}

Future<void> _openActions(WidgetTester tester) async {
  await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular));
  await tester.pumpAndSettle();
  expect(find.text('更多选项'), findsOneWidget);
}

Future<void> _tapInSheet(WidgetTester tester, String label) async {
  final tile = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.text(label),
  );
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  for (final (label, stub) in [('规则库管理', '资产页桩'), ('日志', '日志页桩')]) {
    testWidgets('更多选项 -> $label：先收起操作面板，再压入目标页；返回后配置选项页仍在最上', (tester) async {
      final env = await _pump(tester);
      await _openActions(tester);
      env.log.clear();

      await _tapInSheet(tester, label);

      // 顺序：面板（根 Navigator 上的底部弹层）先被 pop，之后才 push 目标页。
      expect(env.log, hasLength(2), reason: env.log.toString());
      expect(env.log[0], startsWith('root pop ModalBottomSheetRoute'));
      expect(env.log[1], 'root push MaterialPageRoute<void>');
      expect(find.text(stub), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // 面板的 context 属于根 Navigator，「最近的 Navigator」就是根；嵌套的没被动过。
      expect(env.log.where((e) => e.startsWith('nested')), isEmpty);

      // 返回：只 pop 目标页，栈顶还是配置选项页，面板不会回来。
      await tester.tap(find.text(stub));
      await tester.pumpAndSettle();
      expect(env.log.last, 'root pop MaterialPageRoute<void>');
      expect(find.text(stub), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ConfigOptionsPage), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(ConfigOptionsPage)))!
            .isCurrent,
        isTrue,
      );
    });
  }
}
