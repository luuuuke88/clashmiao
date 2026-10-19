import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/temp_dirs.dart';

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
    await deleteTempDirBestEffort(tempDir);
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

  group('logAppFailure：业务失败统一落盘', () {
    tearDown(resetAppFailureDedupForTesting);

    test('异常与堆栈写进 app.log，带定位标签', () async {
      final stack = StackTrace.current;
      logAppFailure('profiles.update', StateError('boom'), stack);
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, contains('[ERROR] profiles.update: Bad state: boom'));
      expect(content, contains(stack.toString().split('\n').first));
    });

    test('订阅地址凭据不进 app.log：Dio 包着带 token 的 HttpException', () async {
      const secretUrl = 'https://example.test/sub?token=SECRET';
      final error = DioException(
        requestOptions: RequestOptions(path: secretUrl),
        error: HttpException(
          'Connection closed before full header was received',
          uri: Uri.parse(secretUrl),
        ),
      );
      final stack = StackTrace.current;
      logAppFailure('restore.backfill profile-a', error, stack);
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, isNot(contains('SECRET')));
      expect(content, isNot(contains(secretUrl)));
      // 排障需要的东西都在：异常类别、底层异常、主机路径、堆栈帧。
      expect(content, contains('DioException'));
      expect(content, contains('HttpException: Connection closed'));
      expect(content, contains('https://example.test/sub?…'));
      expect(content, contains(stack.toString().split('\n').first));
    });

    test('脱敏在唯一写入口：直接 append 的行（loggy、未处理异常兜底）也过滤', () async {
      await AppLogger.instance.append(
        '[PlatformDispatcher] fetch failed: https://u:pw@example.test/s?key=K '
        'vless://uuid@1.2.3.4:443#hk',
      );

      final content = await logFile.readAsString();
      expect(content, isNot(contains('key=K')));
      expect(content, isNot(contains('u:pw@')));
      expect(content, isNot(contains('uuid@1.2.3.4')));
      expect(content, contains('https://example.test/s?…'));
      expect(content, contains('vless://…'));
    });

    test('logAppFailureOnce：同一标签同一错误只记一次，换了错误再记', () async {
      final first = StateError('first');
      logAppFailureOnce('profiles.list', first);
      await AppLogger.instance.flush();
      logAppFailureOnce('profiles.list', first);
      await AppLogger.instance.flush();
      logAppFailureOnce('profiles.list', StateError('second'));
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect('first'.allMatches(content), hasLength(1));
      expect(content, contains('second'));
    });

    test('logAppFailureOnce：每次新建但内容相同的错误也只记一次', () async {
      logAppFailureOnce('tray.setIcon', Exception('asset missing'));
      await AppLogger.instance.flush();
      logAppFailureOnce('tray.setIcon', Exception('asset missing'));
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect('asset missing'.allMatches(content), hasLength(1));
    });

    test('测试接缝 debugAppFailureSink：拿到完整记录，且不写盘', () async {
      final records = <AppFailureRecord>[];
      debugAppFailureSink = records.add;
      addTearDown(() => debugAppFailureSink = null);
      final error = StateError('seam');
      final stack = StackTrace.current;

      logAppFailure('where', error, stack);
      await AppLogger.instance.flush();

      expect(records, hasLength(1));
      expect(records.single.where, 'where');
      expect(records.single.error, same(error));
      expect(records.single.stackTrace, same(stack));
      expect(records.single.line, contains('[ERROR] where: Bad state: seam'));
      expect(logFile.existsSync(), isFalse, reason: '接缝生效时不写盘');
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

  group('升级前写下的旧日志：启动迁移与导出副本都脱敏', () {
    const rawLine =
        '2026-06-01T10:00:00.000 [ERROR] profiles.update: HttpException: '
        'Connection closed, uri = https://example.test/sub?token=SECRET';
    const rawJson = '{"password":"hello world","server":"h.example.test"}';

    tearDown(resetAppLoggerInitializedForTesting);

    Future<void> seedOldLog() async {
      await logFile.writeAsString('$rawLine\n$rawJson\nplain line\n');
    }

    void expectRedacted(String content) {
      expect(content, isNot(contains('SECRET')));
      expect(content, isNot(contains('hello world')));
      expect(content, contains('https://example.test/sub?…'));
      expect(content, contains('"password":"…"'));
      expect(content, contains('plain line'));
    }

    test('迁移把 app.log 与 app.log.<数字> 重写为脱敏内容，别的文件不碰', () async {
      await seedOldLog();
      final rotated = File('${tempDir.path}/app.log.1');
      await rotated.writeAsString('$rawLine\n');
      final unrelated = File('${tempDir.path}/notes.txt');
      await unrelated.writeAsString(rawLine);
      // 上次迁移被打断留下的临时文件。
      final leftover = File('${tempDir.path}/app.log.redacting');
      await leftover.writeAsString(rawLine);

      await AppLogger.instance.redactExistingLogFiles();

      expectRedacted(await logFile.readAsString());
      expect(await rotated.readAsString(), isNot(contains('SECRET')));
      expect(await unrelated.readAsString(), rawLine);
      expect(leftover.existsSync(), isFalse);
    });

    test('迁移幂等：重复运行、去掉完成标记再跑，内容都不再变化', () async {
      await seedOldLog();
      await AppLogger.instance.redactExistingLogFiles();
      final first = await logFile.readAsString();

      await AppLogger.instance.redactExistingLogFiles();
      expect(await logFile.readAsString(), first);

      for (final entity in tempDir.listSync()) {
        final name = entity.uri.pathSegments.last;
        if (name != 'app.log') entity.deleteSync();
      }
      await AppLogger.instance.redactExistingLogFiles();
      expect(await logFile.readAsString(), first);
      expectRedacted(first);
    });

    test('迁移只跑一次：完成标记在且版本一致时直接跳过', () async {
      await AppLogger.instance.redactExistingLogFiles();
      await seedOldLog(); // 迁移完成之后才出现的原文（正常不会发生）

      await AppLogger.instance.redactExistingLogFiles();

      expect(await logFile.readAsString(), contains('SECRET'));
    });

    test('迁移期间来的新行排在后面，不会被改名覆盖吞掉', () async {
      await seedOldLog();

      final migration = AppLogger.instance.redactExistingLogFiles();
      final appended = AppLogger.instance.append('new line after upgrade');
      await Future.wait([migration, appended]);

      final content = await logFile.readAsString();
      expectRedacted(content);
      expect(content.trimRight().split('\n').last, 'new line after upgrade');
    });

    test('旧日志里有非法 UTF-8 也照样迁移，不抛异常', () async {
      await logFile.writeAsBytes([
        ...'$rawLine\n'.codeUnits,
        0xE9, 0xA6, // 截断的多字节字符
        ...'\nplain line\n'.codeUnits,
      ]);

      await AppLogger.instance.redactExistingLogFiles();

      final content = await logFile.readAsString();
      expect(content, isNot(contains('SECRET')));
      expect(content, contains('plain line'));
    });

    test('initAppLogger 启动时触发迁移', () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      });
      await seedOldLog();

      await initAppLogger();
      await AppLogger.instance.flush();

      expectRedacted(await logFile.readAsString());
    });

    test('导出副本：没迁移过的旧日志也脱敏，原文件不交出去', () async {
      await seedOldLog();
      final outDir = Directory('${tempDir.path}/share');

      final copy = await AppLogger.instance.writeRedactedCopy(outDir);

      expect(copy.path, isNot(logFile.path));
      expect(copy.parent.path, outDir.path);
      expectRedacted(await copy.readAsString());
    });
  });

  group('日志目录消失时 append 不能抛异常', () {
    test('目录被删掉之后再 append，静默丢弃而不是抛 PathNotFoundException', () async {
      final tmp = await Directory.systemTemp.createTemp('app_logger_gone_');
      AppLogger.configureForTesting(
        resolveLogFile: () async => File('${tmp.path}/app.log'),
      );
      addTearDown(AppLogger.resetForTesting);
      await AppLogger.instance.append('第一行');

      // 模拟"日志目录在两次写入之间消失"
      await tmp.delete(recursive: true);

      // 不抛才算通过。这条路径的调用方是 FlutterError.onError 里的
      // fire-and-forget，抛出来就是一条没人接的异步异常，而且是在处理另一个
      // 错误的过程中产生的，堆栈跟真正的故障毫无关系。
      await AppLogger.instance.append('目录已经没了');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────
// 追加：日志目录消失时不能抛异常
//
// CI 上真实发生过：`FlutterError.onError` 里的 fire-and-forget append 活得比
// 测试还长，等它执行时临时目录已经被 tearDown 删掉，`file.length()` 抛
// PathNotFoundException，报在一条**已经结束**的测试上（"This test failed after
// it had already completed"）——排查时极具误导性。
//
// 生产上同样会发生：用户清 App 数据、系统清理临时目录、外部工具删目录。
