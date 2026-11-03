// 日志脱敏：所有**落盘 / 导出 / 上报**的日志文本都先过这里（app.log、导出的
// 日志、全局错误兜底、Sentry 事件与面包屑，见 `AppLogger.append` 与
// `sentry_redaction.dart`），没有第二条出口。
//
// 应用日志会被用户分享出去排障，崩溃上报会离开设备，而异常文本里常带着：
// 订阅地址（本身就是凭据：路径或查询里的 token，短 token 也算）、代理分享链接
// （服务器、端口、密码 / UUID 全写在一起）、节点地址（`host:port`、IP）。
// 所以这里按**白名单**处理：除非主机在公共白名单里（[isPublicHost]：GitHub、
// 官网、构建期外链、本机回环），一律遮盖；不再靠「看起来像不像 token」去猜。
// GitHub 这类谁都能托管订阅的多租户主机，还要路径在本项目仓库或构建期外链的路径
// 前缀之下才放行（[publicUrlAccess]）。离开设备的通道（Sentry）用严格模式
// （[withStrictRedaction] / [redactStrict]）：白名单主机也只留 scheme + 主机，不留路径。
//
// 规则（按顺序执行，结果幂等，可以重复过滤）：
// 1. 代理分享链接（vmess:// vless:// ss:// trojan:// hysteria2:// tuic:// …）整条
//    折叠为 `<scheme>://…`。
// 2. 其它 URL（任何 scheme：http / https / ws / wss / clash:// / sing-box:// …）：
//    主机不在白名单里，整条换成 [kRedactedUrl]（`<url>`）。主机在白名单里：去掉
//    userinfo、查询串与片段，保留 scheme、主机、端口与路径（多租户主机路径不在放行
//    前缀下仍是 `<url>`；对象存储 / 发布资源主机只留 scheme + 主机）；路径段按子段判断像不像
//    token（长十六进制、UUID、长 base64、16 位以上字母数字混排、JWT），像就把
//    **整个原始段**换成 `…`（最多三轮宽松百分号解码）。空 authority 的 `file:///`（堆栈帧）在本地日志规则下不处理，严格模式（上报）下整条换成 `<url>`；`file://host/…` 照常过白名单。
//    百分号编码（`https%3A%2F%2F…`）与 JSON unicode 转义（`https\u003a\u002f\u002f…`）的 URL
//    还原后的整段文本走完整脱敏，
//    任何一部分需要遮盖就整段换成 `<url>`。
//    JSON 里转义成 `https:\/\/host\/path` 的 URL 先还原 `\/` 再按同样规则处理，处理完再
//    转义回去。
// 3. 裸地址：IPv4 / IPv6（带不带端口、带不带方括号都算）与 `host:port` 换成
//    [kRedactedAddr]（`<addr>`），本机回环与白名单主机除外（IPv6 可带 zone id，端口 1~5 位，
//    TLD 可以是 punycode，主机名可以是 Unicode IDN；带路径或带行列的堆栈帧
//    形态天然不匹配，裸的 `main.js:12` 会被当主机遮盖；单标签 `node:443` 不处理）；SocketException 的
//    `address = host` 与 `Failed host lookup: 'host'` 同样处理。时间戳（`12:34:56`）、
//    版本号（`1.14.3`）、Dart 堆栈帧（`package:foo/bar.dart:12:7`、`dart:async`）与
//    时长不会被碰。
// 4. 键值形式的秘密：字段名（可带引号，含转义引号）+ 分隔符 `=` 或 `:`。识别出
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
// 5. 游离的 `Bearer <token>`：token 像凭据时遮盖。

import 'dart:collection';
import 'dart:convert';

import 'package:clashmiao/core/logger/public_hosts.dart';

/// 脱敏后的占位符。
const String kRedacted = '…';

/// 非白名单 URL 的占位符。
const String kRedactedUrl = '<url>';

/// 节点地址（`host:port`、IP）的占位符。
const String kRedactedAddr = '<addr>';

