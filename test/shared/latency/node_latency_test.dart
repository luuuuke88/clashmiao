import 'package:clashmiao/shared/latency/node_latency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 20, 12);
  DateTime ago(Duration d) => now.subtract(d);

  NodeLatency resolve({
    int liveMs = 0,
    int? cachedMs,
    DateTime? cachedAt,
    bool testing = false,
    bool timedOut = false,
    bool cacheIsFallback = true,
  }) => resolveNodeLatency(
    liveMs: liveMs,
    cachedMs: cachedMs,
    cachedAt: cachedAt,
    testing: testing,
    timedOut: timedOut,
    now: now,
    cacheIsFallback: cacheIsFallback,
  );

  test('什么都没有：未测', () {
    final r = resolve();
    expect(r.state, LatencyDisplayState.untested);
    expect(r.ms, isNull);
  });

  test('实时有值且新鲜：成功', () {
    final r = resolve(
      liveMs: 120,
      cachedMs: 120,
      cachedAt: ago(const Duration(seconds: 30)),
    );
    expect(r.state, LatencyDisplayState.success);
    expect(r.ms, 120);
  });

  test('实时有值但缓存里的测量时间已超过 5 分钟：历史值', () {
    final r = resolve(
      liveMs: 120,
      cachedMs: 120,
      cachedAt: ago(const Duration(minutes: 6)),
    );
    expect(r.state, LatencyDisplayState.stale);
    expect(r.ms, 120);
  });

  test('恰好 5 分钟还算新鲜，超过才是历史值', () {
    expect(
      resolve(cachedMs: 80, cachedAt: ago(const Duration(minutes: 5))).state,
      LatencyDisplayState.success,
    );
    expect(
      resolve(
        cachedMs: 80,
        cachedAt: ago(const Duration(minutes: 5, seconds: 1)),
      ).state,
      LatencyDisplayState.stale,
    );
  });

  test('实时有值而缓存还没写进去：按刚测到处理（成功）', () {
    expect(resolve(liveMs: 90).state, LatencyDisplayState.success);
  });

  test('只有缓存且新鲜（刚断开）：成功；旧格式无时间：历史值', () {
    expect(
      resolve(cachedMs: 200, cachedAt: ago(const Duration(minutes: 1))).state,
      LatencyDisplayState.success,
    );
    final legacy = resolve(cachedMs: 200);
    expect(legacy.state, LatencyDisplayState.stale);
    expect(legacy.ms, 200);
  });

  test('测量中：保留旧值；无旧值则只有占位', () {
    final withOld = resolve(
      testing: true,
      cachedMs: 150,
      cachedAt: ago(const Duration(minutes: 10)),
    );
    expect(withOld.state, LatencyDisplayState.testing);
    expect(withOld.ms, 150);

    final noOld = resolve(testing: true);
    expect(noOld.state, LatencyDisplayState.testing);
    expect(noOld.ms, isNull);
  });

  test('测量中、实时值是开测前的旧值：保留旧值，状态是测量中而不是成功', () {
    final r = resolve(
      testing: true,
      liveMs: 77,
      cachedMs: 77,
      cachedAt: ago(const Duration(minutes: 1)),
    );
    expect(r.state, LatencyDisplayState.testing);
    expect(r.ms, 77);
  });

  test('同一轮里已经出了结果的节点（不再等结果）：直接显示新值', () {
    final r = resolve(
      liveMs: 88,
      cachedMs: 88,
      cachedAt: ago(const Duration(seconds: 1)),
    );
    expect(r.state, LatencyDisplayState.success);
    expect(r.ms, 88);
  });

  test('旧格式无时间的缓存与实时值相同：仍是历史值，直到确认出新结果', () {
    for (final fallback in [true, false]) {
      final r = resolve(liveMs: 120, cachedMs: 120, cacheIsFallback: fallback);
      expect(r.state, LatencyDisplayState.stale, reason: 'fallback=$fallback');
      expect(r.ms, 120);
    }
    // 确认出新结果后缓存带上了测量时间：成功。
    expect(
      resolve(liveMs: 120, cachedMs: 120, cachedAt: now).state,
      LatencyDisplayState.success,
    );
  });

  test('本轮没确认出结果的节点：即使实时值还是旧数字也显示超时', () {
    final r = resolve(
      liveMs: 100,
      cachedMs: 100,
      cachedAt: ago(const Duration(minutes: 1)),
      timedOut: true,
    );
    expect(r.state, LatencyDisplayState.timeout);
    expect(r.ms, isNull);
  });

  test('本轮超时：显示超时，且不再用缓存里的旧数字顶替', () {
    final r = resolve(
      timedOut: true,
      cachedMs: 150,
      cachedAt: ago(const Duration(minutes: 1)),
    );
    expect(r.state, LatencyDisplayState.timeout);
    expect(r.ms, isNull);
  });

  test('内核返回超时哨兵（65535）：超时', () {
    expect(resolve(liveMs: 65535).state, LatencyDisplayState.timeout);
  });

  test('新一轮开始后（testing）压过上一轮的超时标记', () {
    expect(
      resolve(testing: true, timedOut: true).state,
      LatencyDisplayState.testing,
    );
  });

  test('缓存里的哨兵值不当作有效延迟', () {
    expect(resolve(cachedMs: 65535).state, LatencyDisplayState.untested);
  });

  group('已连接且有真实实时分组（cacheIsFallback=false）', () {
    test('实时值缺席时不拿缓存顶替：未测', () {
      final r = resolve(
        cachedMs: 999,
        cachedAt: ago(const Duration(minutes: 1)),
        cacheIsFallback: false,
      );
      expect(r.state, LatencyDisplayState.untested);
      expect(r.ms, isNull);
    });

    test('测量中保留缓存旧值（实时值缺席）', () {
      final r = resolve(
        testing: true,
        cachedMs: 999,
        cachedAt: ago(const Duration(minutes: 1)),
        cacheIsFallback: false,
      );
      expect(r.state, LatencyDisplayState.testing);
      expect(r.ms, 999);
    });

    test('测完（不再测量中）且本轮超时：不再带缓存旧值', () {
      final r = resolve(
        timedOut: true,
        cachedMs: 999,
        cachedAt: ago(const Duration(minutes: 1)),
        cacheIsFallback: false,
      );
      expect(r.state, LatencyDisplayState.timeout);
      expect(r.ms, isNull);
    });

    test('实时值存在时缓存仍用于判断过期', () {
      final r = resolve(
        liveMs: 120,
        cachedMs: 120,
        cachedAt: ago(const Duration(minutes: 9)),
        cacheIsFallback: false,
      );
      expect(r.state, LatencyDisplayState.stale);
      expect(r.ms, 120);
    });
  });
}
