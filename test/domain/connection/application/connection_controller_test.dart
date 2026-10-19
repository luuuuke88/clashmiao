import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/profile_store_support.dart';

// ─────────────────────────────────────────────────────────────────────────
// 测试替身
// ─────────────────────────────────────────────────────────────────────────

/// 不碰磁盘的启动产物准备：可编程失败 / 悬停，记录 bindSeq / sendFinished / discard。
class _FakeLauncher extends ConnectionLauncher {
  _FakeLauncher(super.ref);

  /// 非空时 prepare 先等它。
  Completer<void>? gate;

  /// 非空时 prepare 抛 [LaunchPreparationException]。
  ConnectionFailure? failWith;

  int revision = 1;
  final List<int> prepared = [];
  final List<({int id, int seq, String path})> bound = [];
  final List<int> finished = [];
  final List<int> discards = [];

  @override
  Future<LaunchSpec> prepare(int id) async {
    prepared.add(id);
    final g = gate;
    if (g != null) await g.future;
    final f = failWith;
    if (f != null) throw LaunchPreparationException(f);
    return LaunchSpec(
      runtimeConfigPath: '/work/runtime-config-prep-$id.json',
      optionsJson: '{"id":$id}',
      profileName: 'profile',
      configRevision: revision,
    );
  }

  @override
  Future<LaunchSpec> bindSeq(int id, LaunchSpec spec, int seq) async {
    final path = '/work/runtime-config-$seq.json';
    bound.add((id: id, seq: seq, path: path));
    return LaunchSpec(
      runtimeConfigPath: path,
      optionsJson: spec.optionsJson,
      profileName: spec.profileName,
      configRevision: spec.configRevision,
    );
  }

  @override
  void sendFinished(int id) => finished.add(id);

  @override
  Future<void> discard(int id) async => discards.add(id);
}

class _FakeHaptic extends HapticService {
  _FakeHaptic(super.ref);
  int heavy = 0;
  int medium = 0;

  @override
  Future<void> heavyImpact() async => heavy++;

  @override
  Future<void> mediumImpact() async => medium++;
}

class _FakeReview extends StoreReviewService {
  _FakeReview(super.ref);
  int calls = 0;

  @override
  Future<void> maybeRequestReview() async => calls++;
}

/// 可悬停的脏标记持久化：真实写 prefs，但 mark / clear 之前各自可以等一个
/// Completer，用来在「持久化尚未完成」的窗口里构造交错。
class _GatedDirtyStore implements SystemProxyDirtyStore {
  _GatedDirtyStore(this._prefs);

  final SharedPreferences _prefs;
  Completer<void>? markGate;
  Completer<void>? clearGate;
  final List<String> log = [];

  @override
  Future<void> mark() async {
    log.add('mark:start');
    final g = markGate;
    if (g != null) await g.future;
    await markSystemProxyDirty(_prefs);
    log.add('mark:done');
  }

  @override
  Future<void> clear() async {
    log.add('clear:start');
    final g = clearGate;
    if (g != null) await g.future;
    await clearSystemProxyDirty(_prefs);
    log.add('clear:done');
  }
}

/// 一个跑在 fake_async 里的完整环境：真实控制器 + 状态机，假端口 / 假 launcher。
class _Env {
  _Env._(
    this.fa,
    this.prefs,
    ProfileStore store, {
    required bool desktop,
    required bool analytics,
    required bool holdProfile,
    required bool gateDirty,
  }) {
    final clk = fa.getClock(DateTime.utc(2026, 1, 1, 12));
    if (holdProfile) profileGate = Completer<void>();
    if (gateDirty) dirtyStore = _GatedDirtyStore(prefs);
    port = FakeKernelPort();
    container = ProviderContainer(
      overrides: [
        // 每个内核实例的实时分组由测试推送（见 [kernelStarted] / [pushGroups]）。
        liveGroupsProvider.overrideWith((_) => liveGroups.stream),
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        // 手选写入经 ProfileStore.writeAux 校验订阅存在：种好 p1 / p2。
        profileStoreProvider.overrideWith((_) => Future.value(store)),
        kernelPortProvider.overrideWithValue(port),
        connectionClockProvider.overrideWithValue(clk.now),
        isDesktopPlatformProvider.overrideWithValue(desktop),
        connectionLauncherProvider.overrideWith((ref) {
          return launcher = _FakeLauncher(ref);
        }),
        hapticServiceProvider.overrideWith((ref) => haptic = _FakeHaptic(ref)),
        storeReviewServiceProvider.overrideWith(
          (ref) => review = _FakeReview(ref),
        ),
        fatalFailureReporterProvider.overrideWithValue(reported.add),
        activeProfileProvider.overrideWith((ref) async {
          final p = _activeProfile(ref);
          final gate = profileGate;
          if (gate != null) await gate.future;
          return p;
        }),
        if (dirtyStore != null)
          systemProxyDirtyStoreProvider.overrideWithValue(dirtyStore!),
      ],
    );
    container.read(sharedPreferencesProvider);
    container.read(profileStoreProvider);
    fa.flushMicrotasks();
    container.read(activeProfileProvider);
    fa.flushMicrotasks();
    // 先建出 launcher / haptic / review 的替身，再创建控制器。
    container.read(connectionLauncherProvider);
    container.read(hapticServiceProvider);
    container.read(storeReviewServiceProvider);
    // 保持实时分组 provider 常驻：推送发生在任何读取之前也不会丢。
    container.listen(liveGroupsProvider, (_, _) {});
    ctl = container.read(connectionControllerProvider.notifier);
    if (analytics) prefs.setBool('clashmiao_analytics_enabled', true);
    fa.flushMicrotasks();
  }

  static ProfileEntity? _activeProfile(Ref ref) {
    final id = ref.watch(activeProfileIdProvider);
    if (id == null) return null;
    // 代际取自存储里的真实记录：手选写入经 writeAux 按 (id, inc) 校验。
    final inc =
        ref.watch(profileStoreProvider).valueOrNull?.view().find(id)?.inc ?? '';
    return ProfileEntity(
      id: id,
      name: 'P-$id',
      url: 'https://example.invalid/$id',
      active: true,
      inc: inc,
    );
  }

  final FakeAsync fa;
  final SharedPreferences prefs;

  /// 非空时激活订阅的加载悬停在它上面（模拟订阅晚于内核快照到达）。
  Completer<void>? profileGate;

  /// 实时分组流（带实例归属）。
  final StreamController<LiveGroups?> liveGroups =
      StreamController<LiveGroups?>.broadcast();

  /// 运行时分组：[kernelStarted] 默认随快照推送这一份。
  List<OutboundGroup> runtimeGroups = const [
    OutboundGroup(
      tag: 'proxy',
      type: 'selector',
      selected: 'hk',
      items: [
        OutboundProxy(tag: 'hk', type: 'vless'),
        OutboundProxy(tag: 'old', type: 'vless'),
        OutboundProxy(tag: 'new', type: 'vless'),
      ],
    ),
    OutboundGroup(
      tag: 'auto',
      type: 'urltest',
      selected: 'sg',
      items: [OutboundProxy(tag: 'sg', type: 'vless')],
    ),
  ];

  /// 推一份归属于 [attempt] 实例的实时分组。
  void pushGroups({
    required int attempt,
    String epoch = 'e1',
    List<OutboundGroup>? groups,
  }) {
    liveGroups.add(
      LiveGroups((epoch: epoch, attempt: attempt), groups ?? runtimeGroups),
    );
    fa.flushMicrotasks();
  }

