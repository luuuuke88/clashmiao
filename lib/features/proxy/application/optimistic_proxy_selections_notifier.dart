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

  /// 撤销一次乐观选择：native `selectOutbound` 失败后调用，把 UI 恢复到用户
  /// 点击前的状态，避免永久停留在"想选但实际没切成功"的错误节点上。
  /// [previousProxy] 是点击前该 group 的乐观值快照——非空则恢复为它，
  /// 为 null（点击前该 group 还没有任何乐观选择）则直接移除这条 group 记录，
  /// 让 UI 回退去读取真实的 `group.selected`。
  void revert(String group, String? previousProxy) {
    if (previousProxy != null) {
      state = {...state, group: previousProxy};
    } else {
      state = {...state}..remove(group);
    }
  }
}
