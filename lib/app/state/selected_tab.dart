import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 底部导航当前选中的 tab 索引。
/// 0 = Home, 1 = Proxies, 2 = Profiles, 3 = Settings
final selectedTabProvider = StateProvider<int>((_) => 0);

/// 语义化常量，避免散落数字 magic number。
class AppTab {
  static const home = 0;
  static const proxies = 1;
  static const profiles = 2;
  static const settings = 3;
}
