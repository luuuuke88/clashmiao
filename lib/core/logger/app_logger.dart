import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';
import 'package:path_provider/path_provider.dart';

/// App 层（Dart/Flutter）日志基础设施。
///
/// 和 `core/box_service` 那条实时 log 流（sing-box 核心自己的输出，见
/// `features/logs/state/log_filter_notifier.dart`）是两个完全独立的数据源：
/// 这里只关心 Dart/Flutter 应用层——未处理异常、原生层桥接错误——落地到
/// 本地 [kAppLogFileName] 文件，供"设置 -> 日志 -> 分享应用日志"排障使用。
/// 不做多级别、多文件的日志框架；持久化就是"追加写 + 超阈值截断"，运行时
/// 的分级过滤已经由 `log_filter_notifier.dart` 处理，职责不重叠。
///
/// 调用 [initAppLogger] 完成两件事：
/// 1. 挂载 `FlutterError.onError` / `PlatformDispatcher.instance.onError`
///    兜底，把捕获到的错误写入日志文件（且不会吞掉之前已经注册的 handler，
///    原有的会在写完日志后继续被调用）。
/// 2. 用 loggy 的自定义 [LoggyPrinter] 把之后所有 `logDebug`/`logInfo`/
///    `logWarning`/`logError` 调用也写入同一个文件。
///
/// 这个初始化不受"数据分析"开关影响——纯本地文件，不涉及任何上报，任何
/// 情况下都应该记录，方便排障（对照 main.dart 里 Sentry SDK 的门控逻辑，
/// 那个才是真正决定"要不要上报"的开关）。

/// 单个日志文件允许的最大字节数，超过就触发截断（只保留最后
/// [kAppLogMaxLines] 行）。刻意不做多文件滚动系统，保持简单。
const int kAppLogMaxBytes = 2 * 1024 * 1024; // 2MB

/// 截断时保留的最后行数。
const int kAppLogMaxLines = 4000;

/// 本地应用日志文件名。
const String kAppLogFileName = 'app.log';

typedef LogFileResolver = Future<File> Function();

/// App 层日志文件的读写门面。用 [AppLogger.instance] 拿到单例；测试里用
/// [AppLogger.configureForTesting] 注入一个不依赖真实平台 path_provider 的
/// resolver（以及可选的更小 maxBytes/maxLines，方便验证截断逻辑不用真的
/// 写几 MB 数据）。
class AppLogger {
  AppLogger._(
    this._resolveLogFile, {
    required this.maxBytes,
    required this.maxLines,
  });

  static AppLogger? _instance;

  static AppLogger get instance {
    return _instance ??= AppLogger._(
      _defaultResolver,
      maxBytes: kAppLogMaxBytes,
      maxLines: kAppLogMaxLines,
    );
  }

  /// 测试专用：注入自定义日志文件 resolver（通常指向临时目录），绕开
  /// 真实 path_provider 平台通道；也可以覆盖 maxBytes/maxLines 以便用很小
  /// 的阈值验证截断逻辑。
  @visibleForTesting
  static void configureForTesting({
    required LogFileResolver resolveLogFile,
    int maxBytes = kAppLogMaxBytes,
    int maxLines = kAppLogMaxLines,
  }) {
    _instance = AppLogger._(
      resolveLogFile,
      maxBytes: maxBytes,
      maxLines: maxLines,
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  final LogFileResolver _resolveLogFile;
  final int maxBytes;
  final int maxLines;

  File? _cachedFile;
  Future<void>? _pendingWrite;

  static Future<File> _defaultResolver() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$kAppLogFileName');
    return file;
  }

  Future<File> _file() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final resolved = await _resolveLogFile();
    await resolved.parent.create(recursive: true);
    if (!await resolved.exists()) {
      await resolved.create(recursive: true);
    }
    _cachedFile = resolved;
    return resolved;
  }

  /// 日志文件路径，给"分享应用日志"功能使用。
  Future<String> getLogFilePath() async {
    final file = await _file();
    return file.path;
  }

