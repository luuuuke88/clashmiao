import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 底部导航当前选中的 tab 索引。
/// 0 = Home, 1 = Proxies, 2 = Settings, 3 = About
final selectedTabProvider = StateProvider<int>(
  (_) => const int.fromEnvironment('CLASHMIAO_INITIAL_TAB'),
);

/// 语义化常量，避免散落数字 magic number。
class AppTab {
  static const home = 0;
  static const proxies = 1;
  static const settings = 2;
  static const about = 3;
}
