// 手选节点流程：先把新选择写入存储，再让内核切换，失败（非 stale）则回滚。
//
// 为什么先写存储：选择存储是「用户最后一次选了什么」的唯一真值，手选重放
// （`ConnectionController` 在每个新 attempt 进入 started 后执行）每一项都读
// 存储里的最新值。如果等内核切换成功才写存储，就会出现「旧重放悬停 → 用户
// 新选择 → 旧重放继续并把旧值写回内核」的错乱；先写存储，重放自己会收敛到
// 用户最后的选择（见控制器的重放循环）。
//
// 为什么按意图代际：同一 (订阅, 组) 的每次点击是一个新的「意图代际」。旧意图
// 在 stale 之后要先去问内核权威 attempt（异步），这期间用户可能已经在新
// attempt 里选了别的；旧意图恢复后若仍按自己捕获的节点重试，内核最终会是旧
// 值、存储却是新值。所以重试前先确认自己仍是最新意图，否则丢弃——存储里的
// 才是用户最后的选择，重放总是读最新存储。
//
// 订阅也是代际的一部分：重试前还要确认激活订阅仍是发起选择时的那一个——
// 两份订阅可能有同名的组与节点，旧订阅的选择不能落到新订阅的内核实例上。
//
// 为什么 stale 不回滚：stale 表示内核已经换了新 attempt（例如网络切换触发
// 了重载）。新 attempt 的重放会按存储值重放这次选择，回滚反而会丢掉用户意图。

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 一次手选的结果。
sealed class SelectionResult {
  const SelectionResult();
}

/// 内核已切换，选择已持久化。
final class SelectionApplied extends SelectionResult {
  const SelectionApplied();
}

/// 内核已换了新 attempt，这次没有写入内核；选择仍保留在存储里，由新 attempt
/// 的重放应用。
final class SelectionDeferred extends SelectionResult {
  const SelectionDeferred();
}

/// 在等待内核期间用户又对同一个组做了新的选择，或切换了激活订阅；这次选择已被
/// 取代，不再向内核重试（存储里是更新的值 / 它属于已不再激活的订阅）。
final class SelectionSuperseded extends SelectionResult {
  const SelectionSuperseded();
}

/// 内核拒绝切换；存储已回滚到点击前的值。
final class SelectionFailed extends SelectionResult {
  const SelectionFailed(this.code, this.message);

  final String code;
  final String message;
}

class ProxySelectionService {
  ProxySelectionService(this._ref);

  final Ref _ref;

  /// 每个 (订阅, 组) 的最新意图代际。
  final Map<(String?, String), int> _intent = {};

  /// 选择 [groupTag] 组里的 [outboundTag]。[expectedAttempt] 是调用方看到的
  /// 当前 attempt；原生在 attempt 不符时返回 stale 且不写入。
  Future<SelectionResult> select(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    final profileId = _activeProfileId();
    final key = (profileId, groupTag);
    final gen = (_intent[key] ?? 0) + 1;
    _intent[key] = gen;
    bool isLatest() => _intent[key] == gen;

    final store = _ref.read(proxySelectionStoreProvider.notifier);
    final previous = _ref.read(proxySelectionStoreProvider)[groupTag];
    final write = store.persistTracked(groupTag, outboundTag);
    await write.persisted;

    final port = _ref.read(kernelPortProvider);
    var outcome = await _select(port, groupTag, outboundTag, expectedAttempt);

    if (outcome is SelectStale) {
      // 调用方的 attempt 可能只是比内核慢了一步：向内核要权威 attempt，若它
      // 仍在运行就用它再试一次。
      try {
        final snap = await port.current();
        // 等待期间用户有了新选择，或者切换了激活订阅：旧选择属于旧订阅，不能再
        // 对内核（现在属于新订阅的 attempt）重试，终止旧的内核操作。
        if (!isLatest() || _activeProfileId() != profileId) {
          return const SelectionSuperseded();
        }
        if (snap.status == KernelStatus.started &&
            snap.attempt != expectedAttempt) {
          outcome = await _select(port, groupTag, outboundTag, snap.attempt);
        }
      } catch (e) {
        debugPrint('手选 stale 后读取内核快照失败: $e');
      }
    }

    switch (outcome) {
      case SelectOk():
        return const SelectionApplied();
      case SelectStale():
        return const SelectionDeferred();
      case SelectFailed(:final code, :final message):
        // 只在仍是最新意图、且该组记录仍是我们这次写入的（版本没变）时才回
        // 滚：期间用户又选了别的、或启动编排改写了该组，那是更新的状态，不能
        // 被这次失败覆盖。
        if (isLatest()) {
          await store.restore(groupTag, previous, ifVersion: write.version);
        }
        return SelectionFailed(code, message);
    }
  }

  String? _activeProfileId() =>
      _ref.read(activeProfileProvider).valueOrNull?.id;

  Future<SelectOutcome> _select(
    KernelPort port,
    String groupTag,
    String outboundTag,
    int? expectedAttempt,
  ) async {
    try {
      return await port.selectOutbound(
        groupTag,
        outboundTag,
        expectedAttempt: expectedAttempt,
      );
    } catch (e) {
      return SelectFailed('exception', '$e');
    }
  }
}

final proxySelectionServiceProvider = Provider<ProxySelectionService>((ref) {
  return ProxySelectionService(ref);
});
