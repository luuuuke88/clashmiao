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
}
