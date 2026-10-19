// 连接控制器：把用户意图交给 [ConnectionMachine]，执行它产出的动作（准备启动
// 产物、发送带序号的期望请求、重新同步、副作用），并把内核快照与链路状态喂回
// 去。界面看到的一切连接状态都来自 [ConnectionSnapshot]——控制器自己不推断、
// 不合成任何终态。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §5 与 §10。

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_error_classifier.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// ============ 致命失败上报 ============

/// 致命 [ConnectionFailure] 的上报回调类型。抽成可覆盖的 provider 是为了在纯
/// Dart 测试环境里能注入一个记录调用次数的 fake，绕开「直接 mock 静态方法
/// `Sentry.captureMessage`」在这套测试框架里不可行的限制。
typedef FatalFailureReporter = void Function(ConnectionFailure failure);

/// 默认实现：真的调用 Sentry。是否发送仍然只由编译期 `SENTRY_DSN` 决定
/// （SDK 是否存在是启动期一次性决定，见 main.dart）。运行时「数据分析」开关
/// 的判断在 [ConnectionController] 里完成，这里不重复读取。
final fatalFailureReporterProvider = Provider<FatalFailureReporter>((ref) {
  return (failure) {
    const dsn = sentryDsn;
    if (dsn.isEmpty) return;
    unawaited(
      Sentry.captureMessage(
        'Connection fatal: ${failure.runtimeType}',
        level: SentryLevel.error,
      ),
    );
  };
});

/// 控制器与状态机共用的时钟。生产用系统时间；fake_async 测试注入
/// `fakeAsync.getClock(...).now`（`DateTime.now()` 不受 FakeAsync 控制）。
final connectionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 是否桌面平台（macOS / Windows / Linux）：只有桌面端会改系统代理，需要脏标记
/// 保护。可覆盖，让测试不依赖宿主平台。
final isDesktopPlatformProvider = Provider<bool>(
  (ref) => Platform.isMacOS || Platform.isWindows || Platform.isLinux,
);

/// 点一下连接按钮（`toggle`）将要发出的目标。UI 据此决定是否要先过「实验性
/// 功能」确认门禁。语义见 spec §5：
/// - 连接中 / 已连接 / 重新连接中 → 断开；
/// - 未连接、尚无快照 → 连接；
/// - 断开中 → 带失败（内核无响应）则重发断开，否则改为连接。
/// 与原生失联（nativeUnresponsive）时：重发最新意图，由控制器内部处理。
Desired toggleTarget(ConnectionSnapshot s) {
  switch (s.phase) {
    case ConnectionPhase.connected:
    case ConnectionPhase.connecting:
    case ConnectionPhase.reconnecting:
      return Desired.off;
    case ConnectionPhase.disconnected:
    case ConnectionPhase.resolving:
      return Desired.on;
    case ConnectionPhase.disconnecting:
      return s.failure != null ? Desired.off : Desired.on;
  }
}

// ============ 系统代理脏标记存储 ============

/// 「系统代理由我们设着」脏标记的持久化。抽成可覆盖的 provider：生产写
/// SharedPreferences；测试里换成可悬停的替身，才能在「持久化尚未完成」的窗口
/// 里构造交错。
abstract class SystemProxyDirtyStore {
  Future<void> mark();
  Future<void> clear();
}

class _PrefsDirtyStore implements SystemProxyDirtyStore {
  _PrefsDirtyStore(this._ref);

  final Ref _ref;

  @override
  Future<void> mark() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await markSystemProxyDirty(prefs);
  }

  @override
  Future<void> clear() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await clearSystemProxyDirty(prefs);
  }
}

final systemProxyDirtyStoreProvider = Provider<SystemProxyDirtyStore>(
  _PrefsDirtyStore.new,
);

// ============ Connection Controller ============

class ConnectionController extends StateNotifier<ConnectionSnapshot> {
  ConnectionController(this._ref) : super(ConnectionSnapshot.initial) {
    _now = _ref.read(connectionClockProvider);
    _port = _ref.read(kernelPortProvider);
    _mstate = MachineState.initial(_now());

    _snapshotSub = _port.watch().listen(
      (s) => _dispatch(SnapshotReceived(s, now: _now())),
      onError: (Object e) => debugPrint('内核快照流错误: $e'),
    );
    _linkSub = _port.watchLink().listen(
      (l) => _dispatch(LinkChanged(l, now: _now())),
      onError: (Object e) => debugPrint('内核链路流错误: $e'),
    );
    // 立即推进一次，让状态机报出「无首个快照 10 s」等截止时间。
    _dispatch(Tick(now: _now()));
  }

