import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_connection_controller.dart';

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

/// 经 tun 探测用的假适配器：按构造方式给出固定状态码、连接被拒、永不返回，
/// 或 204 头之后响应体一点点地吐、永不结束。
class _TunnelAdapter implements HttpClientAdapter {
  _TunnelAdapter.status(
    this.statusCode, {
    this.body = '',
    this.location,
    this.trickle = false,
  }) : _mode = _Mode.status;
  _TunnelAdapter.refused()
    : statusCode = 0,
      body = '',
      location = null,
      trickle = false,
      _mode = _Mode.refused;
  _TunnelAdapter.hang()
    : statusCode = 0,
      body = '',
      location = null,
      trickle = false,
      _mode = _Mode.hang;

  final int statusCode;
  final String body;
  final String? location;
  final bool trickle;
  final _Mode _mode;

  int requests = 0;
  int cancelled = 0;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    lastOptions = options;
    switch (_mode) {
      case _Mode.refused:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Connection refused',
        );
      case _Mode.hang:
        final never = Completer<ResponseBody>();
        unawaited(
          cancelFuture?.then((_) {
            cancelled++;
            if (!never.isCompleted) {
              never.completeError(
                DioException.requestCancelled(
                  requestOptions: options,
                  reason: 'cancelled',
                ),
              );
            }
          }),
        );
        return never.future;
      case _Mode.status:
        final headers = <String, List<String>>{
          if (location != null) HttpHeaders.locationHeader: [location!],
        };
        if (trickle) {
          return ResponseBody(
            Stream<Uint8List>.periodic(
              const Duration(milliseconds: 500),
              (_) => Uint8List.fromList([0x61]),
            ),
            statusCode,
            headers: headers,
          );
        }
        return ResponseBody.fromString(body, statusCode, headers: headers);
    }
  }

  @override
  void close({bool force = false}) {}
}

enum _Mode { status, refused, hang }

