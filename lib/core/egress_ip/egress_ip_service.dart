import 'dart:async';

import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 跟 settings_page.dart "自动检查连接 IP" 开关（`_BoolPreferenceTile`）共用的
/// pref key。
const _autoCheckPrefKey = 'clashmiao_auto_ip_check';

/// 默认开启，和 settings 页该开关的 `defaultValue: true` 保持一致
/// （`settings_page.dart` 里 `prefKey: 'clashmiao_auto_ip_check'` 那个 tile）。
const _autoCheckDefault = true;

/// 单次查询的应用层硬超时（连接、接收、JSON 解析全流程封顶）。
///
/// 这是"第二道防线"：Dio 自己的 connectTimeout/receiveTimeout 只在真实的
/// `IOHttpClientAdapter`（生产环境实际用的那个）下由原生 socket 层强制执行——
/// 一旦换成自定义 `HttpClientAdapter`（比如单测里的假实现），这两个配置就不
/// 再自动生效（`connectTimeout` 完全是 IOHttpClientAdapter 内部实现的，通用
/// 的 `dio_mixin.dart`/`response_stream_handler.dart` 并不会替任意 adapter
/// 强制执行）。用 `Future.timeout` 在 service 这一层再兜底一次，不管底层
/// adapter 是什么，都能保证"最多等这么久"；这也让单测可以用一个"永远不响应"
/// 的假 adapter + 很短的 timeout 精确、快速地触发这条路径，不用真的等生产
/// 环境的 12 秒。
const _defaultFetchTimeout = Duration(seconds: 12);

/// 出口 IP 查询结果。
///
/// [ip] 为 `null`（或空字符串）表示"未知"——对应 UI 上的 `t.proxies.unknownIp`：
/// 可能是还没查过、查询失败、超时，或者服务端返回的逻辑失败。
/// [countryCode] 是 ISO 3166-1 alpha-2 两位国家码（大写），拿不到时为
/// `null`，不影响 IP 本身的展示（UI 只是不显示国旗）。
@immutable
class EgressIpResult {
  const EgressIpResult({this.ip, this.countryCode});

  const EgressIpResult.unknown() : ip = null, countryCode = null;

  final String? ip;
  final String? countryCode;

  bool get isUnknown => ip == null || ip!.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EgressIpResult &&
          other.ip == ip &&
          other.countryCode == countryCode);

  @override
  int get hashCode => Object.hash(ip, countryCode);

  @override
  String toString() => 'EgressIpResult(ip: $ip, countryCode: $countryCode)';
}

/// 出口公网 IP 查询的薄封装。
///
/// 背景：设置页"自动检查连接 IP"开关（`clashmiao_auto_ip_check`）此前只把
/// pref 写进 SharedPreferences，全代码库没有任何地方读取它；翻译文件里
/// `t.proxies.checkIp`（"检测 IP 地址"）/`t.proxies.unknownIp`（"未知的 IP"）
/// 两个 key 也是孤儿——从没有被引用过。本类是唯一的查询实现，让这个功能真正
/// 跑起来：VPN 连接成功后（或者用户手动点击），查一次当前出口公网 IP，
/// 受这个开关控制是否自动查。
///
/// ## 用的服务：ipwho.is
///
/// 选了 `https://ipwho.is/`（免费、不需要 API key、HTTPS），而不是候选的
/// 另一个服务 `ipapi.co/json/`——原因是实测出来的：写这个类之前直接从当前
/// 开发环境 curl 了一次 `https://ipapi.co/json/`，直接拿到
/// `{"error":true,"reason":"RateLimited","message":"Please sign up for a
/// paid plan..."}`——免费额度在共享出口 IP 下已经被限流，说明它的免费层在
/// 真实环境里不够稳定，不适合作为"连接成功就自动查一次"这种可能频繁触发的
/// 场景的默认服务。同一时间 `https://ipwho.is/` 正常返回完整数据（HTTP 200，
/// 实测耗时 3~8 秒不等）。`ipwho.is` 的响应体里还带一个明确的 `success` 布尔
/// 字段，用来判断"查询"这个动作本身有没有成功——这个服务查询失败时也可能
/// 返回 HTTP 200 + `success:false`（比如查询一个非法 IP 时），不能只看 HTTP
/// 状态码，`success` 字段让这个判断不用猜。附带的 `country_code` 字段
/// （ISO 3166-1 alpha-2）用来给 UI 拼国旗 emoji。
///
/// 响应体拿到的字段（只用到这三个，其余字段比如城市/时区/ASN/经纬度忽略）：
/// ```json
/// {
///   "success": true,
///   "ip": "156.243.244.222",
///   "country_code": "JP"
///   // ...城市/时区/ASN 等字段本类不关心
/// }
/// ```
/// 查询失败时（比如传了一个非法 IP 查询）`ipwho.is` 会返回 HTTP 200 +：
/// `{"ip": "...", "success": false, "message": "Invalid IP address"}`。
///
/// ## 失败/超时处理
///
/// [fetch] 永远不抛异常——HTTP 错误状态码、超时、JSON 畸形、字段缺失或类型
/// 不对、服务端返回 `success:false`，统统吞掉，返回 [EgressIpResult.unknown]。
/// 这个查询是首页的锦上添花展示，绝不能因为一次网络请求把整个页面拖住或
/// 崩溃。超时用两道防线：Dio 自身的 `connectTimeout`/`receiveTimeout`（生产
/// 环境的真实 `IOHttpClientAdapter` 下有效），加上本类在调用处再包一层
/// `Future.timeout`（见 [_defaultFetchTimeout] 的文档），后者是权威超时，
/// 保证不管传输层细节如何都有一个硬上限，也让单测能精确、快速地触发超时
/// 分支。
class EgressIpService {
  EgressIpService(this._ref, {Dio? dio, Duration? timeout})
    : _dio = dio ?? _buildDefaultDio(_ref),
      _timeout = timeout ?? _defaultFetchTimeout;