  /// 只给 UI 测试用：直接以 [snapshot] 为状态，不接内核端口、不启动状态机。
  /// 调用方（测试里的假控制器）必须覆盖会用到端口的方法。
  @visibleForTesting
  ConnectionController.preset(this._ref, ConnectionSnapshot snapshot)
    : super(snapshot) {
    _now = DateTime.now;
    _mstate = MachineState.initial(_now());
  }

  final Ref _ref;
  late final DateTime Function() _now;
  late final KernelPort _port;
  late MachineState _mstate;
  static const _machine = ConnectionMachine();

  StreamSubscription<KernelSnapshot>? _snapshotSub;
  StreamSubscription<KernelLink>? _linkSub;
  Timer? _wake;

  /// 事件队列：处理事件期间产生的新事件（监听器里再次调用控制器）排队，按序
  /// 处理，保证 [_mstate] 总是「上一个事件处理完」之后的值。
  final Queue<MachineEvent> _events = Queue();
  bool _draining = false;

  int _nextId = 0;
  final Map<int, Completer<RequestOutcome>> _completers = {};

  /// 已终结的意图 id（最近 64 个）：准备在它终结之后才完成的，丢弃结果并删文件。
  final List<int> _settled = [];

  /// 上一个用户意图（用于原生失联时「重发最新意图」）。
  Desired? _lastIntent;

  /// 系统代理脏标记的所有读写操作按序串行（mark / clear 一条队列）。发送 on
  /// 请求前要等它排空，保证标记先落盘。
  Future<void> _dirtyChain = Future<void>.value();

  /// 「连接意图」代际：每提交一个 on 意图 +1（发送之前就算，不等标记落盘）。
  int _onGen = 0;

  /// 每个断开意图（按意图 id）提交时的 [_onGen]：这次断开产生的清标记归它所有。
  final Map<int, int> _offGenById = {};

  /// 已发出的断开请求（`epoch/seq`）→ 它提交时的 [_onGen]。停止快照用自己的
  /// `appliedSeq` 在这里查它到底属于哪一次断开，而不是「最近一次」断开——否则
  /// `on1 → off1 → on2 → off2` 里旧快照会被记到 off2 名下。之后若有新的 on 意图，
  /// 代际前进，旧的清标记作废（哪怕新 on 的 mark 还没排上队）。
  final Map<String, int> _offGenBySeq = {};

  /// 已经为哪一代安排过清理：同一代只清一次（效果清理与 `disconnect` 收尾共用
  /// 同一个入口，后到的那次直接并入）。
  int _clearedForGen = -1;

  ConnectionLauncher get _launcher => _ref.read(connectionLauncherProvider);

  // ── 对外 API ─────────────────────────────────────────────────────

  /// 连接。Future 在该请求终结时完成（见 [RequestOutcome]）；从不抛。
  Future<RequestOutcome> connect() =>
      _submit(Desired.on, RequestReason.userConnect);

  /// 断开。成功（内核确认已停止）时清系统代理脏标记；失败/被中断时不清，让
  /// 下次启动的自愈去处理残留。
  Future<RequestOutcome> disconnect() async {
    // 这次断开「看到的」脏标记代际：清标记只对它有效，之后若有新的连接置了
    // 标记，迟到的清理必须让位（见 [_clearSystemProxyDirty]）。
    final gen = _onGen;
    final outcome = await _submit(Desired.off, RequestReason.userDisconnect);
    if (outcome is RequestSucceeded) await _clearSystemProxyDirty(gen);
    return outcome;
  }

  /// 设置 / 模式 / 订阅变化：已经在连接或已连接时，以新配置重新发一次 on（协
  /// 调器按 revision 合并为一次重载，revision 没变则无操作）。未连接时没有
  /// 副作用——下次连接自然使用最新配置。
  Future<RequestOutcome> applyConfig() async {
    if (!_wantsConnection) return const RequestSucceeded();
    return _submit(Desired.on, RequestReason.applyConfig);
  }

