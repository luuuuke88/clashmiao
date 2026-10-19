// 手选存储与运行时分组的对齐（真机验收 BUG-1 的善后）。
//
// 运行中内核的分组 tag 只能从实时分组流得知。旧版本按配置文件里的分组 tag
// （运行时并不存在）记下了手选，重放这些记录每次都失败、用户看到的选择从未
// 生效。实时分组一到，就按 [planSelectionMigration] 把旧记录迁到运行时主组上
// （经正常的手选流程：先写存储、再带 attempt 写内核），并删掉运行时不存在的
// 分组记录——之后的重放只会对真实存在的分组发起。
//
// 接线放在连接层：需要当前 attempt（routing 不能反向依赖 connection）。

import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_service.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SelectionStoreReconciler {
  SelectionStoreReconciler(this._ref) {
    _sub = _ref.listen<AsyncValue<List<OutboundGroup>>>(
      outboundGroupsProvider,
      (_, next) => _onGroups(next.valueOrNull ?? const []),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  ProviderSubscription<AsyncValue<List<OutboundGroup>>>? _sub;
  Future<void> _chain = Future<void>.value();

  /// 最近一次处理（含在途）完成的 Future；测试用。
  @visibleForTesting
  Future<void> get idle => _chain;

  void _onGroups(List<OutboundGroup> live) {
    if (live.isEmpty) return;
    // 串行：上一轮的写入（会让分组流再推一次）完成后再看下一份。
    _chain = _chain.then((_) => _reconcile(live)).catchError((Object e) {
      debugPrint('手选存储对齐失败: $e');
    });
  }

  Future<void> _reconcile(List<OutboundGroup> live) async {
    final conn = _ref.read(connectionControllerProvider);
    // 只在稳定连接时判断：重载中的分组可能还属于上一个实例。
    if (conn.phase != ConnectionPhase.connected) return;
    final stored = _ref.read(proxySelectionStoreProvider);
    final plan = planSelectionMigration(stored, live);
    if (plan.drop.isEmpty && plan.adopt.isEmpty) return;

    for (final MapEntry(key: group, value: node) in plan.adopt.entries) {
      debugPrint('手选存储对齐：迁移 [$node] 到运行时分组 [$group]');
      final result = await _ref
          .read(proxySelectionServiceProvider)
          .select(group, node, expectedAttempt: conn.attempt);
      if (result is SelectionFailed) {
        debugPrint('手选存储对齐：迁移失败 ${result.code} ${result.message}');
      }
    }
    debugPrint('手选存储对齐：删除运行时不存在的分组记录 ${plan.drop}');
    await _ref
        .read(proxySelectionStoreProvider.notifier)
        .removeGroups(plan.drop);
  }

  void dispose() {
    _sub?.close();
    _sub = null;
  }
}

/// 常驻：在 main 里读一次即开始工作。
final selectionStoreReconcilerProvider = Provider<SelectionStoreReconciler>((
  ref,
) {
  final reconciler = SelectionStoreReconciler(ref);
  ref.onDispose(reconciler.dispose);
  return reconciler;
});
