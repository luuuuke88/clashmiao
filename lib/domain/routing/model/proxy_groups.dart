import 'package:clashmiao/core/box_service/model/outbound.dart';
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

/// 存储里的手选与运行时分组对不上时的处理计划，见 [planSelectionMigration]。
typedef SelectionMigration = ({Map<String, String> adopt, Set<String> drop});

/// 手选存储里有、运行中内核却没有的分组记录怎么处理。
///
/// 运行时配置由内核重建分组（订阅自带的 selector 被丢掉），旧版本却按配置文件
/// 里的分组 tag（例如 `proxy`）记下了手选——这些记录每次重放都只会换来
/// 「selector not found」，用户在界面上看到的选择从未真正生效。处理方式：
/// - `drop`：所有不在 [live] 里的记录（运行时没有这个组，留着只会继续失败）；
/// - `adopt`：若运行时主组是选择器、存储里还没有它的记录、且旧记录的节点就在
///   主组里，把这个节点迁到主组上（它就是用户当初在主列表里点的那个节点）。
///
/// [live] 为空（还没拿到实时分组）时什么都不做——没有运行时的事实就不判断。
SelectionMigration planSelectionMigration(
  Map<String, String> stored,
  List<OutboundGroup> live,
) {
  final liveTags = {
    for (final g in live)
      if (g.items.isNotEmpty) g.tag,
  };
  if (liveTags.isEmpty) return (adopt: const {}, drop: const {});
  final stale = stored.keys.where((k) => !liveTags.contains(k)).toSet();
  if (stale.isEmpty) return (adopt: const {}, drop: const {});

  final primary = primaryVisibleGroup(live);
  final adopt = <String, String>{};
  final primaryIsSelector =
      primary != null && normalizeGroupType(primary.type) == 'selector';
  if (primaryIsSelector && !stored.containsKey(primary.tag)) {
    for (final key in stale) {
      final node = stored[key]!;
      if (primary.items.any((item) => item.tag == node)) {
        adopt[primary.tag] = node;
        break;
      }
    }
  }
  return (adopt: adopt, drop: stale);
}
