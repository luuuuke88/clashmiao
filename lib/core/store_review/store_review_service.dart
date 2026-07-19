import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

/// 首次成功连接后是否已经请求过商店评分弹窗的持久化标记位。
const _storeReviewRequestedPrefKey = 'clashmiao_store_review_requested';

/// 请求 App Store / Play Store 内置评分弹窗（`in_app_review`）的薄封装。
///
/// 背景：`in_app_review` 包的 [InAppReview] 是私有构造的单例
/// (`InAppReview._()`)，没法在测试里用假实现替换/子类化——这层封装把
/// "判断是否已经弹过 + 调用平台评分弹窗"包成可以被 Riverpod 覆盖的服务，
/// [ConnectionController] 每次真正"进入" [BoxStarted]（跟触觉反馈同一个
/// 触发点）都调用一次 [maybeRequestReview]，具体"只弹一次"的持久化保护
/// 完全在这个类内部完成——调用方不需要、也不应该自己去重复判断。
class StoreReviewService {
  StoreReviewService(this._ref);

  final Ref _ref;

  /// 已经成功请求过一次就什么都不做。
  ///
  /// 持久化标记只在真正判定"设备可以弹" ([InAppReview.isAvailable] 为
  /// true) 之后、真正调用 [InAppReview.requestReview] 之前写入——哪怕
  /// `requestReview()` 本身失败或者系统因为频率限制没有真的弹出来，也认为
  /// "已经尝试过"，不再重试。这是有意的取舍：这类锦上添花的一次性动作，
  /// 宁可偶尔漏弹，也不要每次连接都打扰用户。
  ///
  /// 反过来，如果 [InAppReview.isAvailable] 返回 false（比如 Play Store
  /// 未安装、系统版本过低等一次性/环境性原因），则不写标记——下次连接时
  /// 环境可能已经变化，值得再判断一次。
  Future<void> maybeRequestReview() async {
    final prefs = _ref.read(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return;
    if (prefs.getBool(_storeReviewRequestedPrefKey) ?? false) return;

    try {
      if (!await InAppReview.instance.isAvailable()) return;
      await prefs.setBool(_storeReviewRequestedPrefKey, true);
      await InAppReview.instance.requestReview();
    } catch (e) {
      // 评分请求是锦上添花的副作用，绝不能因为插件调用失败拖累调用方
      // （VPN 连接主流程）。
      debugPrint('StoreReviewService: 请求商店评分失败，已忽略: $e');
    }
  }
}

final storeReviewServiceProvider = Provider<StoreReviewService>((ref) {
  return StoreReviewService(ref);
});