  /// 切换连接状态（首页按钮、托盘、dev 自动连接）。语义见 [toggleTarget]。
  Future<RequestOutcome> toggle() {
    final s = state;
    // 与原生失联时按钮可点：点击 = 立即重新同步后重发最新意图。
    if (s.failure is NativeUnresponsive && _lastIntent != null) {
      return _submit(_lastIntent!, RequestReason.retry);
    }
    if (s.phase == ConnectionPhase.disconnecting && s.failure != null) {
      return _submit(Desired.off, RequestReason.retry);
    }
    return toggleTarget(s) == Desired.off ? disconnect() : connect();
  }

  /// 当前连接阶段（供 provider 体内的监听器读取）。
  ConnectionPhase get phase => state.phase;

  /// 当前是否「想保持连接」。以状态机里**最新的未终结意图**为准——包括首个
  /// 快照到达前（resolving）已经记录、甚至已经准备好的连接意图；没有未终结
  /// 意图时，才看快照派生的阶段（connected / connecting / reconnecting）。
  bool get _wantsConnection {
    final pending = _mstate.latestRequest;
    if (pending != null) return pending.desired == Desired.on;
    return switch (state.phase) {
      ConnectionPhase.connected ||
      ConnectionPhase.connecting ||
      ConnectionPhase.reconnecting => true,
      _ => false,
    };
  }

  /// 激活订阅变化（由 [connectionControllerProvider] 的监听器调用）。
  /// - 连接中/已连接时激活订阅被删光（变为 null）→ 断开；
  /// - 从一个订阅切到另一个 → 以新订阅重新发一次 on。
  void onActiveProfileChanged(String? previousId, String? nextId) {
    if (previousId == nextId || !_wantsConnection) return;
    if (nextId == null) {
      unawaited(disconnect());
    } else if (previousId != null) {
      unawaited(applyConfig());
    }
  }

  Future<RequestOutcome> _submit(Desired desired, RequestReason reason) {
    final id = ++_nextId;
    if (desired == Desired.on) {
      _onGen++;
    } else {
      _offGenById[id] = _onGen;
      while (_offGenById.length > 64) {
        _offGenById.remove(_offGenById.keys.first);
      }
    }
    final completer = Completer<RequestOutcome>();
    _completers[id] = completer;
    _lastIntent = desired;
    _dispatch(
      UserIntent(id: id, desired: desired, reason: reason, now: _now()),
    );
    return completer.future;
  }

  // ── 事件循环 ─────────────────────────────────────────────────────

  void _dispatch(MachineEvent e) {
    if (!mounted) return;
    _events.add(e);
    if (_draining) return;
    _draining = true;
    try {
      while (_events.isNotEmpty && mounted) {
        _step(_events.removeFirst());
      }
    } finally {
      _draining = false;
    }
  }

  void _step(MachineEvent e) {
    final t = _machine.reduce(_mstate, e);
    _mstate = t.state;
    state = t.snapshot;
    _rearm(t.nextWake);
    if (e is SnapshotReceived) {
      final accepted = _mstate.snapshot;
      if (accepted != null) unawaited(_launcher.observe(accepted));
    }
    _execute(t.actions);
  }

  /// 按 [Transition.nextWake] 安排下一个 [Tick]。
  void _rearm(DateTime? wake) {
    _wake?.cancel();
    _wake = null;
    if (wake == null) return;
    var delay = wake.difference(_now());
    // 防御：截止时间已过却仍被再次报出时，不要空转。
    if (delay < const Duration(milliseconds: 10)) {
      delay = const Duration(milliseconds: 10);
    }
    _wake = Timer(delay, () {
      _wake = null;
      _dispatch(Tick(now: _now()));
    });
  }

  void _execute(List<MachineAction> actions) {
    // 同一批动作里的副作用要在随后的 SettleRequest 之前完成（例如退出时先清脏
    // 标记再放行）。
    final pendingEffects = <Future<void>>[];
    for (final a in actions) {
      switch (a) {
        case PrepareLaunch(:final id):
          unawaited(_prepare(id));
        case SendRequest(:final id, :final request):
          if (request.desired == Desired.off) {
            _recordOffSend(id, request);
          }
          unawaited(_send(id, request));
        case Resync():
          unawaited(_resync());
        case RunEffect(:final effect):
          final f = _runEffect(effect);
          // 只有系统代理脏标记必须在放行之前落盘；触觉、评分、手选重放、上报
          // 不能拖慢请求的终结。
          if (effect.kind == SideEffectKind.markSystemProxyDirty ||
              effect.kind == SideEffectKind.clearSystemProxyDirty) {
            pendingEffects.add(f);
          } else {
            unawaited(f);
          }
        case SettleRequest(:final id, :final outcome):
          _settle(id, outcome, List.of(pendingEffects));
      }
    }
  }