  /// 非空时系统代理脏标记的持久化可被悬停。
  _GatedDirtyStore? dirtyStore;
  late final FakeKernelPort port;
  late final ProviderContainer container;
  late final ConnectionController ctl;
  late final _FakeLauncher launcher;
  late final _FakeHaptic haptic;
  late final _FakeReview review;
  final List<ConnectionFailure> reported = [];
  int _version = 0;

  static final activeProfileIdProvider = StateProvider<String?>((_) => 'p1');

  ConnectionPhase get phase =>
      container.read(connectionControllerProvider).phase;
  ConnectionSnapshot get view => container.read(connectionControllerProvider);

  /// 推一份内核快照（version 自增）。
  void push({
    KernelStatus status = KernelStatus.stopped,
    int attempt = 0,
    Desired desired = Desired.off,
    DesiredSource source = DesiredSource.system,
    int appliedSeq = 0,
    int? revision,
    KernelFailure? failure,
    bool replay = false,
    String epoch = 'e1',
  }) {
    port.push(
      FakeKernelPort.snap(
        epoch: epoch,
        version: ++_version,
        status: status,
        attempt: attempt,
        desired: desired,
        source: source,
        appliedSeq: appliedSeq,
        activeConfigRevision: revision,
        lastFailure: failure,
        selectionsReplayNeeded: replay,
      ),
    );
    fa.flushMicrotasks();
  }

  /// 内核受理 on 请求 [r] 并走到 started。
  /// [withGroups]：随后推送这个实例的实时分组（真机上 started 之后很快就到）。
  void kernelStarted(
    DesiredRequest r, {
    int attempt = 1,
    bool replay = false,
    bool withGroups = true,
  }) {
    push(
      status: KernelStatus.started,
      attempt: attempt,
      desired: Desired.on,
      source: DesiredSource.app,
      appliedSeq: r.seq,
      revision: r.launch!.configRevision,
      replay: replay,
    );
    if (withGroups) pushGroups(attempt: attempt);
  }

  void kernelStopped(DesiredRequest r, {int attempt = 1}) {
    push(
      status: KernelStatus.stopped,
      attempt: attempt,
      desired: Desired.off,
      source: DesiredSource.app,
      appliedSeq: r.seq,
    );
  }

  /// 触发一个意图并收集它的终结结果。
  List<RequestOutcome> track(Future<RequestOutcome> f) {
    final out = <RequestOutcome>[];
    f.then(out.add);
    fa.flushMicrotasks();
    return out;
  }

  /// 同 [track]，但不推进微任务：模拟同一帧内的连点（准备尚未完成）。
  List<RequestOutcome> burst(Future<RequestOutcome> f) {
    final out = <RequestOutcome>[];
    f.then(out.add);
    return out;
  }

  void settle() => fa.flushMicrotasks();

  /// 让 Riverpod 的延迟刷新（依赖变化后重建 provider 走计时器）也跑完。
  void rebuild() {
    fa.flushMicrotasks();
    fa.elapse(const Duration(milliseconds: 1));
    fa.flushMicrotasks();
  }

  List<DesiredRequest> get requests => port.requests;

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    unawaited(liveGroups.close());
    fa.flushMicrotasks();
  }
}

