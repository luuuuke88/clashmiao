// 日志脱敏：所有**落盘 / 导出 / 上报**的日志文本都先过这里。
//
// 应用日志（app.log）与导出的核心日志会被用户分享出去排障，而异常文本里常带着
// 订阅地址：订阅链接本身就是凭据（路径或查询里的 token），代理分享链接更是把
// 服务器、端口、密码 / UUID 全写在一起。这里只抹掉这些，**保留**排障需要的
// 东西：异常类名、错误码、主机名与端口、堆栈帧（`file://` / `package:` 路径不动）。
//
// 规则（按顺序执行，结果幂等，可以重复过滤）：
// 1. 代理分享链接（vmess:// vless:// ss:// trojan:// hysteria2:// tuic:// …）整条
//    折叠为 `<scheme>://…`。
// 2. 头部写法的 `Authorization` / `Proxy-Authorization` / `Cookie` / `Set-Cookie`
//    （`Name: value`，值不带引号）：冒号后到行尾整体替换。
// 3. 其它 URL：去掉 userinfo；查询串换成 `?…`、片段换成 `#…`；路径段先做宽松的
//    百分号解码再判断像不像 token（长十六进制、UUID、长 base64、16 位以上字母
//    数字混排、JWT），像就把**整个原始段**换成 `…`，不像就原样保留（包括原来的
//    编码）。scheme、主机、端口保留。`file://` 不处理（堆栈帧）。
// 4. 键值形式的秘密：字段名可带引号（含转义引号），分隔符 `=` 或 `:`；值分
//    引号值（正确跳过转义引号，可含空白与分隔符）、`[...]` 列表与裸值三种解析。
//    - 强字段（password / token / secret / api_key / uuid / authorization /
//      cookie …，含 `obfs-password`、`access_token` 这类复合名）：任何写法都遮盖。
//    - 弱字段（key / auth / sid / sig / signature / pwd …）：只在结构化写法里
//      遮盖——`key=`、带引号的字段名 `"key":`——或者值本身像凭据；
//      `Invalid key: profiles` 这类自然语言诊断原样保留。
// 5. 游离的 `Bearer <token>`：token 像凭据时遮盖。

import 'dart:convert';

/// 脱敏后的占位符。
const String kRedacted = '…';

/// 脱敏规则的版本号。规则收紧时递增：应用日志启动时据此把旧文件重新过一遍
/// （见 `AppLogger.redactExistingLogFiles`）。
const int kLogRedactionVersion = 2;

/// 会被整条折叠的代理分享链接 scheme。
const Set<String> kProxyShareSchemes = {
  'vmess',
  'vless',
  'ss',
  'ssr',
  'trojan',
  'hysteria',
  'hysteria2',
  'hy2',
  'tuic',
  'wireguard',
  'wg',
  'socks',
  'socks4',
  'socks5',
  'naive+https',
  'naive+quic',
  'anytls',
  'shadowtls',
  'juicity',
};

final RegExp _shareLink = RegExp(
  '\\b(${kProxyShareSchemes.map(RegExp.escape).join('|')})://[^\\s"\'<>]+',
  caseSensitive: false,
);

/// 头部写法：`Authorization: Basic x`、`"Cookie": a=b; c=d`。值以引号、`[`、`{`
/// 开头的交给键值解析（JSON 写法），这里只管裸值，到行尾为止。
final RegExp _headerLine = RegExp(
  r'''(?<![A-Za-z0-9_\-])(\\*["']?)((?:proxy-)?authorization|set-cookie|cookie)\1[ \t]*:[ \t]*(?![\\"'\[{])([^\r\n]*)''',
  caseSensitive: false,
);

final RegExp _url = RegExp(
  r'\b([a-zA-Z][a-zA-Z0-9+.\-]*)://([^\s/?#"'
  "'"
  r'<>]*)([^\s?#"'
  "'"
  r'<>]*)'
  r'(\?[^\s#"'
  "'"
  r'<>]*)?(#[^\s"'
  "'"
  r'<>]*)?',
);

