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

/// 检查字符串是否为有效 URL
bool isValidUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
