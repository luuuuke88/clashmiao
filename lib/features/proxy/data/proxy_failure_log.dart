import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:flutter/foundation.dart';

/// 代理分组 / 节点选择路径的失败落盘口。
///
/// app.log 是用户可导出、可分享的文件，而这条通路上的异常消息可能夹带订阅
/// 地址、节点地址、规则内容或文件路径（配置编译器、文件系统、内核桥都会把
/// 输入原文拼进消息）。所以这里**不把异常对象交给 [logAppFailure]**，只落
/// 可信的上下文：定位标签、异常类型名和堆栈。需要原文排障时只在 debug 构建
/// 的控制台看，不进 app.log。
///
/// [where] 必须是固定的定位标签，不要拼运行时内容。
///
/// 这个函数**绝不抛出**：调用方都是 catch 块里的回退路径（离线解析回退、空
/// 排除集、手选 stale 的延后重放），日志自己出问题（异常的 toString 抛错、
/// 堆栈文本化抛错、日志系统故障）不能改变这些路径的行为。
void logProxyFailure(String where, Object error, [StackTrace? stackTrace]) {
  try {
    if (kDebugMode) {
      debugPrint('[$where] $error');
    }
    logAppFailure(where, ProxyFailureSummary(error.runtimeType), stackTrace);
  } catch (_) {
    // 丢一行日志远好过让回退路径跟着失败；这里不再打任何东西，避免套娃。
  }
}

/// 只含类型名的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class ProxyFailureSummary {
  const ProxyFailureSummary(this.type);

  final Type type;

  @override
  String toString() => '$type';
}
