import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';

/// [BoxService] 的全空实现，给测试替身当基类用：`extends FakeBoxService`
/// 之后只重写自己关心的那几个方法。
///
/// ## 为什么需要它，而不是共用一个"大而全"的替身
///
/// 仓库里有 6 个测试替身实现 BoxService，规模从 138 行 19 个字段到 11 行
/// 3 个字段——它们**不是重复，是各自裁剪过的**。硬合并成一个类会造出一个
/// 19+ 字段的杂物箱，让只需要 3 个字段的测试也得先读懂整个类，可读性反而更差。
///
/// 真正重复的是别的东西：`implements BoxService` 要求实现**每一个**成员，于是
/// 每个替身都得抄大约 40 行 `@override` 空方法，真正有意义的那几行淹没在里面。
/// 这个基类只消除那部分噪音，每个替身保留自己裁剪过的表面。
///
/// ## 为什么不用 `StubBoxService`
///
/// `ConnectionController` 会把 `StubBoxService` 识别出来（`_isStub`），
/// `connect()`/`disconnect()` 直接早返回——凡是要验证"到底有没有调用内核"的
/// 测试都不能拿它当基类。这个类是普通实现，不会被识别成 stub。
class FakeBoxService implements BoxService {
  const FakeBoxService();

  @override
  Future<void> init() async {}
  @override
  Future<void> setup(AppDirectories directories, {bool debug = false}) async {}
  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async => null;
  @override
  Future<void> changeConfigOptions(String jsonOptions) async {}
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
  Stream<BoxStatus> watchStatus() => const Stream.empty();
  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String path) async => null;
  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String path) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => const Stream.empty();
  @override
  Future<void> resetTunnel() async {}
}
