import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_hub.dart';
import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 的 [KernelPort]：Pigeon 请求/查询 + 事件通道快照流。
///
/// 事件通道 `com.clashmiao.app/kernel.snapshot`（`JSONMethodCodec`）推 JSON map，
/// 格式见 [KernelSnapshot]。本类负责三件事（连接生命周期 spec §10.5 / §10.8）：
///
/// 1. **版本过滤**：只接受 `(epoch 相同且 version 更大)`，或 `epoch 不同且来自
///    当前订阅 / 当前查询 token` 的快照。
/// 2. **重订阅**：流报错或结束 → 0.5/1/2/4 s（封顶 4 s）退避重订阅，每次重订阅
///    后做一次带 token、2 s 超时的 [current] 重新同步；首次同步失败同样退避重试。
/// 3. **链路健康度**：[watchLink]；失联超过 10 s 的判定属于状态机，不在这里。
///
/// 订阅按需：第一个 [watch]/[watchLink] 订阅者出现时才开始，最后一个离开即停。
class PlatformKernelPort implements KernelPort {
  PlatformKernelPort({
    pigeon.BoxHostApi? hostApi,
    Stream<Object?> Function()? eventStream,
    this.requestTimeout = const Duration(seconds: 2),
    this.backoff = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
  }) : _host = hostApi ?? pigeon.BoxHostApi(),
       _eventStream = eventStream ?? _defaultEventStream {
    _snapshots = KernelPortHub<KernelSnapshot>(
      onFirstListener: _startUpstream,
      onNoListeners: _stopUpstream,
    );
    _links = KernelPortHub<KernelLink>(
      onFirstListener: _startUpstream,
      onNoListeners: _stopUpstream,
    );
  }

  static const channel = EventChannel(
    'com.clashmiao.app/kernel.snapshot',
    JSONMethodCodec(),
  );

  static Stream<Object?> _defaultEventStream() =>
      channel.receiveBroadcastStream();

  final pigeon.BoxHostApi _host;
  final Stream<Object?> Function() _eventStream;

  /// `current()` / `request()` 的单次超时（spec §2：2 s）。
  final Duration requestTimeout;

  /// 重订阅退避序列；用完后一直用最后一项。
  final List<Duration> backoff;

  late final KernelPortHub<KernelSnapshot> _snapshots;
  late final KernelPortHub<KernelLink> _links;

  /// 最近一次被接受的快照。版本过滤的基准。
  KernelSnapshot? _accepted;

  /// 查询 token（代际）。以下任一事件都会递增，使此前发出的在途查询作废：
  /// 发起新查询、从流接受快照（此时在途查询已老于手上的快照）、一轮订阅结束
  /// 或被取消、全部订阅取消、dispose。只有持有当前 token 的查询才能更新缓存。
  int _queryToken = 0;
  _Query? _newestQuery;

  /// 订阅轮次（代际）。每次（重）订阅开始 +1，结束/取消时再 +1；旧一轮的流
  /// 事件、同步结果和同步失败一律按轮次丢弃，不得改缓存或链路状态。
  int _round = 0;

  // ── 订阅管理 ────────────────────────────────────────────────

  bool _upstreamActive = false;
  int _generation = 0;
  // 订阅由 _runUpstream 独占：重订阅、_stopUpstream、dispose 都会 cancel。
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _sub;
  Completer<void>? _wake;
  KernelLink? _link;

  void _startUpstream() {
    if (_upstreamActive) return;
    _upstreamActive = true;
    // 上游刚启动、还没有任何快照：保守地报失联，不谎报在线。
    _setLink(KernelLink.lost);
    final gen = ++_generation;
    unawaited(_runUpstream(gen));
  }

  void _stopUpstream() {
    if (_snapshots.hasListeners || _links.hasListeners) return;
    _upstreamActive = false;
    _generation++;
    _round++;
    _queryToken++; // 取消全部订阅：在途查询作废，返回后不得回填已清空的缓存
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
    _wake?.complete();
    _wake = null;
    // 停止订阅后旧值不再可信：下一批订阅者不回放它，也不再据它过滤。
    _snapshots.clearLatest();
    _links.clearLatest();
    _accepted = null;
    _link = null;
  }

