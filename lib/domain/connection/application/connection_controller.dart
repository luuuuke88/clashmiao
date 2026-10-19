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
import 'package:clashmiao/domain/connection/application/selection_replay_pipeline.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
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

  /// 网络设置变更的防抖定时器（见 [onNetworkSettingsChanged]）。
  Timer? _settingsDebounce;

  /// 未释放的 [pauseConfigChanges] 数。大于 0 时配置变更只记下、不触发请求。
  int _configPauses = 0;

  /// 暂停期间是否有过网络设置变更。
  bool _deferredSettings = false;

  /// 暂停期间激活订阅的变化：第一次变化前的 id 与最新的 id。
  bool _deferredActive = false;
  String? _deferredActiveFrom;
  String? _deferredActiveTo;

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
    if (previousId == nextId) return;
    if (_configPauses > 0) {
      if (!_deferredActive) _deferredActiveFrom = previousId;
      _deferredActive = true;
      _deferredActiveTo = nextId;
      return;
    }
    if (!_wantsConnection) return;
    if (nextId == null) {
      unawaited(disconnect());
    } else if (previousId != null) {
      unawaited(applyConfig());
    }
  }

  /// 网络设置（端口 / TUN / LAN / DNS）变更（由 [connectionControllerProvider]
  /// 的监听器调用）。正在跑的内核仍用旧值，必须重新应用配置才生效。
  ///
  /// 防抖：把一串密集的设置变更合并成**一次**请求 + 一条提示
  /// （`NetworkSettingsNotifier.importJson` 会逐字段更新，滑杆拖动同理）。
  /// 400 ms 用户无感，而且「等用户改完再应用」本来就更合理。
  void onNetworkSettingsChanged() {
    if (_configPauses > 0) {
      _deferredSettings = true;
      return;
    }
    if (!_wantsConnection) return;
    _settingsDebounce?.cancel();
    _settingsDebounce = _ref.read(configChangeDebounceTimerProvider)(
      kConfigChangeReconnectDebounce,
      () {
        _settingsDebounce = null;
        // 防抖窗口内用户可能已经断开了，那就别把连接顶回去。
        if (!_wantsConnection) return;
        _applyWithNotice();
      },
    );
  }

  /// 暂停「配置变更 → 重新应用」（备份恢复期间用）。
  ///
  /// 恢复会逐项改写偏好与订阅，期间的网络设置 / 激活订阅变化如果各自触发
  /// 重新应用，内核会在半新半旧的中间态上重载。暂停期间：已排队的防抖重新
  /// 应用立即取消；新的变化只记下。最后一个暂停被释放时，按最终状态**至多**
  /// 处理一次：已连接（或想连接）而激活订阅没了 → 断开；激活订阅换了或设置
  /// 变了 → 重新应用一次（已连接时推进提示 nonce）。
  ///
  /// 可嵌套；返回的 [ConfigChangePause.release] 幂等。
  ConfigChangePause pauseConfigChanges() {
    _configPauses++;
    if (_settingsDebounce != null) {
      _settingsDebounce!.cancel();
      _settingsDebounce = null;
      // 已排队、但还没发出的那一次：并入释放时的统一处理，不丢。
      _deferredSettings = true;
    }
    return ConfigChangePause._(this);
  }

  /// 当前是否处于 [pauseConfigChanges] 之内。
  bool get configChangesPaused => _configPauses > 0;

  void _releaseConfigPause() {
    if (_configPauses == 0) return;
    if (--_configPauses > 0 || !mounted) return;
    final settings = _deferredSettings;
    final active = _deferredActive;
    final from = _deferredActiveFrom;
    final to = _deferredActiveTo;
    _deferredSettings = false;
    _deferredActive = false;
    _deferredActiveFrom = null;
    _deferredActiveTo = null;

    // 先定最终配置意图（断开 / 重新应用 / 什么都不做），再按最终归属重新评估
    // 暂停期间欠下的重放：重新应用发出后要等它落定才会调度（见
    // [_maybeRescheduleReplay]）。
    _resolveDeferredConfig(
      settings: settings,
      activeChanged: active && from != to,
      from: from,
      to: to,
    );
    _maybeRescheduleReplay();
  }

  void _resolveDeferredConfig({
    required bool settings,
    required bool activeChanged,
    required String? from,
    required String? to,
  }) {
    if (!_wantsConnection) return;
    if (activeChanged && to == null) {
      unawaited(disconnect());
      return;
    }
    // 与 [onActiveProfileChanged] 一致：首次读到订阅（from == null）不算切换。
    if (settings || (activeChanged && from != null)) _applyWithNotice();
  }

  /// 重新应用配置；已连接时递增提示 nonce，让首页弹一条轻提示，免得用户把
  /// 这次重新应用误当成网络抖动。
  void _applyWithNotice() {
    if (phase == ConnectionPhase.connected) {
      _ref.read(configChangeReconnectNoticeProvider.notifier).state++;
    }
    unawaited(applyConfig());
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
    _maybeRescheduleReplay();
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
          _track(_prepare(id));
        case SendRequest(:final id, :final request):
          if (request.desired == Desired.off) {
            _recordOffSend(id, request);
          }
          _track(_send(id, request));
        case Resync():
          _track(_resync());
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

  /// 在途的准备 / 发送 / 重同步任务（它们自己捕获所有错误，结果以事件喂回）。
  final Set<Future<void>> _tasks = {};

  void _track(Future<void> task) {
    _tasks.add(task);
    unawaited(task.whenComplete(() => _tasks.remove(task)));
  }

  /// 只给测试用：等当前在途的准备 / 发送 / 重同步任务全部结束（含它们结束时新派生
  /// 的任务）。返回是否等到过任务。测试据此在断言请求数之前确定性地等完真实文件
  /// IO，而不是靠真实时间轮询。
  @visibleForTesting
  Future<bool> debugDrainTasks() async {
    var waited = false;
    while (_tasks.isNotEmpty) {
      waited = true;
      await Future.wait(List.of(_tasks));
    }
    return waited;
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

  /// 重放用户手选的节点（spec §10.7），经 [SelectionReplayPipeline] 统一编排：
  /// 有界等待这个实例的实时分组 → 用运行时分组校验 → 迁移运行时不存在的分组
  /// 记录（先写后删）→ 只重放运行时存在的分组 → 确认。每一步都核对归属，过期
  /// 即丢弃。出口探测在确认之后才开始。
  ///
  /// 内核实例上的手选必须与**当前**激活订阅一致。流水线确认后记下「这个实例
  /// 已按哪个归属 (profileId, inc) 应用过」（[_applied]）；之后归属变了而实例
  /// 没变（切到运行时配置 revision 相同的订阅不会产生新 attempt；无论重放是
  /// 否已确认），由 [_maybeRescheduleReplay] 按新归属对同一 epoch/attempt 重跑
  /// 一遍（确认是幂等的：同一 attempt 再确认一次是无操作，见
  /// `KernelPort.acknowledgeReplay`）。归属变化同时带来新 attempt 时只由新
  /// attempt 自己的重放处理一次。
  Future<void> _replaySelections(String epoch, int attempt) async {
    if (!mounted) return;
    final key = (epoch: epoch, attempt: attempt);
    if (_replayRunning == key) return;
    _replayRunning = key;
    final pipeline = SelectionReplayPipeline(
      ref: _ref,
      port: _port,
      isCurrentInstance: (e, a) => mounted && _isCurrentTarget(e, a),
      // 配置变更暂停期间（备份恢复）激活订阅随时可能再变：不按任何订阅重放、
      // 确认，记成欠账，释放后再按最终归属评估。
      ownerUnsettled: () => _configPauses > 0,
      // 写内核之前先作废「已应用」记录：这条流水线中途被丢弃时，内核上可能
      // 已经是它（另一个归属）的部分选择，不能再假定任何归属已应用。
      beforeKernelWrite: () => _applied = null,
      groupsWait: _ref.read(replayGroupsWaitProvider),
    );
    ReplayPipelineOutcome? outcome;
    try {
      outcome = await pipeline.run(epoch, attempt);
      debugPrint('手选编排 [$epoch/$attempt]：${outcome.name}');
    } finally {
      if (_replayRunning == key) _replayRunning = null;
      if (mounted) {
        // 只有这条流水线完整走完（未被丢弃）才记「已按它的归属应用」。
        if (outcome == ReplayPipelineOutcome.acknowledged ||
            outcome == ReplayPipelineOutcome.acknowledgedWithoutGroups) {
          final owner = pipeline.owner;
          if (owner != null) _applied = owner;
        }
        // 任一出口（成功、丢弃、延后、超时、异常）都对账：实例仍在运行而当前
        // 归属不是已应用的归属，就按当前归属补齐。异常出口、以及内核已判定
        // 本实例过期（stale）的出口只记账、不立即重跑——等下一个事件（新快照、
        // 请求终结）再评估，避免确认持续失败或内核已换实例时原地空转。
        _replayOwed = key;
        if (outcome != null && outcome != ReplayPipelineOutcome.dropped) {
          _maybeRescheduleReplay();
        }
      }
    }
  }

  /// 激活订阅的归属 (id, inc) 变了（由 [connectionControllerProvider] 的监听器
  /// 在处理完 [onActiveProfileChanged] 之后调用——那里可能已经发出重新应用）：
  /// 内核正在运行就记为欠账，交给 [_maybeRescheduleReplay] 决定是否按新归属
  /// 重放这个实例。
  void onActiveOwnerChanged() {
    if (!mounted) return;
    final s = _mstate.snapshot;
    if (s == null || s.status != KernelStatus.started) return;
    _replayOwed = (epoch: s.epoch, attempt: s.attempt);
    _maybeRescheduleReplay();
  }

  /// 可能需要（重新）按当前归属重放的实例：流水线因订阅切换被丢弃 / 因配置
  /// 暂停而延后，或者确认之后归属又变了。
  ({String epoch, int attempt})? _replayOwed;

  /// 正在跑流水线的实例（同一实例不并发跑两条）。
  ({String epoch, int attempt})? _replayRunning;

  /// 最近一次确认时，手选是按哪个归属应用到哪个实例的。
  ReplayOwner? _applied;

  /// 当前实例上的手选是否已按当前激活订阅应用过。
  bool _appliedForCurrentOwner(String epoch, int attempt) {
    final applied = _applied;
    if (applied == null ||
        applied.epoch != epoch ||
        applied.attempt != attempt) {
      return false;
    }
    final profile = _ref.read(activeProfileProvider).valueOrNull;
    return applied.profileId == profile?.id &&
        applied.profileInc == profile?.inc;
  }

  /// 欠账的实例若仍是当前实例、且还没有按当前归属完整应用过（[_applied]），
  /// 并且没有未终结的请求（订阅切换引发的重新应用已经落定：要么产生了新
  /// attempt——它有自己的流水线，欠账作废；要么 revision 相同、实例不变），就
  /// 按当前归属重新跑一遍流水线。
  ///
  /// 配置变更暂停期间只记账、不调度：最终归属要等最后一次释放、先处理完最终
  /// 配置意图（[_releaseConfigPause]）之后才确定。
  ///
  /// 重新调度与原始入口一样经 [_runEffect]，异常（确认超时、通道错误、销毁
  /// 后的读取）统一捕获记录，不会成为未处理异常。
  void _maybeRescheduleReplay() {
    final owed = _replayOwed;
    if (owed == null || !mounted || _replayRunning != null) return;
    if (_configPauses > 0) return;
    final s = _mstate.snapshot;
    if (s == null) return;
    if (s.epoch != owed.epoch || s.attempt != owed.attempt) {
      _replayOwed = null; // 新实例：由它自己的重放副作用负责
      return;
    }
    if (s.status != KernelStatus.started) return;
    if (_mstate.latestRequest != null) return; // 等订阅切换引发的请求落定
    // 只看「是否已按当前归属完整应用」，不看快照的 replayNeeded：确认之后
    // replay=false 的快照是异步到的，在它到达之前按 replayNeeded 判断会把刚
    // 确认的实例再跑一遍。
    if (_appliedForCurrentOwner(owed.epoch, owed.attempt)) {
      _replayOwed = null; // 已按当前归属应用过
      return;
    }
    _replayOwed = null;
    debugPrint('手选编排 [${owed.epoch}/${owed.attempt}]：激活订阅已变，按新归属重新调度');
    unawaited(
      _runEffect(
        SideEffect(
          SideEffectKind.replaySelections,
          epoch: owed.epoch,
          attempt: owed.attempt,
        ),
      ),
    );
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
    _settingsDebounce?.cancel();
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

      // 网络设置变更：防抖后重新应用（见 onNetworkSettingsChanged）。
      ref.listen(networkSettingsProvider, (prev, next) {
        if (prev == null || identical(prev, next)) return;
        controller.onNetworkSettingsChanged();
      });

      // 激活订阅变化：连接中最后一个订阅被删 → 断开；切到另一个订阅 → 应用新
      // 配置。只看已稳定的值（刷新中的 loading 不算变化）。
      //
      // 同一个监听器里先处理配置（可能发出重新应用），再通知归属 (id, inc)
      // 变化——手选重放据此判断要不要等这次重新应用落定。
      String? lastActiveId;
      String? lastActiveInc;
      var activeKnown = false;
      ref.listen<AsyncValue<ProfileEntity?>>(activeProfileProvider, (_, next) {
        if (!next.hasValue || next.isLoading) return;
        final id = next.valueOrNull?.id;
        final inc = next.valueOrNull?.inc;
        final ownerChanged =
            activeKnown && (id != lastActiveId || inc != lastActiveInc);
        if (activeKnown && id != lastActiveId) {
          controller.onActiveProfileChanged(lastActiveId, id);
        }
        lastActiveId = id;
        lastActiveInc = inc;
        activeKnown = true;
        if (ownerChanged) controller.onActiveOwnerChanged();
      }, fireImmediately: true);

      return controller;
    });

/// 配置变更触发自动应用前的防抖窗口，见 [connectionControllerProvider]。
const kConfigChangeReconnectDebounce = Duration(milliseconds: 400);

/// 建防抖定时器的工厂。测试替换成可控调度器，不用真实时间等防抖窗口。
final configChangeDebounceTimerProvider =
    Provider<Timer Function(Duration, void Function())>((ref) => Timer.new);

/// 配置（网络设置）变更触发重新应用的通知 nonce。
///
/// 用单调递增的 int 而不是 bool/文本：UI（`HomePage`）用 `ref.listen` 监听变
/// 化弹 toast；取值不变的话连续两次变更之间 Riverpod 不会重新触发回调。
final configChangeReconnectNoticeProvider = StateProvider<int>((_) => 0);

/// [ConnectionController.pauseConfigChanges] 的句柄。
class ConfigChangePause {
  ConfigChangePause._(this._controller);

  final ConnectionController _controller;
  bool _released = false;

  /// 释放这次暂停（幂等）。最后一个暂停释放时按最终状态至多处理一次。
  void release() {
    if (_released) return;
    _released = true;
    _controller._releaseConfigPause();
  }
}
