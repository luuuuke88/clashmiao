import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/core/box_service/model/box_stats.dart';
import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// BoxService 单例
/// 把 [service] 的资源释放挂到 [ref] 的销毁上（仅当它实现了
/// [DisposableBoxService]）。
///
/// 抽成独立函数是为了可测：`boxServiceProvider` 内部直接 `BoxService()`，测试里
/// 没法注入一个假的实现进去（`FFIBoxService` 需要真的 dylib，造不出来）。这个
/// 函数可以配一个测试里自建的 Provider 直接验证"容器销毁 → dispose 被调用"。
///
/// 不 await：`onDispose` 的回调是同步签名，而且 provider 销毁时没人还在等这个
/// 清理完成。释放失败也不该阻断销毁流程，所以额外兜一层 catch——否则一个
/// dispose 异常会变成没人接的异步异常。
@visibleForTesting
void wireBoxServiceDisposal(Ref ref, BoxService service) {
  if (service is! DisposableBoxService) return;
  final disposable = service as DisposableBoxService;
  ref.onDispose(() {
    unawaited(
      disposable.dispose().catchError((Object e) {
        debugPrint('BoxService dispose 失败: $e');
      }),
    );
  });
}

final boxServiceProvider = Provider<BoxService>((ref) {
  final service = BoxService();
  // 实现了 [DisposableBoxService] 的实现（目前只有桌面端的 FFIBoxService）持有
  // StreamController 和 ReceivePort。生产环境里这个 provider 与进程同生命周期，
  // 所以正常运行时这段不会被触发；它保证的是"service 被重建"时旧实例的资源能
  // 真正放掉——否则 ReceivePort 会让对应的 isolate 端口一直存活。
  wireBoxServiceDisposal(ref, service);
  return service;
});

/// 核心层实时推送的运行状态。
///
/// **只**用来给流量统计 / 代理分组这两路订阅做门控（内核没起来就没有可订阅的
/// command server）。界面上一切「是否已连接」的判断都读
/// `connectionControllerProvider` / `isConnectedProvider`（单一真值），架构测试
/// 禁止 `features/` 与 `app/` 引用本 provider。
final boxStatusProvider = StreamProvider<BoxStatus>((ref) {
  final service = ref.watch(boxServiceProvider);
  return service.watchStatus();
});

/// 非致命错误流，UI 用 ref.listen 订阅后弹 toast / dialog。
final boxAlertsProvider = StreamProvider<BoxAlert>((ref) {
  final service = ref.watch(boxServiceProvider);
  return service.watchAlerts();
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

/// 正在运行的内核实例：`(epoch, attempt)`，仅内核快照为 started 时非空。
///
/// 取自权威内核快照（不是兼容的 status 流）：分组订阅按它重建，于是每份实时
/// 分组都能归属到产生它的那个内核实例。
typedef KernelInstance = ({String epoch, int attempt});

final runningKernelInstanceProvider = StreamProvider<KernelInstance?>((ref) {
  final port = ref.watch(kernelPortProvider);
  return port
      .watch()
      .map<KernelInstance?>(
        (s) => s.status == KernelStatus.started
            ? (epoch: s.epoch, attempt: s.attempt)
            : null,
      )
      .distinct();
});

/// 归属到某个内核实例的一份实时分组（只含至少有一个节点的分组列表）。
@immutable
class LiveGroups {
  const LiveGroups(this.instance, this.groups);

  final KernelInstance instance;
  final List<OutboundGroup> groups;

  /// 运行时真实存在的分组 tag。
  Set<String> get tags => {
    for (final g in groups)
      if (g.items.isNotEmpty) g.tag,
  };
}

/// 当前内核实例的实时分组（带实例归属）；实例没在运行、或还没收到非空分组时为
/// `null`。手选校验 / 重放与出口探测按实例归属判断「这份分组是不是这次启动的」。
///
/// **这是平台分组流在 Dart 侧唯一的订阅者**，其它地方（[outboundGroupsProvider]
/// 等）一律从它派生。原因：原生只在 command client 连上新实例时推一次「当前
/// 分组」，之后只在测速结果变化时才推；平台流是 broadcast、不回放。若有两个
/// provider 各自订阅，内核在 App 后台期间重启时，被读到的那个（手选重放会读）
/// 先重新订阅、拿走这次推送，只被界面监听的那个要等回到前台的下一帧才重建、
/// 重新订阅——此时监听数不为 0、平台订阅不会重建，它永远收不到这份分组（真机
/// 验收 BUG-A：后台重启内核后线路页一直「线路信息加载中」）。只有一个订阅者时，
/// 每次换实例都是「取消（监听数归 0）→ 重新监听 → 原生重连、推当前分组」，最新
/// 值由本 provider 的状态保存，后来者直接读到。
final liveGroupsProvider = StreamProvider<LiveGroups?>((ref) {
  final instance = ref.watch(runningKernelInstanceProvider).valueOrNull;
  if (instance == null) return Stream.value(null);
  final service = ref.read(boxServiceProvider);
  return service
      .watchGroups()
      .where((groups) => groups.any((g) => g.items.isNotEmpty))
      .map((groups) => LiveGroups(instance, groups));
});

/// 代理分组（不带实例归属的视图），从 [liveGroupsProvider] 派生、不另开平台
/// 订阅；内核实例没在运行时为空列表。
final outboundGroupsProvider = StreamProvider<List<OutboundGroup>>((ref) {
  final live = ref.watch(liveGroupsProvider);
  return switch (live) {
    AsyncData(:final value) => Stream.value(value?.groups ?? const []),
    AsyncError(:final error, :final stackTrace) => Stream.error(
      error,
      stackTrace,
    ),
    _ => const Stream<List<OutboundGroup>>.empty(),
  };
});

/// 桌面端 libcore 加载失败、整个 App 实际是个空壳时为 true。
///
/// 只认 [StubReason.coreLoadFailed]，不认"是不是桩实现"——桩实现同时被大量
/// widget 测试当替身用（`boxServiceProvider.overrideWithValue(StubBoxService())`），
/// 按类型判断会让那些测试全部误报故障。见 [StubReason] 的文档。
final coreLibraryMissingProvider = Provider<bool>((ref) {
  final service = ref.watch(boxServiceProvider);
  return service is StubBoxService &&
      service.reason == StubReason.coreLoadFailed;
});
