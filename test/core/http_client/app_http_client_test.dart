import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手写的假 [HttpClientAdapter]：跟 `egress_ip_service_test.dart` /
/// `region_detection_service_test.dart` 已经建立的模式完全一致——直接返回
/// 预置的 [ResponseBody] 或抛出预置的 [DioException]，不发出任何真实网络请求。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _handler(options);

  @override
  void close({bool force = false}) {}
}

/// 启动一个只会绑定、不会真正响应任何逻辑的本地 HTTP 服务器，返回固定文本，
/// 用来在真实 loopback socket 层面区分"请求最终落到了哪一个服务器"——不需要
/// 真的实现一个符合 RFC 的转发代理，dart:io 的 `HttpClient` 对非 HTTPS 请求
/// 通过 proxy 转发时，只是把带 host 的请求行原样发给 proxy 侧的 socket，
/// 随便一个 HttpServer 都能收到并响应，足够验证"连的是谁"。
Future<HttpServer> _startServer(String label) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      request.response.write(label);
      await request.response.close();
    }),
  );
  return server;
}

void main() {
  group('createAppHttpClient 基础配置', () {
    test('默认设置了统一的 connectTimeout/receiveTimeout', () {
      final dio = createAppHttpClient();
      expect(dio.options.connectTimeout, kDefaultConnectTimeout);
      expect(dio.options.receiveTimeout, kDefaultReceiveTimeout);
    });

    test('默认设置了统一的 User-Agent 请求头', () {
      final dio = createAppHttpClient();
      expect(dio.options.headers['User-Agent'], isNotNull);
      expect(dio.options.headers['User-Agent'], isNotEmpty);
    });

    test('可以覆盖 connectTimeout/receiveTimeout/userAgent', () {
      final dio = createAppHttpClient(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 9),
        userAgent: 'custom-ua/1.0',
      );
      expect(dio.options.connectTimeout, const Duration(seconds: 3));
      expect(dio.options.receiveTimeout, const Duration(seconds: 9));
      expect(dio.options.headers['User-Agent'], 'custom-ua/1.0');
    });
  });

  group('preferTunnel 代理绕行策略（核心 bug 修复）', () {
    late HttpServer directServer;
    late HttpServer proxyServer;

    setUp(() async {
      directServer = await _startServer('via-direct');
      proxyServer = await _startServer('via-proxy');
    });

    tearDown(() async {
      await directServer.close(force: true);
      await proxyServer.close(force: true);
    });

    test('preferTunnel:true 且 mixed 端口可用时，优先经过本地代理端口', () async {
      final dio = createAppHttpClient(
        preferTunnel: true,
        mixedPort: proxyServer.port,
      );

      final response = await dio.get<String>(
        'http://127.0.0.1:${directServer.port}/',
      );

      // 请求目标写的虽然是 directServer 的地址，但因为 preferTunnel:true
      // 把 mixed 端口设成了 proxyServer，dart:io 的 HttpClient 应该先把请求
      // 转发给 proxyServer（"PROXY host:port"在前），验证响应体确实来自
      // proxyServer 而不是 directServer，证明"隧道优先"生效。
      expect(response.data, 'via-proxy');
    });

    test('preferTunnel:true 但 mixed 端口拒绝连接时，自动降级直连', () async {
      // 绑定一个临时端口后立刻关闭，制造一个确定性的"连接被拒绝"目标
      // （没有任何进程在监听这个端口，模拟 sing-box 未启动 / mixed 端口未监听）。
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close(force: true);

      final dio = createAppHttpClient(preferTunnel: true, mixedPort: deadPort);

      final response = await dio.get<String>(
        'http://127.0.0.1:${directServer.port}/',
      );

      expect(response.data, 'via-direct');
    });

    test('preferTunnel:false 时始终直连，即使 mixed 端口本身是可用的', () async {
      final dio = createAppHttpClient(
        preferTunnel: false,
        mixedPort: proxyServer.port,
      );

      final response = await dio.get<String>(
        'http://127.0.0.1:${directServer.port}/',
      );

      expect(response.data, 'via-direct');
    });
  });

  group('订阅刷新场景的 Dio 不再硬编码 DIRECT（回归验证 app_providers.dart 的 bug 修复）', () {
    test(
      'createAppHttpClient(preferTunnel: true) 构造出的 adapter 不会强制 DIRECT',
      () async {
        final proxyServer = await _startServer('via-proxy');
        addTearDown(() => proxyServer.close(force: true));
        final directServer = await _startServer('via-direct');
        addTearDown(() => directServer.close(force: true));

        // 这是订阅刷新此前的 bug：无论 preferTunnel 设成什么，请求永远直连，
        // 完全绕不过本地隧道。这里用跟 profileRepositoryProvider 完全一致的
        // 调用方式（preferTunnel: true）验证它确实会先尝试 mixed 端口。
        final dio = createAppHttpClient(
          preferTunnel: true,
          mixedPort: proxyServer.port,
        );
        final response = await dio.get<String>(
          'http://127.0.0.1:${directServer.port}/',
        );
        expect(response.data, 'via-proxy');
      },
    );
  });

  group('重试拦截器：网络类错误重试，业务错误不重试', () {
    test('connectionError 重试后最终成功，验证确实重试了 N 次', () async {
      var callCount = 0;
      final dio = createAppHttpClient(
        preferTunnel: false,
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 1),
      );
      dio.httpClientAdapter = _FakeAdapter((options) async {
        callCount++;
        if (callCount < 3) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException('Connection refused'),
          );
        }
        return ResponseBody.fromString('ok', 200);
      });

      final response = await dio.get<String>('http://example.test/');

      expect(response.data, 'ok');
      expect(callCount, 3); // 原始 1 次 + 重试 2 次
    });

    test('connectionTimeout 也会被视为网络类错误并重试', () async {
      var callCount = 0;
      final dio = createAppHttpClient(
        preferTunnel: false,
        maxRetries: 1,
        retryDelay: const Duration(milliseconds: 1),
      );
      dio.httpClientAdapter = _FakeAdapter((options) async {
        callCount++;
        if (callCount < 2) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
        return ResponseBody.fromString('ok', 200);
      });

      final response = await dio.get<String>('http://example.test/');

      expect(response.data, 'ok');
      expect(callCount, 2);
    });

    test('重试次数耗尽后仍然失败，最终把异常抛出去', () async {
      var callCount = 0;
      final dio = createAppHttpClient(
        preferTunnel: false,
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 1),
      );
      dio.httpClientAdapter = _FakeAdapter((options) async {
        callCount++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException('Connection refused'),
        );
      });

      await expectLater(
        dio.get<String>('http://example.test/'),
        throwsA(isA<DioException>()),
      );
      expect(callCount, 3); // 原始 1 次 + 最多重试 2 次，之后放弃
    });

    test('4xx/5xx 业务错误不应该被误判成网络错误重试', () async {
      var callCount = 0;
      final dio = createAppHttpClient(
        preferTunnel: false,
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 1),
      );
      dio.httpClientAdapter = _FakeAdapter((options) async {
        callCount++;
        return ResponseBody.fromString('server error', 500);
      });

      await expectLater(
        dio.get<String>('http://example.test/'),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.badResponse,
          ),
        ),
      );
      // 业务错误（HTTP 500）不是网络错误，重试拦截器不应该介入——只请求了 1 次。
      expect(callCount, 1);
    });

    test('maxRetries:0 时完全不重试', () async {
      var callCount = 0;
      final dio = createAppHttpClient(preferTunnel: false, maxRetries: 0);
      dio.httpClientAdapter = _FakeAdapter((options) async {
        callCount++;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });

      await expectLater(
        dio.get<String>('http://example.test/'),
        throwsA(isA<DioException>()),
      );
      expect(callCount, 1);
    });
  });
}
