import 'package:clashmiao/core/localization/translations.dart';

/// 格式化字节数为可读字符串
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 格式化速度
String formatSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

/// "这条订阅算不算无限期"的**唯一**判定。
///
/// 抽出来是因为到期信息在界面上有两种展示形态（剩余天数 vs 绝对日期），
/// 但"什么算无限期"必须是同一条规则——此前详情页用的是 `expire.year > 2099`，
/// 首页/列表用的是"剩余 > 365 天"，结果一条 2028 年到期的订阅在首页显示
/// "无限期"、在详情页显示一个具体日期，同一条订阅两个说法。
bool isEffectivelyUnlimited(DateTime? expire) {
  if (expire == null) return true;
  final remaining = expire.difference(DateTime.now());
  // 剩余超过一年当"无限期"处理，不然会显示一个没什么实际意义的三位数天数
  // （例如"还剩 730 天"）。
  return !remaining.isNegative && remaining.inDays > 365;
}

/// 格式化剩余天数（首页 footer / 订阅列表用）。
///
/// 文案走 i18n，复用 profile 模块已有的 key（跟
/// `lib/features/profile/widget/profiles_page.dart` 里的 `_formatExpire`
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

/// 检查字符串是否为有效 URL
bool isValidUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
