import 'dart:async';

import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../support/profile_harness.dart';

/// 同步读取（`read` / `view`，以及依赖它们的 provider）只能看到「最后一次成功
/// 提交」的快照。
///
/// `SharedPreferences.setString` 先改内存缓存、后返回磁盘结果：如果读取直接看偏好，
/// 提交进行中读到的就是未提交的数据。提交最终失败时 Store 会回滚但**不广播**，
/// 在这段窗口里建好（或重建）的 provider 就会永远缓存一份已被回滚的列表。
void main() {
  late ProfileHarness h;
  late ProviderContainer container;

  setUp(() async {
    h = await ProfileHarness.create(flaky: true);
    container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWith((_) async => h.repo)],
    );
  });

  tearDown(() async {
    container.dispose();
    await h.dispose();
  });

  /// 让下一次列表键的写入「内存已改、结果未回」，直到 [release] 被完成。
  ({Future<void> reached, Completer<void> release}) gateListWrite() {
    final reached = Completer<void>();
    final release = Completer<void>();
    h.flaky!.afterWrite = (key) async {
      if (key != ProfileStore.profilesKey) return;
      if (!reached.isCompleted) reached.complete();
      await release.future;
    };
    return (reached: reached.future, release: release);
  }

  test('提交最终失败：窗口内同步读取与 provider 都只看到旧快照，回滚后也不留未提交数据', () async {
    final a = await h.repo.addByContent('ss://a@h:1#a', name: 'A');
    final gate = gateListWrite();
    h.flaky!
      ..failKeys = {ProfileStore.profilesKey}
      ..failuresLeft = 1;

    final pending = h.repo.addByContent('ss://b@h:1#b', name: 'B');
    final failed = expectLater(
      pending,
      throwsA(isA<ProfileStorageException>()),
    );
    await gate.reached;

    // 证明窗口真实存在：偏好的内存缓存里此刻已经是未提交的新列表。
    expect(h.rawList, contains('"B"'), reason: '偏好缓存里已经有未提交的 B');
    // 窗口内的同步读取：只有已提交的 A。
    expect(h.repo.getAll().map((e) => e.id), [a.id]);
    expect(h.store.readActiveId(), a.id);
    expect(h.store.exists(a.id), isTrue);
    // provider 恰好在窗口内首次构建：同样只能看到 A。
    final during = await container.read(profileListProvider.future);
    expect(during.map((e) => e.id), [a.id]);

    gate.release.complete();
    await failed;
    await pumpEventQueue();

    expect(h.repo.getAll().map((e) => e.id), [a.id]);
    final after = await container.read(profileListProvider.future);
    expect(after.map((e) => e.id), [
      a.id,
    ], reason: '失败的提交不广播，provider 不能留着窗口内读到的未提交数据');
    expect(h.strayFiles(), isEmpty);
  });

  test('提交成功：窗口内仍是旧快照；成功后新数据可见，已建好的 provider 随广播更新', () async {
    final a = await h.repo.addByContent('ss://a@h:1#a', name: 'A');
    expect((await container.read(profileListProvider.future)).length, 1);
    final gate = gateListWrite();

    final pending = h.repo.addByContent('ss://b@h:1#b', name: 'B');
    await gate.reached;
    expect(h.repo.getAll().map((e) => e.id), [a.id], reason: '尚未成功，读到旧快照');

    gate.release.complete();
    final b = await pending;
    await pumpEventQueue();

    expect(h.repo.getAll().map((e) => e.id), [a.id, b.id]);
    final after = await container.read(profileListProvider.future);
    expect(after.map((e) => e.id), [a.id, b.id]);
  });

  test('激活键写入失败的窗口里，列表与激活 id 同样保持提交前的一致视图', () async {
    final a = await h.repo.addByContent('ss://a@h:1#a', name: 'A');
    final b = await h.repo.addByContent('ss://b@h:1#b', name: 'B');
    final reached = Completer<void>();
    final release = Completer<void>();
    h.flaky!
      ..afterWrite = (key) async {
        if (key != ProfileStore.activeProfileKey) return;
        if (!reached.isCompleted) reached.complete();
        await release.future;
      }
      ..failKeys = {ProfileStore.activeProfileKey}
      ..failuresLeft = 1;

    final pending = h.repo.delete(a.id); // 删激活项：列表与激活键都要改
    final failed = expectLater(
      pending,
      throwsA(isA<ProfileStorageException>()),
    );
    await reached.future;

    expect(h.repo.getAll().map((e) => e.id), [a.id, b.id]);
    expect(h.store.readActiveId(), a.id, reason: '不能出现「列表已删 A、激活仍指 A」的半成品视图');

    release.complete();
    await failed;
    expect(h.repo.getAll().map((e) => e.id), [a.id, b.id]);
    expect(h.store.readActiveId(), a.id);
  });
}
