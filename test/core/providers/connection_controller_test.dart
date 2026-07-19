import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
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

/// 非 stub spy，控制 watchStatus/watchNetworkChanged 流，记录方法调用次数。
class _SpyBoxService implements BoxService {
  final statusStreamController = StreamController<BoxStatus>.broadcast();
  final networkChangedController = StreamController<void>.broadcast();
  final alertStreamController = StreamController<BoxAlert>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int changeConfigCalls = 0;
  int restartCalls = 0;

  /// 若非 null，每次调用 stop() 都会 throw 这个异常（模拟 stop 持续失败，
  /// 用于测试 disconnect() "重试也失败" 时绝不能谎报 BoxStopped 的核心不变量）。
  Object? stopError;

  /// 前 N 次调用 stop() 会 throw（然后自减），之后正常返回。
  /// 用于模拟 disconnect() 里 "首次失败、强制清理重试后成功" 的分支。
  int stopFailTimes = 0;

  /// 若非 null，每次调用 start() 都会 throw 这个异常。用于模拟 connect() 里
  /// try/catch 捕获到常见 Dart 异常（SocketException / TimeoutException 等）
  /// 时，connectionErrorProvider 应该写入分类后的本地化文案，而不是原始
  /// e.toString()。
  Object? startError;

  @override
  Future<void> start(String path, {String name = ''}) async {
    startCalls++;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (stopFailTimes > 0) {
      stopFailTimes--;
      throw Exception('mock stop failure (transient #$stopCalls)');
    }
    if (stopError != null) {
      throw stopError!;
    }
  }

  @override
  Future<void> restart(String path, {String name = ''}) async {
    restartCalls++;
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
  Future<void> selectOutbound(String g, String o) async {}
  @override
  Future<void> urlTest(String g) async {}
  @override
  Stream<BoxStatus> watchStatus() => statusStreamController.stream;
  @override
  Stream<BoxAlert> watchAlerts() => alertStreamController.stream;
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String p) async => null;
  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => networkChangedController.stream;
  @override
  Future<void> resetTunnel() async {}
}

/// [StoreReviewService] 真实实现最终会调到私有构造单例 [InAppReview]，
/// 测试用这个假实现覆盖 [storeReviewServiceProvider]，只记录调用次数，
/// 不触碰任何原生插件。
class _FakeStoreReviewService extends StoreReviewService {
  _FakeStoreReviewService(super.ref);

  int maybeRequestReviewCalls = 0;

  @override
  Future<void> maybeRequestReview() async {
    maybeRequestReviewCalls++;
  }
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

