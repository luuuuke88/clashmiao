import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';

// ─────────────────────────────────────────────────────────────────────────
// 测试替身
// ─────────────────────────────────────────────────────────────────────────

/// 不碰磁盘的启动产物准备：可编程失败 / 悬停，记录 bindSeq / accepted / discard。
class _FakeLauncher extends ConnectionLauncher {
  _FakeLauncher(super.ref);

  /// 非空时 prepare 先等它。
  Completer<void>? gate;

  /// 非空时 prepare 抛 [LaunchPreparationException]。
  ConnectionFailure? failWith;

  int revision = 1;
  final List<int> prepared = [];
  final List<({int id, int seq, String path})> bound = [];
  final List<int> accepts = [];
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
  Future<void> accepted(int id, LaunchSpec spec) async => accepts.add(id);

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

/// 一个跑在 fake_async 里的完整环境：真实控制器 + 状态机，假端口 / 假 launcher。
class _Env {
  _Env._(
    this.fa,
    this.prefs, {
    required bool desktop,
    required bool analytics,
  }) {
    final clk = fa.getClock(DateTime.utc(2026, 1, 1, 12));
    port = FakeKernelPort();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
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
        activeProfileProvider.overrideWith((ref) async => _activeProfile(ref)),
      ],
    );
    container.read(sharedPreferencesProvider);
    fa.flushMicrotasks();
    container.read(activeProfileProvider);
    fa.flushMicrotasks();
    // 先建出 launcher / haptic / review 的替身，再创建控制器。
    container.read(connectionLauncherProvider);
    container.read(hapticServiceProvider);
    container.read(storeReviewServiceProvider);
    ctl = container.read(connectionControllerProvider.notifier);
    if (analytics) prefs.setBool('clashmiao_analytics_enabled', true);
    fa.flushMicrotasks();
  }

  static ProfileEntity? _activeProfile(Ref ref) {
    final id = ref.watch(activeProfileIdProvider);
    if (id == null) return null;
    return ProfileEntity(
      id: id,
      name: 'P-$id',
      url: 'https://example.invalid/$id',
      active: true,
    );
  }

  final FakeAsync fa;
  final SharedPreferences prefs;
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
  void kernelStarted(DesiredRequest r, {int attempt = 1, bool replay = false}) {
    push(
      status: KernelStatus.started,
      attempt: attempt,
      desired: Desired.on,
      source: DesiredSource.app,
      appliedSeq: r.seq,
      revision: r.launch!.configRevision,
      replay: replay,
    );
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
    fa.flushMicrotasks();
  }
}

/// 在 fake_async 里跑一个用例，结束时释放容器。
void _sim(
  String name,
  void Function(_Env e) body, {
  bool desktop = false,
  bool analytics = false,
  Map<String, Object> prefs = const {},
}) {
  test(name, () async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    fakeAsync((fa) {
      final e = _Env._(fa, p, desktop: desktop, analytics: analytics);
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
        expect(e.launcher.accepts, [1], reason: '受理后交给 launcher 清理旧文件');
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

    _sim('冷启动首次读到激活订阅不算「变化」', (e) {
      connect(e);
      final base = e.requests.length;
      e.settle();
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
