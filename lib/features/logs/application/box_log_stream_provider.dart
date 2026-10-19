// sing-box 实时日志流 provider。

import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// sing-box 实时日志流。
///
/// 移动端使用原生 service.logs EventChannel；桌面端参照 sing-box 的日志
/// 文件轮询实现，保留 box.log 文件轮询。
///
/// autoDispose：日志页关闭、没有任何 watcher 时应该停止轮询——否则桌面端
/// 这个 while(true) 文件轮询循环会常驻内存持续消耗 CPU 和文件 IO，即使
/// 用户再也不会打开日志页。
final boxLogStreamProvider = StreamProvider.autoDispose<List<String>>((
  ref,
) async* {
  if (kDebugMode && const bool.fromEnvironment('CLASHMIAO_DEBUG_LOG_FIXTURE')) {
    yield const [
      '2026-06-12 23:58:01 INFO service started',
      '2026-06-12 23:58:02 DEBUG route rule matched proxy',
      '2026-06-12 23:58:03 WARN dns fallback used',
      '2026-06-12 23:58:04 ERROR outbound dial failed: timeout',
    ];
    return;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    yield* ref.watch(boxServiceProvider).watchLogs('');
    return;
  }

  final docsDir = await getApplicationDocumentsDirectory();
  final logFile = File('${docsDir.path}/box.log');
  // provider 被 dispose 时（离开日志页），停掉这个循环。文件内容不变的
  // tick 里循环体走不到任何 yield，光靠"stream 订阅被取消时在下一个
  // yield 处停止"这套 async* 内建机制救不了这种情况，必须显式检查。
  var disposed = false;
  ref.onDispose(() => disposed = true);
  // 第一帧立即 yield 当前内容（若有），之后每 1.5s 重读
  String? prev;
  while (true) {
    if (disposed) return;
    if (await logFile.exists()) {
      final content = await logFile.readAsString();
      if (content != prev) {
        prev = content;
        // 只保留最后 500 行，避免 UI 卡死
        final lines = const LineSplitter().convert(content);
        yield lines.length > 500 ? lines.sublist(lines.length - 500) : lines;
      }
    } else {
      yield const [];
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
  }
});
