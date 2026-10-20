import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:clashmiao/app/bootstrap/resident_services.dart';
import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_fakes/fake_kernel_port.dart';
import '../../support/fake_box_service.dart';
import '../../support/profile_store_support.dart';

// 这组测试走 main() 用的同一个入口 [startResidentServices]，业务 provider 全是
// 真的（连接控制器 + 状态机、手选重放流水线、出口探测、健康探测、测速协调器），
// 只替换平台边界：内核端口、启动产物准备、触觉 / 评分、网络请求、深链平台通道。
//
// 「页面全部暂停」：ShellPage 把非当前 tab 包在 TickerMode(enabled: false) 里，
// Riverpod 3 的 Consumer 会随之暂停监听。这里按生产顺序先走启动入口，再给
// 每个服务挂一个页面订阅并 pause 掉，模拟用户切到别的 tab。provider 由「活跃」
// 变「不活跃」时会停用自己的内部订阅，激活订阅的变化就不再往下传；此时只有
// startResidentServices 建的容器级订阅让服务保持活跃。
//
// 已做变异验证：把 listenResidentServices 退回「只 read 一次」后，删除订阅 →
// 断开、切订阅 → 重新应用 / 重放 / 出口重探、暂停内 A→B→A 三条都会失败。

/// 不碰磁盘的启动产物准备。
class _FakeLauncher extends ConnectionLauncher {
  _FakeLauncher(super.ref);

  @override
  Future<LaunchSpec> prepare(int id) async => LaunchSpec(
    runtimeConfigPath: '/work/runtime-config-prep-$id.json',
    optionsJson: '{"id":$id}',
    profileName: 'profile',
    // revision 不变：切订阅后由同一个内核实例按新订阅重放手选。
    configRevision: 0,
  );

  @override
  Future<Map<String, String>> selectorDefaults(int? revision) async => const {};

  @override
  Future<LaunchSpec> bindSeq(int id, LaunchSpec spec, int seq) async =>
      LaunchSpec(
        runtimeConfigPath: '/work/runtime-config-$seq.json',
        optionsJson: spec.optionsJson,
        profileName: spec.profileName,
        configRevision: spec.configRevision,
      );

  @override
  void sendFinished(int id) {}

  @override
  Future<void> discard(int id) async {}
}

class _QuietHaptic extends HapticService {
  _QuietHaptic(super.ref);

  @override
  Future<void> heavyImpact() async {}

  @override
  Future<void> mediumImpact() async {}
}

class _QuietReview extends StoreReviewService {
  _QuietReview(super.ref);

  @override
  Future<void> maybeRequestReview() async {}
}

/// 深链平台通道的替身：没有任何链接。
class _NoLinks implements AppLinks {
  @override
  Stream<Uri> get uriLinkStream => const Stream.empty();

  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Env {
  _Env(this.fa, SharedPreferences prefs, ProfileStore store) {
    final clock = fa.getClock(DateTime.utc(2026, 1, 1, 12));
    container = ProviderContainer(
      // 与 main() 的根容器一致：不启用 Riverpod 3 的自动重试。
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(store)),
        activeProfileProvider.overrideWith((ref) async {
          final id = ref.watch(activeIdProvider);
          if (id == null) return null;
          final inc =
              ref.watch(profileStoreProvider).value?.view().find(id)?.inc ?? '';
          return ProfileEntity(
            id: id,
            name: 'P-$id',
            url: 'https://example.invalid/$id',
            active: true,
            inc: inc,
          );
        }),
        kernelPortProvider.overrideWithValue(port),
        boxServiceProvider.overrideWithValue(const FakeBoxService()),
        liveGroupsProvider.overrideWith((_) => liveGroups.stream),
        connectionClockProvider.overrideWithValue(clock.now),
        latencyClockProvider.overrideWithValue(clock.now),
        isDesktopPlatformProvider.overrideWithValue(false),
        connectionLauncherProvider.overrideWith(_FakeLauncher.new),
        hapticServiceProvider.overrideWith(_QuietHaptic.new),
        storeReviewServiceProvider.overrideWith(_QuietReview.new),
        fatalFailureReporterProvider.overrideWithValue((_) {}),
        egressProbeFetchProvider.overrideWithValue(() {
          egressFetches++;
          return Completer<EgressIpResult>().future;
        }),
        connectionHealthProbeProvider.overrideWithValue((_) async {
          healthProbes++;
          return true;
        }),
        deepLinkServiceProvider.overrideWith(
          (ref) => DeepLinkService(ref, appLinks: _NoLinks()),
        ),
      ],
    );
    container.read(sharedPreferencesProvider);
    container.read(profileStoreProvider);
    fa.flushMicrotasks();

