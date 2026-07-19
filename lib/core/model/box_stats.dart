/// 流量统计数据
class BoxStats {
  const BoxStats({
    required this.uplink,
    required this.downlink,
    required this.uplinkTotal,
    required this.downlinkTotal,
    required this.connectionsIn,
    required this.connectionsOut,
  });

  /// 上行实时速率 (bytes/s)
  final int uplink;

  /// 下行实时速率 (bytes/s)
  final int downlink;

  /// 上行累计流量 (bytes)
  final int uplinkTotal;

  /// 下行累计流量 (bytes)
  final int downlinkTotal;

  /// 入站连接数
  final int connectionsIn;

  /// 出站连接数
  final int connectionsOut;

  /// 原生层推的 stats 事件用连字符 key（iOS `TrafficStatsStream.swift`、
  /// Android `StreamBridge.kt` 的 `StatsSubscriber.onStats`，桌面端 FFI
  /// 编译产物里也是同样的字面量）：`uplink` / `downlink` / `uplink-total` /
  /// `downlink-total` / `connections-in` / `connections-out`。
  /// 之前这里 uplinkTotal/downlinkTotal 读的是驼峰 key（`uplinkTotal`），
  /// 跟原生实际下发的连字符 key 对不上，两条平台链路都会导致这两个字段
  /// 一直解析成默认值 0；connectionsIn/connectionsOut 则是模型里完全没有
  /// 这两个字段，原生下发了也没地方放，被静默丢弃。这里统一按连字符 key
  /// 解析，两个问题一起修。
  factory BoxStats.fromJson(Map<String, dynamic> json) {
    return BoxStats(
      uplink: json['uplink'] as int? ?? 0,
      downlink: json['downlink'] as int? ?? 0,
      uplinkTotal: json['uplink-total'] as int? ?? 0,
      downlinkTotal: json['downlink-total'] as int? ?? 0,
      connectionsIn: json['connections-in'] as int? ?? 0,
      connectionsOut: json['connections-out'] as int? ?? 0,
    );
  }

  static const BoxStats empty = BoxStats(
    uplink: 0,
    downlink: 0,
    uplinkTotal: 0,
    downlinkTotal: 0,
    connectionsIn: 0,
    connectionsOut: 0,
  );
}
