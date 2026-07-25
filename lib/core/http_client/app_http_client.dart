import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 全项目统一的 [Dio] 实例工厂。
///
/// ## 背景
///
/// 在这个文件出现之前，全项目有 5 处各自独立 `Dio()` 实例化的地方
/// （订阅刷新、出口 IP 查询、地区识别、GeoIP 资源更新、更新检查），
/// 超时策略互不一致、零重试逻辑、大多没有默认 User-Agent。其中订阅刷新那处
/// （`app_providers.dart` 的 `profileRepositoryProvider`）还把代理绕行策略
/// 硬编码成"永远走 DIRECT"——如果订阅源本身是那种必须经隧道才能访问的服务器
/// （比如被墙的域名），订阅刷新会在隧道明明健康可用的情况下必定失败。
///
/// 本文件把这些关注点收敛成一个工厂函数：统一超时、统一 User-Agent、一个
/// 轻量的网络错误重试拦截器，以及一个可参数化的"隧道优先/纯直连"代理绕行
/// 策略。
///
/// ## 代理绕行策略（[preferTunnel]）
///
/// - `preferTunnel: true`：优先尝试通过本地 sing-box 的 mixed 代理端口
///   （`127.0.0.1:<mixedPort>`，端口配置见 `network_settings.dart` 的
///   `NetworkSettings.mixedPort`）发出请求；如果连接被拒绝/超时（sing-box
///   没启动、mixed 端口没监听），自动降级直连。这个"先试代理、失败再直连"的
///   降级完全由 `dart:io` 的 `HttpClient.findProxy` 原生支持——返回值写成
///   `"PROXY host:port; DIRECT"`（分号分隔的候选列表），dart:io 内部
///   （见 `_HttpClient._getConnection`）会按顺序尝试，前一个连接失败就自动
///   换下一个，不需要手写降级重试逻辑。
/// - `preferTunnel: false`：不经过 mixed 端口，纯直连。用于语义上必须拿到
///   "设备真实网络路径"结果的场景（比如识别用户真实地理位置），走隧道会
///   拿到隧道出口节点的结果，语义就错了。
///
/// ## 重试拦截器
///
/// 只重试网络类错误（连接超时/连接失败等 [DioExceptionType]，不包括
/// HTTP 4xx/5xx 业务错误——那些是服务端明确的响应，重试没有意义，只会
/// 浪费时间），最多重试 [maxRetries] 次，每次间隔固定的 [retryDelay]。
/// 没有引入 `dio_retry` 之类的新依赖，就是一个 [Interceptor.onError] 钩子。
Dio createAppHttpClient({
  bool preferTunnel = true,
  int mixedPort = kDefaultMixedPort,
  Duration connectTimeout = kDefaultConnectTimeout,
  Duration receiveTimeout = kDefaultReceiveTimeout,
  int maxRetries = kDefaultMaxRetries,
  Duration retryDelay = kDefaultRetryDelay,
  String userAgent = kDefaultUserAgent,
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'User-Agent': userAgent},
    ),
  );

  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.findProxy = (_) =>
          preferTunnel ? 'PROXY 127.0.0.1:$mixedPort; DIRECT' : 'DIRECT';
      return client;
    },
  );

  dio.interceptors.add(
    _RetryInterceptor(dio, maxRetries: maxRetries, retryDelay: retryDelay),
  );

  return dio;
}

/// mixed 端口未显式传入时的兜底默认值，跟 `network_settings.dart` 里
/// `NetworkSettings.mixedPort` 的默认值保持一致。
const int kDefaultMixedPort = 2080;

/// 统一的默认连接超时——取自项目里此前出现过的最长 `connectTimeout`
/// （`app_providers.dart` 订阅刷新 / `geo_update_service.dart` 资源下载
/// 都用的 15 秒），作为其余调用点的基准，不凭空定数字。
const Duration kDefaultConnectTimeout = Duration(seconds: 15);

/// 统一的默认接收超时——取自 `app_providers.dart` 订阅刷新此前的 30 秒
/// （比 `geo_update_service.dart` 下载大文件用的 60 秒更保守，后者作为
/// 单独场景可以在调用处显式覆盖，见 `geo_update_service.dart`）。
const Duration kDefaultReceiveTimeout = Duration(seconds: 30);

/// 网络类错误默认最多重试 2 次（加上原始请求共 3 次尝试）。
const int kDefaultMaxRetries = 2;

/// 每次重试前的固定等待——不引入指数退避框架，一个短暂固定延迟足够。
const Duration kDefaultRetryDelay = Duration(milliseconds: 500);

/// 统一的默认 User-Agent。项目当前版本见 `pubspec.yaml` 的 `version:`
/// 字段；调用方如果需要更精确地跟随发布版本变化，可以用
/// `package_info_plus`（`PackageInfo.fromPlatform()`，项目里
/// `update_checker.dart`/`about_page.dart`/`home_page.dart` 已经在用同一个
/// API）读出真实版本号后通过 [createAppHttpClient] 的 [userAgent] 参数覆盖；
/// 这里的常量只是一个不需要异步 I/O 就能用的合理兜底默认值。
const String kDefaultUserAgent = 'ClashMiao/0.1.0 (Dio)';

/// 只重试网络类错误的轻量拦截器（超时 / 连接失败），HTTP 4xx/5xx 业务错误
/// 不重试。
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(
    this._dio, {
    required this.maxRetries,
    required this.retryDelay,
  });

  final Dio _dio;
  final int maxRetries;
  final Duration retryDelay;

  /// 记在 [RequestOptions.extra] 里的重试计数，跟随同一个请求在递归重试间
  /// 传递（`_dio.fetch` 复用同一个 [RequestOptions] 对象）。
  static const _attemptKey = '_appHttpClientRetryAttempt';

  static const _retryableTypes = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  };

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (!_retryableTypes.contains(err.type) || attempt >= maxRetries) {
      handler.next(err);
      return;
    }
    unawaited(_retry(err, handler, attempt));
  }

  Future<void> _retry(
    DioException err,
    ErrorInterceptorHandler handler,
    int attempt,
  ) async {
    await Future<void>.delayed(retryDelay);
    final options = err.requestOptions;
    options.extra[_attemptKey] = attempt + 1;
    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    } catch (e) {
      handler.next(DioException(requestOptions: options, error: e));
    }
  }
}
