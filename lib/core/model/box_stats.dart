/// 流量统计数据
class BoxStats {
  const BoxStats({
    required this.uplink,
    required this.downlink,
    required this.uplinkTotal,
    required this.downlinkTotal,
  });

  /// 上行实时速率 (bytes/s)
  final int uplink;

  /// 下行实时速率 (bytes/s)
  final int downlink;

  /// 上行累计流量 (bytes)
  final int uplinkTotal;

  /// 下行累计流量 (bytes)
  final int downlinkTotal;

  factory BoxStats.fromJson(Map<String, dynamic> json) {
    return BoxStats(
      uplink: json['uplink'] as int? ?? 0,
      downlink: json['downlink'] as int? ?? 0,
      uplinkTotal: json['uplinkTotal'] as int? ?? 0,
      downlinkTotal: json['downlinkTotal'] as int? ?? 0,
    );
  }

  static const BoxStats empty = BoxStats(
    uplink: 0,
    downlink: 0,
    uplinkTotal: 0,
    downlinkTotal: 0,
  );
}