  void _settle(int id, RequestOutcome outcome, List<Future<void>> after) {
    _settled.add(id);
    if (_settled.length > 64) _settled.removeAt(0);
    unawaited(_launcher.discard(id));
    final c = _completers.remove(id);
    if (c == null || c.isCompleted) return;
    if (after.isEmpty) {
      c.complete(outcome);
    } else {
      unawaited(
        Future.wait(after).whenComplete(() {
          if (!c.isCompleted) c.complete(outcome);
        }),
      );
    }
  }

  // ── 动作执行 ─────────────────────────────────────────────────────

  Future<void> _prepare(int id) async {
    ConnectionFailure? failure;
    LaunchSpec? spec;
    try {
      spec = await _launcher.prepare(id);
    } on LaunchPreparationException catch (e) {
      failure = e.failure;
    } catch (e) {
      failure = failureFromError(e);
    }
    if (!mounted) return;
    // 准备期间意图已被取代（状态机已立即终结它）：丢弃结果与文件，不占 seq。
    if (_settled.contains(id)) {
      if (spec != null) unawaited(_launcher.discard(id));
      return;
    }
    if (spec != null) {
      _dispatch(LaunchPrepared(id: id, launch: spec, now: _now()));
    } else {
      _dispatch(
        LaunchPrepareFailed(
          id: id,
          failure: failure ?? const UnexpectedFailure(),
          now: _now(),
        ),
      );
    }
  }

  void _recordOffSend(int id, DesiredRequest request) {
    final gen = _offGenById.remove(id);
    if (gen == null) return;
    _offGenBySeq['${request.epoch}/${request.seq}'] = gen;
    while (_offGenBySeq.length > 64) {
      _offGenBySeq.remove(_offGenBySeq.keys.first);
    }
  }

  Future<void> _send(int id, DesiredRequest request) async {
    try {
      await _sendRequest(id, request);
    } finally {
      // 发送路径（含回执处理）走完：发送元数据（绑定 seq 时内核的 attempt）才可
      // 以丢弃。意图可能早已因快照先到而终结，那不是丢弃它的理由。
      if (mounted) _launcher.sendFinished(id);
    }
  }

  Future<void> _sendRequest(int id, DesiredRequest request) async {
    // 先等系统代理脏标记落盘：一旦请求启动，内核就可能已经改了系统代理。
    // （循环：等待期间排进来的新操作也要一并等完。）
    Future<void> tail;
    do {
      tail = _dirtyChain;
      await tail;
    } while (!identical(tail, _dirtyChain));

    var req = request;
    final launch = request.launch;
    if (launch != null) {
      try {
        final bound = await _launcher.bindSeq(id, launch, request.seq);
        req = DesiredRequest(
          epoch: request.epoch,
          seq: request.seq,
          desired: request.desired,
          reason: request.reason,
          launch: bound,
        );
      } catch (e) {
        _dispatch(
          SendFailed(id: id, failure: failureFromError(e), now: _now()),
        );
        return;
      }
    }

    final RequestReceipt receipt;
    try {
      receipt = await _port.request(req);
    } catch (e) {
      _dispatch(SendFailed(id: id, failure: failureFromError(e), now: _now()));
      return;
    }
    _dispatch(ReceiptReceived(id: id, receipt: receipt, now: _now()));
  }

  Future<void> _resync() async {
    try {
      final s = await _port.current();
      _dispatch(SnapshotReceived(s, now: _now(), fromResync: true));
    } catch (e) {
      debugPrint('重新同步失败: $e');
      _dispatch(ResyncFailed(now: _now()));
    }
  }

