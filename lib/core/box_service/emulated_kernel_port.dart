import 'dart:async';

import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_hub.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// 非 Android 平台（iOS Pigeon、桌面 FFI）的 [KernelPort]：包装现有
/// [BoxService]，在 Dart 里实现同样的协调语义（spec §4、§10.3 降级契约）。
///
/// 承诺（与 Android 协调器相同）：
/// - 请求按 seq 顺序受理、后到覆盖先到；`on/off/on` 同一事件循环内连发只执行最后
///   一个。受理 = 设 desired、`source=app`、`appliedSeq=seq`，随后串行驱动内核。
/// - `seq ≤ appliedSeq` → `stale`；纪元不符 → `wrongEpoch`；二者都不改变状态。
/// - 启动失败 / 启动超时（30 s）/ fatal alert → desired 置 off，写 `lastFailure`，
///   驱动到 stopped；失败只归属仍是当前请求的那次执行，已被更新请求取代的执行
///   只回收资源，不改 desired、不写 failure。
/// - 配置 revision 与 `activeConfigRevision` 不同 → 重载（`restart`，attempt+1）；
///   相同则无操作。
/// - 单次停止等待超过 20 s → `kernelUnresponsive`，状态保持 stopping（如实）。
///
/// 降级（§10.3）：epoch/attempt 是本实例的本地值；平台状态推送是「内核回报」
/// 输入，来自平台自身的变化（iOS 系统设置、意外退出）一律记 `source=system`，
/// 且不写 failure；`stop()` 之后等待平台推送 Stopped，不合成终态。
/// 桌面 FFI 调用仍阻塞 UI isolate（子项目 D）。
///
/// [StubBoxService]（核心库不可用）：任何 `on` 请求立即以
/// [KernelFailureCode.coreUnavailable] 失败，不调用内核。
class EmulatedKernelPort implements KernelPort {
  EmulatedKernelPort(
    this._service, {
    this.startTimeout = const Duration(seconds: 30),
    this.stopTimeout = const Duration(seconds: 20),
    this.initTimeout = const Duration(seconds: 2),
    String Function()? epochGenerator,
  }) : epoch = (epochGenerator ?? () => const Uuid().v4())() {
    _hub = KernelPortHub<KernelSnapshot>(onFirstListener: _onFirstWatcher);
  }

  final BoxService _service;
  final Duration startTimeout;
  final Duration stopTimeout;
  final Duration initTimeout;

  /// 本实例的纪元（构造时生成）。
  final String epoch;

  late final KernelPortHub<KernelSnapshot> _hub;

  // ── 快照字段 ────────────────────────────────────────────────
  int _version = 0;
  KernelStatus _status = KernelStatus.stopped;
  int _attempt = 0;
  Desired _desired = Desired.off;
  DesiredSource _source = DesiredSource.system;
  int _appliedSeq = 0;
  int? _activeRev;
  KernelFailure? _failure;
  bool _replay = false;
  KernelSnapshot? _last;

  // ── 驱动状态 ────────────────────────────────────────────────
  LaunchSpec? _launch;
  BoxStatus? _native;
  bool _driving = false;
  bool _needsTeardown = false;
  bool _stopStuck = false;
  bool _sawProgress = false;
  bool _disposed = false;
  Completer<_Fault?>? _startWaiter;
  Completer<void>? _stopWaiter;

  // ── 初始化 ──────────────────────────────────────────────────
  Future<void>? _init;
  bool _ready = false;
  StreamSubscription<BoxStatus>? _statusSub;
  StreamSubscription<BoxAlert>? _alertSub;

  void _onFirstWatcher() {
    _ensureInitialized().then<void>(
      (_) {},
      onError: (Object e) => debugPrint('EmulatedKernelPort 初始化失败: $e'),
    );
  }

  Future<void> _ensureInitialized() {
    if (_ready) return Future<void>.value();
    return _init ??= _initialize().catchError((Object e) {
      _init = null;
      unawaited(_statusSub?.cancel());
      unawaited(_alertSub?.cancel());
      _statusSub = null;
      _alertSub = null;
      throw e;
    });
  }

