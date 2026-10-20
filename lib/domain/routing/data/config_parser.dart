import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/config/model/profile_nodes.dart';

/// 从 sing-box 配置文件解析代理分组和节点
class ConfigParser {
  /// 代理组类型
  static const _groupTypes = {'selector', 'urltest', 'url_test'};

  /// 解析配置文件获取代理分组
  static List<OutboundGroup> parseConfig(String configContent) {
    try {
      final config = jsonDecode(configContent) as Map<String, dynamic>;
      // 完整实体集合（出站 ∪ 端点）：分组遍历与成员类型索引都要认端点——
      // `select` 里的 WireGuard 端点成员是 `wireguard`，`auto` 成员是
      // `urltest`，不能认成 `unknown`。叶子视图会丢掉全部分组，不能用在这里。
      final entities = profileEntities(config);
      final typeByTag = <String, String>{};
      for (final e in entities) {
        typeByTag.putIfAbsent(e.tag, () => e.type);
      }

      final groups = <OutboundGroup>[];

      for (final entity in entities) {
        final outbound = entity.raw;
        final type = entity.type;
        if (!_groupTypes.contains(type)) continue;

        final tag = entity.tag;
        final itemTags =
            (outbound['outbounds'] as List?)?.whereType<String>().toList() ??
            [];

        // 默认选中第1个或 default 字段
        final selected =
            (outbound['default'] as String?) ??
            (itemTags.isNotEmpty ? itemTags.first : '');

        // 为每个子节点查找类型
        final items = <OutboundProxy>[];
        for (final itemTag in itemTags) {
          final itemType = typeByTag[itemTag] ?? 'unknown';

          items.add(
            OutboundProxy(
              tag: itemTag,
              type: itemType,
              delay: 0,
              isSelected: itemTag == selected,
            ),
          );
        }

        groups.add(
          OutboundGroup(tag: tag, type: type, selected: selected, items: items),
        );
      }

      return groups;
    } catch (_) {
      return [];
    }
  }

  /// 从文件路径解析
  static Future<List<OutboundGroup>> parseFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      return parseConfig(content);
    } catch (_) {
      return [];
    }
  }
}
