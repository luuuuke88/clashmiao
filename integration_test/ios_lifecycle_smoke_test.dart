import 'dart:io';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/directories.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:clashmiao/features/home/presentation/connection_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '_fixtures/subscription_source.dart';
import '_fixtures/test_helpers.dart';

/// iOS 真机冒烟：导入订阅 → 连接 → 出口 IP 变化 → 健康探测 → 延迟列表 → 切节点（含 stale）→
/// 断开 → 再连接。每一步打 `[e2e]` 日志，并把内核快照的 epoch/attempt/desired/source 序列打出来。
///
/// 订阅地址走 `--dart-define-from-file`（`CLASHMIAO_TEST_SUB_URL`），不会进日志。
/// `CLASHMIAO_SMOKE_LEAVE_CONNECTED=true` 时结束时保持连接，供「杀进程重开后挂接」的人工 / 脚本验证。
const _leaveConnected = bool.fromEnvironment('CLASHMIAO_SMOKE_LEAVE_CONNECTED');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS lifecycle smoke', (tester) async {
    if (!Platform.isIOS) {
      markTestSkipped('iOS-only E2E');
      return;
    }

    final url = await SubscriptionSource.resolve();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final boxService = container.read(boxServiceProvider);
    expect(boxService is StubBoxService, isFalse);
    await _step('boxService.init', () => boxService.init());
    final workingDir = await resolveSingBoxWorkingDirectory();
    final tempDir = await getTemporaryDirectory();
    await _step(
      'boxService.setup',
      () => boxService.setup(
        AppDirectories(
          baseDir: workingDir,
          workingDir: workingDir,
          tempDir: tempDir,
        ),
        debug: true,
      ),
    );

    final port = container.read(kernelPortProvider);
    final snapshots = <KernelSnapshot>[];
    final sub = port.watch().listen((s) {
      snapshots.add(s);
      debugPrint(
        '[e2e] snapshot v${s.version} ${s.status.name} attempt=${s.attempt} '
        'desired=${s.desired.name} source=${s.source.name} '
        'rev=${s.activeConfigRevision} replay=${s.selectionsReplayNeeded} '
        'failure=${s.lastFailure?.code.name}',
      );
    });
    addTearDown(sub.cancel);

    final repo = await _step(
      'profileRepositoryProvider',
      () => container.read(profileRepositoryProvider.future),
    );
    if (repo.getAll().isEmpty) {
      await _step(
        'repo.addByUrl',
        () => repo.addByUrl(url, customName: 'e2e-test'),
        timeout: const Duration(seconds: 75),
      );
    }
    final prefs = container.read(sharedPreferencesProvider).requireValue;
    await prefs.setBool('onboarding_done', true);
    await container.read(proxyModeProvider.notifier).updateMode(1);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ClashMiaoApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final baselineIp = await _step('baseline IP', fetchEgressIp);
    debugPrint('[e2e] baseline IP fetched');

    final connectFinder = find.byType(ConnectionButton);
    await _waitForFinder(tester, connectFinder);

    // ── 第一轮：连接 ─────────────────────────────────────────
    debugPrint('[e2e] tap connect');
    await tester.tap(connectFinder);
    await tester.pump();
    await waitForPhase(
      tester,
      container,
      ConnectionPhase.connected,
      timeout: const Duration(seconds: 120),
      onTimeout: (f) => debugPrint('[e2e] connection failure: $f'),
    );
    debugPrint('[e2e] connected');

    var connectedSnap = await port.current();
    expect(connectedSnap.status, KernelStatus.started);
    expect(connectedSnap.desired, Desired.on);
    expect(connectedSnap.source, DesiredSource.app);
    expect(connectedSnap.lastFailure, isNull);
    expect(connectedSnap.activeConfigRevision, isNotNull);
    expect(connectedSnap.retainedConfigPaths, isNotNull);

    // 出口 IP 变化
    var proxiedIp = baselineIp;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 4));
      try {
        proxiedIp = await fetchEgressIp(timeout: const Duration(seconds: 8));
        if (proxiedIp != baselineIp) break;
      } catch (_) {}
    }
    expect(proxiedIp, isNot(equals(baselineIp)), reason: '出口 IP 应当改变');
    debugPrint('[e2e] egress IP changed');

    // 健康探测：经 tun 直连 204
    final health = container.read(connectionHealthProvider.notifier)..start();
    await tester.pump(const Duration(seconds: 1));
    await health.probeNow();
    await _waitUntil(
      tester,
      () =>
          container.read(connectionHealthProvider) == ConnectionHealth.healthy,
      timeout: const Duration(seconds: 40),
      what: 'health=healthy',
    );
    debugPrint('[e2e] health healthy');

    // 延迟列表
    final groups = await _step(
      'groups',
      () => boxService
          .watchGroups()
          .firstWhere((g) => g.any((x) => x.items.length > 1))
          .timeout(const Duration(seconds: 30)),
    );
    final group = groups.firstWhere(
      (g) => g.type == 'selector' && g.items.length > 1,
    );
    await boxService.urlTest(group.tag);
    final tested = await _step(
      'latency list',
      () => boxService
          .watchGroups()
          .map((gs) => gs.firstWhere((g) => g.tag == group.tag))
          .firstWhere((g) => g.items.where((p) => p.delay > 0).length >= 2)
          .timeout(const Duration(seconds: 45)),
      timeout: const Duration(seconds: 50),
    );
    debugPrint(
      '[e2e] latency list: ${tested.items.where((p) => p.delay > 0).length}'
      '/${tested.items.length} nodes responded',
    );

    // 切节点：当前 attempt 成功；过期 attempt 返回 stale 且不写入
    final candidates = tested.items
        .where((OutboundProxy p) => p.delay > 0 && p.tag != tested.selected)
        .toList();
    expect(candidates, isNotEmpty);
    final target = candidates.first;
    connectedSnap = await port.current();
    final ok = await port.selectOutbound(
      group.tag,
      target.tag,
      expectedAttempt: connectedSnap.attempt,
    );
    expect(ok, isA<SelectOk>(), reason: '$ok');
    await _waitUntil(
      tester,
      () => true,
      timeout: const Duration(seconds: 1),
      what: 'settle',
    );
    final switched = await boxService
        .watchGroups()
        .map((gs) => gs.firstWhere((g) => g.tag == group.tag))
        .firstWhere((g) => g.selected == target.tag)
        .timeout(const Duration(seconds: 20));
    expect(switched.selected, target.tag);
    debugPrint('[e2e] node switched');
    final stale = await port.selectOutbound(
      group.tag,
      tested.selected,
      expectedAttempt: connectedSnap.attempt + 99,
    );
    expect(stale, isA<SelectStale>());
    final afterStale = await boxService
        .watchGroups()
        .map((gs) => gs.firstWhere((g) => g.tag == group.tag))
        .first
        .timeout(const Duration(seconds: 10));
    expect(afterStale.selected, target.tag, reason: 'stale 的手选不得写入');
    debugPrint('[e2e] stale select rejected without writing');

    final ipAfterSwitch = await fetchEgressIp(
      timeout: const Duration(seconds: 12),
    );
    expect(ipAfterSwitch, isNotEmpty);

    // ── 断开 ─────────────────────────────────────────────
    debugPrint('[e2e] tap disconnect');
    await tester.tap(connectFinder);
    await tester.pump();
    await waitForPhase(
      tester,
      container,
      ConnectionPhase.disconnected,
      timeout: const Duration(seconds: 60),
      onTimeout: (f) => debugPrint('[e2e] disconnect failure: $f'),
    );
    final stoppedSnap = await port.current();
    expect(stoppedSnap.status, KernelStatus.stopped);
    expect(stoppedSnap.desired, Desired.off);
    debugPrint('[e2e] disconnected');

    // ── 第二轮：再连接（验证重复生命周期，attempt 递增）─────────
    await tester.tap(connectFinder);
    await tester.pump();
    await waitForPhase(
      tester,
      container,
      ConnectionPhase.connected,
      timeout: const Duration(seconds: 120),
      onTimeout: (f) => debugPrint('[e2e] reconnect failure: $f'),
    );
    final again = await port.current();
    expect(again.attempt, greaterThan(connectedSnap.attempt));
    debugPrint('[e2e] reconnected attempt=${again.attempt}');

    if (!_leaveConnected) {
      await tester.tap(connectFinder);
      await tester.pump();
      await waitForPhase(
        tester,
        container,
        ConnectionPhase.disconnected,
        timeout: const Duration(seconds: 60),
      );
      debugPrint('[e2e] final disconnect');
    } else {
      debugPrint('[e2e] leaving tunnel connected for relaunch check');
    }
    debugPrint('[e2e] snapshot sequence length=${snapshots.length}');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

Future<T> _step<T>(
  String name,
  Future<T> Function() action, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  debugPrint('[e2e] START $name');
  try {
    final result = await action().timeout(timeout);
    debugPrint('[e2e] DONE $name');
    return result;
  } catch (error, stackTrace) {
    debugPrint('[e2e] FAIL $name: $error\n$stackTrace');
    rethrow;
  }
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().length == 1) return;
  }
  expect(finder, findsOneWidget);
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (condition()) return;
  }
  fail('timeout waiting for $what');
}
