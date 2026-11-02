import 'package:clashmiao/features/assets/presentation/assets_page.dart';
import 'package:clashmiao/features/config/presentation/config_options_page.dart';
import 'package:clashmiao/features/logs/presentation/logs_page.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';

/// [AppRoute] 到页面的映射。页面只在 `app/` 构造，功能之间经 [AppRouteScope] 跳转。
final Map<AppRoute, AppRouteBuilder> appRouteBuilders = {
  AppRoute.configOptions: (_) => const ConfigOptionsPage(),
  AppRoute.assets: (_) => const AssetsPage(),
  AppRoute.logs: (_) => const LogsPage(),
  // 首页底部弹层里展开的订阅页（嵌入形态），见 buildAppRoute。
  AppRoute.profiles: (_) => const ProfilesPage(embedInSheet: true),
};
