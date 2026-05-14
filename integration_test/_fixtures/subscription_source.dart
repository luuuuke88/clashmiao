import 'dart:io';

/// 测试用订阅 URL 解析。
///
/// 优先级：
///  1. `--dart-define=CLASHMIAO_TEST_SUB_URL=...` （CI 用）
///  2. `~/.clashmiao_dev_subscription_url` 文件 （本地开发约定，DevBoot 也读）
///
/// 两个都没有就抛 [StateError]，避免假绿。
class SubscriptionSource {
  static const _defineKey = 'CLASHMIAO_TEST_SUB_URL';
  static const _fromDefine = String.fromEnvironment(_defineKey);

  static Future<String> resolve() async {
    if (_fromDefine.isNotEmpty) return _fromDefine;

    final home = Platform.environment['HOME'];
    if (home != null) {
      final f = File('$home/.clashmiao_dev_subscription_url');
      if (await f.exists()) {
        return (await f.readAsString()).trim();
      }
    }
    throw StateError(
      'No test subscription URL: set --dart-define=$_defineKey=... '
      'or create ~/.clashmiao_dev_subscription_url',
    );
  }
}
