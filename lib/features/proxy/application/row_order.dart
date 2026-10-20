/// 线路列表的行顺序：测速进行中、或手指按在列表上时**冻结**，不随延迟重排。
///
/// 为什么要冻结：按延迟排序时，测速结果一条条回来，列表每次都重排。手指按下时
/// 指着的是 A，抬起前列表一重排，同一个位置换成了 B——真机实测按下香港01、
/// 最终选中的是德国。冻结之后，重排只在测速结束且没有手指按着时发生一次。
///
/// [sorted] 是这一刻按当前排序规则排好的条目，[shown] 是上一次实际展示的 key
/// 顺序（第一次展示时为 null）。[frozen] 为真时：
/// - 上次展示过、现在仍在的条目保持上次的相对顺序；
/// - 新出现的条目按 [sorted] 的顺序接在后面；
/// - 已经不在的条目去掉。
///
/// 不冻结时直接返回 [sorted]。纯函数，不改动入参。
List<T> stableRowOrder<T>({
  required List<T> sorted,
  required String Function(T item) keyOf,
  required List<String>? shown,
  required bool frozen,
}) {
  if (!frozen || shown == null) return sorted;
  final byKey = {for (final item in sorted) keyOf(item): item};
  final kept = <T>[
    for (final key in shown)
      if (byKey.containsKey(key)) byKey[key] as T,
  ];
  final shownKeys = shown.toSet();
  return [
    ...kept,
    for (final item in sorted)
      if (!shownKeys.contains(keyOf(item))) item,
  ];
}
