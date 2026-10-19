import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';
import 'package:path_provider/path_provider.dart';

/// App 层（Dart/Flutter）日志基础设施。
///
/// 和 `core/box_service` 那条实时 log 流（sing-box 核心自己的输出，见
/// `features/logs/application/log_filter_notifier.dart`）是两个完全独立的数据源：
/// 这里只关心 Dart/Flutter 应用层——未处理异常、原生层桥接错误——落地到
/// 本地 [kAppLogFileName] 文件，供"设置 -> 日志 -> 分享应用日志"排障使用。
/// 不做多级别、多文件的日志框架；持久化就是"追加写 + 超阈值截断"，运行时
/// 的分级过滤已经由 `log_filter_notifier.dart` 处理，职责不重叠。
///
/// 调用 [initAppLogger] 完成三件事：
/// 1. 把升级前写下的旧日志过一遍脱敏器（[AppLogger.redactExistingLogFiles]）。
/// 2. 挂载 `FlutterError.onError` / `PlatformDispatcher.instance.onError`
///    兜底，把捕获到的错误写入日志文件（且不会吞掉之前已经注册的 handler，
///    原有的会在写完日志后继续被调用）。
/// 3. 用 loggy 的自定义 [LoggyPrinter] 把之后所有 `logDebug`/`logInfo`/
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

/// 「分享应用日志」导出的脱敏副本文件名（写在临时目录，见
/// [AppLogger.writeRedactedCopy]）。
const String kAppLogShareFileName = 'clashmiao-app-logs.log';

/// 旧日志迁移完成的标记文件（内容是 [kLogRedactionVersion]），与 app.log 同目录。
const String _kRedactionMarkerName = '.app_log_redaction';

/// 迁移时临时文件的后缀：`app.log.redacting`，写完再改名覆盖。
const String _kRedactionTempSuffix = 'redacting';

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

  /// 所有对日志文件的读写都串在这条链上：追加、截断、旧文件迁移、导出副本
  /// 互不交错——迁移「写临时文件 → 改名覆盖」期间来的新行会排在后面，不会被
  /// 改名吞掉；导出读到的也是已经落盘的完整内容。
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

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

  /// 原始日志文件的路径。**不要**把它直接交给分享：那会把升级前写下、没有
  /// 脱敏的旧内容原样送出去；分享一律用 [writeRedactedCopy]。
  @visibleForTesting
  Future<String> getLogFilePath() async {
    final file = await _file();
    return file.path;
  }

  /// 把当前日志过一遍脱敏器，写成 [directory] 下的一个临时副本，返回副本。
  /// 「分享应用日志」只分享这个副本，从不交出原始 app.log——即便启动迁移
  /// 还没跑完或者失败了，分享出去的内容也是脱敏过的。
  Future<File> writeRedactedCopy(Directory directory) {
    return _serialized(() async {
      final source = await _file();
      final content = await _readLenient(source);
      await directory.create(recursive: true);
      final copy = File('${directory.path}/$kAppLogShareFileName');
      await copy.writeAsString(redactLogText(content), flush: true);
      return copy;
    });
  }

  /// 启动时的一次性迁移：把升级前写下的 app.log（以及按 `app.log.<数字>`
  /// 命名的旧滚动文件）整个过一遍脱敏器。
  ///
  /// - 一次性：完成后在同目录写下 [kLogRedactionVersion] 标记，之后启动直接
  ///   跳过；脱敏规则升级（版本号变了）会再跑一次。
  /// - 幂等：脱敏器本身幂等，内容没变的文件不重写。
  /// - 崩溃安全：先写同目录的临时文件并刷盘，再改名覆盖原文件；任何一步被
  ///   打断，原文件要么是旧的完整内容，要么是新的完整内容。残留的临时文件
  ///   下次启动时清掉。
  /// - 不抛异常：迁移失败只是这次没迁，分享时的脱敏副本照样兜底。
  Future<void> redactExistingLogFiles() {
    return _serialized(() async {
      try {
        final log = await _resolveLogFile();
        final dir = log.parent;
        if (!await dir.exists()) return;
        final marker = File('${dir.path}/$_kRedactionMarkerName');
        if (await marker.exists() &&
            (await marker.readAsString()).trim() == '$kLogRedactionVersion') {
          return;
        }
        final logName = log.uri.pathSegments.last;
        final escaped = RegExp.escape(logName);
        final rotated = RegExp('^$escaped\\.\\d+\$');
        // 只认自己的临时文件：app.log.redacting、app.log.<数字>.redacting。
        // 目录是 App 的 Documents，不是日志专用目录，别的 `.redacting` 不碰。
        final ownTemp = RegExp(
          '^$escaped(?:\\.\\d+)?\\.${RegExp.escape(_kRedactionTempSuffix)}\$',
        );
        final targets = <File>[];
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (ownTemp.hasMatch(name)) {
            await entity.delete(); // 上次迁移被打断留下的
          } else if (name == logName || rotated.hasMatch(name)) {
            targets.add(entity);
          }
        }
        for (final file in targets) {
          await _rewriteRedacted(file);
        }
        await marker.writeAsString('$kLogRedactionVersion', flush: true);
      } catch (_) {
        // 同 _appendInternal：日志系统自己的失败不往外抛，也不再打日志。
      }
    });
  }

  Future<void> _rewriteRedacted(File file) async {
    final original = await _readLenient(file);
    final redacted = redactLogText(original);
    if (redacted == original) return;
    final temp = File('${file.path}.$_kRedactionTempSuffix');
    await temp.writeAsString(redacted, flush: true);
    await temp.rename(file.path);
  }

  /// 读文本，遇到非法 UTF-8 用替换字符而不是抛异常（日志可能被截断在多字节
  /// 字符中间）。
  static Future<String> _readLenient(File file) async {
    if (!await file.exists()) return '';
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  /// 追加一行日志并在超阈值时触发截断。返回的 Future 在这一行真正落盘后
  /// 完成；测试可以用 [flush] 等待所有排队的写入。
  ///
  /// 这是 app.log 唯一的写入口：业务失败（[logAppFailure]）、loggy、未处理异常
  /// 兜底都从这里落盘，所以脱敏（[redactLogText]：订阅地址凭据、键值秘密、代理
  /// 分享链接）只在这里做一次，任何来源都绕不过去。
  Future<void> append(String line) {
    final redacted = redactLogText(line);
    return _serialized(() => _appendInternal(redacted));
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

  /// 测试专用：等待已排队的写入（追加、迁移、导出）全部完成，避免断言在
  /// 写入完成前跑。
  @visibleForTesting
  Future<void> flush() => _queue;
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

  // 升级前写下的旧日志可能带着没脱敏的凭据：排进写入队列里迁移一次，不阻塞
  // 启动；之后的追加自动排在它后面。
  unawaited(AppLogger.instance.redactExistingLogFiles());

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
      buffer.write('\n  error: ${_structuredFirst(record.error)}');
    }
    if (record.stackTrace != null) {
      buffer.write('\n${record.stackTrace}');
    }
    unawaited(AppLogger.instance.append(buffer.toString()));
  }
}

