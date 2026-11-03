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

/// 手选节点失败的落盘口：固定标签 `proxies.select` + 失败码。
///
/// 分组名与节点名是订阅里用户 / 机场自己起的名字，常常就是一个裸域名
/// （`node.example.com`，没有端口，日志脱敏器认不出来），所以**绝不**拼进日志；
/// 内核回显的 message 同样可能带着节点名，也不记。失败码只接受 `[a-z0-9_.-]`
/// 的短码（原生桥与内核端的固定码表），别的一律记成 `other`。
///
/// 绝不抛出，理由同 [logProxyFailure]。
void logProxySelectionFailure(String code) {
  try {
    final safe = _stableCode.hasMatch(code) ? code : 'other';
    logAppFailure('proxies.select', 'SelectionFailed(code=$safe)');
  } catch (_) {
    // 同上：不递归打日志。
  }
}

final RegExp _stableCode = RegExp(r'^[a-z0-9_.\-]{1,40}$');

/// 只含类型名的失败摘要；[toString] 就是写进日志的全部内容。
@immutable
class ProxyFailureSummary {
  const ProxyFailureSummary(this.type);

  final Type type;

  @override
  String toString() => '$type';
}
