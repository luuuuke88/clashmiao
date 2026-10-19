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
// 2. 其它 URL：去掉 userinfo；查询串换成 `?…`、片段换成 `#…`；路径段原样以及
//    最多三轮宽松的百分号解码之后，都按解出的 `/` 拆成子段逐个判断像不像 token
//    （长十六进制、UUID、长 base64、16 位以上字母数字混排、JWT），任何子段像就把
//    **整个原始段**换成 `…`，都不像就原样保留（包括原来的编码）。scheme、主机、端口保留。`file://` 不处理（堆栈帧）。JSON 里转义成
//    `https:\/\/host\/path` 的 URL 先还原 `\/` 再按同样规则处理，处理完再转义回去。
// 3. 键值形式的秘密：字段名（可带引号，含转义引号）+ 分隔符 `=` 或 `:`。识别出
//    秘密字段后**从值开头一直遮到行尾**，不去猜值在哪里结束——打印出来的文本
//    （`Map.toString` 不给字符串加引号、不转义）里值的边界本来就不可靠。
//    - 结构化写法：带引号的字段名（JSON `"key":`，值是任何类型）、`key=`、
//      同一行前面出现过 `{` 或未闭合的 `[`（Map / Set / List 打印）里的 `key:`。
//      强弱字段一律遮盖。
//    - 其余的 `name: value`（自然语言、头部写法 `Authorization: Basic x`）：
//      强字段（password / token / secret / api_key / uuid / authorization /
//      cookie …，含 `obfs-password`、`access_token`、`Set-Cookie` 这类复合名）
//      遮盖；弱字段（key / auth / sid / sig / signature / pwd …）把冒号后整行
//      余下内容按非 token 字符拆成片段，任何一个片段像凭据就遮盖，
//      `Invalid key: profiles` 原样保留。
// 4. 游离的 `Bearer <token>`：token 像凭据时遮盖。

import 'dart:collection';
import 'dart:convert';

/// 脱敏后的占位符。
const String kRedacted = '…';

/// 脱敏规则的版本号。规则收紧时递增：应用日志启动时据此把旧文件重新过一遍
/// （见 `AppLogger.redactExistingLogFiles`）。
const int kLogRedactionVersion = 6;

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

/// JSON 里转义过斜杠的 URL：`https:\/\/example.test\/sub?token=x`。
final RegExp _escapedUrl = RegExp(
  r'''\b[a-zA-Z][a-zA-Z0-9+.\-]*:\\/\\/[^\s"'<>]*''',
);
final RegExp _trailingBackslashes = RegExp(r'\\+$');

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
  out = out.replaceAllMapped(_url, _redactUrlMatch);
  out = out.replaceAllMapped(_escapedUrl, _redactEscapedUrlMatch);
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

/// 结构化数据（Map / List / JSON 值）在转成文本**之前**按键名脱敏：键名是秘密
/// 字段（[isSecretFieldName]）的整项（含整个子树）换成 [kRedacted]，其余字符串
/// 过 [redactLogText]；数字、布尔、null 原样；其它对象转成字符串后再过
/// [redactLogText]。
///
/// 循环引用安全：按对象身份记录当前递归路径上的 Map / List，再次遇到时换成
/// [kCyclePlaceholder]，不会栈溢出（日志、loggy、Sentry 都走这里）。
/// `toString()` 自己抛异常的对象换成 [kUnprintablePlaceholder]。
Object? redactStructuredValue(Object? value) =>
    _redactStructured(value, HashSet<Object>.identity());

/// [redactStructuredValue] 的 `Map<String, dynamic>` 版本，保持类型。
Map<String, dynamic> redactStructuredMap(Map<String, dynamic> map) =>
    _redactStringKeyedMap(map, HashSet<Object>.identity()..add(map));

/// 结构化遍历里循环引用节点的占位。
const String kCyclePlaceholder = '<cycle>';

/// 结构化遍历里 `toString()` 抛异常的对象的占位。
const String kUnprintablePlaceholder = '<unprintable>';

Object? _redactStructured(Object? value, Set<Object> path) {
  switch (value) {
    case null || bool() || num():
      return value;
    case final String s:
      return redactLogText(s);
    case final Map<dynamic, dynamic> m:
      if (!path.add(m)) return kCyclePlaceholder;
      try {
        if (m is Map<String, dynamic>) return _redactStringKeyedMap(m, path);
        return {
          for (final entry in m.entries)
            entry.key: _redactStructuredEntry(entry.key, entry.value, path),
        };
      } finally {
        path.remove(m);
      }
    case final Iterable<dynamic> l:
      if (!path.add(l)) return kCyclePlaceholder;
      try {
        return [for (final v in l) _redactStructured(v, path)];
      } finally {
        path.remove(l);
      }
    default:
      String text;
      try {
        text = value.toString();
      } catch (_) {
        return kUnprintablePlaceholder;
      }
      return redactLogText(text);
  }
}

Map<String, dynamic> _redactStringKeyedMap(
  Map<String, dynamic> map,
  Set<Object> path,
) => {
  for (final entry in map.entries)
    entry.key: _redactStructuredEntry(entry.key, entry.value, path),
};

