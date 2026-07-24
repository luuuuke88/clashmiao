import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/egress_ip/egress_ip_service.dart';
import 'package:clashmiao/core/health/connection_health_monitor.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可切换成功/失败的假 [HttpClientAdapter]，沿用仓库既有范式
/// （`egress_ip_service_test.dart` 里的同款 `_FakeAdapter`）。
class _SwitchableAdapter implements HttpClientAdapter {
  /// 置为 false 后每次请求都抛——模拟"隧道结构性建好了，但数据包送不出去"，
  /// 也就是黑洞时探测请求的真实表现。
  bool reachable = true;

  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (!reachable) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'simulated blackhole',
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'ip': '203.0.113.7', 'country_code': 'JP'}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 直接把 connectionControllerProvider 推到任意状态的假 controller，
/// 沿用 `home_page_test.dart` 里 `_FakeConnectionController` 的同款做法。
class _FakeConnectionController extends ConnectionController {
  _FakeConnectionController(super.ref);

  void emit(BoxStatus status) => state = AsyncData(status);
}

Future<(ProviderContainer, _SwitchableAdapter, _FakeConnectionController)>
_makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final adapter = _SwitchableAdapter();
  final dio = Dio();
  dio.httpClientAdapter = adapter;

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      egressIpServiceProvider.overrideWith(
        (ref) => EgressIpService(ref, dio: dio),
      ),
      connectionControllerProvider.overrideWith(_FakeConnectionController.new),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  // 必须先 read 一次 notifier 才会真正构造出来（Riverpod 是惰性的）
  final controller =
      container.read(connectionControllerProvider.notifier)
          as _FakeConnectionController;
  return (container, adapter, controller);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionHealthMonitor', () {
    test('未连接时不探测，健康度为 unknown', () async {
      final (container, adapter, _) = await _makeContainer();
      addTearDown(container.dispose);
      // 真的激活监控——否则这个断言会因为"压根没启动"而平凡成立，测不到东西
      container.read(connectionHealthProvider.notifier).start();

      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.unknown,
      );
      // 首次探测有 5 秒延迟，这里等得比它久，确认确实一次都没发
      await Future<void>.delayed(
        ConnectionHealthMonitor.firstProbeDelay + const Duration(seconds: 1),
      );
      expect(adapter.requestCount, 0, reason: '没连接就不该有任何探测请求');
    });

    test('探测通过时健康度变 healthy', () async {
      final (container, adapter, controller) = await _makeContainer();
      addTearDown(container.dispose);
      container.read(connectionHealthProvider.notifier).start();

      controller.emit(const BoxStarted());
      await container.read(connectionHealthProvider.notifier).probeNow();

      expect(adapter.requestCount, greaterThan(0));
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.healthy,
      );
    });

    test('连续失败达到阈值才判 degraded——单次失败不算（防误报）', () async {
      final (container, adapter, controller) = await _makeContainer();
      addTearDown(container.dispose);
      container.read(connectionHealthProvider.notifier).start();
      final notifier = container.read(connectionHealthProvider.notifier);

      controller.emit(const BoxStarted());
      adapter.reachable = false;

      for (var i = 1; i < ConnectionHealthMonitor.failureThreshold; i++) {
        await notifier.probeNow();
        expect(
          container.read(connectionHealthProvider),
          isNot(ConnectionHealth.degraded),
          reason:
              '第 $i 次失败（未达阈值 '
              '${ConnectionHealthMonitor.failureThreshold}）不该判定黑洞',
        );
      }

      await notifier.probeNow(); // 第 threshold 次
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.degraded,
        reason: '连续失败达到阈值必须升级成 degraded，不能继续静默',
      );
    });

    test('degraded 后恢复连通，下一次探测成功就回到 healthy', () async {
      final (container, adapter, controller) = await _makeContainer();
      addTearDown(container.dispose);
      container.read(connectionHealthProvider.notifier).start();
      final notifier = container.read(connectionHealthProvider.notifier);

      controller.emit(const BoxStarted());
      adapter.reachable = false;
      for (var i = 0; i < ConnectionHealthMonitor.failureThreshold; i++) {
        await notifier.probeNow();
      }
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.degraded,
      );

      adapter.reachable = true;
      await notifier.probeNow();
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.healthy,
      );
    });

    test('断开后复位成 unknown——上一条连接的结论不能套到下一条上', () async {
      final (container, adapter, controller) = await _makeContainer();
      addTearDown(container.dispose);
      container.read(connectionHealthProvider.notifier).start();
      final notifier = container.read(connectionHealthProvider.notifier);

      controller.emit(const BoxStarted());
      adapter.reachable = false;
      for (var i = 0; i < ConnectionHealthMonitor.failureThreshold; i++) {
        await notifier.probeNow();
      }
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.degraded,
      );

      controller.emit(const BoxStopped());
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.unknown,
        reason: '断开后必须复位，否则重连上来会立刻误报黑洞',
      );
    });

    test('探测期间不会并发发起第二次请求', () async {
      final (container, adapter, controller) = await _makeContainer();
      addTearDown(container.dispose);
      container.read(connectionHealthProvider.notifier).start();
      final notifier = container.read(connectionHealthProvider.notifier);

      controller.emit(const BoxStarted());
      // 同时发起两次：第二次应该被 _probing 闸门挡掉
      await Future.wait([notifier.probeNow(), notifier.probeNow()]);

      expect(adapter.requestCount, 1, reason: '并发探测会让失败计数翻倍，必须挡住');
    });

    test('监控不受"自动检查 IP"用户开关影响——健康探测是安全兜底不是展示功能', () async {
      SharedPreferences.setMockInitialValues({
        'clashmiao_auto_ip_check': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final adapter = _SwitchableAdapter();
      final dio = Dio();
      dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(const StubBoxService()),
          egressIpServiceProvider.overrideWith(
            (ref) => EgressIpService(ref, dio: dio),
          ),
          connectionControllerProvider.overrideWith(
            _FakeConnectionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final controller =
          container.read(connectionControllerProvider.notifier)
              as _FakeConnectionController;
      container.read(connectionHealthProvider.notifier).start();

      controller.emit(const BoxStarted());
      await container.read(connectionHealthProvider.notifier).probeNow();

      expect(
        adapter.requestCount,
        greaterThan(0),
        reason: '用户关掉的是首页那个 IP 展示，不该连安全兜底一起关掉',
      );
    });

    // 结构性守卫，不是行为测试：周期探测改成由启动流程显式 start() 激活之后，
    // 多了一个新的失效模式——**万一哪次重构把这行调用删了，整个黑洞检测会
    // 静默地不工作，而所有其它测试仍然全绿**（它们都自己调 start()）。
    // main() 里混着一堆平台初始化，没法在单测里真的跑一遍，所以这里退而求
    // 其次直接检查源码里这条接线还在。
    test('启动流程必须激活周期探测（接线不能被悄悄删掉）', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(
        source.contains('connectionHealthProvider.notifier).start()'),
        isTrue,
        reason: 'main.dart 里少了这行，黑洞检测就永远不会跑，且不会有任何测试报警',
      );
    });
  });
}