  Future<void> _initialize() async {
    final first = Completer<void>();
    try {
      _statusSub = _service.watchStatus().listen(
        (s) {
          if (first.isCompleted) {
            _onNativeStatus(s);
          } else {
            _initFromNative(s);
            first.complete();
          }
        },
        onDone: () {
          // 空流：没有任何平台状态可读，按已停止处理。
          if (!first.isCompleted) {
            _initFromNative(const BoxStopped());
            first.complete();
          }
        },
        onError: (Object e) => debugPrint('watchStatus 报错: $e'),
      );
      _alertSub = _service.watchAlerts().listen(
        _onAlert,
        onError: (Object e) => debugPrint('watchAlerts 报错: $e'),
      );
    } catch (e) {
      throw KernelPortException('unavailable', '$e');
    }
    try {
      await first.future.timeout(initTimeout);
    } on TimeoutException {
      throw const KernelPortException('timeout', '读取平台初始状态超时');
    }
    _ready = true;
  }

  void _initFromNative(BoxStatus s) {
    _native = s;
    switch (s) {
      case BoxStarted():
        _status = KernelStatus.started;
        _desired = Desired.on;
      case BoxStarting():
        _status = KernelStatus.starting;
        _desired = Desired.on;
      case BoxStopping():
        _status = KernelStatus.stopping;
      case BoxStopped():
        _status = KernelStatus.stopped;
    }
    _commit();
  }

  // ── KernelPort ─────────────────────────────────────────────

  @override
  Future<KernelSnapshot> current() async {
    await _ensureInitialized();
    return _last!;
  }

  @override
  Stream<KernelSnapshot> watch() => _hub.stream();

  @override
  Stream<KernelLink> watchLink() =>
      Stream<KernelLink>.multi((c) => c.add(KernelLink.connected));

  @override
  Future<RequestReceipt> request(DesiredRequest request) async {
    await _ensureInitialized();
    if (request.epoch != epoch) {
      return RequestReceipt(
        accepted: false,
        reason: RequestRejection.wrongEpoch,
        epoch: epoch,
        appliedSeq: _appliedSeq,
      );
    }
    if (request.seq <= _appliedSeq) {
      return RequestReceipt(
        accepted: false,
        reason: RequestRejection.stale,
        epoch: epoch,
        appliedSeq: _appliedSeq,
      );
    }
    _appliedSeq = request.seq;
    _desired = request.desired;
    _source = DesiredSource.app;
    if (request.desired == Desired.on) _launch = request.launch;
    if (_stopStuck) {
      // 上次停止卡住（kernelUnresponsive）：任何新请求都重新尝试回收。
      _stopStuck = false;
      _needsTeardown = true;
    }
    _commit();
    _scheduleDrive();
    return RequestReceipt(
      accepted: true,
      epoch: epoch,
      appliedSeq: _appliedSeq,
    );
  }

  @override
  Future<void> acknowledgeReplay(int attempt) async {
    await _ensureInitialized();
    if (attempt != _attempt || !_replay) return;
    _replay = false;
    _commit();
  }

