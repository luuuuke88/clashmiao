// 延迟数值与时效的共用口径：缓存、自动测速、界面展示都读这里，免得各写一份
// 阈值最后对不上。

/// 内核用来表示「测过但超时/失败」的哨兵延迟：大于它的值不是真实毫秒数。
const int kDelayTimeoutSentinelMs = 65000;

/// 是不是一个可以展示、可以缓存的真实延迟（毫秒）。
bool isMeasurableDelay(int? ms) =>
    ms != null && ms > 0 && ms <= kDelayTimeoutSentinelMs;

/// 延迟超过这个时长就算历史值，自动测速也据此判断「数据过期」。
const Duration kLatencyStaleAfter = Duration(minutes: 5);
