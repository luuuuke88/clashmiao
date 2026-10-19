import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/utils/formatters.dart';

/// 格式化剩余天数（首页 footer / 订阅列表用）。
///
/// 文案走 i18n，复用 profile 模块已有的 key（跟
/// `lib/features/profile/presentation/profiles_page.dart` 里的 `_formatExpire`
/// 是同一套 [SubscriptionInfo] 语义，故意不重复造新 key）。
String formatExpireDate(DateTime? expire, TranslationsEn t) {
  if (isEffectivelyUnlimited(expire)) return t.profile.details.unlimited;
  final remaining = expire!.difference(DateTime.now());
  if (remaining.isNegative) return t.profile.subscription.expired;
  return t.profile.overview.remainingDays(days: remaining.inDays);
}

/// 格式化到期日为**绝对日期**（订阅详情页用）。
///
/// 用 ISO 风格的 `YYYY-MM-DD`，不是本地化日期格式：此前这里硬编码成
/// `${year}年${month}月${day}号`，非中文用户看到的也是中文。改用 `intl` 的
/// `DateFormat` 需要给非英语 locale 跑 `initializeDateFormatting()`，等于给
/// 启动流程加一个新的失败点——为一个日期显示不值。ISO 格式在任何语言下都
/// 无歧义，且零额外依赖。
///
/// "无限期"的判定跟 [formatExpireDate] 共用 [isEffectivelyUnlimited]。
String formatExpireAbsolute(DateTime? expire, TranslationsEn t) {
  if (isEffectivelyUnlimited(expire)) return t.profile.details.unlimited;
  final d = expire!;
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}
