import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:flutter/foundation.dart';

/// 连接路径（连接控制器、启动编排、健康监测、出口 IP 探测、手选重放）的失败
/// 落盘口。
///
/// app.log 是用户可导出、可分享的文件，而这条通路上的异常消息可能夹带订阅
/// 地址、节点地址（host:port）、出口探测地址或文件路径（Dio、文件系统、内核桥
/// 都会把输入原文拼进消息）。所以这里**不把异常对象交给 [logAppFailure]**，
/// 只落可信的上下文：定位标签、异常类型名和堆栈。需要原文排障时只在 debug 构建
/// 的控制台看，不进 app.log。
///
/// [where] 必须是固定的定位标签，不要拼运行时内容。
///
/// 这个函数**绝不抛出**：调用方全是 catch 块 / onError 里的回退路径（读不到
/// 配置按空处理、探测失败按未知处理、副作用失败忽略……），日志自己出问题
/// （异常的 toString 抛错、堆栈文本化抛错、日志系统故障）不能改变这些路径的
/// 行为，更不能让连接状态机跟着失败。
void logConnectionFailure(
  String where,
  Object error, [
  StackTrace? stackTrace,
]) {
  try {
    if (kDebugMode) {
      debugPrint('[$where] $error');
    }
    logAppFailure(
      where,
      ConnectionFailureSummary(error.runtimeType),
      stackTrace,
    );
  } catch (_) {
    // 丢一行日志远好过让回退路径跟着失败；这里不再打任何东西，避免套娃。
  }
}

/// 只含类型名的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class ConnectionFailureSummary {
  const ConnectionFailureSummary(this.type);

  final Type type;

  @override
  String toString() => '$type';
}
