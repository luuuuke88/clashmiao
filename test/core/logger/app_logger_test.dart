import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// AppLogger 是 App 层（Dart/Flutter）日志基础设施：
/// - `FlutterError.onError` / `PlatformDispatcher.instance.onError` 兜底捕获
///   未处理异常，写入本地 app.log；
/// - 文件超过大小阈值时截断，只保留最后 N 行，避免无限增长；
/// - 和核心（sing-box）日志是完全独立的数据源（见 logs_page_test.dart 里
///   "分享核心日志" vs "分享应用日志" 用不同文件路径的验证）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_logger_test_');
    logFile = File('${tempDir.path}/app.log');
    AppLogger.configureForTesting(resolveLogFile: () async => logFile);
  });

  tearDown(() async {
    AppLogger.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AppLogger.getLogFilePath', () {
    test('返回注入的日志文件路径', () async {
      final path = await AppLogger.instance.getLogFilePath();
      expect(path, logFile.path);
    });
  });

  group('AppLogger.append', () {
    test('把一行写入日志文件', () async {
      await AppLogger.instance.append('hello world');

      final content = await logFile.readAsString();
      expect(content, contains('hello world'));
    });

    test('多次 append 按顺序追加，不覆盖旧内容', () async {
      await AppLogger.instance.append('line-one');
      await AppLogger.instance.append('line-two');

      final lines = await logFile.readAsLines();
      expect(lines, ['line-one', 'line-two']);
    });
  });

  group('AppLogger 日志文件大小控制（超阈值截断）', () {
    test('文件字节数超过阈值时，只保留最后 maxLines 行', () async {
      AppLogger.configureForTesting(
        resolveLogFile: () async => logFile,
        maxBytes: 20,
        maxLines: 2,
      );

      await AppLogger.instance.append('line-one');
      await AppLogger.instance.append('line-two');
      // 前两行合计 18 字节，还没超阈值；这一行会让总字节数越过 20 字节的阈值，
      // 触发截断只保留最后 2 行。
      await AppLogger.instance.append('line-three');

      final lines = await logFile.readAsLines();
      expect(lines.length, lessThanOrEqualTo(2));
      expect(lines.last, 'line-three');
      expect(lines, isNot(contains('line-one')));
    });

    test('文件字节数未超过阈值时不截断，保留全部行', () async {
      AppLogger.configureForTesting(
        resolveLogFile: () async => logFile,
        maxBytes: 1024 * 1024,
        maxLines: 2,
      );

      await AppLogger.instance.append('line-one');
      await AppLogger.instance.append('line-two');
      await AppLogger.instance.append('line-three');

      final lines = await logFile.readAsLines();
      expect(lines, ['line-one', 'line-two', 'line-three']);
    });
  });

  group('initAppLogger 兜底错误捕获', () {
    tearDown(() {
      resetAppLoggerInitializedForTesting();
    });

    test('FlutterError.onError 触发时，错误信息落地到日志文件', () async {
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);

      await initAppLogger();
      FlutterError.onError!(
        FlutterErrorDetails(exception: Exception('boom-flutter-error')),
      );
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, contains('boom-flutter-error'));
    });

    test('PlatformDispatcher.instance.onError 触发时，错误信息落地到日志文件', () async {
      final previous = PlatformDispatcher.instance.onError;
      addTearDown(() => PlatformDispatcher.instance.onError = previous);

      await initAppLogger();
      PlatformDispatcher.instance.onError!(
        Exception('boom-platform-error'),
        StackTrace.current,
      );
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, contains('boom-platform-error'));
    });

    test('initAppLogger 保留之前已有的 FlutterError.onError（不覆盖丢弃）', () async {
      var previousCalled = false;
      FlutterError.onError = (details) {
        previousCalled = true;
      };
      final previous = FlutterError.onError;
      addTearDown(() => FlutterError.onError = previous);

      await initAppLogger();
      FlutterError.onError!(
        FlutterErrorDetails(exception: Exception('chained-error')),
      );
      await AppLogger.instance.flush();

      expect(previousCalled, isTrue, reason: '之前注册的 handler 必须继续被调用，不能被静默替换');
    });
  });
}
