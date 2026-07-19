import 'dart:async';

import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:timezone_to_country/timezone_to_country.dart';

/// 首次启动地区自动识别：把国家码映射到本 App 的 (region, locale)。
///
/// 背景：onboarding_page.dart 的地区/语言此前只能靠用户手选（`_regionChoices`
/// + `_showRegionDialog`）——在中国/伊朗等地区打开也得手动翻列表。本文件是
/// 这个识别流程唯一的实现方，分两部分：
///
/// 1. [RegionDetectionService]：识别"当前国家码"，两级兜底——先试本地时区
///    推断（不发网络请求），失败/为空再兜底一次 IP 地理位置查询（2 秒超时）。
///    两级都失败时返回 `null`，调用方（onboarding 页）应保持 region/locale
///    不变，不阻塞、不崩溃、不弹错误。
/// 2. [mapCountryCodeToRegionLocale]：国家码 -> (region, locale) 的纯函数
///    映射，跟识别逻辑完全解耦，方便单测。
@immutable
class RegionLocaleMapping {
  const RegionLocaleMapping(this.region, this.locale);

  /// 对应 `network_settings.dart` 的 `_validRegions`
  /// （`{ir, cn, ru, af, id, other}`）。
  final String region;

  /// 对应 `AppLocale` 枚举。
  final AppLocale locale;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RegionLocaleMapping &&
          other.region == region &&
          other.locale == locale);

  @override
  int get hashCode => Object.hash(region, locale);

  @override
  String toString() => 'RegionLocaleMapping(region: $region, locale: $locale)';
}

/// 国家码 -> (region, locale) 纯函数映射。
///
/// 只覆盖 IR/CN/RU/AF/BR/TR 六个国家码 + 默认兜底：
/// - IR -> (ir, fa)
/// - CN -> (cn, zhCn)
/// - RU -> (ru, ru)
/// - AF -> (af, fa)
/// - BR -> (other, ptBr)（`_validRegions` 没有独立的 'br' region，映射到
///   'other'，但 locale 仍然给巴西葡语）
/// - TR -> (other, tr)（同上，`_validRegions` 没有独立的 'tr' region）
/// - 其余（含 `null`/空字符串/无法识别的国家码）-> (other, en)
///
/// 大小写、首尾空白容错——`'cn'`、`' CN '`、`'Cn'` 都能正确命中。
RegionLocaleMapping mapCountryCodeToRegionLocale(String? countryCode) {
  final normalized = (countryCode ?? '').trim().toUpperCase();
  return switch (normalized) {
    'IR' => const RegionLocaleMapping('ir', AppLocale.fa),
    'CN' => const RegionLocaleMapping('cn', AppLocale.zhCn),
    'RU' => const RegionLocaleMapping('ru', AppLocale.ru),
    'AF' => const RegionLocaleMapping('af', AppLocale.fa),
    'BR' => const RegionLocaleMapping('other', AppLocale.ptBr),
    'TR' => const RegionLocaleMapping('other', AppLocale.tr),
    _ => const RegionLocaleMapping('other', AppLocale.en),
  };
}

/// 是否应该在 onboarding 页触发一次自动识别。
///
/// 三个条件同时成立才自动识别：region 还没被用户手动改过（仍是
/// `network_settings.dart` 的默认值 `'other'`）、onboarding 还没标记完成、
/// 且用户从没手动选择过 region（[manuallySet] 为 `false`）。任一条件不满足
/// （已经手选过 region、onboarding 已完成、或者 [manuallySet] 为 `true`），
/// 都不再自动跑，避免覆盖用户已经做出的选择。
///
/// ## 为什么需要 [manuallySet]
///
/// 这个参数修复一个真实可复现的跨会话 bug：`network_settings.dart` 的
/// region 字段里，`'other'` 这个值既是"用户从没碰过"的默认哨兵值，又是一个
/// 合法的手选项——光凭 `currentRegion == 'other'` 无法区分这两种情况。
///
/// 复现路径：用户在 onboarding（只有一屏）里手动选了"其它"，`_applyRegion`
/// 已经把 region 持久化成了 `'other'`，但用户没来得及点"开始"就被打断
/// （来电/通知/App 被系统回收，移动端很常见）——`onboarding_done` 仍是
/// `false`。下次重开 App，`OnboardingPage` 重新 `initState`：只看
/// `currentRegion`/`onboardingDone` 这两个条件的旧版本，看到的状态和"第一次
/// 启动、什么都没选过"完全一样，于是照样判定"应该自动识别"，把用户刚手选的
/// "其它"确定性地覆盖回识别结果——而且每次重启都会覆盖一次，直到用户终于
/// 点完"开始"，不是一次性的窄竞态，是确定性的跨会话 bug。
///
/// 调用方（`onboarding_page.dart` 的 `_currentlyShouldAutoDetect`）用一个
/// 独立的 SharedPreferences 标记位（`clashmiao_region_manually_set`）记录
/// "用户是否手动选过地区"，读出来作为 [manuallySet] 传进来。这个标记只能在
/// 手选路径（`_onRegionManuallySelected`）写，绝不能塞进手选和自动识别共用
/// 的 `_applyRegion`——否则自动识别第一次跑完就会把自己标记成"手选"，这条
/// 守卫直接失效。
///
/// 保持纯函数：不在这里读 SharedPreferences，[manuallySet] 由调用方读取后
/// 传入，方便直接构造各种组合单测，不需要搭 provider/prefs 环境。
bool shouldAutoDetectRegion({
  required String currentRegion,
  required bool onboardingDone,
  required bool manuallySet,
}) {
  if (manuallySet) return false;
  return currentRegion == 'other' && !onboardingDone;
}