/// 脱敏规则的版本号。规则收紧时递增：应用日志启动时据此把旧文件重新过一遍
/// （见 `AppLogger.redactExistingLogFiles`）。
const int kLogRedactionVersion = 8;

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
// 编码过的 URL：`https%3A%2F%2Fhost%2Fpath`（百分号，大小写不敏感）与
// `https\u003a\u002f\u002fhost`（JSON unicode 转义）。分隔符 `:` `//` 里至少有
// 一个是编码写法才算（全是明文的已由 [_url] 处理；只有 `\/` 转义的由
// [_escapedUrl] 处理）。
const _encColon = r'(?:%3[Aa]|\\u003[Aa])';
const _encSlash = r'(?:%2[Ff]|\\u002[Ff])';
const _anySlash = r'(?:%2[Ff]|\\u002[Ff]|\\/|/)';
const _plainSlash = r'(?:\\/|/)';
final RegExp _encodedUrl = RegExp(
  r'\b([a-zA-Z][a-zA-Z0-9+.\-]*)'
  '(?:$_encColon$_anySlash$_anySlash'
  '|:(?:$_encSlash$_anySlash|$_plainSlash$_encSlash))'
  r'''[^\s"'<>]*''',
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
  out = out.replaceAllMapped(_encodedUrl, _redactEncodedUrlMatch);
  out = _redactAddresses(out);
  out = _redactKeyValues(out);
  out = out.replaceAllMapped(_bearer, (m) {
    final token = m[1]!;
    if (!_looksLikeToken(token)) return m[0]!;
    return '${m[0]!.substring(0, m[0]!.length - token.length)}$kRedacted';
  });
  return out;
}

// ─── 严格模式 ─────────────────────────────────────────────────────────

int _strictDepth = 0;

/// 在 [body] 执行期间启用**严格模式**：所有 URL 只保留 scheme + 主机（白名单
/// 主机）或 `<url>`（其它），**任何路径都不保留**——包括官网与本项目仓库前缀。
///
/// 脱敏器认得出主机，却无法知道一条 URL 的**来源**：官网或仓库前缀下的短路径
/// 可能就是用户的订阅地址。离开设备的通道（Sentry）不能赌这一点，所以用严格
/// 模式；app.log 本地导出沿用白名单路径规则（来源侧的失败日志另有 `logInputFailure`
/// 等把关）。同步执行，可嵌套。
T withStrictRedaction<T>(T Function() body) {
  _strictDepth++;
  try {
    return body();
  } finally {
    _strictDepth--;
  }
}

/// [redactLogText] 的严格模式版本（见 [withStrictRedaction]）。
String redactStrict(String input) =>
    withStrictRedaction(() => redactLogText(input));

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

/// 编码过的 URL：先还原（`\uXXXX`、`\/`、百分号），再把还原后的**整段文本**交给
/// 完整的 [redactLogText]（URL、分享链接、裸地址、键值……一个都不少）：
/// - 还原后没有任何东西被遮盖：原样返回编码文本（如 `file:///`）。
/// - 有东西被遮盖，且结果里留下了占位符（非白名单 URL、分享链接、`host:port`、
///   IP、被遮的 token……）：整段编码文本换成 `<url>`，不留尾巴，**绝不**返回原文。
/// - 还原后全是白名单 URL：输出脱敏后的还原形式（已去掉查询串与片段）。
String _redactEncodedUrlMatch(Match m) {
  var whole = m[0]!;
  var tail = '';
  final trailing = _trailingBackslashes.firstMatch(whole);
  if (trailing != null) {
    tail = trailing[0]!;
    whole = whole.substring(0, trailing.start);
  }
  final decoded = _percentDecodeLenient(_unescapeJson(whole));
  final redacted = redactLogText(decoded);
  if (redacted == decoded) return m[0]!;
  if (redacted.contains(kRedactedUrl) ||
      redacted.contains(kRedactedAddr) ||
      redacted.contains(kRedacted)) {
    return '$kRedactedUrl$tail';
  }
  return '$redacted$tail';
}

final RegExp _jsonUnicodeEscape = RegExp(r'\\u([0-9a-fA-F]{4})');

/// 还原 JSON 的 `\uXXXX` 与 `\/`。
String _unescapeJson(String text) => text
    .replaceAllMapped(
      _jsonUnicodeEscape,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    )
    .replaceAll(r'\/', '/');

