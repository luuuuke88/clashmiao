import 'dart:io';

import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/logs/widget/logs_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/temp_dirs.dart';

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录（同
/// test/core/providers/connection_controller_test.dart 里的写法）。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp('logs_page_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

Future<Widget> _host({bool? debugShowShareMenu}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxLogStreamProvider.overrideWith(
        (_) => Stream.value(const [
          '2026-06-12 23:58:01 INFO service started',
          '2026-06-12 23:58:02 DEBUG route rule matched proxy',
          '2026-06-12 23:58:03 WARN dns fallback used',
          '2026-06-12 23:58:04 ERROR outbound dial failed: timeout',
          '\x1B[33mWARN\x1B[0m[0000] inbound/tun[tun-in]: bind forwarder',
        ]),
      ),
    ],
  );
  await container.read(sharedPreferencesProvider.future);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: LogsPage(debugShowShareMenu: debugShowShareMenu),
    ),
  );
}

void main() {
  testWidgets('LogsPage renders log controls and rows', (tester) async {
    await tester.pumpWidget(await _host(debugShowShareMenu: false));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('日志'), findsOneWidget);
    expect(find.byIcon(FluentIcons.pause_20_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.delete_lines_20_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.more_vertical_20_regular), findsNothing);
    expect(find.text('筛选'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('INFO'), findsOneWidget);
    expect(find.text('service started'), findsOneWidget);
    expect(find.text('ERROR'), findsOneWidget);
    expect(find.text('outbound dial failed: timeout'), findsOneWidget);
    expect(find.textContaining('[33m'), findsNothing);
    expect(find.text('inbound/tun[tun-in]: bind forwarder'), findsOneWidget);
    expect(find.text('复制全部'), findsNothing);
  });

  testWidgets('LogsPage desktop share menu 同时暴露"分享核心日志"和"分享应用日志"两个选项', (
    tester,
  ) async {
    await tester.pumpWidget(await _host(debugShowShareMenu: true));
    await tester.pump(const Duration(milliseconds: 250));

    // flutter test 默认把 defaultTargetPlatform 判定为 android（见
    // adaptive_icon_test.dart 的说明），所以"更多"菜单图标在这里渲染的
    // 是纵向三点（more_vertical），而不是之前硬编码的横向三点。
    await tester.tap(find.byIcon(FluentIcons.more_vertical_20_regular));
    await tester.pumpAndSettle();

    // 核心验证点：这必须是两个真正不同的入口，而不是同一份数据挂两个
    // 名字——"分享核心日志"分享 sing-box 核心日志，"分享应用日志"分享
    // AppLogger 落地的本地 app.log（见下面 writeCoreLogsTempFile /
    // resolveAppLogSharePath 的单测，验证两者数据源不同）。
    expect(find.text('分享核心日志'), findsOneWidget);
    expect(find.text('分享应用日志'), findsOneWidget);
    expect(find.text('复制全部'), findsNothing);
  });

  group('核心日志 vs 应用日志分享：两个真正不同的数据源', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _mockPathProvider();
      AppLogger.configureForTesting(
        resolveLogFile: () async => File('${tempDir.path}/app.log'),
      );
    });

    tearDown(() async {
      AppLogger.resetForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await deleteTempDirBestEffort(tempDir);
    });

    test('"分享核心日志"和"分享应用日志"用的是不同的文件路径', () async {
      await AppLogger.instance.append('app-layer log line');

      final corePath = await writeCoreLogsTempFile(['core log line one']);
      final appPath = await resolveAppLogSharePath();

      expect(
        corePath,
        isNot(equals(appPath)),
        reason: '两个分享入口必须来自不同文件，否则就是同一份数据挂两个名字',
      );

      final coreContent = await File(corePath).readAsString();
      final appContent = await File(appPath).readAsString();
      expect(coreContent, contains('core log line one'));
      expect(coreContent, isNot(contains('app-layer log line')));
      expect(appContent, contains('app-layer log line'));
      expect(appContent, isNot(contains('core log line one')));
    });
  });
}
