import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// BoxService 单例
final boxServiceProvider = Provider<BoxService>((ref) {
  return BoxService();
});

/// 连接状态（核心层实时推送）
final boxStatusProvider = StreamProvider<BoxStatus>((ref) {
  final service = ref.watch(boxServiceProvider);
  return service.watchStatus();
});

/// 流量统计 — 仅在已连接时才订阅
final boxStatsProvider = StreamProvider<BoxStats>((ref) {
  final status = ref.watch(boxStatusProvider);
  if (status.valueOrNull is! BoxStarted) {
    return Stream.value(BoxStats.empty);
  }
  final service = ref.read(boxServiceProvider);
  return service.watchStats();
});

/// 代理分组 — 仅在已连接时才订阅 command client
final outboundGroupsProvider = StreamProvider<List<OutboundGroup>>((ref) {
  final status = ref.watch(boxStatusProvider);
  if (status.valueOrNull is! BoxStarted) {
    return Stream.value([]);
  }
  final service = ref.read(boxServiceProvider);
  return service.watchGroups();
});

/// 当前是否已连接
final isConnectedProvider = Provider<bool>((ref) {
  final status = ref.watch(boxStatusProvider);
  return status.valueOrNull is BoxStarted;
});