  final Ref _ref;
  final Dio _dio;
  final Duration _timeout;

  static const _endpoint = 'https://ipwho.is/';

  static Dio _buildDefaultDio(Ref ref) {
    // 故意不像 ProfileRepository（app_providers.dart 的
    // profileRepositoryProvider，此前）那样强制 `findProxy = (_) => 'DIRECT'`
    // 跳过系统代理——这里恰恰相反：要查的就是"经过 sing-box 隧道之后"外界
    // 看到的出口 IP，必须优先走隧道，`preferTunnel: true` 正是为这种场景
    // 设计的：优先经本地 mixed 代理端口发出请求，隧道不可用（sing-box 未
    // 启动 / mixed 端口未监听）时自动降级直连，那时查到的就是设备真实的
    // ISP IP——这是"未连接 VPN 时调用这个查询"的诚实结果，不是 bug。
    final mixedPort = ref.read(networkSettingsProvider).mixedPort;
    return createAppHttpClient(
      preferTunnel: true,
      mixedPort: mixedPort,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    );
  }

  /// 设置页"自动检查连接 IP"开关的当前值。
  ///
  /// 读取方式跟随 `haptic_service.dart`/`battery_optimization_service.dart`
  /// 已经建立的模式：每次都重新读一次 [sharedPreferencesProvider]，不做
  /// 缓存，保证用户切换开关后立刻生效；读取失败时保守回退到默认值（开启），
  /// 不影响调用方主流程。
  bool get autoCheckEnabled {
    try {
      final prefs = _ref.read(sharedPreferencesProvider).requireValue;
      return prefs.getBool(_autoCheckPrefKey) ?? _autoCheckDefault;
    } catch (e) {
      debugPrint('EgressIpService: 读取自动检查开关失败，回退默认值: $e');
      return _autoCheckDefault;
    }
  }

  /// 查询当前出口公网 IP。
  ///
  /// 这是一次"真实查询"，不检查 [autoCheckEnabled]——是否要在某个时机调用
  /// 这个方法（自动 vs 手动）由调用方（UI 层）决定，详见类文档。
  Future<EgressIpResult> fetch() async {
    final cancelToken = CancelToken();
    try {
      final response = await _dio
          .get<dynamic>(_endpoint, cancelToken: cancelToken)
          .timeout(
            _timeout,
            onTimeout: () {
              cancelToken.cancel('EgressIpService: 应用层超时');
              throw TimeoutException(
                'EgressIpService: 查询超过 $_timeout',
                _timeout,
              );
            },
          );
      return _parse(response.data);
    } on TimeoutException catch (e) {
      debugPrint('EgressIpService: 查询超时，已忽略: $e');
      return const EgressIpResult.unknown();
    } on DioException catch (e) {
      debugPrint('EgressIpService: 请求失败，已忽略: $e');
      return const EgressIpResult.unknown();
    } catch (e) {
      debugPrint('EgressIpService: 解析响应失败，已忽略: $e');
      return const EgressIpResult.unknown();
    }
  }

  EgressIpResult _parse(dynamic data) {
    if (data is! Map) {
      return const EgressIpResult.unknown();
    }
    if (data['success'] != true) {
      return const EgressIpResult.unknown();
    }
    final ip = data['ip'];
    if (ip is! String || ip.isEmpty) {
      return const EgressIpResult.unknown();
    }
    final rawCountryCode = data['country_code'];
    final countryCode = (rawCountryCode is String && rawCountryCode.length == 2)
        ? rawCountryCode.toUpperCase()
        : null;
    return EgressIpResult(ip: ip, countryCode: countryCode);
  }
}

final egressIpServiceProvider = Provider<EgressIpService>((ref) {
  return EgressIpService(ref);
});
