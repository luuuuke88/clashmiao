import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/temp_dirs.dart';

/// 自愈刷新行为可编程的仓库：`onUpdate` 在 `update()` 里执行，
/// 用来模拟「刷新成功写出配置 / 抛 stale / 刷新期间激活订阅被改掉」。
class _HealRepo extends ProfileRepository {
  _HealRepo({
    required super.dio,
    required super.configDir,
    required super.prefs,
    required super.boxService,
  });

  Future<void> Function(String id)? onUpdate;
  final List<String> updated = [];

  @override
  Future<ProfileEntity> update(String profileId) async {
    updated.add(profileId);
    await onUpdate?.call(profileId);
    return getAll().firstWhere((p) => p.id == profileId);
  }
}

const _config = {
  'outbounds': [
    {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory workDir;
  late SharedPreferences prefs;
  late _HealRepo repo;
  late ProviderContainer container;
  var tokenN = 0;

  Future<void> writeConfig(String id, [Object? json]) async {
    final f = File(repo.configFilePath(id));
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(json ?? _config));
  }

  Future<void> addProfile(String id, {String? name, bool config = true}) async {
    await repo.upsert({
      'id': id,
      'name': name ?? 'profile-$id',
      'url': 'https://example.invalid/$id',
    });
    if (config) await writeConfig(id);
  }

  ConnectionLauncher launcher() => ConnectionLauncher(
    container.read(_refProvider),
    workingDirectory: () async => workDir,
    tokenGenerator: () => 't${tokenN++}',
  );

  setUp(() async {
    tokenN = 0;
    tmp = await Directory.systemTemp.createTemp('launcher_test_');
    workDir = Directory('${tmp.path}/work')..createSync();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = _HealRepo(
      dio: Dio(),
      configDir: Directory('${tmp.path}/profiles'),
      prefs: prefs,
      boxService: const StubBoxService(),
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(
          const StubBoxService(reason: StubReason.unsupported),
        ),
        profileRepositoryProvider.overrideWith((_) async => repo),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await deleteTempDirBestEffort(tmp);
  });

  group('FNV-1a 64', () {
    test('标准测试向量', () {
      expect(fnv1a64(const []), 0xcbf29ce484222325);
      expect(fnv1a64(utf8.encode('a')), 0xaf63dc4c8601ec8c);
      expect(fnv1a64(utf8.encode('foobar')), 0x85944171f73967e8);
    });

    test('computeConfigRevision：稳定、非负、对 options 与内容都敏感', () {
      final a = computeConfigRevision('{"a":1}', utf8.encode('cfg'));
      expect(computeConfigRevision('{"a":1}', utf8.encode('cfg')), a);
      expect(a, isNonNegative);
      expect(computeConfigRevision('{"a":2}', utf8.encode('cfg')), isNot(a));
      expect(computeConfigRevision('{"a":1}', utf8.encode('cfg2')), isNot(a));
      // 分隔符：把边界从 options 挪到内容里必须得到不同 revision。
      expect(computeConfigRevision('{"a":1}c', utf8.encode('fg')), isNot(a));
    });
  });

  group('prepare：每请求独立的启动产物', () {
    test('写 prep 文件 + 内联 options + profileName + revision', () async {
      await addProfile('p1', name: '香港节点');
      await repo.setActive('p1');

      final spec = await launcher().prepare(1);

      expect(spec.profileName, '香港节点');
      expect(
        spec.runtimeConfigPath,
        '${workDir.path}/runtime-config-prep-t0.json',
      );
      expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
      final options = jsonDecode(spec.optionsJson) as Map<String, dynamic>;
      expect(options, isNotEmpty);
      expect(spec.configRevision, isNonNegative);
      // 老的单一文件名不再被写出：每个请求一份。
      expect(File('${workDir.path}/runtime-config.json').existsSync(), isFalse);
    });

    test('相同输入 → 相同 revision（不触发重载）；两次准备用不同 prep 文件', () async {
      await addProfile('p1');
      await repo.setActive('p1');
      final l = launcher();

      final a = await l.prepare(1);
      final b = await l.prepare(2);

      expect(b.configRevision, a.configRevision);
      expect(b.runtimeConfigPath, isNot(a.runtimeConfigPath));
    });

    test('模式 / 网络设置 / 订阅内容变化 → revision 变化', () async {
      await addProfile('p1');
      await repo.setActive('p1');
      final l = launcher();
      final base = (await l.prepare(1)).configRevision;

      await container.read(proxyModeProvider.notifier).updateMode(0);
      final global = (await l.prepare(2)).configRevision;
      expect(global, isNot(base), reason: '智能 → 全局：options 的 rules 变了');

      await container.read(proxyModeProvider.notifier).updateMode(1);
      expect(
        (await l.prepare(3)).configRevision,
        base,
        reason: '改回去 → 同一个 revision',
      );

      final notifier = container.read(networkSettingsProvider.notifier);
      final oldPort = container.read(networkSettingsProvider).mixedPort;
      await notifier.setMixedPort(oldPort + 1);
      final port = (await l.prepare(4)).configRevision;
      expect(port, isNot(base));
      await notifier.setMixedPort(oldPort);

      await writeConfig('p1', {
        'outbounds': [
          {'type': 'direct', 'tag': 'direct'},
        ],
      });
      expect((await l.prepare(5)).configRevision, isNot(base));
    });

    test('无激活订阅 → NoActiveProfile', () async {
      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const NoActiveProfile(),
          ),
        ),
      );
    });

    test('桌面核心库缺失 → CoreUnavailable，且不写任何文件', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(
            const StubBoxService(reason: StubReason.coreLoadFailed),
          ),
          profileRepositoryProvider.overrideWith((_) async => repo),
        ],
      );
      await container.read(sharedPreferencesProvider.future);
      await addProfile('p1');
      await repo.setActive('p1');

      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const CoreUnavailable(),
          ),
        ),
      );
      expect(workDir.listSync(), isEmpty);
    });

    test('仓库读取抛异常 → UnexpectedFailure（不是未捕获异常）', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(
            const StubBoxService(reason: StubReason.unsupported),
          ),
          profileRepositoryProvider.overrideWith(
            (_) async => _ThrowingRepo(
              dio: Dio(),
              configDir: Directory('${tmp.path}/profiles'),
              prefs: prefs,
              boxService: const StubBoxService(),
            ),
          ),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            isA<UnexpectedFailure>(),
          ),
        ),
      );
    });
  });

  group('配置缺失 → 自愈刷新 → 重读当前激活订阅', () {
    setUp(() async {
      await addProfile('p1', config: false);
      await repo.setActive('p1');
    });

    test('刷新成功写出配置 → 继续', () async {
      repo.onUpdate = (id) => writeConfig(id);

      final spec = await launcher().prepare(1);

      expect(repo.updated, ['p1']);
      expect(spec.profileName, 'profile-p1');
    });

    test('刷新抛出（stale / 取消 / 失败一视同仁），但配置已被别处写好 → 继续', () async {
      repo.onUpdate = (id) async {
        await writeConfig(id);
        throw StateError('stale');
      };

      final spec = await launcher().prepare(1);

      expect(spec.profileName, 'profile-p1');
    });

    test('刷新抛出且配置仍缺失 → ConfigMissing', () async {
      repo.onUpdate = (_) async => throw StateError('network down');

      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const ConfigMissing(),
          ),
        ),
      );
    });

    test('刷新期间激活订阅被切换（旧订阅仍缺失、新订阅有配置）→ 用新订阅，不报缺失', () async {
      await addProfile('p2', name: '新订阅');
      repo.onUpdate = (_) async {
        await repo.setActive('p2'); // 并发编辑：旧 id 作废
        throw StateError('stale');
      };

      final spec = await launcher().prepare(1);

      expect(spec.profileName, '新订阅', reason: '必须重读当前激活订阅，不能复用刷新前的 id 与路径');
    });

    test('刷新期间激活订阅被删除 → NoActiveProfile（不是「配置不存在」）', () async {
      repo.onUpdate = (_) async {
        await prefs.remove('clashmiao_active_profile');
      };

      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const NoActiveProfile(),
          ),
        ),
      );
    });

    test('空配置文件按缺失处理（同样先自愈）', () async {
      await File(repo.configFilePath('p1')).parent.create(recursive: true);
      await File(repo.configFilePath('p1')).writeAsString('');
      repo.onUpdate = (id) => writeConfig(id);

      await launcher().prepare(1);

      expect(repo.updated, ['p1']);
    });

    test('配置本来就在 → 不刷新', () async {
      await writeConfig('p1');

      await launcher().prepare(1);

      expect(repo.updated, isEmpty);
    });
  });

  group('bindSeq / discard / accepted：文件生命周期', () {
    late ConnectionLauncher l;
    setUp(() async {
      await addProfile('p1');
      await repo.setActive('p1');
      l = launcher();
    });

    test('bindSeq 把 prep 改名为 runtime-config-<seq>.json，内容不变', () async {
      final spec = await l.prepare(1);
      final prepBytes = File(spec.runtimeConfigPath).readAsBytesSync();

      final bound = await l.bindSeq(1, spec, 7);

      expect(bound.runtimeConfigPath, '${workDir.path}/runtime-config-7.json');
      expect(File(spec.runtimeConfigPath).existsSync(), isFalse);
      expect(File(bound.runtimeConfigPath).readAsBytesSync(), prepBytes);
      expect(bound.optionsJson, spec.optionsJson);
      expect(bound.configRevision, spec.configRevision);
    });

    test('被 stale / wrongEpoch 拒绝后以新 seq 重发：文件跟着改名', () async {
      final spec = await l.prepare(1);
      await l.bindSeq(1, spec, 7);

      final again = await l.bindSeq(1, spec, 9);

      expect(again.runtimeConfigPath, '${workDir.path}/runtime-config-9.json');
      expect(
        File('${workDir.path}/runtime-config-7.json').existsSync(),
        isFalse,
      );
      expect(File(again.runtimeConfigPath).existsSync(), isTrue);
      // 同一 seq 重复绑定是空操作。
      final same = await l.bindSeq(1, spec, 9);
      expect(same.runtimeConfigPath, again.runtimeConfigPath);
    });

    test('discard 删除未使用的 prep 文件', () async {
      final a = await l.prepare(1);
      await l.discard(1);
      expect(File(a.runtimeConfigPath).existsSync(), isFalse);
    });

    test('discard 不删已绑定 seq 的文件：请求可能已交给协调器，它随时会读', () async {
      final b = await l.prepare(2);
      final bound = await l.bindSeq(2, b, 3);
      await l.discard(2);
      expect(File(bound.runtimeConfigPath).existsSync(), isTrue);
    });
  });

  // 清理规则：拿不准就留；只有「更新的 spec 已确认运行」之后才释放旧文件。
  group('清理：保护运行中 / 执行中 / 持久化引用的文件', () {
    late ConnectionLauncher l;
    setUp(() async {
      await addProfile('p1');
      await repo.setActive('p1');
      l = launcher();
      // 控制器发送任何请求之前一定已经收到过首个快照：这是发送元数据（绑定
      // seq 时内核的 attempt）的来源。没有它，launcher 只会保守地保留文件。
      await l.observe(
        FakeKernelPort.snap(
          status: KernelStatus.stopped,
          attempt: 0,
          appliedSeq: 0,
        ),
      );
    });

    KernelSnapshot kernel({
      required int appliedSeq,
      required int attempt,
      required int? revision,
      KernelStatus status = KernelStatus.started,
      String epoch = 'e1',
    }) => FakeKernelPort.snap(
      epoch: epoch,
      status: status,
      attempt: attempt,
      desired: status == KernelStatus.stopped ? Desired.off : Desired.on,
      source: DesiredSource.app,
      appliedSeq: appliedSeq,
      activeConfigRevision: revision,
    );

    /// 准备 + 绑定 + 受理；revision 由测试指定（真实 revision 取决于内容）。
    Future<LaunchSpec> accept(
      int id,
      int seq, {
      required int revision,
      String epoch = 'e1',
    }) async {
      final bound = await l.bindSeq(id, await l.prepare(id), seq);
      final spec = LaunchSpec(
        runtimeConfigPath: bound.runtimeConfigPath,
        optionsJson: bound.optionsJson,
        profileName: bound.profileName,
        configRevision: revision,
      );
      await l.accepted(id, spec, epoch: epoch, seq: seq);
      return spec;
    }

    bool exists(LaunchSpec s) => File(s.runtimeConfigPath).existsSync();

    test('运行中的 spec：之后相同 revision 的请求（内核不重启）受理再多次也不删它；被无操作合并的中间产物回收', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));

      // 相同 revision 的 on：协调器无操作，attempt 不变。
      final s2 = await accept(2, 2, revision: 7);
      await l.observe(kernel(appliedSeq: 2, attempt: 1, revision: 7));
      expect(exists(s2), isTrue, reason: '它此刻是最新一份已处理的（持久化引用）');
      final s3 = await accept(3, 3, revision: 7);
      await l.observe(kernel(appliedSeq: 3, attempt: 1, revision: 7));

      expect(exists(s1), isTrue, reason: 'seq1 启动了运行中的实例，绝不能删');
      expect(exists(s2), isFalse, reason: '被无操作合并、且已被更新的请求取代：证明无引用，回收');
      expect(exists(s3), isTrue, reason: '最新一份');
    });

    test('新实例确认运行（revision 变了且 attempt 增长）之后，被替换的旧文件才释放', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      final s2 = await accept(2, 2, revision: 7);
      await l.observe(kernel(appliedSeq: 2, attempt: 1, revision: 7));

      // 新配置：受理了但内核还没把它跑起来。
      final s3 = await accept(3, 3, revision: 8);
      await l.observe(kernel(appliedSeq: 3, attempt: 1, revision: 7));
      expect(exists(s1), isTrue, reason: '运行中的，替换尚未确认');
      expect(exists(s2), isFalse, reason: '无操作合并的中间产物已回收');
      expect(exists(s3), isTrue);

      await l.observe(kernel(appliedSeq: 3, attempt: 2, revision: 8));

      expect(exists(s1), isFalse, reason: '新实例已在运行，旧文件释放');
      expect(exists(s3), isTrue, reason: '运行中');
    });

    test('尚未被协调器处理的（seq > appliedSeq）：不删', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      // seq2 已受理、仍在执行：快照里 appliedSeq 还停在 1。
      final s2 = await accept(2, 2, revision: 8);
      // 再来一份（seq3，同样没被处理）：两份都在执行中。
      final s3 = await accept(3, 3, revision: 9);
      expect(exists(s1), isTrue);
      expect(exists(s2), isTrue, reason: '仍在执行');
      expect(exists(s3), isTrue, reason: '仍在执行');
    });

    test('还没有任何内核快照（不确定）：什么都不删', () async {
      l = launcher(); // 新的 launcher：没有观察过任何快照
      final s1 = await accept(1, 1, revision: 7);
      final s2 = await accept(2, 2, revision: 8);
      final s3 = await accept(3, 3, revision: 9);
      expect(exists(s1), isTrue);
      expect(exists(s2), isTrue);
      expect(exists(s3), isTrue);
    });

    test('持久化引用：最新一份已处理的 spec 即使内核已停止也保留', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      final s2 = await accept(2, 2, revision: 8);
      await l.observe(kernel(appliedSeq: 2, attempt: 2, revision: 8));
      expect(exists(s1), isFalse);

      // 用户断开：内核停止；最新的 on spec 仍是持久化引用。
      await l.observe(
        kernel(
          appliedSeq: 3,
          attempt: 2,
          revision: null,
          status: KernelStatus.stopped,
        ),
      );
      expect(exists(s2), isTrue);
    });

    test('在途（回执未到）的已绑定文件：清理不得删除，即使别的 spec 已确认运行', () async {
      // 意图 5 已绑定 seq 并发给协调器，回执还在路上（Completer 悬停）。
      final receipt = Completer<void>();
      final inflightSpec = await l.bindSeq(5, await l.prepare(5), 5);

      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      final s2 = await accept(2, 2, revision: 8);
      await l.observe(kernel(appliedSeq: 2, attempt: 2, revision: 8));
      expect(exists(s1), isFalse, reason: '前提：清理确实发生了');
      expect(
        File(inflightSpec.runtimeConfigPath).existsSync(),
        isTrue,
        reason: '回执悬停期间，在途文件不能被清理',
      );

      // 回执到达：受理它。
      receipt.complete();
      await receipt.future;
      await l.accepted(5, inflightSpec, epoch: 'e1', seq: 5);
      expect(File(inflightSpec.runtimeConfigPath).existsSync(), isTrue);
      expect(exists(s2), isTrue);
    });

    test('没有记录引用的 seq 文件：最新两份与宽限期内的保留；其余超过宽限即删；确认运行后旧的也删', () async {
      File mk(int n, Duration age) =>
          File('${workDir.path}/runtime-config-$n.json')
            ..writeAsStringSync('{}')
            ..setLastModifiedSync(DateTime.now().subtract(age));
      final veryOld = mk(97, const Duration(hours: 5));
      final old = mk(99, const Duration(hours: 2));
      final fresh = mk(98, Duration.zero);

      final s1 = await accept(1, 1, revision: 7);
      expect(veryOld.existsSync(), isFalse, reason: '不在最新两份里，且早已过了宽限');
      expect(old.existsSync(), isTrue, reason: '最新两份之一：可能是运行中 / 持久化的那份，先留');
      expect(fresh.existsSync(), isTrue);

      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      expect(old.existsSync(), isFalse, reason: '新 spec 已确认运行，过了宽限的遗留文件释放');
      expect(fresh.existsSync(), isTrue, reason: '刚写的可能还在去协调器的路上（宽限期内）');
      expect(exists(s1), isTrue);
    });

    test('发送元数据在意图终结（discard）后仍保留：快照先于回执时 runtime-1 不被误删', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));

      // 相同 revision 的请求：绑定 seq 发送；快照先到、控制器终结意图并 discard，
      // 回执最后才到。
      final spec = await l.bindSeq(2, await l.prepare(2), 2);
      await l.observe(kernel(appliedSeq: 2, attempt: 1, revision: 7));
      await l.discard(2);
      await l.accepted(
        2,
        LaunchSpec(
          runtimeConfigPath: spec.runtimeConfigPath,
          optionsJson: spec.optionsJson,
          profileName: spec.profileName,
          configRevision: 7,
        ),
        epoch: 'e1',
        seq: 2,
      );
      l.sendFinished(2);

      expect(exists(s1), isTrue, reason: 'runtime-1 仍是运行中实例的 spec');
      expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
    });

    test('发送元数据缺失 = 无法确认：绝不据此推断新启动，旧文件一律保留', () async {
      final s1 = await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));

      final spec = await l.bindSeq(2, await l.prepare(2), 2);
      l.sendFinished(2); // 元数据已被丢弃（模拟缺失）
      await l.accepted(
        2,
        LaunchSpec(
          runtimeConfigPath: spec.runtimeConfigPath,
          optionsJson: spec.optionsJson,
          profileName: spec.profileName,
          configRevision: 7,
        ),
        epoch: 'e1',
        seq: 2,
      );
      await l.observe(kernel(appliedSeq: 2, attempt: 1, revision: 7));

      expect(exists(s1), isTrue, reason: '无法证明 seq2 启动了新实例，不能释放运行中的 seq1');
    });

    int seqFileCount() => workDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'runtime-config-\d+\.json$').hasMatch(f.path))
        .length;

    test('反复失败：每次失败的旧产物被证明无引用而回收，磁盘文件数有界，也不会触发配额', () async {
      for (var seq = 1; seq <= 12; seq++) {
        final spec = await l.prepare(seq); // 配额检查在这里；不得抛
        final bound = await l.bindSeq(seq, spec, seq);
        await l.accepted(
          seq,
          LaunchSpec(
            runtimeConfigPath: bound.runtimeConfigPath,
            optionsJson: bound.optionsJson,
            profileName: bound.profileName,
            configRevision: 100 + seq, // 每次都不同
          ),
          epoch: 'e1',
          seq: seq,
        );
        l.sendFinished(seq);
        // 启动失败：内核停止，appliedSeq 追上。
        await l.observe(
          kernel(
            appliedSeq: seq,
            attempt: seq,
            revision: null,
            status: KernelStatus.stopped,
          ),
        );
        expect(seqFileCount(), lessThanOrEqualTo(2), reason: '第 $seq 次失败后');
      }
    });

    test('大量相同 revision 的请求（内核从不重启）：只留运行中与最新两份，不触发配额', () async {
      await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      for (var seq = 2; seq <= 30; seq++) {
        await accept(seq, seq, revision: 7);
        await l.observe(kernel(appliedSeq: seq, attempt: 1, revision: 7));
        expect(seqFileCount(), lessThanOrEqualTo(2), reason: '第 $seq 次请求后');
      }
      expect(
        File('${workDir.path}/runtime-config-1.json').existsSync(),
        isTrue,
      );
      expect(
        File('${workDir.path}/runtime-config-30.json').existsSync(),
        isTrue,
      );
    });

    test('配额：无法证明可释放的文件达到上限时，新的准备请求以类型化失败拒绝，且不再写文件', () async {
      await accept(1, 1, revision: 7);
      await l.observe(kernel(appliedSeq: 1, attempt: 1, revision: 7));
      // 5 份相同 revision、但缺发送元数据的请求：无法证明它们没被引用。
      // （运行中 1 份 + 最新 1 份之外还留着 3 份，仍低于上限 4。）
      for (var seq = 2; seq <= 6; seq++) {
        final spec = await l.bindSeq(seq, await l.prepare(seq), seq);
        l.sendFinished(seq);
        await l.accepted(
          seq,
          LaunchSpec(
            runtimeConfigPath: spec.runtimeConfigPath,
            optionsJson: spec.optionsJson,
            profileName: spec.profileName,
            configRevision: 7,
          ),
          epoch: 'e1',
          seq: seq,
        );
        await l.observe(kernel(appliedSeq: seq, attempt: 1, revision: 7));
      }
      final before = workDir.listSync().length;

      await expectLater(
        l.prepare(99),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const RuntimeFilesExhausted(),
          ),
        ),
      );

      expect(workDir.listSync().length, before, reason: '拒绝时不得再写任何文件');
    });

    test('清理不动仍在准备中的 prep 文件', () async {
      final inflight = await l.prepare(1);
      final s2 = await accept(2, 5, revision: 7);
      await l.observe(kernel(appliedSeq: 5, attempt: 1, revision: 7));
      expect(File(inflight.runtimeConfigPath).existsSync(), isTrue);
      expect(exists(s2), isTrue);
    });
  });
}

class _ThrowingRepo extends ProfileRepository {
  _ThrowingRepo({
    required super.dio,
    required super.configDir,
    required super.prefs,
    required super.boxService,
  });

  @override
  ProfileEntity? getActive() => throw StateError('模拟仓库读取失败');
}

/// 让测试里能拿到一个 `Ref`：Provider 体内把 ref 暴露出来。
final _refProvider = Provider<Ref>((ref) => ref);
