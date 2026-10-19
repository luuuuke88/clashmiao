import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/store_review/store_review_service.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/restore_harness.dart';

/// 订阅存储（子项目 C）→ 连接控制器（子项目 B）的交接，spec §10.4 / §10.6：
/// **真实**控制器 + 真实 launcher + 真实 ProfileStore / ProfileRepository /
/// BackupEngine，只有内核换成 [FakeKernelPort]（受理请求后像真内核一样推快照）。
///
/// - 已连接时删掉最后一条订阅 → 断开；
/// - 已连接时删掉激活订阅、还有别的 → 以新的激活订阅 applyConfig；
/// - 已连接时导入空备份 → 断开；
/// - 恢复期间配置变更不在中间态上重载，结束后按最终状态只应用一次。

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

/// 像真内核一样回应请求：on → started（revision 变了才算新 attempt），
/// off → stopped。快照在回执之后推（真实顺序之一）。
class _Kernel {
  _Kernel() {
    port.onRequest = (r) {
      scheduleMicrotask(() => _apply(r));
    };
  }

  final port = FakeKernelPort(initial: FakeKernelPort.snap());
  int _version = 1;
  int _attempt = 0;
  int? _revision;
  bool _started = false;

  void _apply(DesiredRequest r) {
    if (r.desired == Desired.on) {
      final revision = r.launch!.configRevision;
      if (!_started || revision != _revision) _attempt++;
      _started = true;
      _revision = revision;
      port.push(
        FakeKernelPort.snap(
          version: ++_version,
          status: KernelStatus.started,
          attempt: _attempt,
          desired: Desired.on,
          source: DesiredSource.app,
          appliedSeq: r.seq,
          activeConfigRevision: revision,
        ),
      );
    } else {
      _started = false;
      port.push(
        FakeKernelPort.snap(
          version: ++_version,
          attempt: _attempt,
          source: DesiredSource.app,
          appliedSeq: r.seq,
        ),
      );
    }
  }
}