    test('网络变更触发退避重连时，用户手动断开应阻止自动重连把连接顶回去', () async {
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
      final repo = await container.read(profileRepositoryProvider.future);

      // 种一个激活订阅 + 可被 RuntimeConfigBuilder 成功解析的最小配置文件，
      // 否则 reconnect() 会在 repo.getActive()==null 或配置文件不存在时提前
      // return，永远走不到 _boxService.restart，测试就测不出真实的修复效果
      // （见 test/core/config/runtime_config_builder_test.dart 里同款最小 fixture）。
      const profileId = 'net-change-profile';
      await repo.upsert({
        'id': profileId,
        'name': '网络切换测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      final controller = container.read(connectionControllerProvider.notifier);

      // 模拟 BoxStarted（不走 connect()，直接推流，绕开配置/权限等无关前提）
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '前置条件：必须先进入已连接态才能触发 autoReconnect',
      );

      // 触发网络变更 → _networkSub 命中 BoxStarted → 启动 _autoReconnect
      // 退避循环（第一档延迟 1 秒）
      spy.networkChangedController.add(null);
      await Future<void>.delayed(Duration.zero);

      // 退避窗口内（1 秒延迟尚未到期），用户手动断开
      await controller.disconnect();

      // disconnect() 自身有 1.5s 展示动画，await 完成时已经跨过 autoReconnect
      // 第一档 1s 检查点。修复前：循环在检查点看到 state 是 BoxStopping（不是
      // BoxStarted），旧的"已恢复"守卫判断为假，继续调用 reconnect() →
      // restart，把用户刚断开的连接顶回去。修复后：_manualDisconnect 守卫
      // 在检查点为真，循环直接 return，不再调用 restart/start。
      expect(spy.restartCalls, 0, reason: '手动断开后 autoReconnect 不应该把连接顶回去');
      expect(spy.startCalls, 0);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });

    test(
      'disconnect 持续失败时，state 绝不能谎报 BoxStopped（核心不变量）',
      () async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        });
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        spy.stopError = Exception('mock stop failure (persistent)');
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (_) => Future.value(prefs),
            ),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        await container.read(profileRepositoryProvider.future);
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        // 模拟已连接态（跳过真实 connect 流程，直接推流，绕开配置/权限等无关前提）
        spy.statusStreamController.add(const BoxStarted());
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStarted>(),
          reason: '前置条件：必须先进入已连接态才能测试断开失败',
        );

        await controller.disconnect();

        // 断言顺序刻意把 "state 不能是 BoxStopped" 放在最前面：
        // 修复前的代码会在这里失败，失败原因精确对应 bug 本身
        // （catch 分支谎报 state = BoxStopped）。
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isNot(isA<BoxStopped>()),
          reason:
              'stop 持续失败时内核可能还在跑，UI 绝不能谎报已断开——'
              '这是本 App 最不能接受的故障形态（界面显示断开，流量还在走）',
        );
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStarted>(),
          reason: '诚实的兜底状态应该是仍连接，让用户能再次点击断开重试',
        );
        expect(
          container.read(connectionErrorProvider),
          isNotNull,
          reason: '断开失败必须让用户能看到错误，不能静默吞掉',
        );
        expect(
          spy.stopCalls,
          2,
          reason: '强制清理应该自动重试恰好一次（初次 + 1 次重试），不是无限重试',
        );

        container.dispose();
      },
    );

    test(
      'disconnect 首次失败但重试成功时，强制清理生效，诚实回到 BoxStopped',
      () async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        });
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        spy.stopFailTimes = 1; // 只有第一次调用失败，重试那次会成功
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (_) => Future.value(prefs),
            ),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        await container.read(profileRepositoryProvider.future);
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        spy.statusStreamController.add(const BoxStarted());
        await Future<void>.delayed(Duration.zero);

        await controller.disconnect();

        expect(spy.stopCalls, 2, reason: '第一次失败后应该自动重试一次');
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStopped>(),
          reason: '重试确认停掉了，应该诚实地报告 BoxStopped',
        );

        container.dispose();
      },
    );

    test(
      'disconnect 一次成功时 state 应该是 BoxStopped（回归：正常路径不能被改坏）',
      () async {
        final tmp = await _mockPathProvider();
        addTearDown(() async {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        });
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (_) => Future.value(prefs),
            ),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        await container.read(profileRepositoryProvider.future);
        final controller = container.read(
          connectionControllerProvider.notifier,
        );

        spy.statusStreamController.add(const BoxStarted());
        await Future<void>.delayed(Duration.zero);

        await controller.disconnect();

        expect(spy.stopCalls, 1, reason: '正常路径不应该触发任何重试');
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStopped>(),
        );

        container.dispose();
      },
    );
  });

  group('配置变更触发的自动重连应该让 UI 能感知到（不是纯静默）', () {
    test('已连接时网络设置变更 → configChangeReconnectNoticeProvider 应该变化一次', () async {
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
      // 触发 ConnectionController 构造，订阅 networkSettingsProvider。
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStarted>(),
        reason: '前置条件：必须已连接，网络设置变更才会触发重连',
      );

      final before = container.read(configChangeReconnectNoticeProvider);

      await container.read(networkSettingsProvider.notifier).setMixedPort(
        23456,
      );
      await Future<void>.delayed(Duration.zero);

      final after = container.read(configChangeReconnectNoticeProvider);
      expect(
        after,
        isNot(equals(before)),
        reason:
            '配置变更触发的自动重连之前是纯静默的，用户可能误以为网络抖动；'
            'UI 需要能感知到这次重连发生（用来弹一条轻提示），因此这个 '
            'nonce 必须在每次触发时变化',
      );

      container.dispose();
    });

    test('未连接时网络设置变更 → 不触发重连通知（保持既有"未连接时改设置无副作用"行为）', () async {
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
      container.read(connectionControllerProvider.notifier);

      final before = container.read(configChangeReconnectNoticeProvider);

      await container.read(networkSettingsProvider.notifier).setMixedPort(
        34567,
      );
      await Future<void>.delayed(Duration.zero);

      final after = container.read(configChangeReconnectNoticeProvider);
      expect(after, equals(before), reason: '未连接时改设置不应该触发重连提示');

      container.dispose();
    });
  });

  group('首次成功连接触发商店评分请求', () {
    test('watchStatus 推 BoxStarted（首次进入已连接态）→ 调用一次 maybeRequestReview', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      late _FakeStoreReviewService fakeReview;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          storeReviewServiceProvider.overrideWith((ref) {
            fakeReview = _FakeStoreReviewService(ref);
            return fakeReview;
          }),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      // 触发 ConnectionController 构造，订阅 watchStatus。
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeReview.maybeRequestReviewCalls,
        1,
        reason: '首次真正进入 BoxStarted（跟触觉反馈同一个触发点）应该请求一次商店评分',
      );

      container.dispose();
    });

    test('同一次连接内重复推送 BoxStarted → 不应该重复调用（wasStarted 守卫）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      late _FakeStoreReviewService fakeReview;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          storeReviewServiceProvider.overrideWith((ref) {
            fakeReview = _FakeStoreReviewService(ref);
            return fakeReview;
          }),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeReview.maybeRequestReviewCalls,
        1,
        reason: '同一段连接内重复推送同样的 BoxStarted 不应该重复触发',
      );

      container.dispose();
    });

    test('断开后再次连接（第二次进入 BoxStarted）→ ConnectionController 会再调用一次'
        '（"只弹一次"的持久化保护由 StoreReviewService 自己负责，不是这里）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      late _FakeStoreReviewService fakeReview;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          storeReviewServiceProvider.overrideWith((ref) {
            fakeReview = _FakeStoreReviewService(ref);
            return fakeReview;
          }),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStopped());
      await Future<void>.delayed(Duration.zero);
      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeReview.maybeRequestReviewCalls,
        2,
        reason:
            'ConnectionController 每次真正"进入" BoxStarted 都调用一次——'
            '"这辈子只弹一次"的持久化保护是 StoreReviewService 内部的职责'
            '（见 store_review_service_test.dart），不应该在这里重复实现',
      );

      container.dispose();
    });
  });

  group('ConnectionController fatal alert 上报（数据分析开关）', () {
    test('数据分析开关关闭（默认值）时，fatal alert 不应该触发 Sentry 上报', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final reported = <BoxAlert>[];
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
          fatalAlertReporterProvider.overrideWithValue(reported.add),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      // 触发 ConnectionController 构造，订阅 watchAlerts。
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.startService, message: 'boom'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        reported,
        isEmpty,
        reason: '数据分析开关关闭（默认值）时，fatal alert 不应该调用 Sentry 上报',
      );
      // 强制回到 BoxStopped + 解锁 transition 等既有逻辑不应该受影响。
      expect(
        container.read(connectionControllerProvider).valueOrNull,
        isA<BoxStopped>(),
      );

      container.dispose();
    });

    test(
      '数据分析开关开启时，fatal alert 仍然正常触发上报（回归：不能把该上报的场景误判为不上报）',
      () async {
        SharedPreferences.setMockInitialValues({
          'clashmiao_analytics_enabled': true,
        });
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final reported = <BoxAlert>[];
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (_) => Future.value(prefs),
            ),
            boxServiceProvider.overrideWithValue(spy),
            fatalAlertReporterProvider.overrideWithValue(reported.add),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        container.read(connectionControllerProvider.notifier);

        spy.alertStreamController.add(
          const BoxAlert(type: BoxAlertType.createService, message: 'boom'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          reported,
          hasLength(1),
          reason: '数据分析开关开启时，fatal alert 应该正常上报一次',
        );
        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStopped>(),
        );

        container.dispose();
      },
    );
  });

  group('ConnectionController fatal alert fail-safe 拆除（Dart 侧纵深兜底）', () {
    test(
      '收到启动失败 alert 时，除了回到 BoxStopped，还必须主动要求内核 stop()（幂等兜底）',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final spy = _SpyBoxService();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (_) => Future.value(prefs),
            ),
            boxServiceProvider.overrideWithValue(spy),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        // 触发 ConnectionController 构造，订阅 watchAlerts。
        container.read(connectionControllerProvider.notifier);

        spy.alertStreamController.add(
          const BoxAlert(type: BoxAlertType.startService, message: 'boom'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(connectionControllerProvider).valueOrNull,
          isA<BoxStopped>(),
          reason: '启动失败 alert 必须把 UI 状态强制回到 BoxStopped',
        );
        expect(
          spy.stopCalls,
          1,
          reason:
              '仅把 UI 掰回 BoxStopped 不够：底层某个终结路径若又漏了清理，'
              'Dart 必须主动要求内核收尾（拆 tun），否则会复现"UI 显示已断开'
              '但设备仍被黑洞"这一最隐蔽的故障形态。',
        );

        container.dispose();
      },
    );

    test('非致命 alert（如 VPN 权限请求）不应该触发 stop()，也不改动状态', () async {
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
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.requestVpnPermission),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        spy.stopCalls,
        0,
        reason: '非启动失败类 alert 不应触发兜底 stop()，避免误伤正常授权流程',
      );

      container.dispose();
    });
  });

  group('connectionErrorProvider 写入分类后的本地化文案（而非原始异常/alert文本）', () {
    final en = Translations.build();

    test('fatal alert（startService）不写 connectionErrorProvider（阻断式弹窗负责提示）', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      const rawMessage = 'native stack: 0xdeadbeef at sing_box.rs:123';
      spy.alertStreamController.add(
        const BoxAlert(type: BoxAlertType.startService, message: rawMessage),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '致命 alert 的用户提示由 ShellPage 的阻断式弹窗负责'
            '（见 shell_page_test.dart），这里不能再写一份，否则 home_page '
            '的 toast 会跟弹窗对同一个错误双重提示',
      );

      container.dispose();
    });

    test('fatal alert（emptyConfiguration）不写 connectionErrorProvider', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(
          type: BoxAlertType.emptyConfiguration,
          message: 'config.json: unexpected token at line 42',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '同 startService：致命 alert 由 ShellPage 阻断式弹窗负责提示',
      );

      container.dispose();
    });

    test('fatal alert（createService）不写 connectionErrorProvider', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider.notifier);

      spy.alertStreamController.add(
        const BoxAlert(
          type: BoxAlertType.createService,
          message: 'IOException: bind failed EADDRINUSE',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(connectionErrorProvider),
        isNull,
        reason: '同 startService：致命 alert 由 ShellPage 阻断式弹窗负责提示',
      );

      container.dispose();
    });

    test('connect() 捕获到 SocketException 时应归类为网络不可用文案', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService()
        ..startError = const SocketException(
          'Connection refused (errno 111, address 10.0.0.1)',
        );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'socket-exception-profile';
      await repo.upsert({
        'id': profileId,
        'name': 'SocketException 测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      await container.read(connectionControllerProvider.notifier).connect();

      final err = container.read(connectionErrorProvider);
      expect(err, isNotNull);
      expect(
        err,
        isNot(contains('errno 111')),
        reason: '不应该把原始 SocketException 消息原样展示给用户',
      );
      expect(
        err,
        en.failure.connectivity.networkUnavailable,
        reason: 'SocketException 应归类为"网络不可用"分类文案',
      );

      container.dispose();
    });

    test('connect() 捕获到 TimeoutException 时应归类为启动超时文案', () async {
      final tmp = await _mockPathProvider();
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService()
        ..startError = TimeoutException('sing-box startup timed out');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      final repo = await container.read(profileRepositoryProvider.future);

      const profileId = 'timeout-exception-profile';
      await repo.upsert({
        'id': profileId,
        'name': 'TimeoutException 测试',
        'url': 'https://example.com/sub',
      });
      await repo.setActive(profileId);
      final configFile = File(repo.configFilePath(profileId));
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
          ],
        }),
      );

      await container.read(connectionControllerProvider.notifier).connect();

      final err = container.read(connectionErrorProvider);
      expect(
        err,
        en.failure.singbox.startTimeout,
        reason: 'TimeoutException 应归类为"启动超时"分类文案',
      );

      container.dispose();
    });

    test('disconnect() 持续失败时，连接错误文案应是分类后的兜底文案（回归：内容而非仅"非空"）', () async {
      SharedPreferences.setMockInitialValues({'locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      final spy = _SpyBoxService();
      spy.stopError = Exception('mock stop failure (persistent)');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(spy),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await container.read(profileRepositoryProvider.future);
      final controller = container.read(
        connectionControllerProvider.notifier,
      );

      spy.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);

      await controller.disconnect();

      final err = container.read(connectionErrorProvider);
      expect(
        err,
        isNot(contains('mock stop failure')),
        reason: '不应该把原始 Exception.toString() 原样展示给用户',
      );
      expect(err, en.failure.unexpected, reason: '未归类异常应兜底为"未知错误"分类文案');

      container.dispose();
    });
  });
}
