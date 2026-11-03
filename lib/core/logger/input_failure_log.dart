import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:flutter/foundation.dart';

/// 用户输入类流程（深链、Geo 资源下载地址、设置 JSON 导入、备份恢复）的失败
/// 落盘口。
///
/// 这些流程的异常消息里就是用户给的内容：深链里的订阅地址、自定义下载地址、
/// 导入文本的片段、备份文件路径。日志脱敏器无法知道一条 URL 的来源，白名单
/// 主机（官网、本项目仓库路径）下的短订阅路径照样会被保留，所以由**来源**这一
/// 侧负责：这里**不把异常对象交给 [logAppFailure]**，只落定位标签、异常类型名
/// 和堆栈。异常原文哪里都不落（app.log、控制台、上报都没有）。
///
/// [where] 必须是固定的定位标签，不要拼运行时内容。
///
/// 这个函数**绝不抛出**：调用方都是 catch 块里的回退路径，日志自己出问题
/// （异常的 toString 抛错、堆栈文本化抛错、日志系统故障）不能改变它们的行为。
void logInputFailure(String where, Object error, [StackTrace? stackTrace]) {
  try {
    // 连 debug 控制台也只打标签 + 类型：debugPrint 的文本会被 Sentry 的 print
    // 面包屑、系统日志带出应用，异常原文（用户给的 URL、裸域名）不能进去。
    if (kDebugMode) {
      debugPrint('[$where] ${error.runtimeType}');
    }
    logAppFailure(where, InputFailureSummary(error.runtimeType), stackTrace);
  } catch (_) {
    // 丢一行日志远好过让回退路径跟着失败；这里不再打任何东西，避免套娃。
  }
}

/// 只含类型名的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class InputFailureSummary {
  const InputFailureSummary(this.type);

  final Type type;

  @override
  String toString() => '$type';
}
