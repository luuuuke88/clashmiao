import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户输入类流程（深链、Geo 资源下载、设置 JSON 导入、备份恢复）的失败日志必须
/// 走 `logInputFailure`（只落标签 + 异常类型 + 堆栈），不能把异常对象交给
/// `logAppFailure`：异常消息里是用户给的 URL，日志脱敏器无法知道它的来源，官网
/// 与本项目仓库前缀下的短订阅路径会被当作白名单保留。
void main() {
  test('输入类流程不直接调用 logAppFailure 落异常', () {
    final pattern = RegExp(
      r'''logAppFailure(?:Once)?\(\s*['"](deepLink\.(?:stream|subscribe)|geo\.\w+|settings\.importJson|backup\.\w+)['"]\s*,\s*(?!\s*'snapshot not found')''',
    );
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        hits.add('${entity.path}: ${m.group(1)}');
      }
    }
    expect(
      hits,
      isEmpty,
      reason: '这些位置改用 logInputFailure（core/logger/input_failure_log.dart）',
    );
  });
}