  Future<void> _runEffect(SideEffect effect) async {
    try {
      switch (effect.kind) {
        case SideEffectKind.hapticHeavy:
          await _ref.read(hapticServiceProvider).heavyImpact();
        case SideEffectKind.requestReview:
          await _ref.read(storeReviewServiceProvider).maybeRequestReview();
        case SideEffectKind.hapticMedium:
          await _ref.read(hapticServiceProvider).mediumImpact();
        case SideEffectKind.replaySelections:
          await _replaySelections(effect.epoch!, effect.attempt!);
        case SideEffectKind.markSystemProxyDirty:
          await _markSystemProxyDirty();
        case SideEffectKind.clearSystemProxyDirty:
          // 这份停止快照对应哪一次断开：看它的 appliedSeq 指向的请求。
          final snap = _mstate.snapshot;
          final gen = snap == null
              ? null
              : _offGenBySeq['${snap.epoch}/${snap.appliedSeq}'];
          if (gen == null) {
            debugPrint('停止快照对应的断开请求未知，不清系统代理脏标记');
          } else {
            await _clearSystemProxyDirty(gen);
          }
        case SideEffectKind.reportFailure:
          if (_shouldReportAnalytics() && effect.failure != null) {
            _ref.read(fatalFailureReporterProvider)(effect.failure!);
          }
      }
    } catch (e) {
      debugPrint('连接副作用 ${effect.kind.name} 失败（忽略）: $e');
    }
  }

  /// 重放用户手选的节点（spec §10.7）。
  ///
  /// 先等激活订阅与选择存储就绪——内核快照可能先于订阅加载到达，此时存储还是
  /// 空的，直接重放会确认一次「空重放」，出口探测随即用默认节点。就绪后再核对
  /// 目标 `(epoch, attempt)` 仍是内核当前的，才开始重放。
  ///
  /// 每一项发送前都读存储里的最新值；发送后若存储里的值又变了（用户在重放期
  /// 间改了选择），继续发最新值，直到收敛。stale（内核已换新 attempt）立即放弃
  /// 且不确认——新 attempt 会触发自己的重放。单项失败只记日志；最后（含有失败
  /// 项）确认重放，保证出口探测能触发。
  Future<void> _replaySelections(String epoch, int attempt) async {
    try {
      await _ref.read(sharedPreferencesProvider.future);
      await _ref.read(activeProfileProvider.future);
    } catch (e) {
      // 订阅读不出来：没有可重放的选择，照常确认，免得出口探测永远等下去。
      debugPrint('重放手选前等待订阅就绪失败: $e');
    }
    if (!mounted || !_isCurrentTarget(epoch, attempt)) return;

    final sent = <String, String>{};
    for (var pass = 0; pass < 4; pass++) {
      var sentAny = false;
      final groups = _ref.read(proxySelectionStoreProvider).keys.toList();
      for (final group in groups) {
        final tag = _ref.read(proxySelectionStoreProvider)[group];
        if (tag == null || sent[group] == tag) continue;
        sentAny = true;
        sent[group] = tag;
        final outcome = await _port.selectOutbound(
          group,
          tag,
          expectedAttempt: attempt,
        );
        if (!mounted) return;
        if (outcome is SelectStale) return;
        if (outcome is SelectFailed) {
          debugPrint('重放手选代理失败 [$group -> $tag]: ${outcome.code}');
        }
      }
      if (!sentAny) break;
    }
    if (!mounted || !_isCurrentTarget(epoch, attempt)) return;
    await _port.acknowledgeReplay(attempt);
  }

  /// 状态机当前接受的内核快照是否仍是 [epoch] / [attempt] 且已启动。
  bool _isCurrentTarget(String epoch, int attempt) {
    final s = _mstate.snapshot;
    return s != null &&
        s.epoch == epoch &&
        s.attempt == attempt &&
        s.status == KernelStatus.started;
  }

  /// 置「系统代理由我们设着」的脏标记——仅在这次连接**真的会去改系统代理**时。
  /// 判定条件跟 `getDefaultConfigOptions` 里 `setSystemProxyFinal` 保持一致：
  /// 移动端不设系统代理（走 TUN），桌面端才看用户开关。多标的代价是下次启动
  /// 多跑几条只读命令，漏标则是真残留没人清。
  ///
  /// 写入排进串行队列。
  Future<void> _markSystemProxyDirty() {
    if (!_ref.read(isDesktopPlatformProvider)) return Future<void>.value();
    if (!_ref.read(networkSettingsProvider).setSystemProxy) {
      return Future<void>.value();
    }
    return _enqueueDirty(() async {
      try {
        await _ref.read(systemProxyDirtyStoreProvider).mark();
      } catch (e) {
        debugPrint('置系统代理脏标记失败: $e');
      }
    });
  }