/// 秘密字段名的末段（复合名如 `access_token`、`obfs-password`、`x-api-key`
/// 由前缀 + 末段组成）。
const _secretWords =
    'password|passwd|passphrase|pwd|token|secret|apikey|privatekey|key|uuid|'
    'auth|authorization|cookie|sid|sig|signature|psk';

/// 秘密字段名（不含引号）：可选的 `xxx-` / `xxx_` 前缀 + 末段。
const _secretName = '(?:[A-Za-z0-9]+[-_])*(?:$_secretWords)';

/// 键值里的字段名 + 分隔符。第 1 组是字段名两侧的引号（可带转义反斜杠，
/// 没有引号时为空），第 2 组字段名，第 3 组分隔符。
final RegExp _kvField = RegExp(
  '(?<![A-Za-z0-9_\\-])(\\\\*["\']?)($_secretName)\\1[ \\t]*([=:])[ \\t]*',
  caseSensitive: false,
);

final RegExp _secretNameExact = RegExp('^$_secretName\$', caseSensitive: false);

/// 归一化（去掉 `-` `_`、小写）后以这些结尾的字段名是**强**秘密字段：
/// 任何写法下都遮盖。其余能匹配 [_secretName] 的是弱字段。
const _strongSuffixes = [
  'password',
  'passwd',
  'passphrase',
  'token',
  'secret',
  'apikey',
  'privatekey',
  'presharedkey',
  'secretkey',
  'accesskey',
  'authkey',
  'authorization',
  'cookie',
  'uuid',
  'psk',
];

final RegExp _bearer = RegExp(
  r'\bBearer[ \t]+([A-Za-z0-9\-._~+/]+=*)',
  caseSensitive: false,
);

/// URL 末尾不属于 URL 的标点（句末、括号、逗号），脱敏时原样留在外面。
final RegExp _trailingPunct = RegExp(r'[.,;:!)\]}]+$');

final RegExp _hex = RegExp(r'^[0-9a-fA-F]{16,}$');
final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _tokenChars = RegExp(r'^[A-Za-z0-9_\-+=~]+$');
final RegExp _base64 = RegExp(r'^[A-Za-z0-9+/_\-]{24,}={0,2}$');
final RegExp _jwt = RegExp(r'^eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-.]*$');
final RegExp _letter = RegExp('[A-Za-z]');
final RegExp _digit = RegExp('[0-9]');
final RegExp _upper = RegExp('[A-Z]');
final RegExp _lower = RegExp('[a-z]');
final RegExp _base64Punct = RegExp(r'[+/_=\-]');
final RegExp _nameSeparators = RegExp('[-_]');

/// 把 [input] 里的订阅地址凭据、键值秘密与代理分享链接抹掉，其余原样返回。
String redactLogText(String input) {
  if (input.isEmpty) return input;
  var out = input.replaceAllMapped(_shareLink, (m) => '${m[1]}://$kRedacted');
  out = out.replaceAllMapped(_headerLine, (m) {
    final value = m[3]!;
    if (value.isEmpty || value == kRedacted) return m[0]!;
    return '${m[0]!.substring(0, m[0]!.length - value.length)}$kRedacted';
  });
  out = out.replaceAllMapped(_url, _redactUrlMatch);
  out = _redactKeyValues(out);
  out = out.replaceAllMapped(_bearer, (m) {
    final token = m[1]!;
    if (!_looksLikeToken(token)) return m[0]!;
    return '${m[0]!.substring(0, m[0]!.length - token.length)}$kRedacted';
  });
  return out;
}

/// 结构化数据（Map 键名、请求头名）里，[name] 是否是秘密字段名。
/// 与文本里键值规则用同一份字段名表；结构化场景下强弱字段都算。
bool isSecretFieldName(String name) => _secretNameExact.hasMatch(name);

bool _isStrongSecretName(String name) {
  final normalized = name.toLowerCase().replaceAll(_nameSeparators, '');
  return _strongSuffixes.any(normalized.endsWith);
}

// ─── 键值 ─────────────────────────────────────────────────────────────

