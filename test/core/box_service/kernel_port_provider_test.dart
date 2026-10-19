import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/emulated_kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/platform_kernel_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../_fakes/fake_kernel_port.dart';
import '../../support/fake_box_service.dart';

void main() {
  test(
    'Android 之外用 EmulatedKernelPort 包装 boxServiceProvider；Android 用 PlatformKernelPort',
    () {
      final container = ProviderContainer(
        overrides: [
          boxServiceProvider.overrideWithValue(const FakeBoxService()),
        ],
      );
      addTearDown(container.dispose);
      final port = container.read(kernelPortProvider);
      expect(port, isA<KernelPort>());
      if (Platform.isAndroid) {
        expect(port, isA<PlatformKernelPort>());
      } else {
        expect(port, isA<EmulatedKernelPort>());
      }
      expect(container.read(kernelPortProvider), same(port), reason: '单例');
    },
  );

  test('FakeKernelPort：可编程推送、记录请求、可配置回执与 select 结果', () async {
    final fake = FakeKernelPort(initial: FakeKernelPort.snap());
    addTearDown(fake.dispose);
    final seen = <KernelSnapshot>[];
    final sub = fake.watch().listen(seen.add);
    await pumpEventQueue();
    fake.push(FakeKernelPort.snap(version: 2, status: KernelStatus.started));
    await pumpEventQueue();
    expect(seen.map((s) => s.version), [1, 2]);
    expect((await fake.current()).version, 2);

    fake.receiptFor = (r) => RequestReceipt(
      accepted: false,
      reason: RequestRejection.stale,
      epoch: r.epoch,
      appliedSeq: 9,
    );
    final receipt = await fake.request(
      DesiredRequest(
        epoch: 'e1',
        seq: 1,
        desired: Desired.off,
        reason: RequestReason.userDisconnect,
      ),
    );
    expect(receipt.reason, RequestRejection.stale);
    expect(fake.requests.single.seq, 1);

    fake.selectResult = (_, _, _) => const SelectStale();
    expect(
      await fake.selectOutbound('g', 't', expectedAttempt: 1),
      isA<SelectStale>(),
    );
    expect(fake.selectCalls.single.expectedAttempt, 1);
    await fake.acknowledgeReplay(3);
    expect(fake.acknowledged, [3]);
    await sub.cancel();
  });

  group('FakeKernelPort 首值原子回放', () {
    test('首值回调里立即 push：后推的快照不丢', () async {
      final fake = FakeKernelPort(initial: FakeKernelPort.snap(version: 1));
      addTearDown(fake.dispose);
      final seen = <int>[];
      final sub = fake.watch().listen((s) {
        seen.add(s.version);
        if (s.version == 1) fake.push(FakeKernelPort.snap(version: 2));
      });
      await pumpEventQueue();
      expect(seen, [1, 2]);
      await sub.cancel();
    });

    test('首值回调里立即 pushLink：后推的链路状态不丢', () async {
      final fake = FakeKernelPort();
      addTearDown(fake.dispose);
      final seen = <KernelLink>[];
      final sub = fake.watchLink().listen((l) {
        seen.add(l);
        if (l == KernelLink.connected) fake.pushLink(KernelLink.lost);
      });
      await pumpEventQueue();
      expect(seen, [KernelLink.connected, KernelLink.lost]);
      expect(fake.link, KernelLink.lost);
      await sub.cancel();
    });

    test('首值回调里发 request，onRequest 同步 push 的快照不丢', () async {
      final fake = FakeKernelPort(initial: FakeKernelPort.snap(version: 1));
      addTearDown(fake.dispose);
      fake.onRequest = (r) => fake.push(
        FakeKernelPort.snap(
          version: 2,
          appliedSeq: r.seq,
          desired: Desired.off,
          source: DesiredSource.app,
        ),
      );
      final seen = <KernelSnapshot>[];
      final sub = fake.watch().listen((s) {
        seen.add(s);
        if (s.version == 1) {
          unawaited(
            fake.request(
              DesiredRequest(
                epoch: 'e1',
                seq: 3,
                desired: Desired.off,
                reason: RequestReason.userDisconnect,
              ),
            ),
          );
        }
      });
      await pumpEventQueue();
      expect(seen.map((s) => s.version), [1, 2]);
      expect(seen.last.appliedSeq, 3);
      await sub.cancel();
    });

    test('push 先于订阅：新订阅者首值是最新快照', () async {
      final fake = FakeKernelPort();
      addTearDown(fake.dispose);
      fake.push(FakeKernelPort.snap(version: 5));
      final seen = <int>[];
      final sub = fake.watch().listen((s) => seen.add(s.version));
      await pumpEventQueue();
      expect(seen, [5]);
      expect((await fake.current()).version, 5);
      await sub.cancel();
    });
  });
}
