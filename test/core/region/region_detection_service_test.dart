import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/region/region_detection_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手写的假 [HttpClientAdapter]，跟 `egress_ip_service_test.dart` 建立的模式
/// 完全一致：直接返回预置的 [ResponseBody]，不发出任何真实网络请求。
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

/// 永远不响应的假 adapter：确定性触发超时分支，不留下真正会触发的 Timer
/// （用永不 complete 的 Completer，而不是 Future.delayed）。
Dio _dioThatNeverResponds() {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter((_) => Completer<ResponseBody>().future);
  return dio;
}

void main() {
  group('mapCountryCodeToRegionLocale 纯函数映射', () {
    test('IR -> (ir, fa)', () {
      final mapping = mapCountryCodeToRegionLocale('IR');
      expect(mapping.region, 'ir');
      expect(mapping.locale, AppLocale.fa);
    });

    test('CN -> (cn, zhCn)', () {
      final mapping = mapCountryCodeToRegionLocale('CN');
      expect(mapping.region, 'cn');
      expect(mapping.locale, AppLocale.zhCn);
    });

    test('RU -> (ru, ru)', () {
      final mapping = mapCountryCodeToRegionLocale('RU');
      expect(mapping.region, 'ru');
      expect(mapping.locale, AppLocale.ru);
    });

    test('AF -> (af, fa)', () {
      final mapping = mapCountryCodeToRegionLocale('AF');
      expect(mapping.region, 'af');
      expect(mapping.locale, AppLocale.fa);
    });

    test('BR -> (other, ptBr)（_validRegions 无独立 br region）', () {
      final mapping = mapCountryCodeToRegionLocale('BR');
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.ptBr);
    });

    test('TR -> (other, tr)（_validRegions 无独立 tr region）', () {
      final mapping = mapCountryCodeToRegionLocale('TR');
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.tr);
    });

    test('未知国家码（如 US）-> default (other, en)', () {
      final mapping = mapCountryCodeToRegionLocale('US');
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.en);
    });

    test('null -> default (other, en)', () {
      final mapping = mapCountryCodeToRegionLocale(null);
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.en);
    });

    test('空字符串 -> default (other, en)', () {
      final mapping = mapCountryCodeToRegionLocale('');
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.en);
    });

    test('纯空白字符串 -> default (other, en)', () {
      final mapping = mapCountryCodeToRegionLocale('   ');
      expect(mapping.region, 'other');
      expect(mapping.locale, AppLocale.en);
    });

    test('小写 cn -> 依然命中 (cn, zhCn)', () {
      final mapping = mapCountryCodeToRegionLocale('cn');
      expect(mapping.region, 'cn');
      expect(mapping.locale, AppLocale.zhCn);
    });

    test('大小写混合 + 首尾空白 -> 依然命中 (ir, fa)', () {
      final mapping = mapCountryCodeToRegionLocale(' Ir ');
      expect(mapping.region, 'ir');
      expect(mapping.locale, AppLocale.fa);
    });

    test('RegionLocaleMapping 值相等（用于其它测试的 expect 比较）', () {
      expect(
        mapCountryCodeToRegionLocale('cn'),
        const RegionLocaleMapping('cn', AppLocale.zhCn),
      );
    });
  });

  group('shouldAutoDetectRegion 只在初始默认态自动识别', () {
    test('默认 region=other 且 onboarding 未完成、且未手动设置过 -> true（唯一应该自动跑的情形）', () {
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'other',
          onboardingDone: false,
          manuallySet: false,
        ),
        isTrue,
      );
    });

    test('已手选过 region（不是 other）-> false，不覆盖用户选择', () {
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'cn',
          onboardingDone: false,
          manuallySet: false,
        ),
        isFalse,
      );
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'ir',
          onboardingDone: false,
          manuallySet: false,
        ),
        isFalse,
      );
    });

    test('onboarding 已完成 -> false，即使 region 仍是 other', () {
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'other',
          onboardingDone: true,
          manuallySet: false,
        ),
        isFalse,
      );
    });

    test('已手选 region 且 onboarding 也已完成 -> false', () {
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'ru',
          onboardingDone: true,
          manuallySet: false,
        ),
        isFalse,
      );
    });

    test(
      '手动设置过标记（manuallySet=true）-> false，即使 region 仍是 other 且 '
      'onboarding 未完成（核心新断言：修复"用户手选 other 后被打断、下次重启'
      '自动识别把手选结果覆盖回去"的跨会话 bug——manuallySet 是唯一能拦住它的'
      '信号，光靠 currentRegion/onboardingDone 这两个旧条件区分不出"手选了'
      ' other"和"从没碰过、还是默认值"）',
      () {
        expect(
          shouldAutoDetectRegion(
            currentRegion: 'other',
            onboardingDone: false,
            manuallySet: true,
          ),
          isFalse,
        );
      },
    );

    test('手动设置过标记 + onboarding 也已完成 -> 仍是 false（多重负向条件不会互相抵消）', () {
      expect(
        shouldAutoDetectRegion(
          currentRegion: 'other',
          onboardingDone: true,
          manuallySet: true,
        ),
        isFalse,
      );
    });
  });

  group('RegionDetectionService.detectCountryCode 两级兜底', () {
    // 测试环境没有真机/模拟器，`timezone_to_country` 依赖的
    // `flutter_timezone` MethodChannel 在这里没有任何平台实现可以响应，
    // 时区这一级必然失败——这些用例借此真实地验证"时区失败 -> 自动降级到
    // IP 兜底"这条路径本身，而不是靠 mock 时区包来伪造这条路径。
    test(
      'IP 兜底成功解析 country_code -> 返回该国家码（间接验证时区在本环境降级）',
      () async {
        final service = RegionDetectionService(
          dio: _dioReturning(jsonEncode({'country_code': 'jp'}), 200),
        );

        final code = await service.detectCountryCode();

        expect(code, 'jp');
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'IP 兜底超时 -> 返回 null，且实际耗时远小于生产环境超时时长',
      () async {
        final service = RegionDetectionService(
          dio: _dioThatNeverResponds(),
          ipTimeout: const Duration(milliseconds: 50),
        );

        final stopwatch = Stopwatch()..start();
        final code = await service.detectCountryCode();
        stopwatch.stop();

        expect(code, isNull);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'IP 兜底 HTTP 错误状态码 -> 返回 null',
      () async {
        final service = RegionDetectionService(
          dio: _dioReturning('internal error', 500, contentType: 'text/plain'),
        );

        final code = await service.detectCountryCode();

        expect(code, isNull);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'IP 兜底响应体不是合法 JSON -> 返回 null',
      () async {
        final service = RegionDetectionService(
          dio: _dioReturning('not-json-at-all-{{{', 200),
        );

        final code = await service.detectCountryCode();

        expect(code, isNull);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'IP 兜底响应体缺失 country_code 字段 -> 返回 null',
      () async {
        final service = RegionDetectionService(
          dio: _dioReturning(jsonEncode({'ip': '1.2.3.4'}), 200),
        );

        final code = await service.detectCountryCode();

        expect(code, isNull);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'IP 兜底响应体是数组（不是 object）-> 返回 null',
      () async {
        final service = RegionDetectionService(
          dio: _dioReturning(jsonEncode([1, 2, 3]), 200),
        );

        final code = await service.detectCountryCode();

        expect(code, isNull);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
