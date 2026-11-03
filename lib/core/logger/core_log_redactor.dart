// 内核（sing-box）日志导出前的脱敏。
//
// 内核日志的前缀里带着出站 / 分组的标签：`outbound/vless[<tag>]: …`、
// `=> outbound/vless[<tag>]`、`selector[<tag>]`。标签是订阅里用户 / 机场起的节点
// 名，常常就是裸域名（`node.example.com`，没有端口），通用脱敏器认不出来。所以导出
// 时先把这些标签整个换成 `…`，再过 [redactLogText]。
//
// inbound 标签是应用内部的固定名字，保留。
//
// 标签之外，内核日志的正文里还有大量域名：`dns: exchange node.example.com: …`、
// selector / urltest 消息里域名形的节点名、连接的目标域名（属于浏览记录）。通用
// 脱敏器认不出无端口、无 scheme 的裸域名，所以导出时在其后再扫一遍：**所有非白名单
// 的多标签主机名**（含 Unicode IDN、punycode，带不带端口）换成 `<host>`；白名单主机
// （[isPublicHost]）与回环保留。宁可过度遮盖（`config.json` 之类也会被当成主机名），
// 也不放过域名。已有的占位符（`<url>`、`<addr>`、`…`）与 `outbound/<类型>` 类型名
// 不含「字母.字母」形态，不受影响。
//
// 只用于内核日志导出；app.log 不走这一步（它的来源侧已不写节点名，且 Dart 堆栈
// 帧 `package:clashmiao/…/x.dart` 不能被当成主机名）。

import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:clashmiao/core/logger/public_hosts.dart';

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

/// 多标签主机名（可带端口）：标签可以含任意语言的字母（Unicode IDN），TLD 是字母
/// 或 punycode。前面不能紧贴标签字符或点（避免从长名字中间截取），后面不能紧跟
/// 字母、数字、下划线、连字符。`1.14.3` 这类版本号与时间戳的 TLD 不是字母，不匹配。
final RegExp _bareHost = RegExp(
  r'(?<![\p{L}\p{M}\p{N}_.\-])'
  r'((?:[\p{L}\p{N}](?:[\p{L}\p{M}\p{N}\-]*[\p{L}\p{M}\p{N}])?\.)+'
  r'(?:\p{L}[\p{L}\p{M}]{1,23}|xn--[A-Za-z0-9\-]{1,59}))'
  r'(?::\d{1,5})?(?![\p{L}\p{M}\p{N}_\-])',
  unicode: true,
);

/// 非白名单主机名的占位符。
const String kRedactedHost = '<host>';

/// 一行（或多行）内核日志：出站 / 分组标签换成 `…`，再过通用脱敏器，最后把所有
/// 非白名单的裸主机名换成 [kRedactedHost]。
String redactCoreLogText(String text) {
  final masked = text
      .replaceAllMapped(_taggedPrefix, (m) => '${m[1]}[$kRedacted]')
      .replaceAllMapped(_groupTagged, (m) => '${m[1]}[$kRedacted]');
  return redactLogText(masked).replaceAllMapped(
    _bareHost,
    (m) => isPublicHost(m[1]!) ? m[0]! : kRedactedHost,
  );
}
