// 内核（sing-box）日志导出前的脱敏。
//
// 内核日志的前缀里带着出站 / 分组的标签：`outbound/vless[<tag>]: …`、
// `=> outbound/vless[<tag>]`、`selector[<tag>]`。标签是订阅里用户 / 机场起的节点
// 名，常常就是裸域名（`node.example.com`，没有端口），通用脱敏器认不出来。所以导出
// 时先把这些标签整个换成 `…`（标签里可以有嵌套的方括号，按配对深度解析），再过
// [redactLogText]。
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

/// 带标签的前缀：`outbound/<type>[`、`endpoint/<type>[`，以及分组类型
/// `selector[` / `urltest[` / `loadbalance[` / `fallback[`。`[` 之后的标签由
/// [_maskBracketTags] 按方括号配对解析。
final RegExp _tagOpen = RegExp(
  r'\b((?:outbound|endpoint)/[A-Za-z0-9_.+\-]+|selector|urltest|loadbalance|fallback)\[',
);

/// [index] 处（`]` 之后）是不是标签结束的位置：文本结尾、`:`、空白、`,`、`)`。
bool _endsTag(String text, int index) {
  if (index >= text.length) return true;
  final c = text[index];
  return c == ':' ||
      c == ',' ||
      c == ')' ||
      c == ' ' ||
      c == '\t' ||
      c == '\n' ||
      c == '\r';
}

/// 把每个 `前缀[标签]` 里的标签换成 `…`。标签按**方括号配对深度**解析（`[[HK] node]`
/// 里的 `[HK]` 计深度），深度回到 0 的 `]` 还要看它**后面紧跟什么**：只有行尾、`:`、
/// 空白、`,`、`)` 才算标签结束；否则它是标签内容里未配对的 `]`（节点名 `a]b`），
/// 深度保持 0 继续往后扫。标签结束之后的正文原样留下。同一行里找不到合格的结束符
/// 时，从 `[` 起到行尾全部换成 `…`（宁可多遮）。
/// 结果幂等：`[…]` 再扫一遍还是 `[…]`，不配对的 `[…` 再扫一遍还是 `[…`。
String _maskBracketTags(String text) {
  final out = StringBuffer();
  var copied = 0;
  for (final m in _tagOpen.allMatches(text)) {
    if (m.start < copied) continue; // 落在已遮盖的标签里
    final open = m.end - 1; // `[` 的位置
    var depth = 0;
    var close = -1;
    var k = open;
    for (; k < text.length; k++) {
      final c = text[k];
      if (c == '\n' || c == '\r') break;
      if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth <= 0) {
          if (_endsTag(text, k + 1)) {
            close = k;
            break;
          }
          depth = 0; // 标签内容里未配对的 `]`：继续扫
        }
      }
    }
    out.write(text.substring(copied, open + 1));
    out.write(kRedacted);
    if (close >= 0) {
      out.write(']');
      copied = close + 1;
    } else {
      copied = k; // 到行尾（不含换行）
    }
  }
  if (copied == 0) return text;
  out.write(text.substring(copied));
  return out.toString();
}

/// 多标签主机名（可带端口）：标签可以含任意语言的字母（Unicode IDN），TLD 是字母
/// 或 punycode。**不设标签长度上限，也不按 DNS 规则（每段 ≤63、总长 ≤253）校验**：
/// 任何长度的都遮盖，比校验更保守——按规则校验的话，超限的名字匹配不上，前面的防
/// 截断条件又阻止从中间匹配，反而会原样导出；超长的也不是合法主机名，宁可遮盖。前面不能紧贴标签字符，也不能是「标签字符 + 点」（避免从长名字中间截取；前导点的 `.example.org` 仍能匹配），后面不能紧跟
/// 字母、数字、下划线、连字符。`1.14.3` 这类版本号与时间戳的 TLD 不是字母，不匹配。
final RegExp _bareHost = RegExp(
  r'(?<![\p{L}\p{M}\p{N}_\-])(?<![\p{L}\p{M}\p{N}_\-]\.)'
  r'((?:[\p{L}\p{N}](?:[\p{L}\p{M}\p{N}\-]*[\p{L}\p{M}\p{N}])?\.)+'
  r'(?:\p{L}[\p{L}\p{M}]+|xn--[A-Za-z0-9\-]+))'
  r'(?::\d{1,5})?(?![\p{L}\p{M}\p{N}_\-])',
  unicode: true,
);

/// 非白名单主机名的占位符。
const String kRedactedHost = '<host>';

/// 一行（或多行）内核日志：出站 / 分组标签换成 `…`，再过通用脱敏器，最后把所有
/// 非白名单的裸主机名换成 [kRedactedHost]。
String redactCoreLogText(String text) {
  return redactLogText(_maskBracketTags(text)).replaceAllMapped(
    _bareHost,
    (m) => isPublicHost(m[1]!) ? m[0]! : kRedactedHost,
  );
}