    // 生产顺序：main() 先建常驻订阅，页面随后 build 并监听这些服务。
    resident = startResidentServices(container);
    fa.flushMicrotasks();

    // 用户切到别的 tab：页面上的监听都被 TickerMode 暂停。顺序不能反——
    // 页面监听先挂上、再暂停，才会触发「活跃 → 不活跃」，provider 把自己的
    // 内部订阅停用；这正是生产里会发生的事。
    for (final p in <ProviderListenable<Object?>>[
      connectionControllerProvider,
      egressIpProbeProvider,
      connectionHealthProvider,
      latencyTestCoordinatorProvider,
      activeProfileProvider,
      outboundGroupsProvider,
    ]) {
      container.listen(p, (_, _) {}).pause();
    }
    fa.flushMicrotasks();
  }

  final FakeAsync fa;
  final port = FakeKernelPort();
  final liveGroups = StreamController<LiveGroups?>.broadcast();
  late final ProviderContainer container;
  late final List<ProviderSubscription<Object?>> resident;
  int egressFetches = 0;
  int healthProbes = 0;
  int _version = 0;

  static final activeIdProvider = StateProvider<String?>((_) => 'p1');

  ConnectionController get ctl =>
      container.read(connectionControllerProvider.notifier);

  void setActive(String? id) {
    container.read(activeIdProvider.notifier).state = id;
    // Riverpod 的延迟刷新走计时器。
    fa.flushMicrotasks();
    fa.elapse(const Duration(milliseconds: 1));
    fa.flushMicrotasks();
  }

  void push({
    KernelStatus status = KernelStatus.stopped,
    int attempt = 0,
    Desired desired = Desired.off,
    int appliedSeq = 0,
    int? revision,
    bool replay = false,
  }) {
    port.push(
      FakeKernelPort.snap(
        epoch: 'e1',
        version: ++_version,
        status: status,
        attempt: attempt,
        desired: desired,
        source: DesiredSource.app,
        appliedSeq: appliedSeq,
        activeConfigRevision: revision,
        selectionsReplayNeeded: replay,
      ),
    );
    fa.flushMicrotasks();
  }

  void started(DesiredRequest r, {bool replay = false}) => push(
    status: KernelStatus.started,
    attempt: 1,
    desired: Desired.on,
    appliedSeq: r.seq,
    revision: r.launch!.configRevision,
    replay: replay,
  );

  void pushGroups(String selected) {
    liveGroups.add(
      LiveGroups(
        (epoch: 'e1', attempt: 1),
        [
          OutboundGroup(
            tag: 'select',
            type: 'selector',
            selected: selected,
            items: const [
              OutboundProxy(tag: 'hk', type: 'vless'),
              OutboundProxy(tag: 'sg', type: 'vless'),
            ],
          ),
        ],
      ),
    );
    fa.flushMicrotasks();
  }

  /// 连上 attempt 1，按 p1 的手选重放 hk 并确认。返回 on 请求。
  DesiredRequest connect() {
    push();
    ctl.connect();
    fa.flushMicrotasks();
    final r = port.requests.single;
    started(r, replay: true);
    pushGroups('sg');
    expect(port.selectCalls, [
      (group: 'select', tag: 'hk', expectedAttempt: 1),
    ], reason: '前提：连上后按 p1 的手选重放');
    pushGroups('hk');
    started(r); // 确认后的快照（replay=false）
    return r;
  }

  void dispose() {
    container.dispose();
    unawaited(liveGroups.close());
    fa.flushMicrotasks();
  }
}

