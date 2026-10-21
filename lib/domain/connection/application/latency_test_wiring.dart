// 测速协调器的 Riverpod 接线。
//
// 协调器本身（纯逻辑）在 `domain/routing`；它要跟着「是否已连接」这份单一真值
// 走，而 domain 内部顺序是 routing < connection，routing 不能反向依赖连接层，
// 所以接线放在连接层。

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/application/latency_test_coordinator.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

/// 协调器的 Riverpod 接线。
///
/// 代理页常驻（`IndexedStack`），它 watch 这个 provider，协调器就与连接状态
/// 同生共死；单独读它的测试也能完整工作。
final latencyTestCoordinatorProvider =
    StateNotifierProvider<LatencyTestCoordinator, LatencyTestState>((ref) {
      final coordinator = LatencyTestCoordinator(
        urlTest: (groupTag) => ref.read(boxServiceProvider).urlTest(groupTag),
        liveGroups: () =>
            ref.read(outboundGroupsProvider).value ?? const <OutboundGroup>[],
        cache: () => ref.read(proxyDelayCacheProvider),
        recordMeasured: (msByTag, at) => ref
            .read(proxyDelayCacheProvider.notifier)
            .recordMeasured(msByTag, at: at),
        recordFailed: (tags, at) => ref
            .read(proxyDelayCacheProvider.notifier)
            .recordFailed(tags, at: at),
        now: ref.read(latencyClockProvider),
      );
      ref.listen<bool>(
        isConnectedProvider,
        (_, connected) => coordinator.onConnectionChanged(connected),
        fireImmediately: true,
      );
      ref.listen<AsyncValue<List<OutboundGroup>>>(
        outboundGroupsProvider,
        (_, next) => coordinator.onGroups(next.value ?? const []),
      );
      ref.listen<String?>(
        activeProfileProvider.select((profile) => profile.value?.id),
        (previous, next) {
          // previous 为空是首次加载出订阅，不是「切订阅」。
          if (previous != null && previous != next) {
            coordinator.onProfileChanged();
          }
        },
      );
      return coordinator;
    });
