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

/// 格式化剩余天数
///
/// 文案走 i18n，复用 profile 模块已有的 key（跟
/// `lib/features/profile/widget/profiles_page.dart` 里的 `_formatExpire`
/// 是同一套 [SubscriptionInfo] 语义，故意不重复造新 key）。
String formatExpireDate(DateTime? expire, TranslationsEn t) {
  if (expire == null) return t.profile.details.unlimited;
  final remaining = expire.difference(DateTime.now());
  if (remaining.isNegative) return t.profile.subscription.expired;
  return t.profile.overview.remainingDays(days: remaining.inDays);
}

/// 检查字符串是否为有效 URL
bool isValidUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