String _redactUrlMatch(Match m) {
  final whole = m[0]!;
  final scheme = m[1]!;
  final lower = scheme.toLowerCase();
  // 堆栈帧与本地路径（`file:///…`）：只放行空 authority；`file://host/…` 的
  // host 是网络共享，照常过白名单。
  if (lower == 'file' && m[2]!.isEmpty) {
    // 严格模式（上报）：本地路径也不出设备（iOS 容器路径里有用户目录与订阅文件名），
    // 整条换成 `<url>`，句末标点留在外面；本地 app.log 仍保留堆栈帧。
    if (_strictDepth == 0) return whole;
    final punct = _trailingPunct.firstMatch(whole);
    return '$kRedactedUrl${punct?[0] ?? ''}';
  }
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

  // 白名单：主机不在里面，整条 URL 都是用户数据（订阅地址、节点地址……）。
  // 多租户主机（GitHub 等）还要看路径：只有本项目自己的仓库路径或构建期外链的
  // 路径前缀才放行；对象存储 / 发布资源主机的路径是不透明 ID，只留 scheme + 主机。
  switch (publicUrlAccess(_hostOfAuthority(authority), path)) {
    case PublicUrlAccess.none:
      return '$kRedactedUrl$tail';
    case PublicUrlAccess.hostOnly:
      return '$scheme://$authority$tail';
    case PublicUrlAccess.hostAndPath:
      // 严格模式：来源不明，路径一律不保留。
      if (_strictDepth > 0) return '$scheme://$authority$tail';
  }

  // 路径里藏着别的地址（`/o/r,https://订阅地址`、编码过的 `%2Chttps%3A%2F%2F…`、
  // 节点 `host:port`）：这条 URL 不再只是「公共主机 + 路径」，整条当用户数据。
  if (_pathHidesAddress(path)) return '$kRedactedUrl$tail';

  final maskedPath = path
      .split('/')
      .map((segment) => _isSensitiveSegment(segment) ? kRedacted : segment)
      .join('/');

  // 公共主机的 URL 也不保留查询串与片段：那里才是 token 的常见位置。
  return '$scheme://$authority$maskedPath$tail';
}

/// `host`、`host:port`、`[v6]:port` → 主机部分（不含端口与方括号外壳以外的东西）。
String _hostOfAuthority(String authority) {
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    return close < 0 ? authority : authority.substring(0, close + 1);
  }
  final colon = authority.indexOf(':');
  return colon < 0 ? authority : authority.substring(0, colon);
}

// ─── 裸地址 ───────────────────────────────────────────────────────────

/// 方括号里的 IPv6，可带端口：`[2001:db8::1]:443`。
final RegExp _bracketedIpv6 = RegExp(
  r'\[([0-9A-Fa-f:.]{2,}(?:%[A-Za-z0-9_.\-]+)?)\](?::\d{1,5})?',
);

/// 没有方括号的 IPv6 候选（可带 zone id：`fe80::1%en0`）；是否真是地址由
/// [Uri.parseIPv6Address] 判定（`12:34:56` 这类时间戳不是合法 IPv6，不会被碰）。
final RegExp _bareIpv6 = RegExp(
  r'(?<![\w:.\[])[0-9A-Fa-f:.]{2,}(?:%[A-Za-z0-9_\-]+)?(?![\w:\[])',
);

/// IPv4，可带端口。`1.14.3` 只有三段不匹配；前面紧跟字母数字（`v1.2.3.4`）也不匹配。
final RegExp _ipv4 = RegExp(
  r'(?<![\w.])((?:\d{1,3}\.){3}\d{1,3})(?::(\d{1,5}))?(?!\w|\.\d)',
);

