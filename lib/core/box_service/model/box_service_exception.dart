/// [BoxService] 实现抛出的类型化失败（桌面 FFI 的调用错误）。
///
/// [code] 是调用名（`start` / `stop` / `restart` / `selectOutbound` /
/// `urlTest`），[message] 是内核返回的原始文本。上层据此判断失败来源，
/// 不再靠 `toString().contains(...)` 做字符串匹配。
class BoxServiceException implements Exception {
  const BoxServiceException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() =>
      'BoxServiceException($code${message.isEmpty ? '' : ': $message'})';
}