Object? _redactStructuredEntry(Object? key, Object? value, Set<Object> path) {
  if (value == null) return null;
  if (key is String && isSecretFieldName(key)) return kRedacted;
  return _redactStructured(value, path);
}

// ─── 键值 ─────────────────────────────────────────────────────────────

String _redactKeyValues(String text) {
  StringBuffer? out;
  var copied = 0; // text[0, copied) 已写进 out
  var resume = 0; // 已遮盖区域（到行尾）的末尾；落在里面的匹配跳过
  for (final m in _kvField.allMatches(text)) {
    if (m.start < resume) continue;
    final valueStart = m.end;
    final eol = _endOfLine(text, valueStart);
    final rest = text.substring(valueStart, eol);
    if (rest.isEmpty || rest == kRedacted) continue;
    final structured =
        m[1]!.isNotEmpty || m[3] == '=' || _inStructure(text, m.start);
    final mask =
        structured || _isStrongSecretName(m[2]!) || _containsToken(rest);
    if (!mask) continue;
    (out ??= StringBuffer())
      ..write(text.substring(copied, valueStart))
      ..write(kRedacted);
    copied = eol;
    resume = eol;
  }
  if (out == null) return text;
  out.write(text.substring(copied));
  return out.toString();
}

/// [index] 之前、同一行内出现过 `{`，或者有未闭合的 `[`：位于 Map / Set /
/// List 打印或 JSON 里。`{` 不要求未闭合——Map 打印里的字符串值本身可能带
/// `}`，宁可多遮。`[` 要求未闭合，免得 `[ERROR] x: Invalid key: profiles` 这类
/// 日志前缀把普通诊断也算进去。
bool _inStructure(String text, int index) {
  var closedSquare = 0;
  for (var k = index - 1; k >= 0; k--) {
    switch (text[k]) {
      case '\n' || '\r':
        return false;
      case '{':
        return true;
      case ']':
        closedSquare++;
      case '[':
        if (closedSquare == 0) return true;
        closedSquare--;
    }
  }
  return false;
}

/// 弱字段在自然语言写法里：冒号后整行余下的内容里有没有像凭据的片段。
///
/// 不去猜「第一个词」：按非 token 字符（空白、括号、引号、标点）拆开，每个片段
/// 原样判断一次，再按 `.` `/` 拆成子片段各判断一次（句末句点、路径里的 token）。
/// 只要有一个像凭据，就由调用方从值开头遮到行尾。
bool _containsToken(String rest) {
  for (final fragment in rest.split(_nonTokenChars)) {
    if (fragment.isEmpty) continue;
    if (_looksLikeToken(fragment)) return true;
    if (fragment.contains(_fragmentSeparators) &&
        fragment.split(_fragmentSeparators).any(_looksLikeToken)) {
      return true;
    }
  }
  return false;
}

/// 不可能出现在 token 里的字符；`.`（JWT）与 `/`（base64）留在片段里。
final RegExp _nonTokenChars = RegExp(r'[^A-Za-z0-9_\-+=~/.]+');
final RegExp _fragmentSeparators = RegExp('[./]');

int _endOfLine(String text, int from) {
  for (var k = from; k < text.length; k++) {
    final c = text[k];
    if (c == '\n' || c == '\r') return k;
  }
  return text.length;
}

// ─── URL ──────────────────────────────────────────────────────────────

/// 转义过斜杠的 URL：还原 `\/`，按普通 URL 与分享链接的规则处理，再把 `/`
/// 转义回去。末尾的反斜杠（属于后面的 `\"`）原样留在外面。
String _redactEscapedUrlMatch(Match m) {
  var whole = m[0]!;
  var tail = '';
  final trailing = _trailingBackslashes.firstMatch(whole);
  if (trailing != null) {
    tail = trailing[0]!;
    whole = whole.substring(0, trailing.start);
  }
  final plain = whole.replaceAll(r'\/', '/');
  final redacted = plain
      .replaceAllMapped(_shareLink, (s) => '${s[1]}://$kRedacted')
      .replaceAllMapped(_url, _redactUrlMatch);
  if (redacted == plain) return m[0]!;
  return '${redacted.replaceAll('/', r'\/')}$tail';
}

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

/// 路径段：原样以及每一轮宽松解码（最多三轮，应对重复编码）之后，整段与按解出
/// 的 `/` 拆开的每个子段都判断一次；任何一个像 token，整个原始段都算敏感。
bool _isSensitiveSegment(String segment) {
  if (segment.isEmpty || segment == kRedacted) return false;
  var current = segment;
  for (var round = 0; ; round++) {
    // 整段（含 `/` 的 base64 之类）与按 `/` 拆开的子段都要查。
    if (_looksLikeToken(current) || current.split('/').any(_looksLikeToken)) {
      return true;
    }
    if (round == 3 || !current.contains('%')) return false;
    final decoded = _percentDecodeLenient(current);
    if (decoded == current) return false;
    current = decoded;
  }
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
