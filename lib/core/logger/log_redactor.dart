// 日志脱敏：所有**落盘 / 导出**的日志文本都先过这里。
//
// 应用日志（app.log）与导出的核心日志会被用户分享出去排障，而异常文本里常带着
// 订阅地址：订阅链接本身就是凭据（路径或查询里的 token），代理分享链接更是把
// 服务器、端口、密码 / UUID 全写在一起。这里只抹掉这些，**保留**排障需要的
// 东西：异常类名、错误码、主机名与端口、堆栈帧（`file://` / `package:` 路径不动）。
//
// 规则（按顺序执行，结果幂等，可以重复过滤）：
// 1. 代理分享链接（vmess:// vless:// ss:// trojan:// hysteria2:// tuic:// …）整条
//    折叠为 `<scheme>://…`。
// 2. `Authorization:` / `Proxy-Authorization:` 头：冒号后到行尾整体替换。
// 3. 其它 URL：去掉 userinfo；查询串换成 `?…`、片段换成 `#…`；路径里像 token
//    的段（长十六进制、UUID、长 base64、16 位以上字母数字混排）换成 `…`；
//    scheme、主机、端口与普通路径段保留。`file://` 不处理（堆栈帧）。
// 4. 键值形式的秘密：`token=` `key=` `password=` `uuid=` `secret=` `auth=` 等
//    （含 `:` 分隔与 JSON 引号写法），值换成 `…`。

/// 脱敏后的占位符。
const String kRedacted = '…';

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

final RegExp _authHeader = RegExp(
  r'\b(proxy-authorization|authorization)(\s*:\s*)[^\r\n]*',
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

const _secretKeys =
    'access_token|refresh_token|id_token|token|api_key|apikey|key|password|'
    'passwd|pwd|uuid|secret|client_secret|auth|sid|sig|signature';

final RegExp _keyValue = RegExp(
  '(["\']?)\\b($_secretKeys)\\1(\\s*[=:]\\s*)(["\']?)([^\\s"\'&,;}\\]]+)\\4',
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
final RegExp _letter = RegExp('[A-Za-z]');
final RegExp _digit = RegExp('[0-9]');
final RegExp _upper = RegExp('[A-Z]');
final RegExp _lower = RegExp('[a-z]');

/// 把 [input] 里的订阅地址凭据、键值秘密与代理分享链接抹掉，其余原样返回。
String redactLogText(String input) {
  if (input.isEmpty) return input;
  var out = input.replaceAllMapped(_shareLink, (m) => '${m[1]}://$kRedacted');
  out = out.replaceAllMapped(_authHeader, (m) => '${m[1]}${m[2]}$kRedacted');
  out = out.replaceAllMapped(_url, _redactUrlMatch);
  out = out.replaceAllMapped(_keyValue, (m) {
    final value = m[5]!;
    if (value == kRedacted) return m[0]!;
    return '${m[1]}${m[2]}${m[1]}${m[3]}${m[4]}$kRedacted${m[4]}';
  });
  return out;
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
      .map((segment) => _looksLikeToken(segment) ? kRedacted : segment)
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

bool _looksLikeToken(String segment) {
  if (segment.isEmpty || segment == kRedacted) return false;
  if (_uuid.hasMatch(segment)) return true;
  if (_hex.hasMatch(segment)) return true;
  if (_base64.hasMatch(segment) &&
      _upper.hasMatch(segment) &&
      _lower.hasMatch(segment) &&
      (_digit.hasMatch(segment) || segment.contains(RegExp(r'[+/_=\-]')))) {
    return true;
  }
  return segment.length >= 16 &&
      _tokenChars.hasMatch(segment) &&
      _letter.hasMatch(segment) &&
      _digit.hasMatch(segment);
}
