// 内核（sing-box）日志导出前的脱敏。
//
// 内核日志的前缀里带着出站 / 分组的标签：`outbound/vless[<tag>]: …`、
// `=> outbound/vless[<tag>]`、`selector[<tag>]`。标签是订阅里用户 / 机场起的节点
// 名，常常就是裸域名（`node.example.com`，没有端口），通用脱敏器认不出来。所以导出
// 时先把这些标签整个换成 `…`，再过 [redactLogText]。
//
// inbound 标签是应用内部的固定名字，保留。

import 'package:clashmiao/core/logger/log_redactor.dart';

/// `outbound/<type>[<tag>]`、`endpoint/<type>[<tag>]`。标签里可能带 `]`
/// （`[HK] node`），所以先找「后面紧跟 `:` 或行尾」的第一个 `]`；找不到再退回到
/// 最近的 `]`。宁可多遮，不留尾巴。
final RegExp _taggedPrefix = RegExp(
  r'\b((?:outbound|endpoint)/[A-Za-z0-9_.+\-]+)'
  r'\[(?:.*?\](?=:|[ \t]*$)|[^\]\r\n]*\])',
  multiLine: true,
);

/// `selector[<tag>]`、`urltest[<tag>]` 等分组类型的标签写法。
final RegExp _groupTagged = RegExp(
  r'\b(selector|urltest|loadbalance|fallback)'
  r'\[(?:.*?\](?=:|[ \t]*$)|[^\]\r\n]*\])',
  multiLine: true,
);

/// 一行（或多行）内核日志：出站 / 分组标签换成 `…`，再过通用脱敏器。
String redactCoreLogText(String text) {
  final masked = text
      .replaceAllMapped(_taggedPrefix, (m) => '${m[1]}[$kRedacted]')
      .replaceAllMapped(_groupTagged, (m) => '${m[1]}[$kRedacted]');
  return redactLogText(masked);
}