String _backup({
  List<String> ids = const [],
  String? active,
  Map<String, Object> prefs = const {},
}) => jsonEncode({
  'version': 2,
  'schema': 1,
  'createdAt': 1,
  'profiles': [
    for (final id in ids)
      {
        'id': id,
        'name': 'backup-$id',
        'url': 'https://example.com/$id',
        'lastUpdate': null,
        'updateInterval': 1,
        'subInfo': null,
        'customUserAgent': null,
        'rev': 1,
      },
  ],
  'activeProfileId': active,
  'profileConfigs': {for (final id in ids) id: sampleConfig(id)},
  'preferences': prefs,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RestoreHarness h;
  late ProfileRepository repo;
  late _Kernel kernel;
  late ProviderContainer container;
  late Directory workDir;

  ConnectionController ctl() =>
      container.read(connectionControllerProvider.notifier);
  ConnectionPhase phase() => container.read(connectionControllerProvider).phase;
  List<DesiredRequest> requests() => kernel.port.requests;

  Future<void> until(bool Function() ok, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!ok()) {
      if (DateTime.now().isAfter(deadline)) fail('等待超时：$what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// 比防抖窗口更久：证明没有迟到的配置变更请求。
  Future<void> quiet() => Future<void>.delayed(
    kConfigChangeReconnectDebounce + const Duration(milliseconds: 250),
  );

  Future<void> setUpWith(List<String> ids, {required String active}) async {
    h = await RestoreHarness.create(
      initialPrefs: {'clashmiao_mixed_port': 2080},
    );
    for (final id in ids) {
      await h.seed(id, active: id == active);
    }
    repo = ProfileRepository(
      dio: Dio(),
      configDir: h.tmp,
      prefs: h.prefs,
      boxService: const StubBoxService(),
      store: h.store,
    );
    workDir = Directory('${h.tmp.path}/work')..createSync();
    kernel = _Kernel();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => h.prefs),
        profileStoreProvider.overrideWith((ref) async => h.store),
        profileRepositoryProvider.overrideWith((ref) async => repo),
        boxServiceProvider.overrideWithValue(
          const StubBoxService(reason: StubReason.unsupported),
        ),
        kernelPortProvider.overrideWithValue(kernel.port),
        connectionLauncherProvider.overrideWith(
          (ref) =>
              ConnectionLauncher(ref, workingDirectory: () async => workDir),
        ),
        isDesktopPlatformProvider.overrideWithValue(false),
        hapticServiceProvider.overrideWith(_QuietHaptic.new),
        storeReviewServiceProvider.overrideWith(_QuietReview.new),
        fatalFailureReporterProvider.overrideWithValue((_) {}),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(activeProfileProvider.future);
    // 控制器随 App 创建（main.dart）；它的激活订阅监听从这里开始。
    ctl();
    await pumpEventQueue();
  }

  Future<void> connected() async {
    unawaited(ctl().connect());
    await until(() => phase() == ConnectionPhase.connected, '连上');
    await pumpEventQueue();
  }

  tearDown(() async {
    container.dispose();
    await kernel.port.dispose();
    await h.dispose();
  });

  group('§10.6 删除订阅时的连接状态', () {
    test('已连接时删掉最后一条订阅 → 控制器发起断开，最终 disconnected', () async {
      await setUpWith(['a'], active: 'a');
      await connected();
      final base = requests().length;

      await repo.delete('a');
      await until(() => phase() == ConnectionPhase.disconnected, '断开');
      await quiet();

      final sent = requests().sublist(base);
      expect(sent.map((r) => r.desired), [Desired.off]);
      expect(sent.single.reason, RequestReason.userDisconnect);
      expect(phase(), ConnectionPhase.disconnected);
    });

    test('已连接时删掉激活订阅、还有别的 → 自动切到剩下的，并以新订阅 applyConfig 一次', () async {
      await setUpWith(['a', 'b'], active: 'a');
      await connected();
      expect(requests().single.launch!.profileName, 'name-a');
      final base = requests().length;

      await repo.delete('a');
      await until(() => requests().length > base, '重新应用');
      await until(() => phase() == ConnectionPhase.connected, '新配置连上');
      await quiet();

      final sent = requests().sublist(base);
      expect(sent, hasLength(1));
      expect(sent.single.desired, Desired.on);
      expect(sent.single.reason, RequestReason.applyConfig);
      expect(
        sent.single.launch!.profileName,
        'name-b',
        reason: '必须用删除后自动切换到的新激活订阅，而不是被删掉的那条',
      );
      expect((await container.read(activeProfileProvider.future))!.id, 'b');
    });

    test('删掉的不是激活订阅 → 连接不受影响，不发任何请求', () async {
      await setUpWith(['a', 'b'], active: 'a');
      await connected();
      final base = requests().length;

      await repo.delete('b');
      await quiet();

      expect(requests().length, base);
      expect(phase(), ConnectionPhase.connected);
    });
  });

  group('备份恢复与连接', () {
    RestoreRefresher refresher() => RestoreRefresher(
      container: container,
      // 补拉不走网络；重连与暂停用默认接线（真实控制器）。
      fetchProfile: (_) async {},
    );

    test('已连接时导入空备份 → 断开，最终 disconnected', () async {
      await setUpWith(['a'], active: 'a');
      await connected();
      final base = requests().length;

      final plan = h.engine.prepare(_backup());
      final outcome = await refresher().restore(h.engine, plan);
      await outcome.backfill;
      await until(() => phase() == ConnectionPhase.disconnected, '断开');
      await quiet();

      expect(await container.read(activeProfileProvider.future), isNull);
      expect(requests().sublist(base).map((r) => r.desired), [Desired.off]);
    });

    test('已连接时恢复（激活订阅与网络设置都变）：期间不重载，结束后以最终配置只应用一次', () async {
      await setUpWith(['a'], active: 'a');
      await connected();
      final base = requests().length;
      final nonce = container.read(configChangeReconnectNoticeProvider);

      final plan = h.engine.prepare(
        _backup(
          ids: ['b', 'c'],
          active: 'c',
          prefs: {'clashmiao_mixed_port': 3000},
        ),
      );
      final outcome = await refresher().restore(h.engine, plan);
      await outcome.backfill;
      expect(ctl().configChangesPaused, isFalse, reason: '恢复结束必须释放暂停');
      await until(() => requests().length > base, '重新应用');
      await quiet();

      final sent = requests().sublist(base);
      expect(sent, hasLength(1), reason: '激活订阅切换 + 网络设置变化只合并成一次');
      expect(sent.single.reason, RequestReason.applyConfig);
      expect(sent.single.launch!.profileName, 'backup-c');
      expect(
        jsonDecode(sent.single.launch!.optionsJson),
        containsPair('mixed-port', 3000),
        reason: '应用的是恢复后的最终网络设置',
      );
      expect(container.read(networkSettingsProvider).mixedPort, 3000);
      expect(container.read(configChangeReconnectNoticeProvider) - nonce, 1);
    });

    test('恢复开始前已排队的防抖重新应用被取消：整个过程只应用一次', () async {
      await setUpWith(['a'], active: 'a');
      await connected();
      final base = requests().length;

      await container.read(networkSettingsProvider.notifier).setMixedPort(2999);
      // 防抖窗口还没到就开始恢复。
      final plan = h.engine.prepare(_backup(ids: ['b'], active: 'b'));
      final outcome = await refresher().restore(h.engine, plan);
      await outcome.backfill;
      await until(() => requests().length > base, '重新应用');
      await quiet();

      final sent = requests().sublist(base);
      expect(sent, hasLength(1));
      expect(sent.single.launch!.profileName, 'backup-b');
    });

    test('未连接时恢复：零请求；控制器不存在时也不会被恢复流程建出来', () async {
      await setUpWith(['a'], active: 'a');

      final plan = h.engine.prepare(
        _backup(ids: ['b'], active: 'b', prefs: {'clashmiao_mixed_port': 3000}),
      );
      await (await refresher().restore(h.engine, plan)).backfill;
      await quiet();
      expect(requests(), isEmpty);

      // 换一个从没建过控制器的容器：暂停与补拉后的重连都不得把它建出来。
      final bare = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((ref) async => h.prefs),
          profileStoreProvider.overrideWith((ref) async => h.store),
          profileRepositoryProvider.overrideWith((ref) async => repo),
          kernelPortProvider.overrideWithValue(kernel.port),
        ],
      );
      addTearDown(bare.dispose);
      await bare.read(sharedPreferencesProvider.future);
      final r = RestoreRefresher(
        container: bare,
        fetchProfile: (_) async {},
        activeProfileId: () => 'c',
      );
      final plan2 = h.engine.prepare(_backup(ids: ['c'], active: 'c'));
      await (await r.restore(h.engine, plan2)).backfill;
      await r.backfill(['c']);
      expect(bare.exists(connectionControllerProvider), isFalse);
    });

    test('补拉到激活订阅后的重连走控制器 applyConfig（默认接线）', () async {
      await setUpWith(['a'], active: 'a');
      await connected();
      final base = requests().length;

      // 只测补拉之后的那一步：激活订阅就是补拉的那条。
      final r = RestoreRefresher(
        container: container,
        fetchProfile: (_) async {},
        activeProfileId: () => 'a',
      );
      await r.backfill(['a']);
      await until(() => requests().length > base, '重新应用');

      final sent = requests().sublist(base);
      expect(sent.single.desired, Desired.on);
      expect(sent.single.reason, RequestReason.applyConfig);
    });
  });
}
