import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';

/// main() 的常驻服务接线：建好 [residentServiceProviders] 的容器级订阅，再激活
/// 连接健康探测。返回的订阅由调用方持有到 App 结束（从不关闭）。
///
/// 抽成函数是为了让测试走和生产完全相同的入口（见
/// test/app/bootstrap/resident_services_test.dart）：在「页面全部暂停」的条件下，
/// 订阅变化仍要触发断开、手选重放与探测——退回只 read 一次时那些用例会失败。
List<ProviderSubscription<Object?>> startResidentServices(
  ProviderContainer container,
) {
  final subscriptions = listenResidentServices(
    container,
    residentServiceProviders,
  );
  // 连接健康探测（"已连接但实际不通"的黑洞检测）。周期探测只由这里显式激活，
  // 不会因为首页 watch 了这个 provider 就自动开始——探测该活多久取决于 App，
  // 不取决于某个页面在不在（详见 ConnectionHealthMonitor 类文档）。
  container.read(connectionHealthProvider.notifier).start();
  return subscriptions;
}

/// App 启动时就要创建、并且在整个生命周期里都必须保持活跃的 provider。
///
/// 不能只 `container.read` 一次：Riverpod 3 里 provider 的监听者全部暂停后
/// （由「活跃」变「不活跃」），它会停用自己内部的 `ref.listen` 订阅，上游的
/// 派生 provider（如激活订阅）随之不再重算，变化传不到服务里。页面上的 watch
/// 恰恰会被暂停——ShellPage 把非当前 tab 包在 `TickerMode(enabled: false)` 里，
/// Consumer 会随之暂停监听。只 read 的话，「删除激活订阅 → 断开」「切订阅 → 重新应用」这类
/// 只由服务内部 `ref.listen` 驱动的逻辑，会在用户停留在别的 tab 时静默失效。
/// 容器级 listen 不受 TickerMode 影响，也不会被暂停（见 [listenResidentServices]）。
@visibleForTesting
final residentServiceProviders = <ProviderListenable<Object?>>[
  // 深链导入：监听 sing-box:// clash:// clashmeta:// clashmiao:// 链接
  // （AndroidManifest.xml 已注册好 intent-filter，点击这类链接能拉起 App）。
  // 尽早创建 DeepLinkService——它在创建时自己发起监听（不阻塞启动；解析/导入
  // 结果由 ShellPage 监听后弹 toast）。
  deepLinkServiceProvider,
  // 连接控制器与出口 IP 探测随 App 创建（而不是等首页第一次 build）：它们订阅
  // 内核快照，冷启动挂上运行中隧道、或磁贴 / 开机自启抢先把隧道拉起来时，状态
  // 与出口 IP 都不依赖某个页面在不在。
  connectionControllerProvider,
  egressIpProbeProvider,
  // 连接健康探测：跟随连接状态的 ref.listen 挂在它自己身上，同样需要常驻。
  connectionHealthProvider,
  // 测速协调器：连接后的自动测速、断开时停测都靠它内部的 ref.listen。以前由
  // 常驻 IndexedStack 里的代理页 watch 保活，现在代理页不在前台时会暂停。
  latencyTestCoordinatorProvider,
  // 流量统计是平台 EventChannel 的流，只有首页在看。首页被切走时 Riverpod 3
  // 会暂停底层订阅，而 broadcast 流暂停期间每秒的推送会一直缓存、回到首页时
  // 一次性涌出。保持常驻订阅，与 Riverpod 2 的行为一致。
  boxStatsProvider,
];

/// 对每个 provider 建一个容器级、永不暂停的空监听，返回订阅供调用方持有。
@visibleForTesting
List<ProviderSubscription<Object?>> listenResidentServices(
  ProviderContainer container,
  List<ProviderListenable<Object?>> providers,
) => [for (final p in providers) container.listen(p, (_, _) {})];
