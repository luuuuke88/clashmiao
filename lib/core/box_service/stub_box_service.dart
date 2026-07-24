import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';

/// 为什么退化到了 [StubBoxService]。
///
/// 这个区分是必要的：桩实现同时承担两种完全不同性质的角色——
/// 一种是**正常状态**（平台不支持、或者被测试当替身用），一种是**真实故障**
/// （桌面端 libcore 加载失败）。只有后者需要在界面上告警。
/// 不区分的话，要么真故障被静默吞掉（修复前的现状），要么所有把
/// `boxServiceProvider` 覆盖成桩实现的既有 widget 测试全部误报故障。
enum StubReason {
  /// 平台不支持，或被测试用作替身——不是错误状态，不需要提示用户。
  unsupported,

  /// 桌面端加载 libcore（`FFIBoxService`）抛异常，降级到桩实现。
  /// 这是真实故障：界面看起来一切正常，但所有连接功能都不工作。
  coreLoadFailed,
}

/// 桩实现，核心库未加载时使用
///
/// 所有操作返回空数据/抛出提示，不会崩溃
class StubBoxService implements BoxService {
  const StubBoxService({this.reason = StubReason.unsupported});

  /// 退化到桩实现的原因，见 [StubReason]。
  final StubReason reason;

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
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) => throw UnsupportedError('generateWarpConfig: 核心库未加载');

  @override
  Future<void> clearLogs() async {}

  @override
  Stream<List<String>> watchLogs(String path) => Stream.value([]);

  @override
  Stream<void> watchNetworkChanged() => const Stream.empty();

  @override
  Future<void> resetTunnel() async {}
}
