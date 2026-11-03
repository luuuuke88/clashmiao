import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 订阅地址（短路径 token，日志脱敏器认不出）与节点地址（host:port）：
/// 解析器 / 网络层会把输入原文拼进异常消息，这两样都不允许进 app.log。
const leakSubUrl = 'https://sub.example.com/a1b2c3';
const leakNodeAddr = 'node1.example.com:8443';
const leakMessage = 'dial $leakNodeAddr for $leakSubUrl';

/// 带地址原文的普通异常。
Exception leakyException() => Exception(leakMessage);

/// 带地址原文、且有稳定码的校验异常。
ProfileValidationException leakyValidation() => ProfileValidationException(
  'uri-invalid: $leakMessage',
  code: 'uri-invalid',
);

/// [records] 非空，且每一条持久化文本（含 [AppFailureRecord.error] 的字符串
/// 形式）都不含订阅地址、token、节点地址。
void expectNoLeak(Iterable<AppFailureRecord> records, {String? reason}) {
  expect(records, isNotEmpty, reason: reason ?? '失败应被记录');
  for (final r in records) {
    for (final text in [r.line, '${r.error}']) {
      for (final secret in [
        leakSubUrl,
        'a1b2c3',
        leakNodeAddr,
        'example.com',
        '8443',
      ]) {
        expect(text, isNot(contains(secret)), reason: '${r.where}: $text');
      }
    }
  }
}