  /// 追加一行日志并在超阈值时触发截断。返回的 Future 也保存在
  /// [_pendingWrite] 里，测试可以用 [flush] 等待它写完。
  Future<void> append(String line) {
    final future = _appendInternal(line);
    _pendingWrite = future;
    return future;
  }

  Future<void> _appendInternal(String line) async {
    // 写日志**绝不能**把异常抛出去。这条路径上的调用方是
    // `FlutterError.onError` / `PlatformDispatcher.onError` 里的
    // fire-and-forget（见 initAppLogger），抛出来就是一条没人接的异步异常——
    // 而且是在"处理另一个错误"的过程中产生的，堆栈跟真正的故障毫无关系，
    // 排障时极具误导性。
    //
    // 日志目录消失是真实会发生的：用户清了 App 数据、系统清理临时目录、
    // 外部工具删了目录。CI 上就真的撞到过（PathNotFoundException from
    // `file.length()`，报在一条**已经结束**的测试上）。
    //
    // 丢一行日志远好过制造一条假故障。
    try {
      final file = await _file();
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      await _rotateIfNeeded(file);
    } catch (_) {
      // 这里连 debugPrint 都不做：日志系统自己出问题时再去打日志，容易套娃。
    }
  }

  Future<void> _rotateIfNeeded(File file) async {
    // 先确认文件还在：写完到这里之间目录可能已经被删掉（见 _appendInternal
    // 的注释），`length()` 对不存在的文件会抛 PathNotFoundException。
    if (!await file.exists()) return;
    final length = await file.length();
    if (length <= maxBytes) return;

    final lines = await file.readAsLines();
    final kept = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;
    await file.writeAsString(kept.isEmpty ? '' : '${kept.join('\n')}\n');
  }

  /// 测试专用：等待最近一次 [append] 真正落地磁盘，避免断言在写入完成前跑。
  @visibleForTesting
  Future<void> flush() => _pendingWrite ?? Future<void>.value();
}

bool _appLoggerInitialized = false;

/// 初始化 App 层日志基础设施：挂 loggy 文件 printer + 兜底错误捕获。
/// 幂等——重复调用只生效一次。
///
/// 应该在 main() 启动早期调用（`WidgetsFlutterBinding.ensureInitialized()`
/// 之后即可），且不受"数据分析"开关影响：这里只是本地文件记录，不涉及
/// 任何网络上报，为了排障任何情况下都该记录。
Future<void> initAppLogger() async {
  if (_appLoggerInitialized) return;
  _appLoggerInitialized = true;

  Loggy.initLoggy(logPrinter: const _AppFileLoggyPrinter());

  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(
      AppLogger.instance.append(
        '[FlutterError] ${details.exceptionAsString()}\n${details.stack ?? ''}',
      ),
    );
    previousFlutterOnError?.call(details);
  };

  final previousPlatformOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(AppLogger.instance.append('[PlatformDispatcher] $error\n$stack'));
    return previousPlatformOnError?.call(error, stack) ?? true;
  };
}

/// 测试专用：重置 [initAppLogger] 的幂等 guard，让下一次调用重新生效。
/// 不会自动恢复 `FlutterError.onError` / `PlatformDispatcher.instance.onError`
/// ——测试里请自行保存/恢复这两个 handler（`addTearDown`）。
@visibleForTesting
void resetAppLoggerInitializedForTesting() {
  _appLoggerInitialized = false;
}

class _AppFileLoggyPrinter extends LoggyPrinter {
  const _AppFileLoggyPrinter();

  @override
  void onLog(LogRecord record) {
    final buffer = StringBuffer()
      ..write(record.time.toIso8601String())
      ..write(' [')
      ..write(record.level.toString().toUpperCase())
      ..write('] ')
      ..write(record.loggerName)
      ..write(': ')
      ..write(record.message);
    if (record.error != null) {
      buffer.write('\n  error: ${record.error}');
    }
    if (record.stackTrace != null) {
      buffer.write('\n${record.stackTrace}');
    }
    unawaited(AppLogger.instance.append(buffer.toString()));
  }
}
