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
