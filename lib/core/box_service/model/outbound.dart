/// 从核心推送的 outbound 分组里解析出"首页应展示的当前生效节点"。
///
/// 首页此前直接取 `groups.first` 的 `selected`——但核心推送的分组里第一条
/// 可能是 `GLOBAL`、或某个 `selected` 指向嵌套分组（而非叶子节点）的选择器，
/// 于是 `items.where(tag==selected)` 落空、首页只能回退成"未知"。线路页因为
/// 有整套 `_isUserVisibleGroup` 过滤 + 主组优先逻辑所以显示正常，首页缺这套。
///
/// 规则（与线路页口径对齐）：
///   1. 跳过 `GLOBAL` / `DIRECT` / `REJECT` 这类非用户线路的伪分组；
///   2. 优先主选择器 `proxy`（有节点时）；否则第一个"selected 能在自己 items
///      里解析到"的可见分组；再否则第一个非空可见分组；
///   3. 顺着 `selected` 一路下钻嵌套 selector，直到解到叶子代理节点为止
///      （带深度上限防成环）。
///
/// 解不出返回 `null`（首页据此回退到"未知"文案）。
OutboundProxy? resolveActiveProxy(List<OutboundGroup> groups) =>
    resolveActiveRoute(groups)?.item;

/// 当前生效路径（[resolveActiveRoute] 的结果）。
class ActiveRoute {
  const ActiveRoute(this.item, {required this.viaAuto, required this.isLeaf});

  /// 与 [resolveActiveProxy] 相同的那一项（选择、出口探测都按它）。
  final OutboundProxy item;

  /// 下钻途中经过了自动选择组（主选择组默认选中的就是它）。
  final bool viaAuto;

  /// [item] 是顺着 `selected` 真正解到的叶子节点；为 false 时它只是一个解不
  /// 下去的分组条目（内核没推这个分组的数据），或 `selected` 落空时的兜底首项。
  final bool isLeaf;

  /// 自动选择组当前选中的节点：只在经过自动选择组且真正解到叶子时才有。
  OutboundProxy? get autoNode => viaAuto && isLeaf ? item : null;
}

/// 解析当前生效路径：规则见 [resolveActiveProxy]，另外记下是否经过自动选择组
/// （urltest，或 tag 为 auto——与线路页识别自动选择卡同一口径）。
///
/// 真机验收 BUG-C：内核不一定推送自动选择组本身的数据（单节点订阅、节点从未
/// 测通时只推主选择组），主选择组选中 `auto` 时下钻不下去，首页只能把原始 tag
/// 「auto」当节点名显示。调用方据 [ActiveRoute.viaAuto] 显示本地化的「自动选择」。
ActiveRoute? resolveActiveRoute(List<OutboundGroup> groups) {
  bool visible(OutboundGroup g) {
    final t = g.tag.toUpperCase();
    return t != 'GLOBAL' && t != 'DIRECT' && t != 'REJECT';
  }

  final visibleGroups = groups.where(visible).toList();
  if (visibleGroups.isEmpty) return null;

  final byTag = <String, OutboundGroup>{for (final g in groups) g.tag: g};

  OutboundGroup? primary;
  for (final g in visibleGroups) {
    if (g.tag == 'proxy' && g.items.isNotEmpty) {
      primary = g;
      break;
    }
  }
  primary ??= visibleGroups
      .where((g) => g.items.any((i) => i.tag == g.selected))
      .firstOrNull;
  primary ??= visibleGroups.where((g) => g.items.isNotEmpty).firstOrNull;
  if (primary == null) return null;

  ActiveRoute? fallback(OutboundGroup group, bool viaAuto) {
    final first = group.items.firstOrNull;
    if (first == null) return null;
    return ActiveRoute(
      first,
      viaAuto: viaAuto || _isAutoGroupItem(first),
      isLeaf: false,
    );
  }

  var viaAuto = false;
  var group = primary;
  for (var depth = 0; depth < 8; depth++) {
    final sel = group.selected;
    OutboundProxy? item;
    for (final i in group.items) {
      if (i.tag == sel) {
        item = i;
        break;
      }
    }
    // selected 不在自己 items 里：至少回退到第一个 item，好过显示"未知"。
    if (item == null) return fallback(group, viaAuto);
    if (_isAutoGroupItem(item)) viaAuto = true;
    // selected 指向的又是一个非空分组 → 继续下钻；否则它就是叶子节点。
    final nested = byTag[item.tag];
    if (nested != null && nested.tag != group.tag && nested.items.isNotEmpty) {
      group = nested;
      continue;
    }
    return ActiveRoute(item, viaAuto: viaAuto, isLeaf: !_isGroupItem(item));
  }
  return fallback(group, viaAuto);
}

String _normalizedType(String type) =>
    type.trim().toLowerCase().replaceAll('-', '').replaceAll('_', '');

bool _isGroupItem(OutboundProxy item) {
  final t = _normalizedType(item.type);
  return t == 'selector' || t == 'select' || t == 'urltest';
}

bool _isAutoGroupItem(OutboundProxy item) =>
    _normalizedType(item.type) == 'urltest' || item.tag.toLowerCase() == 'auto';

/// 出站代理节点
class OutboundProxy {
  const OutboundProxy({
    required this.tag,
    required this.type,
    this.delay = 0,
    this.isSelected = false,
  });

  final String tag;
  final String type;
  final int delay;
  final bool isSelected;

  /// 解析核心库推送的 JSON（kebab-case 字段名）
  factory OutboundProxy.fromJson(Map<String, dynamic> json) {
    return OutboundProxy(
      tag: json['tag'] as String? ?? '',
      type: json['type'] as String? ?? '',
      // sing-box 推送的是 url-test-delay
      delay:
          json['url-test-delay'] as int? ??
          json['urlTestDelay'] as int? ??
          json['delay'] as int? ??
          0,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  OutboundProxy copyWith({
    String? tag,
    String? type,
    int? delay,
    bool? isSelected,
  }) {
    return OutboundProxy(
      tag: tag ?? this.tag,
      type: type ?? this.type,
      delay: delay ?? this.delay,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// 延迟文本显示
  String get delayText {
    if (delay <= 0) return '-';
    return '${delay}ms';
  }

  /// 延迟等级
  DelayLevel get delayLevel {
    if (delay <= 0) return DelayLevel.unknown;
    if (delay < 200) return DelayLevel.fast;
    if (delay < 500) return DelayLevel.medium;
    return DelayLevel.slow;
  }
}

enum DelayLevel { unknown, fast, medium, slow }

/// 出站代理组
class OutboundGroup {
  const OutboundGroup({
    required this.tag,
    required this.type,
    required this.selected,
    required this.items,
  });

  final String tag;
  final String type;
  final String selected;
  final List<OutboundProxy> items;

  /// 解析核心库推送的 JSON（kebab-case 字段名）
  factory OutboundGroup.fromJson(Map<String, dynamic> json) {
    return OutboundGroup(
      tag: json['tag'] as String? ?? '',
      type: json['type'] as String? ?? '',
      selected: json['selected'] as String? ?? '',
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => OutboundProxy.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
