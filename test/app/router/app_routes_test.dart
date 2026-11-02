import 'package:clashmiao/app/router/app_routes.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每个 AppRoute 都在 appRouteBuilders 里注册', () {
    expect(appRouteBuilders.keys.toSet(), AppRoute.values.toSet());
  });
}
