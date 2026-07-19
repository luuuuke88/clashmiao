import 'package:clashmiao/core/model/box_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原生层（iOS `TrafficStatsStream.swift` / Android `StreamBridge.kt` 的
/// `StatsSubscriber.onStats`，桌面端 `libcore` 编译产物里也能直接 strings
/// 出同样的字面量）推的 stats 事件用的是连字符 key：
/// `uplink` / `downlink` / `uplink-total` / `downlink-total` /
/// `connections-in` / `connections-out`。
///
/// `BoxStats` 之前：
///   1. 完全没有 connectionsIn/connectionsOut 字段——原生侧下发了也会被
///      "有 key 没地方放" 静默丢弃。
///   2. `uplinkTotal`/`downlinkTotal` 的 fromJson 读的是 `json['uplinkTotal']`
///      （驼峰、无连字符），跟原生实际下发的 `uplink-total`/`downlink-total`
///      对不上——移动端和桌面端两条链路都会导致这两个字段永远解析成默认值 0，
///      跟"字段缺失静默丢弃"是同一类 bug，只是发生在已存在的字段上。
///
/// 这份测试锁住原生实际下发的连字符 key 格式，两个问题一起修。
void main() {
  group('BoxStats.fromJson', () {
    test('按原生实际下发的连字符 key 解析 uplink/downlink 瞬时速率', () {
      final stats = BoxStats.fromJson({'uplink': 100, 'downlink': 200});
      expect(stats.uplink, 100);
      expect(stats.downlink, 200);
    });

    test('按连字符 key uplink-total/downlink-total 解析累计流量（此前是驼峰键，读不到，恒为 0）', () {
      final stats = BoxStats.fromJson({
        'uplink-total': 123456,
        'downlink-total': 654321,
      });
      expect(stats.uplinkTotal, 123456);
      expect(stats.downlinkTotal, 654321);
    });

    test('按连字符 key connections-in/connections-out 解析连接数（此前模型里根本没有这两个字段）', () {
      final stats = BoxStats.fromJson({
        'connections-in': 5,
        'connections-out': 7,
      });
      expect(stats.connectionsIn, 5);
      expect(stats.connectionsOut, 7);
    });

    test('完整原生 payload 六个字段全部正确解析', () {
      final stats = BoxStats.fromJson({
        'connections-in': 3,
        'connections-out': 4,
        'uplink': 10,
        'downlink': 20,
        'uplink-total': 1000,
        'downlink-total': 2000,
      });
      expect(stats.connectionsIn, 3);
      expect(stats.connectionsOut, 4);
      expect(stats.uplink, 10);
      expect(stats.downlink, 20);
      expect(stats.uplinkTotal, 1000);
      expect(stats.downlinkTotal, 2000);
    });

    test('缺字段时全部默认 0，不抛异常', () {
      final stats = BoxStats.fromJson(<String, dynamic>{});
      expect(stats.uplink, 0);
      expect(stats.downlink, 0);
      expect(stats.uplinkTotal, 0);
      expect(stats.downlinkTotal, 0);
      expect(stats.connectionsIn, 0);
      expect(stats.connectionsOut, 0);
    });
  });

  group('BoxStats.empty', () {
    test('包含 connectionsIn/connectionsOut，全部为 0', () {
      expect(BoxStats.empty.connectionsIn, 0);
      expect(BoxStats.empty.connectionsOut, 0);
      expect(BoxStats.empty.uplink, 0);
      expect(BoxStats.empty.downlink, 0);
      expect(BoxStats.empty.uplinkTotal, 0);
      expect(BoxStats.empty.downlinkTotal, 0);
    });
  });

  group('BoxStats 构造函数', () {
    test('可以显式传入 connectionsIn/connectionsOut', () {
      const stats = BoxStats(
        uplink: 1,
        downlink: 2,
        uplinkTotal: 3,
        downlinkTotal: 4,
        connectionsIn: 5,
        connectionsOut: 6,
      );
      expect(stats.connectionsIn, 5);
      expect(stats.connectionsOut, 6);
    });
  });
}