String _redactKeyValues(String text) {
  StringBuffer? out;
  var copied = 0; // text[0, copied) 已写进 out
  var resume = 0; // 已遮盖区域的末尾；落在里面的匹配跳过
  for (final m in _kvField.allMatches(text)) {
    if (m.start < resume) continue;
    final value = _readValue(text, m.end);
    if (value == null) continue;
    final content = text.substring(value.contentStart, value.contentEnd);
    if (content.isEmpty || content == kRedacted) continue;
    final name = m[2]!;
    final structured = m[1]!.isNotEmpty || m[3] == '=';
    final mask =
        _isStrongSecretName(name) || structured || _looksLikeToken(content);
    if (!mask) continue;
    (out ??= StringBuffer())
      ..write(text.substring(copied, value.contentStart))
      ..write(kRedacted);
    copied = value.contentEnd;
    resume = value.end;
  }
  if (out == null) return text;
  out.write(text.substring(copied));
  return out.toString();
}

/// 分隔符之后的一个值：[contentStart, contentEnd) 是要遮盖的内容（不含引号 /
/// 方括号），[end] 是整个值（含收尾引号）之后的位置。
typedef _Value = ({int contentStart, int contentEnd, int end});

const _bareTerminators = ' \t\r\n&,;}])"\'<>';

_Value? _readValue(String text, int start) {
  if (start >= text.length) return null;

  // 引号值：开头可以有转义反斜杠（嵌在另一个字符串里的 JSON：`\"x\"`）。
  var quoteAt = start;
  while (quoteAt < text.length && text.codeUnitAt(quoteAt) == 0x5C) {
    quoteAt++;
  }
  if (quoteAt < text.length) {
    final q = text[quoteAt];
    if (q == '"' || q == "'") {
      return _readQuoted(text, quoteAt + 1, q, quoteAt - start);
    }
  }

  final first = text[start];
  if (first == '{') return null; // 嵌套对象：里面的字段各自匹配
  if (first == '[') {
    final close = _lineIndexOf(text, ']', start + 1);
    if (close < 0) {
      final eol = _endOfLine(text, start + 1);
      return (contentStart: start + 1, contentEnd: eol, end: eol);
    }
    return (contentStart: start + 1, contentEnd: close, end: close + 1);
  }

  var i = start;
  while (i < text.length && !_bareTerminators.contains(text[i])) {
    i++;
  }
  if (i == start) return null;
  return (contentStart: start, contentEnd: i, end: i);
}

/// 从 [contentStart] 起找与开头配对的收尾引号 [q]。[depth] 是开头引号前的
/// 反斜杠个数：0 是普通字符串（前面有偶数个反斜杠的引号才收尾），1 是嵌在
/// 字符串里转义过一次的 JSON（`\"` 收尾、`\\\"` 是内容里的引号），依此类推。
/// 同一行里找不到收尾就遮到行尾。
_Value _readQuoted(String text, int contentStart, String q, int depth) {
  final period = depth + 1;
  final isPowerOfTwo = (period & (period - 1)) == 0;
  for (var k = contentStart; k < text.length; k++) {
    final c = text[k];
    if (c == '\n' || c == '\r') {
      return (contentStart: contentStart, contentEnd: k, end: k);
    }
    if (c != q) continue;
    var run = 0;
    while (k - run - 1 >= contentStart &&
        text.codeUnitAt(k - run - 1) == 0x5C) {
      run++;
    }
    final closes = isPowerOfTwo ? run % (2 * period) == depth : run == depth;
    if (closes) {
      return (contentStart: contentStart, contentEnd: k - depth, end: k + 1);
    }
  }
  return (
    contentStart: contentStart,
    contentEnd: text.length,
    end: text.length,
  );
}

int _endOfLine(String text, int from) {
  for (var k = from; k < text.length; k++) {
    final c = text[k];
    if (c == '\n' || c == '\r') return k;
  }
  return text.length;
}

