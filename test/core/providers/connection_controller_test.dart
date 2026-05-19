import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把 path_provider 的所有 MethodChannel 调用劫持到一个临时目录。
Future<Directory> _mockPathProvider() async {
  final tmp = await Directory.systemTemp.createTemp('cc_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
  return tmp;
}

/// 非 stub spy，控制 watchStatus 流，记录方法调用次数。
class _SpyBoxService implements BoxService {
  final statusController = const Stream<BoxStatus>.empty().asBroadcastStream();

  int startCalls = 0;
  int stopCalls = 0;
  int changeConfigCalls = 0;

  @override
  Future<void> start(String path, {String name = ''}) async {
    startCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> changeConfigOptions(String json) async {
    changeConfigCalls++;
  }

  // 其余方法最小实现
  @override
  Future<void> init() async {}
  @override
  Future<void> setup(AppDirectories d, {bool debug = false}) async {}
  @override
  Future<String?> validateConfig(
    String a,
    String b, {
    bool debug = false,
  }) async => null;
  @override
  Future<void> restart(String path, {String name = ''}) async {}
  @override
  Future<void> selectOutbound(String g, String o) async {}
  @override
  Future<void> urlTest(String g) async {}
  @override
  Stream<BoxStatus> watchStatus() => statusController;
  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String p) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => const Stream.empty();
  @override
  Future<void> resetTunnel() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionController', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(StubBoxService()),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
    });

    tearDown(() => container.dispose());

    test('初始状态 BoxStopped', () {
      final s = container.read(connectionControllerProvider).valueOrNull;
      expect(s, isA<BoxStopped>());
    });

    test('stub service 下 connect 直接返回，状态不变', () async {
      await container.read(connectionControllerProvider.notifier).connect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('stub service 下 disconnect 直接返回，状态不变', () async {
      await container.read(connectionControllerProvider.notifier).disconnect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('stub service 下 reconnect 直接返回', () async {
      await container.read(connectionControllerProvider.notifier).reconnect();
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });

    test('toggle 从 BoxStopped → 调 connect 路径（stub 下无副作用）', () async {
      await container.read(connectionControllerProvider.notifier).toggle();
      // stub 不会真的连，状态保持
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
    });
  });

  group('ConnectionController spy 路径', () {
    test('spy service 下 connect 无激活订阅时早返回（不调 start）', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);

      await container.read(connectionControllerProvider.notifier).connect();

      expect(spy.startCalls, 0, reason: '无激活订阅不应该调 start');
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );
      container.dispose();
    });
  });
}
