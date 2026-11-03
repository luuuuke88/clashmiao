import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:flutter/foundation.dart';

/// 订阅存储 / 仓库 / 迁移的失败落盘口。
///
/// app.log 是用户可导出、可分享的文件，而这条数据通路上的异常消息可能夹带
/// 订阅地址、节点地址、文件路径或配置片段（native 解析器、网络层、文件系统
/// 异常都会把输入原文拼进消息）。日志脱敏器只能保证常见形态，保不住"短路径
/// token""host:port"这类，所以这里**不把异常对象交给 [logAppFailure]**，只落
/// 可信的上下文：定位标签、异常类型名、解析错误的稳定码（来自固定码表，不含
/// 用户数据）和堆栈。需要原文排障时只在 debug 构建的控制台看，不进 app.log。
///
/// [where] 必须是固定的定位标签，不要拼 key / 路径 / 订阅 id 以外的运行时内容。
void logProfileFailure(
  String where,
  Object error, [
  StackTrace? stackTrace,
  String? code,
]) {
  if (kDebugMode) {
    debugPrint('[$where] $error');
  }
  logAppFailure(
    where,
    ProfileFailureSummary(error.runtimeType, code),
    stackTrace,
  );
}

/// 只含类型名与稳定码的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class ProfileFailureSummary {
  const ProfileFailureSummary(this.type, [this.code]);

  final Type type;
  final String? code;

  @override
  String toString() => code == null ? '$type' : '$type(code=$code)';
}
