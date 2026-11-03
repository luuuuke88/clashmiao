import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/logger/log_redactor.dart'
    show kLogRedactionVersion;
import 'package:clashmiao/features/connection/model/connection_failure.dart';
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
      // 堆栈保留；debug 构建里 file:/// 本机路径整条换成 <url>，包名帧原样。
      expect(content, contains('#1      Declarer.test'));
      expect(content, isNot(contains('file:///')));
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
      // 排障需要的东西都在：异常类别、底层异常、堆栈帧；订阅地址整条是 <url>。
      expect(content, contains('DioException'));
      expect(content, contains('HttpException: Connection closed'));
      expect(content, contains('<url>'));
      expect(content, contains('#1      Declarer.test'));
      expect(content, isNot(contains('file:///')));
    });

    test('端到端：订阅短 token、节点 host:port 与 IP 一律不进 app.log', () async {
      const subUrl = 'https://sub.example.org/s/ab12';
      final error = DioException(
        requestOptions: RequestOptions(path: subUrl),
        error: const SocketException(
          'Connection refused',
          address: null,
          port: 8443,
        ),
        message:
            'The connection errored: dial tcp example.net:443 and '
            '198.51.100.7:8443 and [2001:db8::1]:443 via $subUrl?flag=android',
      );
      logAppFailure('proxies.latencyTest', error, StackTrace.current);
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      for (final leak in [
        'sub.example.org',
        'ab12',
        'example.net',
        '198.51.100.7',
        '2001:db8',
      ]) {
        expect(content, isNot(contains(leak)), reason: leak);
      }
      expect(content, contains('[ERROR] proxies.latencyTest: DioException'));
      expect(content, contains('<url>'));
      expect(content, contains('<addr>'));
    });

    test('连接失败对象：对象里保留原文，写进 app.log 时才脱敏', () async {
      const text =
          'prepare https://sub.example.org/s/ab12 via 198.51.100.7:8443';
      const failure = UnexpectedFailure(text);

      logAppFailure('connection.prepare', failure);
      await AppLogger.instance.flush();

      expect(failure.message, text);
      final content = await logFile.readAsString();
      expect(content, contains('UnexpectedFailure(prepare <url> via <addr>)'));
      for (final leak in ['sub.example.org', 'ab12', '198.51.100.7']) {
        expect(content, isNot(contains(leak)), reason: leak);
      }
    });

    test('结构化的错误先按键名脱敏再转文本：跨行的秘密值也不泄露', () async {
      // 纯文本规则只遮到行尾；值里带换行时，第二行要靠结构化脱敏兜住。
      logAppFailure('profiles.parse', {
        'server': 'h.example.test',
        'password': 'first line\nSECRET second line',
      });
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, isNot(contains('SECRET')));
      expect(
        content,
        contains('[ERROR] profiles.parse: {server: h.example.test'),
      );
    });

    test('结构化错误里有循环引用：不抛异常，秘密不进日志', () async {
      final error = <String, Object?>{'password': 'SECRET', 'server': 'h'};
      error['self'] = error;

      expect(() => logAppFailure('profiles.parse', error), returnsNormally);
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, isNot(contains('SECRET')));
      expect(content, contains('[ERROR] profiles.parse:'));
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
      expect(content, contains('<url>'));
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

    test('全局兜底：未捕获的 Dio 异常里的请求 URI 与节点地址不进 app.log', () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      });
      DioException uncaught(String tag) => DioException(
        requestOptions: RequestOptions(
          path: 'https://sub.example.org/s/$tag?flag=android',
        ),
        message: 'connection error to 198.51.100.7:8443',
      );

      await initAppLogger();
      FlutterError.onError!(FlutterErrorDetails(exception: uncaught('tok1')));
      PlatformDispatcher.instance.onError!(
        uncaught('tok2'),
        StackTrace.current,
      );
      await AppLogger.instance.flush();

      final content = await logFile.readAsString();
      expect(content, contains('[FlutterError]'));
      expect(content, contains('[PlatformDispatcher]'));
      for (final leak in ['sub.example.org', 'tok1', 'tok2', '198.51.100.7']) {
        expect(content, isNot(contains(leak)), reason: leak);
      }
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

  group('脱敏规则升级：旧规则下写下的日志直接丢弃', () {
    const rawLine =
        '2026-06-01T10:00:00.000 [ERROR] proxies.select proxy -> '
        'node.example.com: SelectionFailed(exception, node.example.com not found)';

    tearDown(resetAppLoggerInitializedForTesting);

    Future<void> seedOldLog() async {
      await logFile.writeAsString('$rawLine\nplain line\n');
    }

    test('旧 app.log 与 app.log.<数字> 被丢弃，只留一行固定说明；别的文件不碰', () async {
      await seedOldLog();
      final rotated = File('${tempDir.path}/app.log.1');
      await rotated.writeAsString('$rawLine\n');
      final unrelated = File('${tempDir.path}/notes.txt');
      await unrelated.writeAsString(rawLine);
      // 同后缀但不是日志自己的临时文件：Documents 不是日志专用目录，不能删。
      final foreignTemp = File('${tempDir.path}/notes.redacting');
      await foreignTemp.writeAsString('keep me');
      final rotatedTemp = File('${tempDir.path}/app.log.1.redacting');
      await rotatedTemp.writeAsString(rawLine);
      // 上次清理被打断留下的临时文件。
      final leftover = File('${tempDir.path}/app.log.redacting');
      await leftover.writeAsString(rawLine);

      await AppLogger.instance.discardOutdatedLogFiles();

      expect(await logFile.readAsString(), '$kLogResetNotice\n');
      expect(rotated.existsSync(), isFalse);
      expect(await unrelated.readAsString(), rawLine);
      expect(leftover.existsSync(), isFalse);
      expect(rotatedTemp.existsSync(), isFalse);
      expect(await foreignTemp.readAsString(), 'keep me');
    });

    test('旧版本标记也算旧日志：版本 8 的日志升级后不再存在', () async {
      await seedOldLog();
      await File('${tempDir.path}/.app_log_redaction').writeAsString('8');

      await AppLogger.instance.discardOutdatedLogFiles();

      final content = await logFile.readAsString();
      expect(content, isNot(contains('node.example.com')));
      expect(content, isNot(contains('proxies.select')));
      expect(content, '$kLogResetNotice\n');
    });

    test('升级后分享出去的副本里没有旧日志的裸域名节点名', () async {
      await seedOldLog();
      await AppLogger.instance.discardOutdatedLogFiles();

      final copy = await AppLogger.instance.writeRedactedCopy(
        Directory('${tempDir.path}/share'),
      );

      final shared = await copy.readAsString();
      expect(shared, isNot(contains('node.example.com')));
      expect(shared, contains(kLogResetNotice));
    });

    test('幂等：重复运行不再变化，说明不会重复写', () async {
      await seedOldLog();
      await AppLogger.instance.discardOutdatedLogFiles();
      await AppLogger.instance.append('new line after upgrade');
      final first = await logFile.readAsString();

      await AppLogger.instance.discardOutdatedLogFiles();

      expect(await logFile.readAsString(), first);
    });

    test('只跑一次：完成标记在且版本一致时，之后的内容不被动', () async {
      await AppLogger.instance.discardOutdatedLogFiles();
      await seedOldLog(); // 清理完成之后才出现的内容（正常不会发生）

      await AppLogger.instance.discardOutdatedLogFiles();

      expect(await logFile.readAsString(), contains('node.example.com'));
    });

    test('没有旧内容（首次安装）：不写说明，只写标记', () async {
      await AppLogger.instance.discardOutdatedLogFiles();

      expect(logFile.existsSync() ? await logFile.readAsString() : '', isEmpty);
      expect(
        await File('${tempDir.path}/.app_log_redaction').readAsString(),
        '$kLogRedactionVersion',
      );
    });

    test('清理期间来的新行排在说明后面，不会被改名覆盖吞掉', () async {
      await seedOldLog();

      final cleanup = AppLogger.instance.discardOutdatedLogFiles();
      final appended = AppLogger.instance.append('new line after upgrade');
      await Future.wait([cleanup, appended]);

      final lines = (await logFile.readAsString()).trimRight().split('\n');
      expect(lines, [kLogResetNotice, 'new line after upgrade']);
    });

    test('旧日志里有非法 UTF-8 也照样丢弃，不抛异常', () async {
      await logFile.writeAsBytes([
        ...'$rawLine\n'.codeUnits,
        0xE9, 0xA6, // 截断的多字节字符
        ...'\nplain line\n'.codeUnits,
      ]);

      await AppLogger.instance.discardOutdatedLogFiles();

      expect(await logFile.readAsString(), '$kLogResetNotice\n');
    });

    test('initAppLogger 启动时触发清理', () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
        PlatformDispatcher.instance.onError = previousPlatform;
      });
      await seedOldLog();

      await initAppLogger();
      await AppLogger.instance.flush();

      expect(await logFile.readAsString(), '$kLogResetNotice\n');
    });

    test('导出副本：每次都过脱敏器，原文件不交出去', () async {
      await AppLogger.instance.discardOutdatedLogFiles(); // 标记已是当前版本
      await logFile.writeAsString(
        'fetch https://clashmiao.com/sub/short failed\n',
      );
      final outDir = Directory('${tempDir.path}/share');

      final copy = await AppLogger.instance.writeRedactedCopy(outDir);

      expect(copy.path, isNot(logFile.path));
      expect(copy.parent.path, outDir.path);
      expect(await copy.readAsString(), 'fetch https://clashmiao.com failed\n');
    });

    group('清理失败时旧日志不得进入分享副本', () {
      Future<String> shareCopy() async {
        final copy = await AppLogger.instance.writeRedactedCopy(
          Directory('${tempDir.path}/share'),
        );
        return copy.readAsString();
      }

      test('清理失败 + 旧日志含裸域名节点名：副本不含任何 app.log 内容，只有固定说明', () async {
        await seedOldLog();
        AppLogger.instance.debugBeforeDiscard = () async =>
            throw const FileSystemException('simulated failure');

        // 启动时的清理失败，被吞掉；旧内容仍在盘上。
        await AppLogger.instance.discardOutdatedLogFiles();
        expect(await logFile.readAsString(), contains('node.example.com'));

        final shared = await shareCopy();

        expect(shared, '$kLogShareUnavailableNotice\n');
        expect(shared, isNot(contains('node.example.com')));
        expect(shared, isNot(contains('proxies.select')));
        expect(shared, isNot(contains('plain line')));
      });

      test('分享时重试清理成功：副本是正常脱敏内容，旧内容不存在', () async {
        await seedOldLog();
        var failures = 1;
        AppLogger.instance.debugBeforeDiscard = () async {
          if (failures-- > 0) {
            throw const FileSystemException('simulated failure');
          }
        };
        await AppLogger.instance.discardOutdatedLogFiles(); // 第一次失败

        final shared = await shareCopy();

        expect(shared, '$kLogResetNotice\n');
        expect(shared, isNot(contains('node.example.com')));
        expect(shared, isNot(contains(kLogShareUnavailableNotice)));
        expect(await logFile.readAsString(), '$kLogResetNotice\n');

        // 之后新写的行正常进入副本。
        await AppLogger.instance.append(
          'fetch https://clashmiao.com/sub/short failed',
        );
        expect(
          await shareCopy(),
          '$kLogResetNotice\nfetch https://clashmiao.com failed\n',
        );
      });

      test('日志目录不存在：建出目录、写下当前版本标记，副本是正常（空）内容', () async {
        final missingDir = Directory('${tempDir.path}/fresh/logs');
        final missingLog = File('${missingDir.path}/app.log');
        AppLogger.configureForTesting(resolveLogFile: () async => missingLog);
        expect(missingDir.existsSync(), isFalse);

        final shared = await shareCopy();

        expect(shared, isEmpty);
        expect(shared, isNot(contains(kLogShareUnavailableNotice)));
        expect(missingDir.existsSync(), isTrue);
        expect(
          await File('${missingDir.path}/.app_log_redaction').readAsString(),
          '$kLogRedactionVersion',
        );

        // 之后新写的行正常进入副本。
        await AppLogger.instance.append('plain line');
        expect(await shareCopy(), 'plain line\n');
      });

      test('日志目录建不出来（父路径是个文件）：不返回已是当前版本，副本只有固定说明', () async {
        final blocker = File('${tempDir.path}/blocker');
        await blocker.writeAsString('not a directory');
        AppLogger.configureForTesting(
          resolveLogFile: () async => File('${blocker.path}/logs/app.log'),
        );

        expect(await shareCopy(), '$kLogShareUnavailableNotice\n');
      });

      test('日志目录不存在 + 标记写入失败（注入）：副本只有固定说明，不留标记', () async {
        final missingDir = Directory('${tempDir.path}/fresh2');
        AppLogger.configureForTesting(
          resolveLogFile: () async => File('${missingDir.path}/app.log'),
        );
        AppLogger.instance.debugBeforeDiscard = () async =>
            throw const FileSystemException('simulated failure');

        expect(await shareCopy(), '$kLogShareUnavailableNotice\n');
        expect(
          File('${missingDir.path}/.app_log_redaction').existsSync(),
          isFalse,
        );
      });

      test('重试仍失败：每次分享都只有固定说明，不会死锁', () async {
        await seedOldLog();
        AppLogger.instance.debugBeforeDiscard = () async =>
            throw const FileSystemException('simulated failure');

        expect(await shareCopy(), '$kLogShareUnavailableNotice\n');
        expect(await shareCopy(), '$kLogShareUnavailableNotice\n');
      });

      test('正常路径（标记已是当前版本）：行为不变，读 app.log 过脱敏器', () async {
        await AppLogger.instance.discardOutdatedLogFiles();
        await AppLogger.instance.append(
          'fetch https://clashmiao.com/sub/short failed',
        );

        expect(await shareCopy(), 'fetch https://clashmiao.com failed\n');
      });
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