  Future<void> _runUpstream(int gen) async {
    var retry = 0;
    while (_upstreamActive && gen == _generation) {
      final round = ++_round;
      bool live() => _upstreamActive && gen == _generation && round == _round;

      final ended = Completer<void>();
      var sawEvent = false;
      try {
        _sub = _eventStream().listen(
          (event) {
            if (!live()) return;
            final snap = _parse(event);
            if (snap == null) return;
            sawEvent = true;
            retry = 0;
            _setLink(KernelLink.connected);
            _offerFromStream(snap);
          },
          onError: (Object e, StackTrace st) {
            debugPrint('kernel.snapshot 流报错: $e');
            if (!ended.isCompleted) ended.complete();
          },
          onDone: () {
            if (!ended.isCompleted) ended.complete();
          },
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('kernel.snapshot 订阅失败: $e');
        ended.complete();
      }

      // 订阅（或重订阅）之后立即重新同步；结果只对本轮有效。失败不致命，流若
      // 在推数据就算已恢复，否则按失联处理并退避。
      unawaited(
        current().then<void>(
          (_) {
            if (!live()) return;
            _setLink(KernelLink.connected);
          },
          onError: (Object e) {
            if (!live()) return;
            debugPrint('kernel.snapshot 重新同步失败: $e');
            if (!sawEvent) {
              _setLink(KernelLink.lost);
              // 同步失败且流也没数据：视同这次订阅作废，走退避重订阅。
              if (!ended.isCompleted) ended.complete();
            }
          },
        ),
      );

      await ended.future;
      if (!_upstreamActive || gen != _generation) return;
      // 本轮结束：作废本轮的一切迟到回调与在途查询。
      _round++;
      _queryToken++;
      final old = _sub;
      _sub = null;
      if (old != null) unawaited(old.cancel());
      _setLink(KernelLink.lost);

      final delay =
          backoff[retry < backoff.length ? retry : backoff.length - 1];
      retry++;
      final wake = _wake = Completer<void>();
      await Future.any<void>([Future<void>.delayed(delay), wake.future]);
      _wake = null;
    }
  }

  void _setLink(KernelLink link) {
    if (_link == link) return;
    _link = link;
    _links.add(link);
  }

  // ── 版本过滤 ────────────────────────────────────────────────

  /// 载荷 → 快照；结构非法返回 null（记日志，丢弃，不合成默认值）。
  KernelSnapshot? _parse(Object? event) {
    if (event is! Map) {
      debugPrint('kernel.snapshot 载荷不是 Map: ${event.runtimeType}');
      return null;
    }
    try {
      return KernelSnapshot.fromJson(event.cast<Object?, Object?>());
    } on FormatException catch (e) {
      debugPrint('kernel.snapshot 载荷非法，已丢弃: ${e.message}');
      return null;
    }
  }

  /// 来自**当前订阅**的快照。
  void _offerFromStream(KernelSnapshot snap) {
    if (!_accepts(snap, fromCurrentSource: true)) return;
    _accept(snap);
    // 任何在途查询现在都老于手上这份快照。
    _queryToken++;
  }

  bool _accepts(KernelSnapshot snap, {required bool fromCurrentSource}) {
    final base = _accepted;
    if (base == null) return fromCurrentSource;
    if (snap.epoch == base.epoch) return snap.version > base.version;
    return fromCurrentSource;
  }

  void _accept(KernelSnapshot snap) {
    _accepted = snap;
    _snapshots.add(snap);
  }

  // ── KernelPort ─────────────────────────────────────────────

  @override
  Stream<KernelSnapshot> watch() => _snapshots.stream();

  @override
  Stream<KernelLink> watchLink() => _links.stream();

  /// 整个调用共用一个 2 s 截止时间：等待较新查询的结果也只花剩余预算。
  @override
  Future<KernelSnapshot> current() {
    final q = _Query(++_queryToken);
    _newestQuery = q;
    q.future = _query(q);
    return q.future.timeout(
      requestTimeout,
      onTimeout: () =>
          throw const KernelPortException('timeout', 'getSnapshot 超过 2 s 未返回'),
    );
  }

  Future<KernelSnapshot> _query(_Query q) async {
    final pigeon.KernelSnapshotMsg msg;
    try {
      msg = await _host.getSnapshot();
    } on PlatformException catch (e) {
      throw KernelPortException(e.code, e.message ?? '');
    }
    final KernelSnapshot? snap = _parse(_msgToJson(msg));
    if (snap == null) {
      throw const KernelPortException('malformed', 'getSnapshot 返回了非法快照');
    }
    // 无订阅时不缓存：没有订阅者，也就没有谁来保证缓存不过期。
    if (q.token == _queryToken && _upstreamActive) {
      if (_accepts(snap, fromCurrentSource: true)) _accept(snap);
      return _accepted ?? snap;
    }
    // 作废的查询：结果丢弃（不改缓存、不推送）。返回已接受的较新快照；还没有
    // 就等较新的那次查询；没有更新的查询（订阅被取消）则如实返回自己拿到的值。
    final cached = _accepted;
    if (cached != null) return cached;
    final newest = _newestQuery;
    if (newest != null && !identical(newest, q)) return newest.future;
    return snap;
  }

  @override
  Future<RequestReceipt> request(DesiredRequest request) async {
    final launch = request.launch;
    final msg = pigeon.DesiredRequestMsg(
      epoch: request.epoch,
      seq: request.seq,
      desired: request.desired.name,
      reason: request.reason.name,
      launch: launch == null
          ? null
          : pigeon.LaunchSpecMsg(
              runtimeConfigPath: launch.runtimeConfigPath,
              optionsJson: launch.optionsJson,
              profileName: launch.profileName,
              configRevision: launch.configRevision,
            ),
    );
    final pigeon.ReceiptMsg receipt;
    try {
      receipt = await _host.request(msg).timeout(requestTimeout);
    } on TimeoutException {
      throw const KernelPortException('timeout', 'request 超过 2 s 未返回');
    } on PlatformException catch (e) {
      throw KernelPortException(e.code, e.message ?? '');
    }
    return RequestReceipt(
      accepted: receipt.accepted,
      reason: RequestRejection.tryParse(receipt.reason),
      epoch: receipt.epoch,
      appliedSeq: receipt.appliedSeq,
    );
  }

  @override
  Future<void> acknowledgeReplay(int attempt) async {
    try {
      await _host.acknowledgeReplay(attempt).timeout(requestTimeout);
    } on TimeoutException {
      throw const KernelPortException('timeout', 'acknowledgeReplay 超时');
    } on PlatformException catch (e) {
      throw KernelPortException(e.code, e.message ?? '');
    }
  }

  @override
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    try {
      await _host.selectOutbound(
        pigeon.SelectOutboundRequest(
          groupTag: groupTag,
          outboundTag: outboundTag,
          expectedAttempt: expectedAttempt,
        ),
      );
      return const SelectOk();
    } on PlatformException catch (e) {
      // 原生约定：attempt 不符时以 FlutterError("stale") 回调且不写入。
      if (e.code == 'stale') return const SelectStale();
      return SelectFailed(e.code, e.message ?? '');
    } catch (e) {
      return SelectFailed('unavailable', '$e');
    }
  }

  /// 释放订阅与流。幂等。
  Future<void> dispose() async {
    _upstreamActive = false;
    _generation++;
    _round++;
    _queryToken++;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    _wake?.complete();
    _wake = null;
    await _snapshots.close();
    await _links.close();
  }

  static Map<Object?, Object?> _msgToJson(pigeon.KernelSnapshotMsg m) {
    final f = m.lastFailure;
    return {
      'epoch': m.epoch,
      'version': m.version,
      'status': m.status,
      'attempt': m.attempt,
      'desired': m.desired,
      'source': m.source,
      'appliedSeq': m.appliedSeq,
      'activeConfigRevision': m.activeConfigRevision,
      'selectionsReplayNeeded': m.selectionsReplayNeeded,
      'retainedConfigPaths': m.retainedConfigPaths,
      'lastFailure': f == null
          ? null
          : {
              'code': f.code,
              'message': f.message,
              'attempt': f.attempt,
              'seq': f.seq,
            },
    };
  }
}

/// 一次 [PlatformKernelPort.current] 查询：token 即代际，[future] 供被取代的
/// 旧查询等待较新的结果。
class _Query {
  _Query(this.token);
  final int token;
  late final Future<KernelSnapshot> future;
}
