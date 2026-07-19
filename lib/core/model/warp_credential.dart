import 'dart:convert';

/// 解析自 native `BoxService.generateWarpConfig` 返回的原始 JSON。
///
/// native 端（Android JNI / iOS gomobile / 桌面 FFI，三端共用同一份 Go
/// 实现）成功时返回形如：
/// ```json
/// {"account-id": "...", "access-token": "...", "log": "...", "config": {...}}
/// ```
/// 的 JSON 字符串。`config` 是一个 JSON 对象（WireGuard 端点配置），我们不需要
/// 理解它的内部字段——原样重新序列化成字符串存进
/// `NetworkSettings.warpWireguardConfig`，注入运行时配置时再原样透传给
/// native。
class WarpCredential {
  const WarpCredential({
    required this.accountId,
    required this.accessToken,
    required this.wireguardConfig,
    this.log = '',
  });

  /// Cloudflare WARP 账号 ID。
  final String accountId;

  /// 该账号的访问令牌。
  final String accessToken;

  /// WireGuard 端点配置，JSON 字符串形式（透传给 native，不在 Dart 侧解析）。
  final String wireguardConfig;

  /// native 侧记录的注册过程日志，纯粹用于调试展示，不参与持久化。
  final String log;

  /// 解析 native 返回的原始 JSON 字符串。
  ///
  /// 输入不是合法 JSON、顶层不是对象，或者缺少
  /// `account-id` / `access-token` / `config` 中任意一个必需字段时抛出
  /// [FormatException]——调用方应当把它当成"生成失败"处理，而不是让残缺的
  /// 响应悄悄写成空账号。
  factory WarpCredential.parse(String rawJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      throw FormatException('WARP 响应不是合法 JSON: ${e.message}', rawJson);
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('WARP 响应顶层不是 JSON 对象', rawJson);
    }
    return WarpCredential.fromJson(decoded);
  }

  factory WarpCredential.fromJson(Map<String, dynamic> json) {
    final accountId = json['account-id'];
    if (accountId is! String || accountId.isEmpty) {
      throw const FormatException('WARP 响应缺少有效的 "account-id"');
    }
    final accessToken = json['access-token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const FormatException('WARP 响应缺少有效的 "access-token"');
    }
    final config = json['config'];
    if (config is! Map) {
      throw const FormatException('WARP 响应缺少有效的 "config"');
    }
    final log = json['log'];

    return WarpCredential(
      accountId: accountId,
      accessToken: accessToken,
      wireguardConfig: jsonEncode(config),
      log: log is String ? log : '',
    );
  }

  @override
  String toString() =>
      'WarpCredential(accountId: $accountId, '
      'wireguardConfig: ${wireguardConfig.length} chars)';
}