/// 业务失败的统一落盘口：异常与堆栈写进 [kAppLogFileName]（用户可导出的应用
/// 日志），同时 `debugPrint` 到开发控制台。
///
/// 约定：catch 里**第一句**就调它，且**不看** `mounted`——页面销毁后失败照样
/// 要留下技术详情；之后再用 `mounted` 决定要不要给界面反馈。用户看到的文案
/// 只用本地化的原因描述，异常原文只进这里。
///
/// [where] 是排障用的定位标签（例如 `profiles.update`），不是用户文案。
void logAppFailure(String where, Object error, [StackTrace? stackTrace]) {
  final buffer = StringBuffer()
    ..write(DateTime.now().toIso8601String())
    ..write(' [ERROR] ')
    ..write(where)
    ..write(': ')
    ..write(_structuredFirst(error));
  if (stackTrace != null && stackTrace != StackTrace.empty) {
    buffer.write('\n$stackTrace');
  }
  // 落盘时 [AppLogger.append] 还会再过一次（幂等）；这里先脱敏，控制台与测试
  // 接缝看到的就是将要写进 app.log 的内容。
  final line = redactLogText(buffer.toString());
  debugPrint(line);
  final sink = debugAppFailureSink;
  if (sink != null) {
    sink(AppFailureRecord(where, error, stackTrace, line));
    return;
  }
  unawaited(AppLogger.instance.append(line));
}

/// 错误本身是 Map / List（解析失败时直接抛出的 JSON 片段之类）时，先按键名
/// 结构化脱敏再转文本；其它对象原样交给字符串化，之后统一过 [redactLogText]。
Object? _structuredFirst(Object? error) =>
    error is Map || error is Iterable ? redactStructuredValue(error) : error;

/// 一次 [logAppFailure] 的内容，交给测试用的 [debugAppFailureSink]。
@immutable
class AppFailureRecord {
  const AppFailureRecord(this.where, this.error, this.stackTrace, this.line);

  final String where;
  final Object error;
  final StackTrace? stackTrace;

  /// 本该写进 app.log 的那一行（含时间戳与堆栈，已脱敏）。
  final String line;
}

/// 测试接缝：非空时 [logAppFailure] 把记录交给它，**不**写盘。界面测试据此用
/// 完成信号断言「失败被记录了」，不必等待真实文件 I/O；真实写盘由
/// app_logger_test 覆盖。
@visibleForTesting
void Function(AppFailureRecord record)? debugAppFailureSink;

/// 每个 [where] 最近一次已记录的错误，给 [logAppFailureOnce] 去重。
final Map<String, String> _lastLoggedFailure = {};

/// [logAppFailure] 的去重版，给 `AsyncValue.when(error: ...)` 这类会随重建反复
/// 执行的错误分支、以及会以同样原因反复失败的调用用：同一 [where] 上内容相同的
/// 错误只记一次，不让每次重建都往日志里刷一遍同样的堆栈。
void logAppFailureOnce(String where, Object error, [StackTrace? stackTrace]) {
  // 按文本去重：同一个错误对象，或每次新建但内容相同的错误（例如托盘图标
  // 每次设置都以同样原因失败），都只记一次；内容变了再记。
  final text = '$error';
  if (_lastLoggedFailure[where] == text) return;
  _lastLoggedFailure[where] = text;
  logAppFailure(where, error, stackTrace);
}

/// 测试专用：清空 [logAppFailureOnce] 的去重记录。
@visibleForTesting
void resetAppFailureDedupForTesting() => _lastLoggedFailure.clear();