void _sim(String name, void Function(_Env e) body) {
  test(name, () async {
    SharedPreferences.setMockInitialValues({
      'proxy_selection_p1': '{"select":"hk"}',
      'proxy_selection_p2': '{"select":"sg"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final seeded = await seededProfileStore(prefs, [
      for (final id in ['p1', 'p2'])
        ProfileEntity(
          id: id,
          name: 'P-$id',
          url: 'https://example.invalid/$id',
          active: id == 'p1',
        ),
    ]);
    fakeAsync((fa) {
      // 存储内部的异步锁要在 fake 区里创建（见 connection_controller_test）。
      final store = ProfileStore(prefs: prefs, configDir: seeded.configDir);
      final e = _Env(fa, prefs, store);
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

  test('常驻清单：内部靠 ref.listen 驱动的服务一个不能少', () {
    expect(
      residentServiceProviders,
      containsAll(<Object>[
        deepLinkServiceProvider,
        connectionControllerProvider,
        egressIpProbeProvider,
        connectionHealthProvider,
        latencyTestCoordinatorProvider,
        boxStatsProvider,
      ]),
    );
  });

  // main() 本身没法在单测里跑（沿用 restore_wiring_test 的做法对源码断言）：
  // 下面的行为用例走的是 startResidentServices，这里钉住 main() 确实调用它、
  // 并把返回的订阅持有到 App 结束。
  test('main.dart 经 startResidentServices 建常驻订阅并持有', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains(
        '_residentSubscriptions.addAll(startResidentServices(container));',
      ),
    );
    expect(
      main,
      contains(
        'final _residentSubscriptions = <ProviderSubscription<Object?>>[];',
      ),
    );
    expect(
      main,
      isNot(contains('residentServiceProviders')),
      reason: '常驻清单只能经 startResidentServices 接线，不能在 main() 里另起一套',
    );
  });

  group('页面全部暂停时，经 startResidentServices 常驻的服务照常工作', () {
    _sim('删除激活订阅（激活订阅变 null）→ 自动断开', (e) {
      e.connect();
      final base = e.port.requests.length;

      e.setActive(null);

      expect(e.port.requests.length - base, 1);
      expect(e.port.requests.last.desired, Desired.off);
    });

    _sim('切到另一个订阅 → 以新订阅应用配置，手选按新订阅重放，出口重新探测', (e) {
      e.connect();
      final fetches = e.egressFetches;
      expect(fetches, greaterThan(0), reason: '前提：确认后已探测一次出口');

      e.setActive('p2');
      final r2 = e.port.requests.last;
      expect(r2.desired, Desired.on);
      expect(r2.reason, RequestReason.applyConfig);

      e.started(r2); // revision 相同：同一实例，按 p2 重放
      expect(e.port.selectCalls.last, (
        group: 'select',
        tag: 'sg',
        expectedAttempt: 1,
      ));

      e.pushGroups('sg'); // 生效节点 hk → sg
      expect(e.egressFetches, greaterThan(fetches), reason: '出口重新探测');
    });

    // 控制器必须一直跟着激活订阅走，才能在释放时判断「最终没变」：跟丢了
    // 中间的变化，释放后就会多发一次重新应用请求。
    _sim('配置暂停内 A→B→A：释放后订阅没变，不重新应用，同一实例按 A 重放 hk', (e) {
      e.push();
      e.ctl.connect();
      e.fa.flushMicrotasks();
      final r1 = e.port.requests.single;
      e.started(r1, replay: true);

      final pause = e.ctl.pauseConfigChanges();
      e.setActive('p2');
      e.pushGroups('sg'); // 旧实例的分组在暂停期间到达
      e.fa.elapse(const Duration(seconds: 6));
      expect(e.port.selectCalls, isEmpty, reason: '暂停期间不按 B 重放');

      e.setActive('p1');
      e.fa.elapse(const Duration(seconds: 6));
      expect(e.port.requests, [r1], reason: '暂停期间不发请求');

      pause.release();
      e.fa.flushMicrotasks();
      e.fa.elapse(const Duration(milliseconds: 1));
      e.fa.flushMicrotasks();

      expect(e.port.requests, [r1], reason: '最终订阅没变：不重新应用');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 1),
      ], reason: '内核选择与最终订阅 A 一致');
    });

    _sim('已连接后健康探测按时进行', (e) {
      e.connect();
      expect(e.healthProbes, 0);

      e.fa.elapse(ConnectionHealthMonitor.firstProbeDelay);
      e.fa.flushMicrotasks();

      expect(e.healthProbes, 1);
    });
  });
}
