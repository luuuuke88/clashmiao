import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/profile_harness.dart';

void main() {
  test('任何入口写入订阅后，列表与激活订阅 provider 自动刷新（监听 ProfileStore.changes）', () async {
    final h = await ProfileHarness.create();
    addTearDown(h.dispose);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((_) async => h.repo)],
    );
    addTearDown(container.dispose);

    expect(await container.read(profileListProvider.future), isEmpty);
    expect(await container.read(activeProfileProvider.future), isNull);

    // 不经过任何 UI 的 invalidate：直接走仓库（深链 / 定时刷新 / 备份恢复都是这样）。
    final a = await h.repo.addByContent('ss://a@h:1#a', name: 'A');
    await pumpEventQueue();

    final list = await container.read(profileListProvider.future);
    expect(list.map((e) => e.id), [a.id]);
    expect((await container.read(activeProfileProvider.future))?.id, a.id);

    final b = await h.repo.addByContent('ss://b@h:1#b', name: 'B');
    await h.repo.setActive(b.id);
    await pumpEventQueue();
    expect((await container.read(activeProfileProvider.future))?.id, b.id);

    await h.repo.delete(b.id);
    await pumpEventQueue();
    expect(
      (await container.read(profileListProvider.future)).map((e) => e.id),
      [a.id],
    );
    expect((await container.read(activeProfileProvider.future))?.id, a.id);
  });

  test('provider 释放后不再监听，之后的提交不会报错', () async {
    final h = await ProfileHarness.create();
    addTearDown(h.dispose);
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((_) async => h.repo)],
    );
    await container.read(profileListProvider.future);
    container.dispose();

    await h.repo.addByContent('ss://a@h:1#a', name: 'A');
    await pumpEventQueue();
  });
}