/// 在 fake_async 里跑一个用例，结束时释放容器。
void _sim(
  String name,
  void Function(_Env e) body, {
  bool desktop = false,
  bool analytics = false,
  bool holdProfile = false,
  bool gateDirty = false,
  Map<String, Object> prefs = const {},
}) {
  test(name, () async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final store = await seededProfileStore(p, [
      for (final id in ['p1', 'p2'])
        ProfileEntity(
          id: id,
          name: 'P-$id',
          url: 'https://example.invalid/$id',
          active: id == 'p1',
        ),
    ]);
    fakeAsync((fa) {
      // 存储内部的异步锁要在 fake 区里创建：在真实区里建的锁，其首个排队动作会
      // 被调度到真实微任务队列，fake 时钟永远推不动（订阅附属数据写入会悬停）。
      final fakeZoneStore = ProfileStore(prefs: p, configDir: store.configDir);
      final e = _Env._(
        fa,
        p,
        fakeZoneStore,
        desktop: desktop,
        analytics: analytics,
        holdProfile: holdProfile,
        gateDirty: gateDirty,
      );
      try {
        body(e);
      } finally {
        e.dispose();
      }
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('冷启动与快照', () {
    _sim('尚无快照时是 resolving；首个快照（已停止）到达后是 disconnected', (e) {
      expect(e.phase, ConnectionPhase.resolving);

      e.push();

      expect(e.phase, ConnectionPhase.disconnected);
    });

    _sim('冷启动挂上运行中隧道：已连接，但无触觉 / 评分 / 起始时间 / 重放', (e) {
      e.push(
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        revision: 1,
      );

      expect(e.phase, ConnectionPhase.connected);
      expect(e.view.startedAt, isNull, reason: '起点未知，宁可不显示也不从 0 开始数');
      expect(e.haptic.heavy, 0);
      expect(e.review.calls, 0);
      expect(e.port.selectCalls, isEmpty);
    });

    _sim('外部入口（磁贴）启动：记起始时间，但不触觉、不评分', (e) {
      e.push();
      e.push(
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        source: DesiredSource.tile,
        revision: 1,
      );

      expect(e.phase, ConnectionPhase.connected);
      expect(e.view.startedAt, isNotNull);
      expect(e.haptic.heavy, 0);
      expect(e.review.calls, 0);
    });
  });

  group('connect / disconnect 的请求与终结', () {
    _sim(
      'connect：发 on 请求（seq = appliedSeq+1，路径绑定 seq）→ connecting → 连上后 succeeded',
      (e) {
        e.push(appliedSeq: 4);
        final out = e.track(e.ctl.connect());

        expect(e.requests, hasLength(1));
        final r = e.requests.single;
        expect(r.desired, Desired.on);
        expect(r.reason, RequestReason.userConnect);
        expect(r.seq, 5);
        expect(r.epoch, 'e1');
        expect(r.launch!.runtimeConfigPath, '/work/runtime-config-5.json');
        expect(e.launcher.finished, [1], reason: '发送路径走完后通知 launcher 释放引用');
        expect(e.phase, ConnectionPhase.connecting);
        expect(out, isEmpty, reason: '受理不等于完成');

        e.kernelStarted(r);

        expect(e.phase, ConnectionPhase.connected);
        expect(out, [const RequestSucceeded()]);
        expect(e.view.startedAt, isNotNull);
        expect(e.haptic.heavy, 1);
        expect(e.review.calls, 1);
      },
    );

    _sim('同一次连接内重复推送已连接快照：触觉 / 评分不重复', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      final r = e.requests.single;
      e.kernelStarted(r);
      e.kernelStarted(r); // version 递增但 attempt 不变
      e.kernelStarted(r);

      expect(e.haptic.heavy, 1);
      expect(e.review.calls, 1);
    });

    _sim('断开后再次连接：新的 attempt 再触发一次触觉与评分请求（「只弹一次」由评分服务自己守）', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single, attempt: 1);
      e.ctl.disconnect();
      e.settle();
      e.kernelStopped(e.requests.last, attempt: 1);

      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.last, attempt: 2);

      expect(e.haptic.heavy, 2);
      expect(e.review.calls, 2);
    });

    _sim('disconnect：发 off 请求 → 内核停止后 succeeded，触觉 medium 一次，起始时间清空', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);

      final out = e.track(e.ctl.disconnect());

      final off = e.requests.last;
      expect(off.desired, Desired.off);
      expect(off.reason, RequestReason.userDisconnect);
      expect(e.phase, ConnectionPhase.disconnecting);

      e.kernelStopped(off);

      expect(e.phase, ConnectionPhase.disconnected);
      expect(out, [const RequestSucceeded()]);
      expect(e.view.startedAt, isNull);
      expect(e.haptic.medium, 1);
    });

    _sim('内核启动失败：outcome 是 failed，界面带 failure，failureSeq 递增', (e) {
      e.push();
      final out = e.track(e.ctl.connect());
      final r = e.requests.single;
      final before = e.view.failureSeq;

      e.push(
        status: KernelStatus.stopped,
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
        appliedSeq: r.seq,
        failure: KernelFailure(
          code: KernelFailureCode.startService,
          message: 'boom',
          attempt: 1,
          seq: r.seq,
        ),
      );

      expect(e.phase, ConnectionPhase.disconnected);
      expect(e.view.failure, isA<KernelStartFailed>());
      expect(e.view.failureSeq, greaterThan(before));
      expect(out.single, isA<RequestFailed>());
    });

    _sim('准备失败（无激活订阅）：不发请求，outcome failed，界面可见失败', (e) {
      e.push();
      e.launcher.failWith = const NoActiveProfile();

      final out = e.track(e.ctl.connect());

      expect(e.requests, isEmpty);
      expect(out, [const RequestFailed(NoActiveProfile())]);
      expect(e.view.failure, const NoActiveProfile());
      expect(e.view.failureSeq, greaterThan(0));
      expect(e.phase, ConnectionPhase.disconnected);
    });

    _sim('准备失败（订阅存储只读）：不发请求，界面可见「请升级 App」的类型化失败', (e) {
      e.push();
      e.launcher.failWith = const ProfileStoreReadOnly(9);

      final out = e.track(e.ctl.connect());

      expect(e.requests, isEmpty);
      expect(out, [const RequestFailed(ProfileStoreReadOnly(9))]);
      expect(e.view.failure, const ProfileStoreReadOnly(9));
      expect(e.view.failureSeq, greaterThan(0));
      expect(e.phase, ConnectionPhase.disconnected);
    });

    _sim('准备期间又点断开：不发送 on，旧意图 superseded，准备产物被丢弃', (e) {
      e.push();
      e.launcher.gate = Completer<void>();
      final connectOut = e.track(e.ctl.connect());
      expect(e.launcher.prepared, [1]);

      final disconnectOut = e.track(e.ctl.disconnect());
      e.launcher.gate!.complete();
      e.settle();

      expect(connectOut, [const RequestSuperseded()]);
      expect(
        e.requests.where((r) => r.desired == Desired.on),
        isEmpty,
        reason: '准备期间被取代的 on 绝不发送，也不占 seq',
      );
      expect(e.requests.single.desired, Desired.off);
      expect(e.launcher.discards, contains(1));
      expect(disconnectOut, isEmpty, reason: 'off 已发出，等内核确认');
    });

    _sim('快速连点 开-关-开：最终状态与最后一次点击一致；被取代的意图各得一个 superseded', (e) {
      e.push();
      final a = e.burst(e.ctl.connect());
      final b = e.burst(e.ctl.disconnect());
      final c = e.burst(e.ctl.connect());
      e.settle();

      expect(a, [const RequestSuperseded()], reason: '准备期间被取代：不发送、不占 seq');
      expect(e.launcher.prepared, [1, 3]);
      expect(e.requests.map((r) => r.desired), [Desired.off, Desired.on]);
      expect(b, isEmpty, reason: 'off 已发出，要等更新的请求被内核受理才算被取代');

      e.kernelStarted(e.requests.last);

      expect(b, [const RequestSuperseded()]);
      expect(c, [const RequestSucceeded()]);
      expect(e.phase, ConnectionPhase.connected);
    });

    _sim('resolving 期间点击：先记录意图，首个快照到达后才发送', (e) {
      final out = e.track(e.ctl.connect());
      expect(e.requests, isEmpty);
      expect(e.phase, ConnectionPhase.resolving);

      e.push(appliedSeq: 2);

      expect(e.requests.single.desired, Desired.on);
      expect(e.requests.single.seq, 3);
      expect(out, isEmpty);
    });
  });

  group('toggle：按当前阶段决定动作', () {
    _sim('未连接 → 连接', (e) {
      e.push();
      e.ctl.toggle();
      e.settle();
      expect(e.requests.single.desired, Desired.on);
    });

    _sim('已连接 → 断开', (e) {
      e.push(
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        revision: 1,
      );
      e.ctl.toggle();
      e.settle();
      expect(e.requests.single.desired, Desired.off);
    });

    _sim('连接中点击 = 取消并断开（过渡期可点）', (e) {
      e.push();
      e.ctl.toggle();
      e.settle();
      expect(e.phase, ConnectionPhase.connecting);

      e.ctl.toggle();
      e.settle();

      expect(e.requests.map((r) => r.desired), [Desired.on, Desired.off]);
    });

    _sim('断开中（无失败）点击 = 重新连接', (e) {
      e.push(
        status: KernelStatus.stopping,
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
      );
      expect(e.phase, ConnectionPhase.disconnecting);

      e.ctl.toggle();
      e.settle();

      expect(e.requests.single.desired, Desired.on);
    });

    _sim('断开中且内核无响应（带 failure）点击 = 重发断开', (e) {
      e.push(
        status: KernelStatus.stopping,
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
        failure: const KernelFailure(
          code: KernelFailureCode.kernelUnresponsive,
          message: '',
          attempt: 1,
        ),
      );
      expect(e.view.failure, const KernelUnresponsive());

      e.ctl.toggle();
      e.settle();

      expect(e.requests.single.desired, Desired.off);
      expect(e.requests.single.reason, RequestReason.retry);
    });

    _sim('toggleTarget：与 toggle 同一份语义供按钮门禁复用', (e) {
      e.push();
      expect(toggleTarget(e.view), Desired.on);
      e.push(
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        revision: 1,
      );
      expect(toggleTarget(e.view), Desired.off);
    });
  });

  group('applyConfig（模式 / 设置 / 订阅变化）', () {
    _sim('未连接时没有副作用：不发请求', (e) {
      e.push();
      final out = e.track(e.ctl.applyConfig());
      expect(e.requests, isEmpty);
      expect(out, [const RequestSucceeded()]);
    });

    _sim('已连接时以新配置发一次 on（reason=applyConfig）；revision 一致则内核无操作', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
      e.launcher.revision = 2;

      final out = e.track(e.ctl.applyConfig());

      final r = e.requests.last;
      expect(r.desired, Desired.on);
      expect(r.reason, RequestReason.applyConfig);
      expect(r.launch!.configRevision, 2);
      // 注意：未确认的 on 请求期间展示 connecting 还是 reconnecting 由状态机的
      // phase 表决定（B3），这里不重复断言。

      e.push(
        status: KernelStatus.started,
        attempt: 2,
        desired: Desired.on,
        source: DesiredSource.app,
        appliedSeq: r.seq,
        revision: 2,
      );
      expect(e.phase, ConnectionPhase.connected);
      expect(out, [const RequestSucceeded()]);
      expect(e.haptic.heavy, 1, reason: '重载不是新连接：不再触觉 / 评分');
    });

    _sim('连续多次 applyConfig 合并：只发出最后一次的请求，其余 superseded', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
      final base = e.requests.length;

      final a = e.burst(e.ctl.applyConfig());
      final b = e.burst(e.ctl.applyConfig());
      final c = e.burst(e.ctl.applyConfig());
      e.settle();

      expect(a, [const RequestSuperseded()]);
      expect(b, [const RequestSuperseded()]);
      expect(c, isEmpty);
      expect(e.requests.length - base, 1, reason: '新 revision 只发一次请求');
    });

    _sim('重载中点击断开：最后一次点击生效', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
      e.ctl.applyConfig();
      e.settle();

      e.ctl.toggle();
      e.settle();

      expect(e.requests.last.desired, Desired.off);
    });
  });

  group('手选重放（每个新 attempt 进入 started 后）', () {
    setUp(() {});

    Map<String, Object> stored(Map<String, String> m) => {
      'proxy_selection_p1':
          '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}',
    };

    _sim(
      '按存储里的最新值逐条重放，带 expectedAttempt，最后确认一次',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);

        e.kernelStarted(e.requests.single, attempt: 7, replay: true);

        expect(e.port.selectCalls, [
          (group: 'proxy', tag: 'hk', expectedAttempt: 7),
          (group: 'auto', tag: 'sg', expectedAttempt: 7),
        ]);
        expect(e.port.acknowledged, [7]);
      },
      prefs: stored({'proxy': 'hk', 'auto': 'sg'}),
    );

    _sim('没有任何持久化选择：不调用 selectOutbound，仍确认重放（出口探测据此触发）', (e) {
      e.push();
      e.ctl.connect();
      e.settle();

      e.kernelStarted(e.requests.single, attempt: 1, replay: true);

      expect(e.port.selectCalls, isEmpty);
      expect(e.port.acknowledged, [1]);
    });

    _sim('同一 attempt 内重复推送不重复重放', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.container.read(proxySelectionStoreProvider);
      final r = e.requests.single;
      e.kernelStarted(r, attempt: 1, replay: true);
      e.kernelStarted(r, attempt: 1, replay: true);
      e.kernelStarted(r, attempt: 1, replay: false);

      expect(e.port.selectCalls, hasLength(1));
      expect(e.port.acknowledged, [1]);
    }, prefs: stored({'proxy': 'hk'}));

    _sim(
      '某个 group 重放失败，不影响其它 group 继续重放，且仍然确认',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);
        e.port.selectResult = (g, _, _) =>
            g == 'proxy' ? const SelectFailed('gone') : const SelectOk();

        e.kernelStarted(e.requests.single, attempt: 2, replay: true);

        expect(e.port.selectCalls.map((c) => c.group), ['proxy', 'auto']);
        expect(e.port.acknowledged, [2]);
      },
      prefs: stored({'proxy': 'hk', 'auto': 'sg'}),
    );

    _sim(
      'stale（内核已换新 attempt）：放弃重放且不确认，新 attempt 自己会再来',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);
        e.port.selectResult = (_, _, _) => const SelectStale();

        e.kernelStarted(e.requests.single, attempt: 2, replay: true);

        expect(e.port.selectCalls, hasLength(1), reason: '第一项 stale 就停');
        expect(e.port.acknowledged, isEmpty);
      },
      prefs: stored({'proxy': 'hk', 'auto': 'sg'}),
    );

    _sim('旧重放悬停期间用户做了新选择：重放收敛到用户最后的选择', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      final store = e.container.read(proxySelectionStoreProvider.notifier);
      final gate = Completer<void>();
      e.port.onSelectGate = gate;

      e.kernelStarted(e.requests.single, attempt: 3, replay: true);
      expect(e.port.selectCalls.single.tag, 'old', reason: '旧重放悬停在内核调用上');

      // 用户此刻选了新的节点（选择服务先写存储）。
      store.persist('proxy', 'new');
      e.settle();
      e.port.onSelectGate = null;
      gate.complete();
      e.settle();

      expect(
        e.port.selectCalls.map((c) => c.tag),
        ['old', 'new'],
        reason: '旧值发完后发现存储已变，必须再发最新值，最终内核停在用户最后的选择',
      );
      expect(e.port.acknowledged, [3]);
    }, prefs: stored({'proxy': 'old'}));

    _sim(
      '内核快照先于激活订阅到达：等订阅就绪后才重放，绝不确认「空重放」',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();

        // 快照先到：订阅仍在加载（profileGate 悬停）。
        e.kernelStarted(e.requests.single, attempt: 1, replay: true);
        e.rebuild();
        expect(e.port.acknowledged, isEmpty, reason: '订阅没就绪，存储还是空的：不能确认');
        expect(e.port.selectCalls, isEmpty);

        // 订阅就绪：存储按订阅 p1 读出手选，重放并确认。
        e.profileGate!.complete();
        e.rebuild();

        expect(e.port.selectCalls, [
          (group: 'proxy', tag: 'hk', expectedAttempt: 1),
        ]);
        expect(e.port.acknowledged, [1]);
      },
      holdProfile: true,
      prefs: stored({'proxy': 'hk'}),
    );

    _sim(
      '等订阅期间内核换了新 attempt：旧目标作废，不重放也不确认旧 attempt',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        final r = e.requests.single;
        e.kernelStarted(r, attempt: 1, replay: true);
        e.rebuild();
        // 等订阅期间网络切换触发重载：attempt 2 起来，同样需要重放。
        e.kernelStarted(r, attempt: 2, replay: true);
        e.rebuild();
        expect(e.port.acknowledged, isEmpty);

        e.profileGate!.complete();
        e.rebuild();

        expect(
          e.port.selectCalls.map((c) => c.expectedAttempt),
          [2],
          reason: 'attempt 1 的重放已过期，只为当前 attempt 重放',
        );
        expect(e.port.acknowledged, [2], reason: '不得确认已过期的 attempt 1');
      },
      holdProfile: true,
      prefs: stored({'proxy': 'hk'}),
    );
  });

  // 评审 Important 4：迁移与重放不是一条流水线时，首次升级的重放仍会先对不存在
  // 的 `proxy` 调 selectOutbound。真实控制器 + 编排流水线一起跑。
  group('启动后编排：校验 → 迁移 → 只重放运行时分组 → 确认', () {
    const runtime = [
      OutboundGroup(
        tag: 'select',
        type: 'selector',
        selected: 'auto',
        items: [
          OutboundProxy(tag: 'auto', type: 'urltest'),
          OutboundProxy(tag: 'hk', type: 'vless'),
          OutboundProxy(tag: 'sg', type: 'vless'),
        ],
      ),
      OutboundGroup(
        tag: 'auto',
        type: 'urltest',
        selected: 'sg',
        items: [
          OutboundProxy(tag: 'hk', type: 'vless'),
          OutboundProxy(tag: 'sg', type: 'vless'),
        ],
      ),
    ];

    _sim(
      '升级用户的旧记录（proxy）：分组迟到也等它，迁到 select 后只对 select 重放，绝不碰 proxy',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);

        e.kernelStarted(
          e.requests.single,
          attempt: 3,
          replay: true,
          withGroups: false,
        );
        e.fa.elapse(const Duration(seconds: 2));
        expect(e.port.selectCalls, isEmpty, reason: '分组没到之前什么都不发');
        expect(e.port.acknowledged, isEmpty);

        e.pushGroups(attempt: 3, groups: runtime);
        e.fa.flushMicrotasks();

        expect(e.port.selectCalls, [
          (group: 'select', tag: 'hk', expectedAttempt: 3),
        ]);
        expect(e.port.selectCalls.where((c) => c.group == 'proxy'), isEmpty);
        expect(e.container.read(proxySelectionStoreProvider), {'select': 'hk'});
        expect(e.prefs.getString('proxy_selection_p1'), '{"select":"hk"}');
        expect(e.port.acknowledged, [3]);
      },
      prefs: {'proxy_selection_p1': '{"proxy":"hk"}'},
    );

    _sim(
      '等不到这个实例的分组（5 s）：不重放任何记录、不删任何记录，确认（出口探测得以开始）',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);

        e.kernelStarted(
          e.requests.single,
          attempt: 1,
          replay: true,
          withGroups: false,
        );
        e.pushGroups(attempt: 0, groups: runtime); // 别的实例的分组不算
        e.fa.elapse(const Duration(seconds: 4, milliseconds: 900));
        expect(e.port.acknowledged, isEmpty);
        e.fa.elapse(const Duration(milliseconds: 200));

        expect(e.port.selectCalls, isEmpty);
        expect(e.port.acknowledged, [1]);
        expect(e.container.read(proxySelectionStoreProvider), {'proxy': 'hk'});
      },
      prefs: {'proxy_selection_p1': '{"proxy":"hk"}'},
    );

    _sim(
      '迁移等待期间重连（新 attempt）：旧流水线丢弃，新 attempt 自己完成迁移与确认',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.container.read(proxySelectionStoreProvider);
        final r = e.requests.single;

        e.kernelStarted(r, attempt: 1, replay: true, withGroups: false);
        e.kernelStarted(r, attempt: 2, replay: true, withGroups: false);
        e.pushGroups(attempt: 2, groups: runtime);
        e.fa.elapse(const Duration(seconds: 6));

        expect(e.port.selectCalls, [
          (group: 'select', tag: 'hk', expectedAttempt: 2),
        ]);
        expect(e.port.acknowledged, [2], reason: 'attempt 1 已过期，不确认');
      },
      prefs: {'proxy_selection_p1': '{"proxy":"hk"}'},
    );
  });

  group('失联与超时（Tick 由控制器按 nextWake 安排）', () {
    _sim('始终没有首个快照：10 s 后 nativeUnresponsive，按钮可点', (e) {
      e.fa.elapse(const Duration(seconds: 9, milliseconds: 900));
      expect(e.view.failure, isNull);

      e.fa.elapse(const Duration(milliseconds: 200));

      expect(e.view.failure, const NativeUnresponsive());
    });

    _sim('状态流失联 10 s：phase 保持最后值并标记 stale，之后给出 nativeUnresponsive', (e) {
      e.push(
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        revision: 1,
      );
      e.port.pushLink(KernelLink.lost);
      e.settle();
      expect(e.view.stale, isTrue);
      expect(e.phase, ConnectionPhase.connected);

      e.fa.elapse(const Duration(seconds: 10, milliseconds: 100));

      expect(e.view.failure, const NativeUnresponsive());
      expect(e.phase, ConnectionPhase.connected);
    });

    _sim('失联后点击 = 立即重新同步并重发最新意图', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.port.pushLink(KernelLink.lost);
      e.fa.elapse(const Duration(seconds: 11));
      expect(e.view.failure, const NativeUnresponsive());
      final syncs = e.port.currentCalls;

      e.ctl.toggle();
      e.settle();

      expect(e.port.currentCalls, greaterThan(syncs));
    });

    // 失联后点击 = 先重新同步、拿到有效基线之后才发送最新意图。用 Completer 悬停
    // current()，逐条钉住「发送时机 / 请求内容 / 最终 outcome」三件事。
    /// 已连接 → 状态流失联 10 s（nativeUnresponsive）→ 用户点击；current() 悬停。
    ({Completer<void> gate, List<RequestOutcome> out}) lostThenTap(_Env e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
      expect(e.requests, hasLength(1));
      e.port.pushLink(KernelLink.lost);
      e.fa.elapse(const Duration(seconds: 11));
      expect(e.view.failure, const NativeUnresponsive());

      final gate = Completer<void>();
      e.port.currentGate = gate;
      final before = e.port.currentCalls;
      final out = e.track(e.ctl.toggle());
      e.settle();
      expect(e.port.currentCalls, before + 1, reason: '点击立即发起重新同步');
      return (gate: gate, out: out);
    }

    _sim('重同步成功：完成前不发送；完成后以取回的新基线分配 seq 并发送，最终 succeeded', (e) {
      final (:gate, :out) = lostThenTap(e);
      // 失联期间别人（磁贴）把 appliedSeq 推进到 5：只有重同步能带回这份基线。
      e.port.currentResult = FakeKernelPort.snap(
        version: 100,
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        source: DesiredSource.tile,
        appliedSeq: 5,
        activeConfigRevision: 1,
      );

      e.fa.elapse(const Duration(seconds: 1));
      expect(e.requests, hasLength(1), reason: '重同步没完成：不得发送');

      gate.complete();
      e.settle();

      expect(e.requests, hasLength(2));
      final r = e.requests.last;
      expect(r.seq, 6, reason: '用重同步取回的 appliedSeq(5)+1 作为序号');
      expect(r.desired, Desired.on);
      expect(r.epoch, 'e1');
      expect(r.launch, isNotNull);
      expect(out, isEmpty);

      e.port.push(
        FakeKernelPort.snap(
          version: 101, // 必须新于重同步取回的基线（version 100）
          status: KernelStatus.started,
          attempt: 1,
          desired: Desired.on,
          source: DesiredSource.app,
          appliedSeq: 6,
          activeConfigRevision: 1,
        ),
      );
      e.settle();
      expect(out, [const RequestSucceeded()]);
      expect(e.view.failure, isNull);
    });

    _sim('重同步失败：一直不发送；重试次数有界；最终 failed(nativeUnresponsive)', (e) {
      final (:gate, :out) = lostThenTap(e);
      e.port.currentError = const KernelPortException('timeout', 'x');

      gate.complete();
      e.settle();
      expect(e.requests, hasLength(1), reason: '重同步失败：仍不得发送');
      expect(out, isEmpty, reason: '还在重试');

      e.fa.elapse(const Duration(seconds: 30));

      expect(e.requests, hasLength(1), reason: '从未发送过任何请求');
      expect(out, hasLength(1));
      expect(out.single, isA<RequestFailed>());
      expect((out.single as RequestFailed).failure, const NativeUnresponsive());
      // 重试有界：首次 + 最多 maxResyncAttempts 次，不会无限打 current()。
      expect(
        e.port.currentCalls,
        lessThanOrEqualTo(2 + ConnectionTiming.maxResyncAttempts + 1),
      );
    });

    _sim('重同步带回新纪元（原生进程重启）：基线重设，请求发往新纪元，最终 succeeded', (e) {
      final (:gate, :out) = lostThenTap(e);
      e.port.currentResult = FakeKernelPort.snap(
        epoch: 'e2',
        version: 1,
        status: KernelStatus.stopped,
        attempt: 0,
        appliedSeq: 0,
      );

      gate.complete();
      e.settle();

      expect(e.requests, hasLength(2));
      final r = e.requests.last;
      expect(r.epoch, 'e2', reason: '请求必须发往新纪元，而不是失联前的 e1');
      expect(r.seq, 1, reason: '新纪元从 appliedSeq(0)+1 开始');
      expect(r.desired, Desired.on);

      e.push(
        epoch: 'e2',
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        source: DesiredSource.app,
        appliedSeq: 1,
        revision: 1,
      );
      expect(out, [const RequestSucceeded()]);
    });

    _sim('请求已发出但快照 5 s 追不上：控制器执行重新同步', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      final before = e.port.currentCalls;

      e.fa.elapse(const Duration(seconds: 5, milliseconds: 100));

      expect(e.port.currentCalls, greaterThan(before));
    });
  });

  group('请求发送失败', () {
    _sim('request() 抛错：outcome failed(平台失败)，界面可见', (e) {
      e.push();
      e.port.requestError = const KernelPortException('unsupported', 'ios');

      final out = e.track(e.ctl.connect());

      expect(out.single, isA<RequestFailed>());
      expect(e.view.failure, const PlatformFailure('unsupported', 'ios'));
    });

    _sim('request() 超时 → nativeUnresponsive', (e) {
      e.push();
      e.port.requestError = const KernelPortException('timeout');

      final out = e.track(e.ctl.connect());

      expect(out.single, const RequestFailed(NativeUnresponsive()));
    });
  });

  group('致命失败上报（数据分析开关）', () {
    KernelFailure fatal(int seq) => KernelFailure(
      code: KernelFailureCode.createService,
      message: '',
      attempt: 1,
      seq: seq,
    );

    void failStart(_Env e) {
      e.push();
      e.ctl.connect();
      e.settle();
      final r = e.requests.single;
      e.push(
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
        appliedSeq: r.seq,
        failure: fatal(r.seq),
      );
    }

    _sim('开关关闭（默认）：致命失败不上报', (e) {
      failStart(e);
      expect(e.reported, isEmpty);
    });

    _sim('开关开启：致命失败上报一次', (e) {
      failStart(e);
      expect(e.reported, hasLength(1));
      expect(e.reported.single.isFatal, isTrue);
    }, analytics: true);

    _sim('开关开启：非致命失败（启动超时）不上报', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      final r = e.requests.single;
      e.push(
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
        appliedSeq: r.seq,
        failure: KernelFailure(
          code: KernelFailureCode.startTimeout,
          message: '',
          attempt: 1,
          seq: r.seq,
        ),
      );
      expect(e.reported, isEmpty);
    }, analytics: true);
  });

  group('系统代理脏标记（桌面）', () {
    _sim('发送 on 请求前置标记；连接失败不清', (e) {
      e.push();
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isNull);

      e.ctl.connect();
      e.settle();

      expect(e.requests, hasLength(1));
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);
    }, desktop: true);

    _sim('移动端从不置标记', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isNull);
    });

    _sim('用户关闭「设置系统代理」时不置标记', (e) {
      e.push();
      e.container.read(networkSettingsProvider.notifier).setSystemProxy(false);
      e.settle();
      e.ctl.connect();
      e.settle();
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isNull);
    }, desktop: true);

    _sim('断开成功（内核确认停止）才清标记', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);

      final out = e.track(e.ctl.disconnect());
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue, reason: '还没停下，不能清');
      e.kernelStopped(e.requests.last);

      expect(out, [const RequestSucceeded()]);
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isNull);
    }, desktop: true);

    _sim('断开失败（内核无响应）：不清标记，留给下次启动自愈', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);

      final out = e.track(e.ctl.disconnect());
      final off = e.requests.last;
      e.push(
        status: KernelStatus.stopping,
        attempt: 1,
        desired: Desired.off,
        source: DesiredSource.app,
        appliedSeq: off.seq,
        failure: KernelFailure(
          code: KernelFailureCode.kernelUnresponsive,
          message: '',
          attempt: 1,
          seq: off.seq,
        ),
      );

      expect(out.single, isA<RequestFailed>());
      expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);
    }, desktop: true);

    _sim(
      '旧断开的清标记悬停期间用户重新连接：新连接的标记不得被迟到的清理删掉',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.kernelStarted(e.requests.single);
        expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);

        // 断开：内核停止后，清标记的持久化悬停在 Completer 上。
        final store = e.dirtyStore!;
        final clearGate = Completer<void>();
        store.clearGate = clearGate;
        final out = e.track(e.ctl.disconnect());
        e.kernelStopped(e.requests.last);
        expect(store.log, ['mark:start', 'mark:done', 'clear:start']);
        expect(out, isEmpty, reason: '清标记没落盘，断开请求还不放行');

        // 清标记悬停期间，用户重新连接：置新标记的写入必须排在旧清理之后。
        e.ctl.connect();
        e.settle();
        expect(e.requests.where((r) => r.desired == Desired.on), hasLength(1));
        expect(
          e.requests.last.desired,
          Desired.off,
          reason: '新的 on 要等标记落盘才发送，而标记排在悬停的清理之后',
        );

        clearGate.complete();
        e.settle();

        expect(out, [const RequestSucceeded()]);
        expect(store.log, [
          'mark:start',
          'mark:done',
          'clear:start',
          'clear:done',
          'mark:start',
          'mark:done',
        ], reason: 'mark / clear 严格按序串行');
        expect(
          e.prefs.getBool(kSystemProxyDirtyKey),
          isTrue,
          reason: '迟到的旧清理没有清掉新标记',
        );
        expect(
          e.requests.where((r) => r.desired == Desired.on),
          hasLength(2),
          reason: '标记落盘后新的 on 才发出',
        );
      },
      desktop: true,
      gateDirty: true,
    );

    _sim(
      '新 on 的 mark 已排队、旧 off 的 stopped 快照才到达：旧清理作废，新标记全程保留',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.kernelStarted(e.requests.single);
        expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);
        final store = e.dirtyStore!;

        // 用户断开：off 已发出，内核尚未停下。
        final off = e.track(e.ctl.disconnect());
        final offReq = e.requests.last;
        expect(offReq.desired, Desired.off);

        // 立刻又点了连接：新的 on 要先落标记，而标记的持久化悬停（已排队）。
        final markGate = Completer<void>();
        store.markGate = markGate;
        e.ctl.connect();
        e.settle();
        expect(store.log.last, 'mark:start', reason: '新 on 的 mark 已排队 / 开始');
        expect(
          e.requests.where((r) => r.desired == Desired.on),
          hasLength(1),
          reason: '新 on 要等标记落盘才发送',
        );

        // 这时旧 off 的 stopped 快照才到达：它属于旧断开，清标记必须作废。
        e.kernelStopped(offReq);
        markGate.complete();
        e.settle();

        expect(off.single, const RequestSucceeded(), reason: '旧断开本身确实成功了');
        expect(
          store.log.where((l) => l.startsWith('clear')),
          isEmpty,
          reason: '旧 off 的清理被新 on 的意图作废，根本没有执行',
        );
        expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);

        // 新 on 发出，连接成功：标记仍在。
        final on2 = e.requests.last;
        expect(on2.desired, Desired.on);
        e.kernelStarted(on2, attempt: 2);
        expect(e.phase, ConnectionPhase.connected);
        expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);
      },
      desktop: true,
      gateDirty: true,
    );

    _sim(
      'on1 → off1 → on2 → off2：on2 的 mark 悬停时 off1 的 stopped 到达，off2 的 RPC 失败而 on2 发送成功：标记必须保留',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.kernelStarted(e.requests.single); // on1
        expect(e.prefs.getBool(kSystemProxyDirtyKey), isTrue);
        final store = e.dirtyStore!;

        final off1 = e.track(e.ctl.disconnect()); // off1
        final off1Req = e.requests.last;
        expect(off1Req.desired, Desired.off);

        // on2：它的 mark 悬停。
        final markGate = Completer<void>();
        store.markGate = markGate;
        e.ctl.connect();
        e.settle();
        // off2：紧接着又点了断开。
        final off2 = e.track(e.ctl.disconnect());
        e.settle();

        // off1 的 stopped 快照这时才到：它属于 off1，不属于「最近一次」的 off2。
        e.kernelStopped(off1Req);
        expect(store.log.where((l) => l.startsWith('clear')), isEmpty);

        // 放行：on2 的发送成功，off2 的 RPC 失败。
        e.port.requestErrorFor = (r) =>
            r.desired == Desired.off && r.seq > off1Req.seq
            ? StateError('off2 rpc failed')
            : null;
        markGate.complete();
        e.settle();

        final on2 = e.requests.lastWhere((r) => r.desired == Desired.on);
        expect(on2.seq, greaterThan(off1Req.seq), reason: 'on2 确实发出去了');
        e.kernelStarted(on2, attempt: 2);

        expect(off1.single, const RequestSucceeded());
        // off2 的请求确实发出过（seq=4，先于仍在等标记落盘的 on2=3），且就是那条
        // RPC 失败的 off；它唯一的终结结果是这次 RPC 失败。
        expect(e.requests.map((r) => (r.seq, r.desired)).toList(), [
          (off1Req.seq - 1, Desired.on),
          (off1Req.seq, Desired.off),
          (off1Req.seq + 2, Desired.off),
          (off1Req.seq + 1, Desired.on),
        ]);
        final off2Req = e.requests[2];
        expect(off2Req.seq, 4);
        expect(off2Req.desired, Desired.off);
        expect(on2.seq, 3);
        expect(off2, [
          const RequestFailed(UnexpectedFailure('Bad state: off2 rpc failed')),
        ]);
        expect(
          store.log.where((l) => l.startsWith('clear')),
          isEmpty,
          reason: 'off1 的停止快照（appliedSeq=off1）按它自己的断开归属，被 on2 作废',
        );
        expect(
          e.prefs.getBool(kSystemProxyDirtyKey),
          isTrue,
          reason: '内核在跑，标记必须还在',
        );
        expect(e.phase, ConnectionPhase.connected);
      },
      desktop: true,
      gateDirty: true,
    );

    _sim(
      '清标记只有一个入口：同一次断开不会重复清（效果清理之后 disconnect 收尾不再清第二次）',
      (e) {
        e.push();
        e.ctl.connect();
        e.settle();
        e.kernelStarted(e.requests.single);

        final out = e.track(e.ctl.disconnect());
        e.kernelStopped(e.requests.last);

        expect(out, [const RequestSucceeded()]);
        expect(
          e.dirtyStore!.log.where((l) => l == 'clear:start'),
          hasLength(1),
          reason: '效果清理与 disconnect 收尾合并为一次',
        );
      },
      desktop: true,
      gateDirty: true,
    );
  });

  group('设置变更触发重新应用（防抖 + 提示）', () {
    void connect(_Env e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
    }

    Future<void> change(_Env e, int port) =>
        e.container.read(networkSettingsProvider.notifier).setMixedPort(port);

    _sim('已连接时设置变更：防抖后重新应用一次，并推进提示 nonce', (e) {
      connect(e);
      final base = e.requests.length;
      final nonce = e.container.read(configChangeReconnectNoticeProvider);

      change(e, 3000);
      e.settle();
      expect(e.requests.length, base, reason: '防抖窗口内不发请求');
      e.fa.elapse(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 50),
      );

      expect(e.requests.length - base, 1);
      expect(e.requests.last.reason, RequestReason.applyConfig);
      expect(e.container.read(configChangeReconnectNoticeProvider) - nonce, 1);
    });

    _sim('密集的连续设置变更只合并成一次请求 + 一条提示', (e) {
      connect(e);
      final base = e.requests.length;
      final nonce = e.container.read(configChangeReconnectNoticeProvider);

      for (var p = 3001; p <= 3010; p++) {
        change(e, p);
        e.fa.elapse(const Duration(milliseconds: 50));
      }
      e.fa.elapse(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 100),
      );

      expect(e.requests.length - base, 1);
      expect(e.container.read(configChangeReconnectNoticeProvider) - nonce, 1);
    });

    _sim('防抖窗口内用户断开：不把连接顶回去', (e) {
      connect(e);
      change(e, 3000);
      e.settle();
      e.ctl.disconnect();
      e.settle();
      final base = e.requests.length;
      e.kernelStopped(e.requests.last);

      e.fa.elapse(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 100),
      );

      expect(e.requests.length, base);
    });

    _sim('未连接时改设置：无请求、无提示（保持既有「未连接时改设置无副作用」）', (e) {
      e.push();
      final nonce = e.container.read(configChangeReconnectNoticeProvider);

      change(e, 3000);
      e.fa.elapse(
        kConfigChangeReconnectDebounce + const Duration(milliseconds: 100),
      );

      expect(e.requests, isEmpty);
      expect(e.container.read(configChangeReconnectNoticeProvider), nonce);
    });
  });

  group('激活订阅变化', () {
    void connect(_Env e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
    }

    _sim('连接中最后一个订阅被删除（激活订阅变 null）→ 断开', (e) {
      connect(e);
      final base = e.requests.length;

      e.container.read(_Env.activeProfileIdProvider.notifier).state = null;
      e.rebuild();

      expect(e.requests.length - base, 1);
      expect(e.requests.last.desired, Desired.off);
    });

    _sim('已连接时切换到另一个订阅 → 以新订阅应用配置（on / applyConfig）', (e) {
      connect(e);
      final base = e.requests.length;

      e.container.read(_Env.activeProfileIdProvider.notifier).state = 'p2';
      e.rebuild();

      expect(e.requests.length - base, 1);
      expect(e.requests.last.desired, Desired.on);
      expect(e.requests.last.reason, RequestReason.applyConfig);
    });

    _sim('连接中（尚未连上）切换订阅同样应用新配置', (e) {
      e.push();
      e.ctl.connect();
      e.settle();
      expect(e.phase, ConnectionPhase.connecting);
      final base = e.requests.length;

      e.container.read(_Env.activeProfileIdProvider.notifier).state = 'p2';
      e.rebuild();

      expect(e.requests.length - base, 1);
      expect(e.requests.last.reason, RequestReason.applyConfig);
    });

    _sim('未连接时激活订阅变化：什么都不做', (e) {
      e.push();

      e.container.read(_Env.activeProfileIdProvider.notifier).state = 'p2';
      e.rebuild();
      e.container.read(_Env.activeProfileIdProvider.notifier).state = null;
      e.rebuild();

      expect(e.requests, isEmpty);
    });

    _sim('resolving 期间（首个快照前）连接意图已准备好，此时删除激活订阅 → 不发送旧订阅的 on', (e) {
      // 内核还没有任何快照：意图已记录并准备完毕，但 phase 仍是 resolving。
      final out = e.track(e.ctl.connect());
      expect(e.phase, ConnectionPhase.resolving);
      expect(e.launcher.prepared, [1], reason: '前提：准备已完成，只等首个快照');

      e.container.read(_Env.activeProfileIdProvider.notifier).state = null;
      e.rebuild();

      e.push(); // 首个快照：已停止
      e.settle();
      expect(
        e.requests.where((r) => r.desired == Desired.on),
        isEmpty,
        reason: '旧订阅产物不能在首个快照到达后被发出去',
      );
      expect(out.single, isA<RequestSuperseded>());
      expect(e.requests.map((r) => r.desired), [
        Desired.off,
      ], reason: '用户意图现在是「断开」：只发断开');
    });

    _sim('resolving 期间连接意图已准备好，此时切换激活订阅 → 以新订阅的产物发送', (e) {
      e.ctl.connect();
      e.settle();
      expect(e.phase, ConnectionPhase.resolving);
      expect(e.launcher.prepared, [1]);

      e.container.read(_Env.activeProfileIdProvider.notifier).state = 'p2';
      e.rebuild();
      expect(e.launcher.prepared, [1, 2], reason: '切换订阅 = 重新应用配置，重新准备');

      e.push();
      e.settle();

      final ons = e.requests.where((r) => r.desired == Desired.on).toList();
      expect(ons, hasLength(1), reason: '只发新订阅那一份');
      expect(e.launcher.bound.single.id, 2);
      expect(e.launcher.discards, contains(1), reason: '旧订阅的产物被丢弃');
    });

    _sim('resolving 期间用户已经点了断开，随后订阅变化：不能反过来把连接顶起来', (e) {
      e.ctl.connect();
      e.settle();
      e.ctl.disconnect();
      e.settle();

      e.container.read(_Env.activeProfileIdProvider.notifier).state = 'p2';
      e.rebuild();
      e.push();
      e.settle();

      expect(e.requests.where((r) => r.desired == Desired.on), isEmpty);
    });

    _sim('冷启动首次读到激活订阅不算「变化」', (e) {
      connect(e);
      final base = e.requests.length;
      e.settle();
      expect(e.requests.length, base);
    });
  });

  group('暂停配置变更（备份恢复期间）', () {
    void connect(_Env e) {
      e.push();
      e.ctl.connect();
      e.settle();
      e.kernelStarted(e.requests.single);
    }

    Future<void> change(_Env e, int port) =>
        e.container.read(networkSettingsProvider.notifier).setMixedPort(port);

    void setActive(_Env e, String? id) {
      e.container.read(_Env.activeProfileIdProvider.notifier).state = id;
      e.rebuild();
    }

    const after = Duration(milliseconds: 500);

    _sim('暂停前已排队的防抖重新应用被取消，释放时按最终状态只应用一次', (e) {
      connect(e);
      final base = e.requests.length;
      final nonce = e.container.read(configChangeReconnectNoticeProvider);

      change(e, 3000);
      e.settle();
      final pause = e.ctl.pauseConfigChanges();
      expect(e.ctl.configChangesPaused, isTrue);
      e.fa.elapse(kConfigChangeReconnectDebounce + after);
      expect(e.requests.length, base, reason: '暂停中：排队的那一次不能在中间态上发出');

      pause.release();
      e.settle();
      expect(e.ctl.configChangesPaused, isFalse);
      expect(e.requests.length - base, 1);
      expect(e.requests.last.reason, RequestReason.applyConfig);
      expect(e.container.read(configChangeReconnectNoticeProvider) - nonce, 1);

      e.fa.elapse(kConfigChangeReconnectDebounce + after);
      expect(e.requests.length - base, 1, reason: '释放后不再有迟到的防抖请求');
    });

    _sim('暂停期间设置与激活订阅都变了：期间零请求，释放时合并成一次 applyConfig', (e) {
      connect(e);
      final base = e.requests.length;

      final pause = e.ctl.pauseConfigChanges();
      change(e, 3001);
      e.settle();
      setActive(e, 'p2');
      change(e, 3002);
      e.settle();
      e.fa.elapse(kConfigChangeReconnectDebounce + after);
      expect(e.requests.length, base);

      pause.release();
      e.settle();
      expect(e.requests.length - base, 1);
      expect(e.requests.last.desired, Desired.on);
      expect(e.requests.last.reason, RequestReason.applyConfig);
    });

    _sim('暂停期间激活订阅被清空：释放时断开（off），不是重新应用', (e) {
      connect(e);
      final base = e.requests.length;

      final pause = e.ctl.pauseConfigChanges();
      setActive(e, 'p2');
      setActive(e, null);
      change(e, 3003);
      e.settle();
      expect(e.requests.length, base);

      pause.release();
      e.settle();
      expect(e.requests.length - base, 1);
      expect(e.requests.last.desired, Desired.off);
    });

    _sim('暂停期间订阅换走又换回：最终没变，只因设置变化应用一次；什么都没变则零请求', (e) {
      connect(e);
      final base = e.requests.length;

      var pause = e.ctl.pauseConfigChanges();
      setActive(e, 'p2');
      setActive(e, 'p1');
      pause.release();
      e.settle();
      expect(e.requests.length, base, reason: '激活订阅最终没变、设置也没变');

      pause = e.ctl.pauseConfigChanges();
      setActive(e, 'p2');
      setActive(e, 'p1');
      change(e, 3004);
      e.settle();
      pause.release();
      e.settle();
      expect(e.requests.length - base, 1);
    });

    _sim('嵌套暂停：最后一个释放才处理；release 幂等', (e) {
      connect(e);
      final base = e.requests.length;

      final outer = e.ctl.pauseConfigChanges();
      final inner = e.ctl.pauseConfigChanges();
      change(e, 3005);
      e.settle();

      inner.release();
      inner.release();
      e.settle();
      expect(e.ctl.configChangesPaused, isTrue, reason: '重复释放内层不能顺带释放外层');
      expect(e.requests.length, base);

      outer.release();
      e.settle();
      expect(e.requests.length - base, 1);
      outer.release();
      e.settle();
      expect(e.requests.length - base, 1);
    });

    _sim('未连接时暂停与释放：无请求、无提示', (e) {
      e.push();
      final nonce = e.container.read(configChangeReconnectNoticeProvider);

      final pause = e.ctl.pauseConfigChanges();
      change(e, 3006);
      setActive(e, 'p2');
      pause.release();
      e.fa.elapse(kConfigChangeReconnectDebounce + after);

      expect(e.requests, isEmpty);
      expect(e.container.read(configChangeReconnectNoticeProvider), nonce);
    });

    _sim('暂停期间用户断开：释放时不把连接顶回去', (e) {
      connect(e);

      final pause = e.ctl.pauseConfigChanges();
      change(e, 3007);
      e.settle();
      e.ctl.disconnect();
      e.settle();
      e.kernelStopped(e.requests.last);
      final base = e.requests.length;

      pause.release();
      e.fa.elapse(kConfigChangeReconnectDebounce + after);
      expect(e.requests.length, base);
    });
  });

  group('释放', () {
    _sim('控制器销毁时，未终结的请求以 interrupted 结束', (e) {
      e.push();
      final out = e.track(e.ctl.connect());
      expect(out, isEmpty);

      e.dispose();

      expect(out, [const RequestInterrupted()]);
    });
  });
}
