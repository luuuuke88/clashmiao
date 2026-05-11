import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/model/outbound.dart';

/// 从 sing-box 配置文件解析代理分组和节点
class ConfigParser {
  /// 代理组类型
  static const _groupTypes = {'selector', 'urltest', 'url_test'};

  /// 解析配置文件获取代理分组
  static List<OutboundGroup> parseConfig(String configContent) {
    try {
      final config = jsonDecode(configContent) as Map<String, dynamic>;
      final outbounds = (config['outbounds'] as List?) ?? [];

      final groups = <OutboundGroup>[];

      for (final outbound in outbounds) {
        if (outbound is! Map<String, dynamic>) continue;

        final type = (outbound['type'] as String?) ?? '';
        if (!_groupTypes.contains(type)) continue;

        final tag = (outbound['tag'] as String?) ?? '';
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
          final itemOutbound = outbounds
              .whereType<Map<String, dynamic>>()
              .where((e) => e['tag'] == itemTag)
              .firstOrNull;

          final itemType = (itemOutbound?['type'] as String?) ?? 'unknown';

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
