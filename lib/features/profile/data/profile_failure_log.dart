import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/logger/failure_codes.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart'
    show ProfileValidationException, kParseErrorCodes;
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
/// 数据层之外的调用方（界面、深链 / 粘贴导入、备份恢复）同样走这里：它们
/// catch 到的异常就是数据层抛上来的那一个，消息里的订阅地址、节点地址照样会
/// 被 [logAppFailure] 原样持久化。界面照常给用户看本地化文案，不受影响。
///
/// [code] 缺省时，[error] 是 [ProfileValidationException] 就取它自带的稳定码。
///
/// 本函数是全函数：任何内部失败都被吞掉，不会从 catch 块里抛出。
///
/// [where] 必须是固定的定位标签，不要拼 key / 路径 / 订阅 id 以外的运行时内容。
void logProfileFailure(
  String where,
  Object error, [
  StackTrace? stackTrace,
  String? code,
]) {
  _logSafely(() {
    if (kDebugMode) {
      debugPrint('[$where] $error');
    }
    logAppFailure(where, _summaryOf(error, code), stackTrace);
  });
}

/// [logProfileFailure] 的去重版，给 `AsyncValue.when(error: ...)` 这类随重建
/// 反复执行的错误分支用；去重依据是摘要文本（类型名 + 稳定码），不含原文。
void logProfileFailureOnce(
  String where,
  Object error, [
  StackTrace? stackTrace,
  String? code,
]) {
  _logSafely(() {
    if (kDebugMode) {
      debugPrint('[$where] $error');
    }
    logAppFailureOnce(where, _summaryOf(error, code), stackTrace);
  });
}

/// 落日志绝不能反过来抛异常：这些函数都在 catch 块里调用，从里面再抛会盖掉
/// 原异常、改变导入 / 订阅的回退行为。堆栈或异常对象的 `toString()` 自己抛错、
/// 日志系统出错，一律吞掉。
void _logSafely(void Function() body) {
  try {
    body();
  } catch (_) {
    // 丢一行日志远好过制造一条假故障；这里不再递归打日志。
  }
}

ProfileFailureSummary _summaryOf(Object error, String? code) =>
    ProfileFailureSummary(
      error.runtimeType,
      // 只认解析器的固定码表，其余（包括像短码的裸域名）记成 `other`。
      trustedFailureCode(
        code ?? (error is ProfileValidationException ? error.code : null),
        kParseErrorCodes,
      ),
    );

/// 只含类型名与稳定码的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class ProfileFailureSummary {
  const ProfileFailureSummary(this.type, [this.code]);

  final Type type;
  final String? code;

  @override
  String toString() => code == null ? '$type' : '$type(code=$code)';
}
