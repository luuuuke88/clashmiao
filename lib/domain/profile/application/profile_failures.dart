import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/data/subscription_fetch.dart';
import 'package:dio/dio.dart';

/// 订阅存储相关的异常 → 给用户看的本地化文案；不属于这一类返回 null，
/// 由调用方用自己场景的兜底文案。
///
/// 目前只有一类需要专门提示：存储版本高于当前 App（用户降级运行）时订阅存储
/// 进入只读模式，任何会写订阅的入口都会收到 [StoreReadOnlyException]，
/// 统一提示「请升级 App 后再修改订阅」，而不是各自展示异常原文。
///
/// [translations] 是惰性取值：只有真的是只读异常时才会求值，避免普通失败路径
/// 为了一个用不上的文案去读 provider。
String? profileStoreErrorMessage(
  Object error,
  TranslationsEn Function() translations,
) => error is StoreReadOnlyException
    ? translations().failure.profiles.readOnlyUpgrade
    : null;

/// [error] 是否表示「刷新结果因订阅期间被改动而作废」。
///
/// 这是预期内的取消，不是失败：手动刷新、详情页、首页刷新应静默跳过（或按
/// 「订阅仍然存在」处理），不要弹「刷新失败」。
bool isStaleRefresh(Object error) => error is ProfileUpdateStaleException;

/// 订阅操作（导入、刷新、保存、切换……）失败 → 给用户看的本地化文案。
///
/// [failed] 是该操作自己的失败文案（如 `t.profile.update.failureMsg`）；能从
/// 异常类型识别出原因时，用 `t.failure.withReason` 附上本地化的原因（网络超时、
/// 配置无效……）。只读存储直接给升级提示。异常原文绝不拼进文案。
///
/// 这是纯映射、不记日志：调用方在 catch 里**先**无条件 `logAppFailure`（不看
/// `mounted`），再在页面仍挂载时用它生成提示——日志不能跟着界面反馈一起被
/// `mounted` 挡掉。
String profileFailureMessage(
  Object error,
  TranslationsEn t, {
  required String failed,
}) {
  if (error is StoreReadOnlyException) {
    return t.failure.profiles.readOnlyUpgrade;
  }
  final reason = _profileFailureReason(error, t);
  return reason == null
      ? failed
      : t.failure.withReason(message: failed, reason: reason);
}

String? _profileFailureReason(Object error, TranslationsEn t) {
  return switch (error) {
    // 内核 Parse 的稳定错误码（spec §6.4）：没有可用节点给可操作的提示，其余
    // （格式未知 / 链接不合法 / 选项不合法 …）统一是「配置无效」。
    ProfileValidationException(code: 'no-outbounds') =>
      t.proxies.emptyProxiesMsg,
    ProfileValidationException() ||
    FormatException() => t.failure.profiles.invalidConfig,
    SubscriptionFetchException(reason: SubscriptionFetchFailure.notAConfig) =>
      t.failure.profiles.invalidConfig,
    SubscriptionFetchException(reason: SubscriptionFetchFailure.noNodes) =>
      t.proxies.emptyProxiesMsg,
    DioException(type: DioExceptionType.badCertificate) =>
      t.failure.connection.badCertificate,
    DioException(type: DioExceptionType.badResponse) =>
      t.failure.connection.badResponse,
    DioException(
      type: DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout,
    ) ||
    TimeoutException() => t.failure.connection.timeout,
    DioException() ||
    SocketException() ||
    HandshakeException() => t.failure.connection.connectionError,
    _ => null,
  };
}