  @override
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    try {
      await _ensureInitialized();
    } on KernelPortException catch (e) {
      return SelectFailed(e.code, e.message);
    }
    if (expectedAttempt != null && expectedAttempt != _attempt) {
      return const SelectStale();
    }
    try {
      await _service.selectOutbound(groupTag, outboundTag);
      return const SelectOk();
    } on PlatformException catch (e) {
      return SelectFailed(e.code, e.message ?? '');
    } catch (e) {
      return SelectFailed('unknown', '$e');
    }
  }

  /// 释放对平台状态/alert 流的订阅。幂等。
  Future<void> dispose() async {
    _disposed = true;
    await _statusSub?.cancel();
    await _alertSub?.cancel();
    _statusSub = null;
    _alertSub = null;
    await _hub.close();
  }

  // ── 快照发布 ────────────────────────────────────────────────

  KernelSnapshot _compose(int version) => KernelSnapshot(
    epoch: epoch,
    version: version,
    status: _status,
    attempt: _attempt,
    desired: _desired,
    source: _source,
    appliedSeq: _appliedSeq,
    activeConfigRevision: _activeRev,
    lastFailure: _failure,
    selectionsReplayNeeded: _replay,
  );

  /// 字段有变化才 version+1 并推送。
  void _commit() {
    final candidate = _compose(_version + 1);
    final last = _last;
    if (last != null &&
        last.copyWith(version: candidate.version) == candidate) {
      return;
    }
    _version++;
    _last = candidate;
    _hub.add(candidate);
  }

  // ── 驱动循环 ────────────────────────────────────────────────

  void _scheduleDrive() {
    if (_disposed) return;
    scheduleMicrotask(_drive);
  }

  Future<void> _drive() async {
    if (_driving || _disposed) return;
    _driving = true;
    try {
      while (!_disposed) {
        final action = _nextAction();
        if (action == null) break;
        await action();
      }
    } catch (e, st) {
      debugPrint('EmulatedKernelPort 驱动异常: $e\n$st');
    } finally {
      _driving = false;
    }
  }

  Future<void> Function()? _nextAction() {
    if (_needsTeardown) return _runStop;
    if (_desired == Desired.off) {
      if (_status == KernelStatus.started || _status == KernelStatus.starting) {
        return _runStop;
      }
      return null;
    }
    final launch = _launch;
    if (launch == null) return null;
    if (_status == KernelStatus.stopped) {
      return () => _runStart(reload: false);
    }
    if (_status == KernelStatus.started &&
        launch.configRevision != _activeRev) {
      return () => _runStart(reload: true);
    }
    return null;
  }

  Future<void> _runStart({required bool reload}) async {
    final spec = _launch!;
    final seq = _appliedSeq;
    if (_service is StubBoxService) {
      _fail(seq, const _Fault(KernelFailureCode.coreUnavailable, '核心库未加载'));
      return;
    }
    _attempt++;
    final attempt = _attempt;
    _status = KernelStatus.starting;
    _replay = false;
    _commit();

    final waiter = _startWaiter = Completer<_Fault?>();
    _sawProgress = false;
    _Fault? fault;
    try {
      fault = await (() async {
        await _service.changeConfigOptions(spec.optionsJson);
        if (reload) {
          await _service.restart(
            spec.runtimeConfigPath,
            name: spec.profileName,
          );
        } else {
          await _service.start(spec.runtimeConfigPath, name: spec.profileName);
        }
        // 平台状态可能在调用期间已经推送过（FFI），或本就是 started（重载未
        // 经过中间态）：此时没有后续事件可等。
        if (_native is BoxStarted && !waiter.isCompleted) waiter.complete(null);
        return waiter.future;
      })().timeout(startTimeout);
    } on TimeoutException {
      fault = const _Fault(KernelFailureCode.startTimeout, '启动超过 30 s 仍未完成');
    } catch (e) {
      fault = _Fault(KernelFailureCode.startService, _describe(e));
    }
    _startWaiter = null;

    if (fault == null) {
      _status = KernelStatus.started;
      _activeRev = spec.configRevision;
      _replay = true;
      _commit();
      return;
    }
    // 失败：无论归属，都要回收这个半启动的实例。
    _needsTeardown = true;
    _fail(seq, fault, attempt: attempt);
  }

  /// 只有仍是当前请求的那次执行才能把 desired 置 off 并写 failure。
  void _fail(int seq, _Fault fault, {int? attempt}) {
    if (_appliedSeq == seq) {
      _desired = Desired.off;
      _failure = KernelFailure(
        code: fault.code,
        message: fault.message,
        attempt: attempt ?? _attempt,
        seq: seq,
      );
    }
    _commit();
  }

  Future<void> _runStop() async {
    final seq = _appliedSeq;
    _needsTeardown = false;
    _stopStuck = false;
    _status = KernelStatus.stopping;
    _commit();

    final waiter = _stopWaiter = Completer<void>();
    _Fault? fault;
    try {
      if (_native is BoxStopped) {
        waiter.complete();
      } else {
        await _service.stop();
        if (_native is BoxStopped && !waiter.isCompleted) waiter.complete();
      }
      await waiter.future.timeout(stopTimeout);
    } on TimeoutException {
      fault = const _Fault(
        KernelFailureCode.kernelUnresponsive,
        '停止超过 20 s 仍未完成',
      );
    } catch (e) {
      if (_native is! BoxStopped) {
        fault = _Fault(KernelFailureCode.unknown, _describe(e));
      }
    }
    _stopWaiter = null;

    if (fault == null) {
      _status = KernelStatus.stopped;
      _activeRev = null;
      _replay = false;
      _commit();
      return;
    }
    // 如实：状态保持 stopping。仍是当前请求 → 写 failure 并停住，等下一个请求
    // 重试；已有更新请求 → 为它再回收一次。
    if (_appliedSeq == seq) {
      _failure = KernelFailure(
        code: fault.code,
        message: fault.message,
        attempt: _attempt,
        seq: seq,
      );
      _stopStuck = true;
    } else {
      _needsTeardown = true;
    }
    _commit();
  }

  // ── 平台回报 ────────────────────────────────────────────────

  void _onNativeStatus(BoxStatus s) {
    _native = s;

    final startWaiter = _startWaiter;
    if (startWaiter != null) {
      if (startWaiter.isCompleted) return;
      switch (s) {
        case BoxStarted():
          startWaiter.complete(null);
        case BoxStarting():
          _sawProgress = true;
        case BoxStopping() || BoxStopped():
          // 还没出现过 Starting 的 Stopped 可能是调用之前的陈旧事件，忽略；
          // 出现过进展之后又停止，才算启动失败。
          if (_sawProgress) {
            startWaiter.complete(
              const _Fault(KernelFailureCode.startService, '内核启动后又停止'),
            );
          }
      }
      return;
    }

    final stopWaiter = _stopWaiter;
    if (stopWaiter != null) {
      if (s is BoxStopped && !stopWaiter.isCompleted) stopWaiter.complete();
      return;
    }

    // 不是我们驱动的变化（iOS 系统设置、意外退出）：镜像平台，source=system。
    switch (s) {
      case BoxStarting():
        if (_status != KernelStatus.starting) {
          if (_status != KernelStatus.started) _attempt++;
          _status = KernelStatus.starting;
          _replay = false;
        }
        _desired = Desired.on;
        _source = DesiredSource.system;
        _launch = null;
      case BoxStarted():
        if (_status != KernelStatus.started) {
          if (_status != KernelStatus.starting) _attempt++;
          _status = KernelStatus.started;
          _activeRev = null;
          _replay = _attempt > 0;
          _desired = Desired.on;
          _source = DesiredSource.system;
          _launch = null;
        }
      case BoxStopping():
        if (_status == KernelStatus.started ||
            _status == KernelStatus.starting) {
          _status = KernelStatus.stopping;
          _desired = Desired.off;
          _source = DesiredSource.system;
        }
      case BoxStopped():
        if (_status != KernelStatus.stopped) {
          _status = KernelStatus.stopped;
          _activeRev = null;
          _replay = false;
          if (_desired == Desired.on) {
            _desired = Desired.off;
            _source = DesiredSource.system;
          }
        }
    }
    _commit();
    _scheduleDrive();
  }

  void _onAlert(BoxAlert alert) {
    if (!alert.type.isFatal) return;
    final waiter = _startWaiter;
    if (waiter == null || waiter.isCompleted) return;
    final code = switch (alert.type) {
      BoxAlertType.emptyConfiguration => KernelFailureCode.emptyConfiguration,
      BoxAlertType.createService => KernelFailureCode.createService,
      _ => KernelFailureCode.startService,
    };
    waiter.complete(_Fault(code, alert.message ?? ''));
  }

  static String _describe(Object e) =>
      e is PlatformException ? '${e.code}: ${e.message}' : '$e';
}

class _Fault {
  const _Fault(this.code, this.message);
  final KernelFailureCode code;
  final String message;
}