Future<(ProviderContainer, _SwitchableAdapter, FakeConnectionController)>
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
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  // 必须先 read 一次 notifier 才会真正构造出来（Riverpod 是惰性的）
  final controller =
      container.read(connectionControllerProvider.notifier)
          as FakeConnectionController;
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

      controller.emit(ConnectionPhase.connected);
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

      controller.emit(ConnectionPhase.connected);
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

      controller.emit(ConnectionPhase.connected);
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

      controller.emit(ConnectionPhase.connected);
      adapter.reachable = false;
      for (var i = 0; i < ConnectionHealthMonitor.failureThreshold; i++) {
        await notifier.probeNow();
      }
      expect(
        container.read(connectionHealthProvider),
        ConnectionHealth.degraded,
      );

      controller.emit(ConnectionPhase.disconnected);
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

      controller.emit(ConnectionPhase.connected);
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
            FakeConnectionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final controller =
          container.read(connectionControllerProvider.notifier)
              as FakeConnectionController;
      container.read(connectionHealthProvider.notifier).start();

      controller.emit(ConnectionPhase.connected);
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
    group('VPN 形态：经 tun 探测（真机验收 BUG-B）', () {
      Future<(ProviderContainer, _SwitchableAdapter, FakeConnectionController)>
      vpnContainer(_TunnelAdapter tunnel) async {
        SharedPreferences.setMockInitialValues({'clashmiao_enable_tun': true});
        final prefs = await SharedPreferences.getInstance();
        final adapter = _SwitchableAdapter(); // 经本地代理端口：一直是通的
        final dio = Dio()..httpClientAdapter = adapter;
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(const StubBoxService()),
            egressIpServiceProvider.overrideWith(
              (ref) => EgressIpService(ref, dio: dio),
            ),
            // 只换 HTTP 适配器：判据（严格 204、不跟随重定向、不读响应体）走的
            // 是生产代码。
            tunnelProbeHttpClientProvider.overrideWithValue(
              () => Dio()..httpClientAdapter = tunnel,
            ),
            connectionControllerProvider.overrideWith(
              FakeConnectionController.new,
            ),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        final controller =
            container.read(connectionControllerProvider.notifier)
                as FakeConnectionController;
        return (container, adapter, controller);
      }

      test('tun 转发全部被拒、经代理端口却正常：仍判 degraded，且在半分钟内', () {
        fakeAsync((fa) {
          final tunnel = _TunnelAdapter.refused();
          late ProviderContainer container;
          late _SwitchableAdapter adapter;
          late FakeConnectionController controller;
          vpnContainer(
            tunnel,
          ).then((r) => (container, adapter, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();
          controller.emit(ConnectionPhase.connected);
          fa.flushMicrotasks();

          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                ConnectionHealthMonitor.retryInterval * 2 +
                const Duration(seconds: 1),
          );

          expect(tunnel.requests, ConnectionHealthMonitor.failureThreshold);
          expect(adapter.requestCount, 0, reason: 'VPN 形态不经代理端口探测');
          expect(
            container.read(connectionHealthProvider),
            ConnectionHealth.degraded,
          );
          container.dispose();
        });
      });

      test('tun 通（204）：healthy，之后按常规间隔复查；请求不跟随重定向、不读响应体', () {
        fakeAsync((fa) {
          final tunnel = _TunnelAdapter.status(204);
          late ProviderContainer container;
          late FakeConnectionController controller;
          vpnContainer(tunnel).then((r) => (container, _, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();
          controller.emit(ConnectionPhase.connected);
          fa.flushMicrotasks();

          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                const Duration(seconds: 1),
          );
          expect(
            container.read(connectionHealthProvider),
            ConnectionHealth.healthy,
          );
          expect(tunnel.lastOptions?.followRedirects, isFalse);
          expect(tunnel.lastOptions?.responseType, ResponseType.stream);
          fa.elapse(ConnectionHealthMonitor.retryInterval * 2);
          expect(tunnel.requests, 1, reason: '成功后不走快速重试');
          fa.elapse(ConnectionHealthMonitor.probeInterval);
          expect(tunnel.requests, 2);
          container.dispose();
        });
      });

      test('200 门户页、302 跳转都不算通：连续三次后 degraded', () {
        for (final tunnel in [
          _TunnelAdapter.status(200, body: '<html>请先登录</html>'),
          _TunnelAdapter.status(302, location: 'http://portal.example/login'),
        ]) {
          fakeAsync((fa) {
            late ProviderContainer container;
            late FakeConnectionController controller;
            vpnContainer(tunnel).then((r) => (container, _, controller) = r);
            fa.flushMicrotasks();
            container.read(connectionHealthProvider.notifier).start();
            controller.emit(ConnectionPhase.connected);
            fa.flushMicrotasks();
            fa.elapse(
              ConnectionHealthMonitor.firstProbeDelay +
                  ConnectionHealthMonitor.retryInterval * 2 +
                  const Duration(seconds: 1),
            );
            expect(
              container.read(connectionHealthProvider),
              ConnectionHealth.degraded,
              reason: 'status ${tunnel.statusCode}',
            );
            container.dispose();
          });
        }
      });

      test('204 头之后响应体一点点地吐、永不结束：不读响应体，照样判 healthy 并续排', () {
        fakeAsync((fa) {
          final tunnel = _TunnelAdapter.status(204, trickle: true);
          late ProviderContainer container;
          late FakeConnectionController controller;
          vpnContainer(tunnel).then((r) => (container, _, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();
          controller.emit(ConnectionPhase.connected);
          fa.flushMicrotasks();
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                const Duration(seconds: 1),
          );
          expect(
            container.read(connectionHealthProvider),
            ConnectionHealth.healthy,
          );
          fa.elapse(ConnectionHealthMonitor.probeInterval);
          expect(tunnel.requests, 2, reason: '监控没有被拖住');
          container.dispose();
        });
      });

      test('请求永不返回：整体时限到点取消请求、按失败计，监控继续续排', () {
        fakeAsync((fa) {
          final tunnel = _TunnelAdapter.hang();
          late ProviderContainer container;
          late FakeConnectionController controller;
          vpnContainer(tunnel).then((r) => (container, _, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();
          controller.emit(ConnectionPhase.connected);
          fa.flushMicrotasks();

          // 5 s 首探 → 8 s 时限 → 10 s 重试 → 8 s → 10 s → 8 s。
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                ConnectionHealthMonitor.probeDeadline * 3 +
                ConnectionHealthMonitor.retryInterval * 2 +
                const Duration(seconds: 1),
          );
          expect(tunnel.requests, 3);
          expect(tunnel.cancelled, 3, reason: '每次到点都取消了在途请求');
          expect(
            container.read(connectionHealthProvider),
            ConnectionHealth.degraded,
          );
          fa.elapse(ConnectionHealthMonitor.probeInterval);
          expect(tunnel.requests, 4, reason: '判定 degraded 后照常复查');
          container.dispose();
        });
      });
    });

    group('探测按连接实例与代次归属', () {
      Future<(ProviderContainer, FakeConnectionController)> probeContainer(
        HealthProbe probe,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            boxServiceProvider.overrideWithValue(const StubBoxService()),
            connectionHealthProbeProvider.overrideWithValue(probe),
            connectionControllerProvider.overrideWith(
              FakeConnectionController.new,
            ),
          ],
        );
        await container.read(sharedPreferencesProvider.future);
        final controller =
            container.read(connectionControllerProvider.notifier)
                as FakeConnectionController;
        return (container, controller);
      }

      ConnectionSnapshot connected(int attempt) => ConnectionSnapshot(
        phase: ConnectionPhase.connected,
        epoch: 'e',
        attempt: attempt,
      );

      test('A 的探测悬停 → 断开 → 连上 B → A 返回：B 的首探仍在 5 s 左右，A 的结果不改 B', () {
        fakeAsync((fa) {
          final calls = <(Completer<bool>, CancelToken)>[];
          late ProviderContainer container;
          late FakeConnectionController controller;
          probeContainer((cancel) {
            final c = Completer<bool>();
            calls.add((c, cancel));
            return c.future;
          }).then((r) => (container, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();

          controller.set(connected(1));
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                const Duration(milliseconds: 100),
          );
          expect(calls, hasLength(1), reason: 'A 的首探已发出、悬停中');

          controller.emit(ConnectionPhase.disconnected);
          expect(calls[0].$2.isCancelled, isTrue, reason: '断开即取消 A 的在途请求');
          controller.set(connected(2));
          fa.elapse(const Duration(seconds: 2));
          calls[0].$1.complete(true); // A 晚到的「通」
          fa.flushMicrotasks();
          expect(
            container.read(connectionHealthProvider),
            ConnectionHealth.unknown,
            reason: 'A 的结果不能算到 B 头上',
          );

          fa.elapse(const Duration(milliseconds: 2800));
          expect(calls, hasLength(1), reason: 'B 连上 4.8 s：还没到首探');
          fa.elapse(const Duration(milliseconds: 400));
          expect(calls, hasLength(2), reason: 'B 的首探按时发出，没被 A 推迟');

          calls[1].$1.complete(false);
          fa.flushMicrotasks();
          fa.elapse(ConnectionHealthMonitor.retryInterval);
          expect(calls, hasLength(3), reason: 'B 失败后按快速重试续排');
          container.dispose();
        });
      });

      test('已连接时换了内核实例：取消在途探测、复位并重新安排首探', () {
        fakeAsync((fa) {
          final calls = <(Completer<bool>, CancelToken)>[];
          late ProviderContainer container;
          late FakeConnectionController controller;
          probeContainer((cancel) {
            final c = Completer<bool>();
            calls.add((c, cancel));
            return c.future;
          }).then((r) => (container, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();

          controller.set(connected(1));
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                const Duration(milliseconds: 100),
          );
          controller.set(connected(2));
          expect(calls.single.$2.isCancelled, isTrue);
          calls.single.$1.complete(false);
          fa.flushMicrotasks();
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                const Duration(milliseconds: 100),
          );
          expect(calls, hasLength(2));
          container.dispose();
        });
      });

      test('探测实现无视取消、永不返回：仍按时限计失败并续排', () {
        fakeAsync((fa) {
          var calls = 0;
          late ProviderContainer container;
          late FakeConnectionController controller;
          probeContainer((_) {
            calls++;
            return Completer<bool>().future;
          }).then((r) => (container, controller) = r);
          fa.flushMicrotasks();
          container.read(connectionHealthProvider.notifier).start();
          controller.set(connected(1));
          fa.elapse(
            ConnectionHealthMonitor.firstProbeDelay +
                ConnectionHealthMonitor.probeDeadline +
                ConnectionHealthMonitor.retryInterval +
                const Duration(milliseconds: 100),
          );
          expect(calls, 2);
          container.dispose();
        });
      });
    });

    // 判据在真实 HTTP 层（本机 HttpServer + 生产用的直连客户端）上验证：严格
    // 204、不跟随重定向、不读响应体、取消即放弃。
    group('probeTunnel：真实 HTTP 层', () {
      late HttpServer server;
      late String base;
      late Completer<void> hangArrived;
      HttpOverrides? savedOverrides;

      setUp(() async {
        // TestWidgetsFlutterBinding 把 HttpClient 换成一律回 400 的假实现；这组
        // 要的就是真实 HttpClient 打本机服务器。
        savedOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        hangArrived = Completer<void>();
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        base = 'http://127.0.0.1:${server.port}';
        server.listen((req) async {
          final res = req.response;
          switch (req.uri.path) {
            case '/204':
              res.statusCode = 204;
              await res.close();
            case '/portal':
              res.statusCode = 200;
              res.headers.contentType = ContentType.html;
              res.write('<html>请先登录</html>');
              await res.close();
            case '/redirect':
              res.statusCode = 302;
              res.headers.set(HttpHeaders.locationHeader, '$base/204');
              await res.close();
            case '/trickle':
              res.statusCode = 200;
              res.bufferOutput = false;
              res.contentLength = 1 << 20;
              for (var i = 0; i < 1000; i++) {
                res.add([0x61]);
                await res.flush();
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
              await res.close();
            case '/hang':
              // 不回任何东西；只告诉测试「请求确实到了」。
              if (!hangArrived.isCompleted) hangArrived.complete();
          }
        });
      });

      tearDown(() async {
        HttpOverrides.global = savedOverrides;
        await server.close(force: true);
      });

      Dio client() => createAppHttpClient(
        preferTunnel: false,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        maxRetries: 0,
      );

      test('204 → 通', () async {
        expect(
          await probeTunnel(client(), CancelToken(), url: '$base/204'),
          isTrue,
        );
      });

      test('200 门户页 → 不通', () async {
        expect(
          await probeTunnel(client(), CancelToken(), url: '$base/portal'),
          isFalse,
        );
      });

      test('302 → 不通，且不跟随到 204', () async {
        expect(
          await probeTunnel(client(), CancelToken(), url: '$base/redirect'),
          isFalse,
        );
      });

      test('响应体慢慢吐：不读响应体，读完头就判定', () async {
        final sw = Stopwatch()..start();
        expect(
          await probeTunnel(client(), CancelToken(), url: '$base/trickle'),
          isFalse,
        );
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      });

      test('对端不回：取消后立即放弃', () async {
        final cancel = CancelToken();
        final pending = probeTunnel(client(), cancel, url: '$base/hang');
        // 等服务端真的收到请求再取消，证明取消的是在途请求。
        await hangArrived.future;
        final sw = Stopwatch()..start();
        cancel.cancel('deadline');
        expect(await pending, isFalse);
        expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      });
    });

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