/// 单次 IP 兜底查询的超时（应用层硬超时，Dio 自身的 connect/receiveTimeout
/// 只在真实的 `IOHttpClientAdapter` 下由原生 socket 层强制执行——单测里的假
/// adapter 不受它约束，所以跟 `egress_ip_service.dart` 一样用
/// `Future.timeout` 在这一层再兜底一次，确保"最多等这么久"在任何 adapter 下
/// 都成立，也让单测可以用一个永不响应的假 adapter 精确触发这条路径）。
const _ipFallbackTimeout = Duration(seconds: 2);

/// 首次启动地区自动识别的两级兜底实现。
///
/// [detectCountryCode] 永远不抛异常——时区平台通道不可用/查不到、IP 请求
/// 失败、超时、JSON 畸形、字段缺失，统统吞掉，最终返回 `null`。这是
/// onboarding 页的锦上添花功能，绝不能因为一次识别失败拖住或搞崩首次启动
/// 流程。
class RegionDetectionService {
  RegionDetectionService({Dio? dio, Duration? ipTimeout})
    : _dio = dio ?? _buildDefaultDio(),
      _ipTimeout = ipTimeout ?? _ipFallbackTimeout;

  final Dio _dio;
  final Duration _ipTimeout;

  /// 参照实现同款服务：不需要 API key，纯 IP 地理位置查询，返回体带
  /// `country_code`（ISO 3166-1 alpha-2）字段。
  static const _ipEndpoint = 'https://api.ip.sb/geoip/';

  static Dio _buildDefaultDio() {
    // `preferTunnel: false`——纯直连，不经过本地 sing-box 的 mixed 端口。
    // 这是唯一一处刻意强制直连的调用点：这里要识别的是"设备当前所在的真实
    // 物理位置"（给 onboarding 页推荐 region/locale），如果走隧道，查到的会是
    // 隧道出口节点所在的国家，识别结果就错了，完全违背这个功能存在的意义。
    // 而且识别通常发生在 onboarding 阶段——用户大概率还没连接过 VPN，
    // mixed 端口本来也不一定在监听。
    return createAppHttpClient(
      preferTunnel: false,
      connectTimeout: _ipFallbackTimeout,
      receiveTimeout: _ipFallbackTimeout,
    );
  }

  /// 识别当前国家码（ISO 3166-1 alpha-2，大写）。
  ///
  /// 顺序：本地时区推断（[TimeZoneToCountry]，纯本地数据，不联网）->
  /// （为空/失败时）IP 地理位置查询兜底。两级都拿不到结果时返回 `null`。
  Future<String?> detectCountryCode() async {
    final fromTimeZone = await _detectFromTimeZone();
    if (fromTimeZone != null && fromTimeZone.isNotEmpty) {
      return fromTimeZone;
    }
    return _detectFromIp();
  }

  Future<String?> _detectFromTimeZone() async {
    try {
      return await TimeZoneToCountry.getLocalCountryCodeOrNull();
    } catch (e) {
      // 测试环境（无真机/无平台实现）或者设备时区数据异常时，
      // `flutter_timezone` 的 MethodChannel 调用会抛出——降级到 IP 兜底，
      // 不能让这个异常拖垮 onboarding 页面。
      debugPrint('RegionDetectionService: 时区推断国家码失败，降级到 IP 兜底: $e');
      return null;
    }
  }

  Future<String?> _detectFromIp() async {
    final cancelToken = CancelToken();
    try {
      final response = await _dio
          .get<dynamic>(_ipEndpoint, cancelToken: cancelToken)
          .timeout(
            _ipTimeout,
            onTimeout: () {
              cancelToken.cancel('RegionDetectionService: IP 兜底应用层超时');
              throw TimeoutException(
                'RegionDetectionService: IP 查询超过 $_ipTimeout',
                _ipTimeout,
              );
            },
          );
      return _parseCountryCode(response.data);
    } catch (e) {
      debugPrint('RegionDetectionService: IP 兜底查询失败，已忽略: $e');
      return null;
    }
  }

  String? _parseCountryCode(dynamic data) {
    if (data is! Map) return null;
    final code = data['country_code'];
    if (code is! String || code.isEmpty) return null;
    return code;
  }
}

final regionDetectionServiceProvider = Provider<RegionDetectionService>((ref) {
  return RegionDetectionService();
});
