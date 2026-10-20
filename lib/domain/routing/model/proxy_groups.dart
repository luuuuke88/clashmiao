import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:collection/collection.dart';

/// 代理页与自动测速共用的「分组」口径：哪些组用户看得到、哪个是主组、
/// 哪些组可以测速。放在一处，免得页面和后台测速各算各的、对不上号。

const kUrlTestGroupType = 'urltest';

String normalizeGroupType(String type) {
  final trimmed = type.trim().toLowerCase();
  return trimmed.replaceAll('-', '').replaceAll('_', '');
}

/// 判断一个 outbound 的 type 是否为「分组类型」（selector/urltest），而不是
/// shadowsocks/vmess 这类叶子代理节点。
bool isGroupProxyType(String type) {
  final normalized = normalizeGroupType(type);
  return normalized == 'selector' ||
      normalized == 'select' ||
      normalized == kUrlTestGroupType;
}

/// 分组里用户看得到、可以选的条目：去掉带隐藏标记的节点和订阅信息条目
/// （规则见 subscription_info_node.dart，与运行时配置构建器同一口径）。顺序不变。
///
/// 实时分组里信息条目已经被内核排除，这里主要管离线分组——它解析自订阅配置，
/// 信息条目还在。嵌套分组照常保留，只按叶子节点判断信息条目。
List<OutboundProxy> selectableGroupItems(List<OutboundProxy> items) {
  final info = subscriptionInfoTagsToExclude([
    for (final item in items)
      if (!isGroupProxyType(item.type)) item.tag,
  ]);
  return [
    for (final item in items)
      if (!hasHideMarker(item.tag) && !info.contains(item.tag)) item,
  ];
}

/// 过滤掉内部保留字分组。
bool isUserVisibleGroup(OutboundGroup group) {
  final tag = group.tag.toUpperCase();
  return tag != 'GLOBAL' && tag != 'DIRECT' && tag != 'REJECT';
}

/// 把订阅原始 selector 与修复出的 `proxy` selector 这类等价分组折叠成一个
/// 可操作的主分组。
List<OutboundGroup> collapseDuplicateGroups(List<OutboundGroup> groups) {
  final proxy = groups.firstWhereOrNull(
    (group) => group.tag == 'proxy' && group.items.isNotEmpty,
  );
  if (proxy == null) return groups;

  final proxyItems = _itemTagSet(proxy);
  if (proxyItems.isEmpty) return groups;

  return groups.where((group) {
    if (identical(group, proxy) || group.tag == proxy.tag) return true;
    if (!isGroupProxyType(group.type)) return true;
    return !_sameItemTags(proxyItems, _itemTagSet(group));
  }).toList();
}

/// 用户在代理页看到的第一个分组（主组）；没有则 `null`。
OutboundGroup? primaryVisibleGroup(List<OutboundGroup> groups) {
  return collapseDuplicateGroups(
    groups.where(isUserVisibleGroup).toList(),
  ).firstOrNull;
}

/// 这个分组能不能发起延迟测试。
bool canDelayTestGroup(OutboundGroup group) {
  if (group.items.isEmpty) return false;
  return isGroupProxyType(group.type);
}

Set<String> _itemTagSet(OutboundGroup group) {
  return group.items
      .map((item) => item.tag)
      .where((tag) => tag.isNotEmpty)
      .toSet();
}

bool _sameItemTags(Set<String> left, Set<String> right) {
  if (left.length != right.length) return false;
  return left.containsAll(right);
}

/// 把存储里的手选叠加到（离线展示用的）分组上：某组有记录、且记录的节点在该
/// 组里，就以它为选中项。
///
/// 只用于展示——离线分组解析自配置文件，选中项是静态默认值；下次连接时重放的
/// 是存储里的手选，界面应当显示它。实时分组不需要：内核报的就是真实选中项。
List<OutboundGroup> applyStoredSelections(
  List<OutboundGroup> groups,
  Map<String, String> stored,
) {
  if (stored.isEmpty) return groups;
  return [
    for (final group in groups)
      switch (stored[group.tag]) {
        final tag?
            when tag != group.selected &&
                group.items.any((item) => item.tag == tag) =>
          OutboundGroup(
            tag: group.tag,
            type: group.type,
            selected: tag,
            items: group.items,
          ),
        _ => group,
      },
  ];
}

/// 手选存储与运行时分组对不上时的迁移计划，见 [planSelectionMigration]。
class SelectionMigration {
  const SelectionMigration({
    this.adopt = const {},
    this.superseded = const {},
    this.orphaned = const {},
  });

  static const none = SelectionMigration();

  /// 来源记录（运行时不存在的组）→ 迁往的运行时组与节点。先写目标、确认落盘
  /// 后才删来源。
  final Map<String, ({String target, String node})> adopt;

  /// 来源记录 → 它的目标组。目标组已经（或将要由 [adopt]）有记录：目标确认
  /// 落盘后删掉来源。
  final Map<String, String> superseded;

  /// 迁不过去（节点不在运行时主组里 / 运行时没有可迁的选择器）的来源：保留，
  /// 不删、不重放——留给之后的订阅刷新或下一次启动。
  final Set<String> orphaned;

  bool get isEmpty => adopt.isEmpty && superseded.isEmpty && orphaned.isEmpty;
}

/// 手选存储里有、运行中内核却没有的分组记录怎么迁移。
///
/// 运行时配置由内核重建分组（订阅自带的 selector 被丢掉），旧版本却按配置文件
/// 里的分组 tag（例如 `proxy`）记下了手选——这些记录对运行时毫无意义，重放
/// 它们只会换来「selector not found」。[runtimeTags] 是运行时真实存在的分组
/// tag，[primary] 是运行时主组（用户在主列表里点的就是它）：
/// - 主组是选择器、存储里还没有它的记录、且来源记录的节点在主组里 → `adopt`
///   （每个目标只采纳一个来源）；
/// - 主组已有记录（或已被采纳） → `superseded`；
/// - 其余 → `orphaned`（保留）。
SelectionMigration planSelectionMigration(
  Map<String, String> stored,
  Set<String> runtimeTags,
  OutboundGroup? primary,
) {
  if (runtimeTags.isEmpty) return SelectionMigration.none;
  final stale = stored.keys.where((k) => !runtimeTags.contains(k)).toList()
    ..sort();
  if (stale.isEmpty) return SelectionMigration.none;

  final primaryIsSelector =
      primary != null &&
      runtimeTags.contains(primary.tag) &&
      normalizeGroupType(primary.type) == 'selector';
  final adopt = <String, ({String target, String node})>{};
  final superseded = <String, String>{};
  final orphaned = <String>{};
  for (final source in stale) {
    if (!primaryIsSelector) {
      orphaned.add(source);
      continue;
    }
    final target = primary.tag;
    final node = stored[source]!;
    if (stored.containsKey(target) ||
        adopt.values.any((a) => a.target == target)) {
      superseded[source] = target;
    } else if (primary.items.any((item) => item.tag == node)) {
      adopt[source] = (target: target, node: node);
    } else {
      orphaned.add(source);
    }
  }
  return SelectionMigration(
    adopt: adopt,
    superseded: superseded,
    orphaned: orphaned,
  );
}