int _lineIndexOf(String text, String char, int from) {
  for (var k = from; k < text.length; k++) {
    final c = text[k];
    if (c == char) return k;
    if (c == '\n' || c == '\r') return -1;
  }
  return -1;
}

// ─── URL ──────────────────────────────────────────────────────────────

String _redactUrlMatch(Match m) {
  final whole = m[0]!;
  final scheme = m[1]!;
  final lower = scheme.toLowerCase();
  if (lower == 'file') return whole; // 堆栈帧与本地路径
  if (kProxyShareSchemes.contains(lower)) return whole; // 第 1 步已处理

  // 把末尾的句读还给原文：`…uri = https://x/sub?token=S, next` 里的逗号。
  var tail = '';
  var authority = m[2]!;
  var path = m[3]!;
  var query = m[4];
  var fragment = m[5];
  String lastPart() =>
      fragment ?? query ?? (path.isNotEmpty ? path : authority);
  final trailing = _trailingPunct.firstMatch(lastPart());
  if (trailing != null) {
    tail = trailing[0]!;
    final cut = lastPart().length - tail.length;
    if (fragment != null) {
      fragment = fragment.substring(0, cut);
    } else if (query != null) {
      query = query.substring(0, cut);
    } else if (path.isNotEmpty) {
      path = path.substring(0, cut);
    } else {
      authority = authority.substring(0, cut);
    }
  }

  final at = authority.lastIndexOf('@');
  if (at >= 0) authority = authority.substring(at + 1);

  final maskedPath = path
      .split('/')
      .map((segment) => _isSensitiveSegment(segment) ? kRedacted : segment)
      .join('/');

  final buffer = StringBuffer()
    ..write(scheme)
    ..write('://')
    ..write(authority)
    ..write(maskedPath);
  if (query != null) buffer.write(query.length > 1 ? '?$kRedacted' : query);
  if (fragment != null) {
    buffer.write(fragment.length > 1 ? '#$kRedacted' : fragment);
  }
  buffer.write(tail);
  return buffer.toString();
}

/// 路径段：先宽松解码（最多三层，应对重复编码）再判断；任何一层像 token 都算。
bool _isSensitiveSegment(String segment) {
  if (segment.isEmpty || segment == kRedacted) return false;
  var current = segment;
  for (var round = 0; round < 3; round++) {
    if (_looksLikeToken(current)) return true;
    if (!current.contains('%')) return false;
    final decoded = _percentDecodeLenient(current);
    if (decoded == current) return false;
    current = decoded;
  }
  return _looksLikeToken(current);
}

/// 百分号解码，容忍畸形转义：`%` 后面不是两位十六进制就原样保留；解出的字节
/// 不是合法 UTF-8 时用替换字符，不会抛异常。
String _percentDecodeLenient(String s) {
  final bytes = <int>[];
  var literalStart = 0;
  void flushLiteral(int end) {
    if (end > literalStart) {
      bytes.addAll(utf8.encode(s.substring(literalStart, end)));
    }
  }

  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) != 0x25 || i + 2 >= s.length) continue;
    final hi = _hexValue(s.codeUnitAt(i + 1));
    final lo = _hexValue(s.codeUnitAt(i + 2));
    if (hi < 0 || lo < 0) continue; // 畸形转义：当普通字符
    flushLiteral(i);
    bytes.add(hi * 16 + lo);
    i += 2;
    literalStart = i + 1;
  }
  flushLiteral(s.length);
  return utf8.decode(bytes, allowMalformed: true);
}

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

bool _looksLikeToken(String value) {
  if (value.isEmpty || value == kRedacted) return false;
  if (_uuid.hasMatch(value)) return true;
  if (_hex.hasMatch(value)) return true;
  if (_jwt.hasMatch(value)) return true;
  if (_base64.hasMatch(value) &&
      _upper.hasMatch(value) &&
      _lower.hasMatch(value) &&
      (_digit.hasMatch(value) || value.contains(_base64Punct))) {
    return true;
  }
  return value.length >= 16 &&
      _tokenChars.hasMatch(value) &&
      _letter.hasMatch(value) &&
      _digit.hasMatch(value);
}
