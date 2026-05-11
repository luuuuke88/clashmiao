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

/// 格式化时间差
String formatDuration(Duration duration) {
  if (duration.inDays > 0) return '${duration.inDays}天';
  if (duration.inHours > 0) return '${duration.inHours}小时';
  if (duration.inMinutes > 0) return '${duration.inMinutes}分钟';
  return '${duration.inSeconds}秒';
}

/// 格式化剩余天数
String formatExpireDate(DateTime? expire) {
  if (expire == null) return '永不过期';
  final remaining = expire.difference(DateTime.now());
  if (remaining.isNegative) return '已过期';
  return '剩余 ${remaining.inDays} 天';
}

/// 检查字符串是否为有效 URL
bool isValidUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
