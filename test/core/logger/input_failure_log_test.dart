import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/logger/input_failure_log.dart';
import 'package:clashmiao/features/config/application/network_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 用户输入类流程（深链、Geo 下载地址、设置导入、备份）的失败日志：异常消息里
/// 就是用户给的内容（订阅地址、自定义下载地址、导入文本片段、文件路径）。官网
/// 与本项目仓库前缀下的 URL 会被脱敏器当作白名单保留路径，所以来源侧不写异常
/// 原文：落盘只有标签 + 异常类型 + 堆栈。
const _officialSub = 'https://clashmiao.com/sub/short';
const _userUrl = 'https://sub.example.com/s/ab12';
const _message = 'secret-user-message';

final _refProvider = Provider<Ref>((ref) => ref);

class _FakeAppLinks implements AppLinks {
  _FakeAppLinks(this._stream);

  final Stream<Uri> _stream;

  @override
  Stream<Uri> get uriLinkStream => _stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void _expectClean(String line) {
  for (final leak in [
    _officialSub,
    '/sub/short',
    _userUrl,
    'example.com',
    'ab12',
    _message,
    'clashmiao.com',
  ]) {
    expect(line, isNot(contains(leak)), reason: '$leak in $line');
  }
}

void main() {
  late List<AppFailureRecord> records;

  setUp(() {
    records = [];
    debugAppFailureSink = records.add;
  });
  tearDown(() => debugAppFailureSink = null);

  group('logInputFailure', () {
    test('只写标签、异常类型与堆栈：FormatException 的 source 不落盘', () {
      logInputFailure(
        'settings.importJson',
        FormatException(_message, '{"u":"$_officialSub"}', 5),
        StackTrace.current,
      );
      final line = records.single.line;
      expect(line, contains('[ERROR] settings.importJson: FormatException'));
      _expectClean(line);
    });

    test('geo 自定义下载地址：DioException 的 uri / message 不落盘', () {
      logInputFailure(
        'geo.update',
        DioException(
          requestOptions: RequestOptions(path: _userUrl),
          message: '$_message $_officialSub',
        ),
        StackTrace.empty,
      );
      final line = records.single.line;
      expect(line, contains('geo.update: InputFailureSummary'.split(':')[0]));
      expect(line, contains('DioException'));
      _expectClean(line);
    });

    test('backup：文件系统异常的路径不落盘', () {
      logInputFailure(
        'backup.applyRestore',
        FileSystemException(_message, '/Users/someone/$_officialSub'),
      );
      final line = records.single.line;
      expect(line, contains('FileSystemException'));
      expect(line, isNot(contains('someone')));
      _expectClean(line);
    });

    test('不向外抛', () {
      debugAppFailureSink = (_) => throw StateError('sink failed');
      expect(() => logInputFailure('x', StateError('y')), returnsNormally);
    });
  });

  group('真实调用点', () {
    test('settings.importJson：非法 JSON 里的 URL 不进日志', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = NetworkSettingsNotifier(prefs);

      final result = await notifier.importJson(
        '{"u":"$_officialSub" $_message',
      );

      expect(result.hasParseError, isTrue);
      final line = records.single.line;
      expect(line, contains('settings.importJson: FormatException'));
      _expectClean(line);
    });

    test('deepLink.stream：流错误里的 URL 不进日志', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = StreamController<Uri>();
      addTearDown(controller.close);
      final service = DeepLinkService(
        container.read(_refProvider),
        appLinks: _FakeAppLinks(controller.stream),
      );
      await service.start();

      controller.addError(
        DioException(
          requestOptions: RequestOptions(path: _officialSub),
          message: '$_message $_userUrl',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.dispose();

      final line = records.single.line;
      expect(line, contains('deepLink.stream: DioException'));
      _expectClean(line);
    });
  });
}
