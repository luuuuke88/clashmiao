import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clashmiao/core/egress_ip/egress_ip_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手写的假 [HttpClientAdapter]：直接返回预置的 [ResponseBody]，不发出任何
/// 真实网络请求。仓库里没有引入 mockito/mocktail/http_mock_adapter 之类的
/// mock 依赖，硬约束也不允许为了测试改 pubspec.yaml，所以这是本次为"如何在
/// 这个仓库里给 Dio 网络请求写单测"建立的新写法——参照的是 dio 包自己
/// （`dio-5.9.2/test/mock/adapters.dart`）内部测试用的同款手写 adapter 模式；
/// 仓库既有的 `geo_update_service_test.dart` 实际上并没有真正 mock 过 Dio
/// 层（只测了纯函数 sha256），没有可直接抄的先例。
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

Dio _dioReturning(
  String body,
  int statusCode, {
  String contentType = 'application/json',
}) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter((_) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  });
  return dio;
}

/// 永远不响应的假 adapter：用来确定性地触发超时分支，且不留下任何真正会
/// 触发的 Timer（用一个永不 complete 的 Completer，而不是 Future.delayed）。
Dio _dioThatNeverResponds() {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter((_) => Completer<ResponseBody>().future);
  return dio;
}

/// 暴露一个绑定到当前 container 的真实 [Ref]，给测试直接构造
/// [EgressIpService] 用。`EgressIpService` 跟 `HapticService` 一样需要一个
/// `Ref` 来读取 `clashmiao_auto_ip_check` 这个 pref；`ProviderContainer`
/// 本身不是 `Ref`，没法直接传进去——这是 Riverpod 测试里获取"裸" Ref 的
/// 标准写法（用一个只做透传的 Provider 把 container 内部的 Ref 挖出来）。
final _refExposerProvider = Provider<Ref>((ref) => ref);

Future<EgressIpService> _service({
  Map<String, Object> prefs = const {},
  required Dio dio,
  Duration? timeout,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(sp)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  final ref = container.read(_refExposerProvider);
  return EgressIpService(ref, dio: dio, timeout: timeout);
}

void main() {
  group('EgressIpService.fetch 成功解析', () {
    test('success:true + ip + country_code -> 正确的 EgressIpResult', () async {
      final service = await _service(
        dio: _dioReturning(
          jsonEncode({
            'success': true,
            'ip': '156.243.244.222',
            'country_code': 'jp', // 故意用小写，验证会被归一化成大写
          }),
          200,
        ),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isFalse);
      expect(result.ip, '156.243.244.222');
      expect(result.countryCode, 'JP');
    });

    test('country_code 缺失时 countryCode 为 null，但 ip 仍正确', () async {
      final service = await _service(
        dio: _dioReturning(
          jsonEncode({'success': true, 'ip': '203.0.113.9'}),
          200,
        ),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isFalse);
      expect(result.ip, '203.0.113.9');
      expect(result.countryCode, isNull);
    });
  });

  group('EgressIpService.fetch HTTP 错误 -> unknown', () {
    test('HTTP 500 返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning('internal error', 500, contentType: 'text/plain'),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
      expect(result.ip, isNull);
    });

    test('HTTP 429（限流，真实碰到过 ipapi.co 返回这个）返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning(
          jsonEncode({'error': true, 'reason': 'RateLimited'}),
          429,
        ),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });

    test('服务端逻辑失败（HTTP 200 + success:false）返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning(
          jsonEncode({
            'ip': '999.999.999.999',
            'success': false,
            'message': 'Invalid IP address',
          }),
          200,
        ),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });
  });

  group('EgressIpService.fetch 超时 -> unknown', () {
    test('查询超时返回 unknown，且实际耗时远小于生产环境超时时长', () async {
      final service = await _service(
        dio: _dioThatNeverResponds(),
        timeout: const Duration(milliseconds: 50),
      );

      final stopwatch = Stopwatch()..start();
      final result = await service.fetch();
      stopwatch.stop();

      expect(result.isUnknown, isTrue);
      // 生产环境默认超时是 12 秒；这里验证的是"确实提前触发了"，不是真的等满。
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('EgressIpService.fetch 畸形响应体 -> unknown', () {
    test('响应体不是合法 JSON 文本返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning('not-json-at-all-{{{', 200),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });

    test('响应体是合法 JSON 但不是 object（数组）返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning(jsonEncode([1, 2, 3]), 200),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });

    test('ip 字段缺失返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning(jsonEncode({'success': true}), 200),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });

    test('ip 字段是空字符串返回 unknown', () async {
      final service = await _service(
        dio: _dioReturning(jsonEncode({'success': true, 'ip': ''}), 200),
      );

      final result = await service.fetch();

      expect(result.isUnknown, isTrue);
    });
  });

  group('EgressIpService.autoCheckEnabled', () {
    test('pref 未设置时默认开启（与 settings_page.dart defaultValue: true 一致）', () async {
      final service = await _service(dio: Dio());
      expect(service.autoCheckEnabled, isTrue);
    });

    test('pref 显式设为 true 时开启', () async {
      final service = await _service(
        prefs: {'clashmiao_auto_ip_check': true},
        dio: Dio(),
      );
      expect(service.autoCheckEnabled, isTrue);
    });

    test('pref 显式设为 false 时关闭', () async {
      final service = await _service(
        prefs: {'clashmiao_auto_ip_check': false},
        dio: Dio(),
      );
      expect(service.autoCheckEnabled, isFalse);
    });
  });
}
