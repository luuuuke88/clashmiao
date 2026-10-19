import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 延迟相关逻辑读「现在」的唯一入口。
///
/// 缓存的测量时间戳、自动测速的 30 s 去重、「超过 5 分钟算过期」都读它，
/// 测试里覆盖成可控时钟即可，不必真等。
final latencyClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
