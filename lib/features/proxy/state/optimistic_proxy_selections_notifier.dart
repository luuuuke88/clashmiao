import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 用户点击代理项后、等待 sing-box 实际切换前的乐观选择缓存。
/// key = 代理组 tag，value = 用户刚选中的 outbound tag。
final optimisticProxySelectionsProvider =
    StateNotifierProvider<
      OptimisticProxySelectionsNotifier,
      Map<String, String>
    >((ref) {
      return OptimisticProxySelectionsNotifier();
    });

class OptimisticProxySelectionsNotifier
    extends StateNotifier<Map<String, String>> {
  OptimisticProxySelectionsNotifier() : super({});

  void update(String group, String proxy) {
    state = {...state, group: proxy};
  }
}
