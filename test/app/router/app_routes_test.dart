import 'package:clashmiao/app/router/app_routes.dart';
import 'package:clashmiao/features/assets/presentation/assets_page.dart';
import 'package:clashmiao/features/options/presentation/config_options_page.dart';
import 'package:clashmiao/features/logs/presentation/logs_page.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每个 AppRoute 都在 appRouteBuilders 里注册', () {
    expect(appRouteBuilders.keys.toSet(), AppRoute.values.toSet());
  });

  testWidgets('每个路由构造出约定的页面', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );

    Widget build(AppRoute route) => appRouteBuilders[route]!(context);

    expect(build(AppRoute.configOptions), isA<ConfigOptionsPage>());
    expect(build(AppRoute.assets), isA<AssetsPage>());
    expect(build(AppRoute.logs), isA<LogsPage>());

    final profiles = build(AppRoute.profiles);
    expect(profiles, isA<ProfilesPage>());
    expect(
      (profiles as ProfilesPage).embedInSheet,
      isTrue,
      reason: '首页是在底部弹层里嵌入订阅页，必须是嵌入形态',
    );
  });
}