/// 带点的主机名 + 端口（1~5 位）。标签可以含任意语言的字母（Unicode IDN，
/// `例子.测试:443`）；TLD 是字母（`.org`、`.测试`）或 punycode（`.xn--p1ai`）。
/// 端口后面不能再跟 `:数字`（`foo.dart:12:7` 堆栈帧），前面不能是路径字符
/// （`package:foo/bar.dart:12`、`dart:core/x.dart:12`、`(lib/x.dart:12:7)`）——
/// 真实的堆栈帧形态都因此不会被碰，不需要按文件扩展名豁免：
/// 单个数字的 `(server.rs:443)` 是主机，`at main.js:12` 也会被当成主机遮盖
/// （保守，见测试）。
final RegExp _hostPort = RegExp(
  r'(?<![\p{L}\p{M}\p{N}_.\-/%])'
  r'((?:[\p{L}\p{N}](?:[\p{L}\p{M}\p{N}\-]*[\p{L}\p{M}\p{N}])?\.)+'
  r'(?:\p{L}[\p{L}\p{M}]{1,23}|xn--[A-Za-z0-9\-]{1,59}))'
  r':(\d{1,5})(?![\p{L}\p{M}\p{N}_]|:\d|\.\d)',
  unicode: true,
);

/// SocketException 的 `address = host`、`Failed host lookup: 'host'`。
final RegExp _socketHost = RegExp(
  r"(\baddress = |\bhost lookup: ')([^\s,)'<>]+)",
  caseSensitive: false,
);

String _redactAddresses(String text) {
  var out = text.replaceAllMapped(_socketHost, (m) {
    final host = m[2]!;
    if (host == kRedactedAddr || isPublicHost(host)) return m[0]!;
    return '${m[1]}$kRedactedAddr';
  });
  out = out.replaceAllMapped(_bracketedIpv6, (m) {
    if (!_isIpv6(m[1]!) || isLoopbackHost(_withoutZone(m[1]!))) return m[0]!;
    return kRedactedAddr;
  });
  out = out.replaceAllMapped(_bareIpv6, (m) {
    final candidate = m[0]!;
    if (_redactableIpv6(candidate)) return kRedactedAddr;
    // 句末的 `.` / `:` 不属于地址：`peer 2001:db8::1.`
    if (candidate.length > 2 &&
        (candidate.endsWith('.') || candidate.endsWith(':'))) {
      final trimmed = candidate.substring(0, candidate.length - 1);
      if (_redactableIpv6(trimmed)) {
        return '$kRedactedAddr${candidate[candidate.length - 1]}';
      }
    }
    return candidate;
  });
  out = out.replaceAllMapped(_ipv4, (m) {
    final octets = m[1]!.split('.');
    if (octets.any((o) => int.parse(o) > 255)) return m[0]!;
    if (octets.first == '127') return m[0]!; // 回环
    final port = m[2];
    if (port != null && int.parse(port) > 65535) return m[0]!;
    return kRedactedAddr;
  });
  out = out.replaceAllMapped(_hostPort, (m) {
    final host = m[1]!;
    if (int.parse(m[2]!) > 65535) return m[0]!;
    if (isPublicHost(host)) return m[0]!;
    return kRedactedAddr;
  });
  return out;
}

bool _isIpv6(String candidate) {
  if (!candidate.contains(':')) return false;
  try {
    Uri.parseIPv6Address(_withoutZone(candidate));
    return true;
  } on FormatException {
    return false;
  }
}

/// 去掉 IPv6 的 zone id（`fe80::1%en0` -> `fe80::1`）。
String _withoutZone(String address) {
  final percent = address.indexOf('%');
  return percent < 0 ? address : address.substring(0, percent);
}

/// 要遮盖的 IPv6：合法、至少含一个十六进制数字（排除孤立的 `::`）、不是回环。
bool _redactableIpv6(String candidate) =>
    _isIpv6(candidate) &&
    RegExp('[0-9A-Fa-f]').hasMatch(candidate) &&
    !isLoopbackHost(_withoutZone(candidate));

final RegExp _nestedScheme = RegExp(r'[a-zA-Z][a-zA-Z0-9+.\-]*://');

/// 白名单 URL 的路径（原样以及最多三轮 JSON / 百分号解码之后）里是否含有另一个
/// URL（任意 scheme，含分享链接）或节点地址。
bool _pathHidesAddress(String path) {
  var current = path;
  for (var round = 0; ; round++) {
    if (_nestedScheme.hasMatch(current)) return true;
    if (_redactAddresses(current) != current) return true;
    if (round == 3) return false;
    final decoded = _percentDecodeLenient(_unescapeJson(current));
    if (decoded == current) return false;
    current = decoded;
  }
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
