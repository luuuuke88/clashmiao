import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
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

/// 连接状态（核心层实时推送）
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
