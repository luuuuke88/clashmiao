import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 外层 MaterialApp（根 Navigator）里放一个嵌套 Navigator，
/// 嵌套 Navigator 的首页是一个按钮，点击后跳转到 [route]。
Widget _host({
  required Map<AppRoute, AppRouteBuilder> builders,
  required AppRoute route,
  required bool rootNavigator,
  void Function(Future<Object?> result)? onPushed,
}) {
  return AppRouteScope(
    builders: builders,
    child: MaterialApp(
      home: Scaffold(
        body: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  final result = pushAppRoute<Object>(
                    context,
                    route,
                    rootNavigator: rootNavigator,
                  );
                  onPushed?.call(result);
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('已注册的路由 push 后能找到目标页面', (tester) async {
    await tester.pumpWidget(
      _host(
        builders: {AppRoute.logs: (_) => const Text('日志页')},
        route: AppRoute.logs,
        rootNavigator: false,
      ),
    );
    expect(find.text('日志页'), findsNothing);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('日志页'), findsOneWidget);
  });

  // 探针页：记下自己所在的 Navigator 与根 Navigator。
  ({Widget Function(BuildContext) builder, List<NavigatorState> seen}) probe() {
    final seen = <NavigatorState>[];
    return (
      builder: (context) {
        seen
          ..add(Navigator.of(context))
          ..add(Navigator.of(context, rootNavigator: true));
        return const Text('目标页');
      },
      seen: seen,
    );
  }

  testWidgets('rootNavigator: true 压在根 Navigator 上', (tester) async {
    final p = probe();
    await tester.pumpWidget(
      _host(
        builders: {AppRoute.assets: p.builder},
        route: AppRoute.assets,
        rootNavigator: true,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('目标页'), findsOneWidget);
    expect(p.seen[0], same(p.seen[1]), reason: '页面应属于根 Navigator');
  });

  testWidgets('rootNavigator: false 压在最近的（嵌套）Navigator 上', (tester) async {
    final p = probe();
    await tester.pumpWidget(
      _host(
        builders: {AppRoute.assets: p.builder},
        route: AppRoute.assets,
        rootNavigator: false,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('目标页'), findsOneWidget);
    expect(p.seen[0], isNot(same(p.seen[1])), reason: '页面应属于嵌套 Navigator');
  });

  testWidgets('push 的返回值经页面 pop 带回调用方', (tester) async {
    late Future<Object?> result;
    await tester.pumpWidget(
      _host(
        builders: {
          AppRoute.profiles: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).pop('done'),
            child: const Text('back'),
          ),
        },
        route: AppRoute.profiles,
        rootNavigator: false,
        onPushed: (r) => result = r,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    expect(await result, 'done');
  });

  testWidgets('未注册的路由抛 FlutterError，消息含路由名', (tester) async {
    await tester.pumpWidget(
      _host(
        builders: const {},
        route: AppRoute.configOptions,
        rootNavigator: false,
      ),
    );
    await tester.tap(find.text('go'));
    final error = tester.takeException();

    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('AppRoute.configOptions'));
    expect(error.toString(), contains('未注册'));
  });

  testWidgets('缺少 AppRouteScope 抛 FlutterError', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => pushAppRoute<void>(context, AppRoute.logs),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    final error = tester.takeException();

    expect(error, isA<FlutterError>());
    expect(error.toString(), contains('AppRouteScope 缺失'));
  });

  testWidgets('buildAppRoute 直接返回已注册的页面，未注册同样抛错', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      AppRouteScope(
        builders: {AppRoute.profiles: (_) => const Text('订阅页')},
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect((buildAppRoute(ctx, AppRoute.profiles) as Text).data, '订阅页');
    expect(
      () => buildAppRoute(ctx, AppRoute.logs),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.toString(),
          'message',
          contains('AppRoute.logs'),
        ),
      ),
    );
  });
}