  /// 清除脏标记的**唯一入口**。只在内核确认已停止之后调用——那时 sing-box 已经
  /// 走完 listener 的 Close、还原了系统代理。[decidedGen] 是产生这次清理的断开
  /// 意图提交时的连接意图代际；执行时代际已前进说明之后又有了新的连接意图，
  /// 这次清理属于旧断开，作废。
  Future<void> _clearSystemProxyDirty(int decidedGen) {
    if (!_ref.read(isDesktopPlatformProvider)) return Future<void>.value();
    if (_clearedForGen == decidedGen) return _dirtyChain;
    _clearedForGen = decidedGen;
    return _enqueueDirty(() async {
      if (decidedGen != _onGen) return;
      try {
        await _ref.read(systemProxyDirtyStoreProvider).clear();
      } catch (e) {
        debugPrint('清除系统代理脏标记失败: $e');
      }
    });
  }

  Future<void> _enqueueDirty(Future<void> Function() op) {
    final run = _dirtyChain.then((_) => op());
    _dirtyChain = run;
    return run;
  }

  /// 设置页「数据分析」开关；prefs 还没就绪时保守按「不上报」处理。
  bool _shouldReportAnalytics() {
    final prefs = _ref.read(sharedPreferencesProvider).valueOrNull;
    if (prefs == null) return false;
    return prefs.getBool('clashmiao_analytics_enabled') ?? false;
  }

  @override
  void dispose() {
    _wake?.cancel();
    unawaited(_snapshotSub?.cancel());
    unawaited(_linkSub?.cancel());
    for (final c in _completers.values) {
      if (!c.isCompleted) c.complete(const RequestInterrupted());
    }
    _completers.clear();
    super.dispose();
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionSnapshot>((ref) {
      final controller = ConnectionController(ref);

      // 网络设置（端口 / TUN / LAN / DNS）变更后，正在跑的内核仍用旧值，必须
      // 重新应用配置才生效。防抖：把一串密集的设置变更合并成**一次**请求 +
      // 一条提示（`NetworkSettingsNotifier.importJson` 会逐字段更新，滑杆拖动
      // 同理）。400 ms 用户无感，而且「等用户改完再应用」本来就更合理。
      Timer? settingsDebounce;
      ref.onDispose(() => settingsDebounce?.cancel());
      ref.listen(networkSettingsProvider, (prev, next) {
        if (prev == null || identical(prev, next)) return;
        if (!controller._wantsConnection) return;
        settingsDebounce?.cancel();
        settingsDebounce = Timer(kConfigChangeReconnectDebounce, () {
          // 防抖窗口内用户可能已经断开了，那就别把连接顶回去。
          if (!controller._wantsConnection) return;
          // 已连接时递增 nonce，让首页弹一条轻提示，免得用户把这次重新应用
          // 误当成网络抖动。
          if (controller.phase == ConnectionPhase.connected) {
            ref.read(configChangeReconnectNoticeProvider.notifier).state++;
          }
          unawaited(controller.applyConfig());
        });
      });

      // 激活订阅变化：连接中最后一个订阅被删 → 断开；切到另一个订阅 → 应用新
      // 配置。只看已稳定的值（刷新中的 loading 不算变化）。
      String? lastActiveId;
      var activeKnown = false;
      ref.listen<AsyncValue<ProfileEntity?>>(activeProfileProvider, (_, next) {
        if (!next.hasValue || next.isLoading) return;
        final id = next.valueOrNull?.id;
        if (activeKnown && id != lastActiveId) {
          controller.onActiveProfileChanged(lastActiveId, id);
        }
        lastActiveId = id;
        activeKnown = true;
      }, fireImmediately: true);

      return controller;
    });

/// 配置变更触发自动应用前的防抖窗口，见 [connectionControllerProvider]。
const kConfigChangeReconnectDebounce = Duration(milliseconds: 400);

/// 配置（网络设置）变更触发重新应用的通知 nonce。
///
/// 用单调递增的 int 而不是 bool/文本：UI（`HomePage`）用 `ref.listen` 监听变
/// 化弹 toast；取值不变的话连续两次变更之间 Riverpod 不会重新触发回调。
final configChangeReconnectNoticeProvider = StateProvider<int>((_) => 0);
