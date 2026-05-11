import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';

/// 桩实现，核心库未加载时使用
///
/// 所有操作返回空数据/抛出提示，不会崩溃
class StubBoxService implements BoxService {
  @override
  Future<void> init() async {}

  @override
  Future<void> setup(AppDirectories directories, {bool debug = false}) async {}

  @override
  Future<void> changeConfigOptions(String jsonOptions) async {}

  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async => '核心库未加载';

  @override
  Future<void> start(String configPath, {String name = ''}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restart(String configPath, {String name = ''}) async {}

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {}

  @override
  Future<void> urlTest(String groupTag) async {}

  @override
  Stream<BoxStatus> watchStatus() => Stream.value(const BoxStopped());

  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();

  @override
  Stream<BoxStats> watchStats() => Stream.value(BoxStats.empty);

  @override
  Stream<List<OutboundGroup>> watchGroups() => Stream.value([]);

  @override
  Future<String?> generateFullConfig(String path) async => null;

  @override
  Future<void> clearLogs() async {}

  @override
  Stream<List<String>> watchLogs(String path) => Stream.value([]);
}
