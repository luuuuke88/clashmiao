// 失败码的可信判定。
//
// 失败码来自原生桥、内核或解析器，看起来像「短码」，但并不能因此信任：平台
// 异常的 `code` 字段曾经被直接传入，裸域名（`node.example.com`）、`a.b`、
// `hk-01` 这类像节点名的短串都符合任何「短码」的字符格式。所以每个失败日志口
// 只认**自己明确列出的固定码集合**，集合之外一律记为 [kOtherFailureCode]。

/// 不在白名单里的失败码统一记成它。
const String kOtherFailureCode = 'other';

/// [code] 在 [allowed] 里就原样返回，否则返回 [kOtherFailureCode]；
/// [code] 为 null 时返回 null（调用方据此省略码）。
String? trustedFailureCode(String? code, Set<String> allowed) {
  if (code == null) return null;
  return allowed.contains(code) ? code : kOtherFailureCode;
}
