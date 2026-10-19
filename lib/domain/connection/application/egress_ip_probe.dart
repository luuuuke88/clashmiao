// 出口 IP 探测（spec §6）：连上之后、手选重放确认之后，经本地代理查一次出口
// IP，首次就能拿到正确的结果。
//
// - 触发：某 `(epoch, attempt)` 进入 connected 且其手选重放已确认
//   （`replayPending == false`）；
// - 客户端：只走 `PROXY 127.0.0.1:<mixedPort>`，没有 DIRECT 回退。这验证的是
//   「经本地代理、按当前路由规则」的出口，不是对某个 outbound 的强制探测；
// - 节奏：串行最多 4 次，单次 4 s，失败后间隔 1 s，首次成功即停（总上限约
//   20 s）；
// - 作废：`(epoch, attempt)` 变化、离开 connected、手动查询都会使在途探测作废，
//   旧结果被丢弃。

import 'dart:async';

import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 探测节奏常量（spec §6）。
abstract final class EgressProbeTiming {
  static const maxAttempts = 4;
  static const perAttemptTimeout = Duration(seconds: 4);
  static const retryGap = Duration(seconds: 1);
}

/// 出口 IP 卡的四种内容状态外加「未连接」。
enum EgressIpStatus {
  /// 未连接（含重载中）：整卡不可点，提示「连接后显示出口 IP」。
  notConnected,

  /// 已连接，但没有在查（自动检测关闭，或还没轮到）：提示「点击检测」。
  idle,

  /// 查询中：提示「正在检测…」，不显示「未知的 IP」。
  checking,

  /// 全部尝试失败：提示「检测失败，点击重试」。
  failed,

  /// 成功：[EgressIpState.result] 里是 IP 与国家码。
  success,
}

@immutable
class EgressIpState {
  const EgressIpState(this.status, [this.result]);

  static const notConnected = EgressIpState(EgressIpStatus.notConnected);

  final EgressIpStatus status;
  final EgressIpResult? result;

  @override
  bool operator ==(Object other) =>
      other is EgressIpState &&
      other.status == status &&
      other.result == result;

  @override
  int get hashCode => Object.hash(status, result);

  @override
  String toString() => 'EgressIpState(${status.name}, $result)';
}

/// 一次查询的实现。默认经 [egressProbeServiceProvider]（仅代理、4 s 超时）；
/// 测试里覆盖成脚本化结果。
final egressProbeFetchProvider = Provider<Future<EgressIpResult> Function()>((
  ref,
) {
  return () => ref.read(egressProbeServiceProvider).fetch();
});

/// 仅代理的查询服务。mixed 端口变化时重建，保证探测用的是当前端口。
final egressProbeServiceProvider = Provider<EgressIpService>((ref) {
  ref.watch(networkSettingsProvider.select((s) => s.mixedPort));
  return EgressIpService(
    ref,
    proxyOnly: true,
    timeout: EgressProbeTiming.perAttemptTimeout,
  );
});

/// 连接状态里与探测相关的那一小片（`select` 用，其余字段变化不触发）。
typedef _ConnView = ({
  bool connected,
  String? epoch,
  int? attempt,
  bool replayPending,
});

class EgressIpProbe extends StateNotifier<EgressIpState> {
  EgressIpProbe(this._ref) : super(EgressIpState.notConnected) {
    _sub = _ref.listen<_ConnView>(
      connectionControllerProvider.select(
        (s) => (
          connected: s.phase == ConnectionPhase.connected,
          epoch: s.epoch,
          attempt: s.attempt,
          replayPending: s.replayPending,
        ),
      ),
      (_, next) => _onConnection(next),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  ProviderSubscription<_ConnView>? _sub;

  /// 作废令牌：每次状态切换 / 新查询 +1；在途探测完成时比对，不符即丢弃。
  int _generation = 0;
  (String?, int?)? _session;
  bool _autoStarted = false;

  bool get _autoCheckEnabled =>
      _ref.read(egressIpServiceProvider).autoCheckEnabled;

  void _onConnection(_ConnView c) {
    if (!c.connected) {
      _generation++; // 离开 connected：在途探测作废
      _session = null;
      _autoStarted = false;
      state = EgressIpState.notConnected;
      return;
    }
    final key = (c.epoch, c.attempt);
    if (_session != key) {
      // 新的 (epoch, attempt)：清掉上一段连接的出口 IP，在途探测作废。
      _generation++;
      _session = key;
      _autoStarted = false;
      state = const EgressIpState(EgressIpStatus.idle);
    }
    if (!_autoStarted && !c.replayPending && _autoCheckEnabled) {
      _autoStarted = true;
      unawaited(_run());
    }
  }

  /// 手动查询（点击出口 IP 卡）：使在途探测作废并重新开始。未连接时无效。
  Future<void> checkNow() async {
    if (state.status == EgressIpStatus.notConnected) return;
    _autoStarted = true;
    await _run();
  }

  Future<void> _run() async {
    final gen = ++_generation;
    state = const EgressIpState(EgressIpStatus.checking);
    final fetch = _ref.read(egressProbeFetchProvider);
    for (var i = 0; i < EgressProbeTiming.maxAttempts; i++) {
      EgressIpResult result;
      try {
        result = await fetch();
      } catch (e) {
        debugPrint('出口 IP 探测第 ${i + 1} 次异常: $e');
        result = const EgressIpResult.unknown();
      }
      if (!mounted || gen != _generation) return;
      if (!result.isUnknown) {
        state = EgressIpState(EgressIpStatus.success, result);
        return;
      }
      if (i < EgressProbeTiming.maxAttempts - 1) {
        await Future<void>.delayed(EgressProbeTiming.retryGap);
        if (!mounted || gen != _generation) return;
      }
    }
    state = const EgressIpState(EgressIpStatus.failed);
  }

  @override
  void dispose() {
    _sub?.close();
    _generation++;
    super.dispose();
  }
}

final egressIpProbeProvider =
    StateNotifierProvider<EgressIpProbe, EgressIpState>((ref) {
      return EgressIpProbe(ref);
    });
