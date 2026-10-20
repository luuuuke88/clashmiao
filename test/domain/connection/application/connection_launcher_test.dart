import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/connection/application/connection_launcher.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
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

  group('prepare：按 revision 命名的启动产物', () {
    test(
      '写 runtime-<revision>.json + 内联 options + profileName + revision',
      () async {
        await addProfile('p1', name: '香港节点');
        await repo.setActive('p1');

        final spec = await launcher().prepare(1);

        expect(spec.profileName, '香港节点');
        expect(
          spec.runtimeConfigPath,
          '${workDir.path}/runtime-${spec.configRevision}.json',
          reason: '文件名里的 revision 就是随请求发出的 revision',
        );
        expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
        expect(workDir.listSync().map((e) => e.uri.pathSegments.last), [
          'runtime-${spec.configRevision}.json',
        ], reason: '临时文件不残留');
        final options = jsonDecode(spec.optionsJson) as Map<String, dynamic>;
        expect(options, isNotEmpty);
        expect(spec.configRevision, isNonNegative);
        // 老的单一文件名不再被写出。
        expect(
          File('${workDir.path}/runtime-config.json').existsSync(),
          isFalse,
        );
      },
    );

    // 真机验收 BUG-B：Android VPN 档曾保留订阅里的 tun inbound，内核配置构建器
    // 又按 enable-tun 再 append 一个 → 每次启动 establish() 两次（tun0 被 tun1
    // 替换），偶发 tun 转发监听缺失、经 tun 的 TCP 全被拒。tun 只能有一个来源。
    test('Android VPN 档：运行配置不带订阅里的 tun inbound，tun 只由 enable-tun 创建', () async {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      addTearDown(() => debugServiceModePlatformOverride = null);
      await addProfile('p1', config: false);
      await writeConfig('p1', {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in', 'stack': 'mixed'},
          {'type': 'mixed', 'tag': 'mixed-in', 'listen_port': 2080},
        ],
      });
      await repo.setActive('p1');

      final spec = await launcher().prepare(1);

      final options = jsonDecode(spec.optionsJson) as Map<String, dynamic>;
      expect(options['enable-tun'], isTrue, reason: '默认设置在 Android 上就是 VPN 档');
      final cfg =
          jsonDecode(File(spec.runtimeConfigPath).readAsStringSync())
              as Map<String, dynamic>;
      final inbounds = (cfg['inbounds'] as List<dynamic>? ?? const [])
          .cast<Map<dynamic, dynamic>>();
      expect(inbounds.where((i) => i['type'] == 'tun'), isEmpty);
    });

    test('相同输入 → 相同 revision（不触发重载）、同一份文件，且不被重写', () async {
      await addProfile('p1');
      await repo.setActive('p1');
      final l = launcher();

      final a = await l.prepare(1);
      // 把修改时间调到很久以前：复用时文件不能被重写（重写会刷新修改时间）。
      final past = DateTime(2020, 1, 1);
      File(a.runtimeConfigPath).setLastModifiedSync(past);
      final b = await l.prepare(2);

      expect(b.configRevision, a.configRevision);
      expect(b.runtimeConfigPath, a.runtimeConfigPath);
      expect(File(b.runtimeConfigPath).lastModifiedSync(), past);
      expect(workDir.listSync(), hasLength(1), reason: '没有临时文件残留');
    });

    test('并发的相同 revision 请求：同一路径、文件完整', () async {
      await addProfile('p1');
      await repo.setActive('p1');
      final l = launcher();

      final specs = await Future.wait([
        l.prepare(1),
        l.prepare(2),
        l.prepare(3),
      ]);

      expect({for (final s in specs) s.runtimeConfigPath}, hasLength(1));
      final decoded = jsonDecode(
        File(specs.first.runtimeConfigPath).readAsStringSync(),
      );
      expect(decoded, isA<Map<String, dynamic>>());
      expect(workDir.listSync(), hasLength(1));
    });

    test('目标已存在但内容不同：原子改名覆盖——旧读取方读到完整旧文件，新读取方读到完整新文件，没有半份文件', () async {
      await addProfile('p1');
      await repo.setActive('p1');
      final l = launcher();
      final probe = await l.prepare(1);
      final target = File(probe.runtimeConfigPath);
      final expected = target.readAsStringSync();
      final stale = '{"stale":${'0' * 4096}}'; // 内容不同的旧文件
      target.writeAsStringSync(stale);

      // 读取方先打开旧文件（持有句柄），然后另一个请求要求重写。
      final handle = target.openSync();
      final observed = <String>[];
      var rewriting = true;
      Future<void> reader() async {
        while (rewriting) {
          observed.add(target.readAsStringSync());
          await Future<void>.delayed(Duration.zero);
        }
      }

      final readerDone = reader();
      final rewritten = await l.prepare(2);
      rewriting = false;
      await readerDone;
      observed.add(target.readAsStringSync());

      expect(rewritten.runtimeConfigPath, target.path);
      expect(
        observed.toSet().difference({stale, expected}),
        isEmpty,
        reason: '读取方只可能看到完整的旧内容或完整的新内容，不会看到半份',
      );
      expect(target.readAsStringSync(), expected);
      // 先前打开的句柄仍能读到完整旧内容（改名替换而不是原地截断重写）。
      final old = handle.readSync(handle.lengthSync());
      handle.closeSync();
      expect(utf8.decode(old), stale);
      expect(workDir.listSync(), hasLength(1), reason: '没有临时文件残留');
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

  group('selectorDefaults：按 revision 给出运行时选择组默认值', () {
    test(
      'prepare 过的 revision 直接给；新实例（冷启动）读 runtime-<revision>.json 现算',
      () async {
        await addProfile('p1');
        await writeConfig('p1', {
          'outbounds': [
            {
              'type': 'selector',
              'tag': 'proxy',
              'outbounds': ['hk', 'sg'],
              'default': 'sg',
            },
            {'type': 'vless', 'tag': 'hk'},
            {'type': 'vless', 'tag': 'sg'},
          ],
        });
        await repo.setActive('p1');
        final prepared = launcher();
        final spec = await prepared.prepare(1);
        expect(await prepared.selectorDefaults(spec.configRevision), {
          'proxy': 'sg',
          'select': 'auto',
        });

        final fresh = launcher(); // 另一个进程：没 prepare 过，只能读文件
        final defaults = await fresh.selectorDefaults(spec.configRevision);
        expect(defaults['select'], 'auto');
        expect(defaults['proxy'], 'sg');

        expect(await fresh.selectorDefaults(null), isEmpty);
        expect(
          await fresh.selectorDefaults(424242),
          isEmpty,
          reason: '文件不在：不臆造',
        );
      },
    );
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

    test('刷新撞上只读存储（降级安装）→ ProfileStoreReadOnly，不误报「配置不存在」', () async {
      repo.onUpdate = (_) async => throw const StoreReadOnlyException(9);

      await expectLater(
        launcher().prepare(1),
        throwsA(
          isA<LaunchPreparationException>().having(
            (e) => e.failure,
            'failure',
            const ProfileStoreReadOnly(9),
          ),
        ),
      );
      expect(repo.updated, ['p1'], reason: '只读是在自愈刷新里才发现的');
      expect(workDir.listSync(), isEmpty, reason: '准备失败不留下任何启动产物');
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

  group('bindSeq / discard / sendFinished：引用生命周期', () {
    late ConnectionLauncher l;
    setUp(() async {
      await addProfile('p1');
      await repo.setActive('p1');
      l = launcher();
    });

    test('bindSeq 不再改名：文件名与 seq 无关，原样返回', () async {
      final spec = await l.prepare(1);
      final bound = await l.bindSeq(1, spec, 7);
      expect(bound.runtimeConfigPath, spec.runtimeConfigPath);
      expect(bound.configRevision, spec.configRevision);
      expect(File(bound.runtimeConfigPath).existsSync(), isTrue);
    });

    test('discard 不删文件：它可能仍被协调器读取，或被相同 revision 的请求复用', () async {
      final spec = await l.prepare(1);
      await l.bindSeq(1, spec, 3);
      await l.discard(1);
      l.sendFinished(1);
      expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
    });
  });

  // 删除只依据原生声明的引用与本进程已知的引用，绝不看修改时间、不做推断。
  group('清理：快照声明的 ∪ 未终结请求的 ∪ 最近 3 个 revision 之外才删', () {
    late ConnectionLauncher l;
    setUp(() async {
      await addProfile('p1');
      await repo.setActive('p1');
      l = launcher();
    });

    String at(String name) => '${workDir.path}/$name';

    KernelSnapshot kernel({
      int? active,
      KernelStatus status = KernelStatus.started,
      int appliedSeq = 0,
      int attempt = 1,
      List<String>? retained = const [],
    }) => FakeKernelPort.snap(
      status: status,
      attempt: attempt,
      desired: status == KernelStatus.stopped ? Desired.off : Desired.on,
      source: DesiredSource.app,
      appliedSeq: appliedSeq,
      activeConfigRevision: active,
      retainedConfigPaths: retained,
    );

    File leftover(String name, {Duration age = Duration.zero}) => File(at(name))
      ..writeAsStringSync('{}')
      ..setLastModifiedSync(DateTime.now().subtract(age));

    Future<LaunchSpec> prepareRevision(
      ConnectionLauncher l,
      int id,
      int variant,
    ) async {
      await writeConfig('p1', {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy$variant', 'outbounds': <String>[]},
        ],
      });
      return l.prepare(id);
    }

    Future<void> finish(ConnectionLauncher l, int id) async {
      await l.bindSeq(id, await _noopSpec(), id);
      await l.discard(id);
      l.sendFinished(id);
      await l.idle;
    }

    test('冷启动：首个快照之前什么都不删；之后只留快照声明的与本进程最近准备的', () async {
      final f111 = leftover('runtime-111.json');
      final f222 = leftover('runtime-222.json', age: const Duration(days: 30));
      final legacy = leftover('runtime-config-5.json');
      final legacyPrep = leftover('runtime-config-prep-x.json');
      final prep = leftover('runtime-prep-old.json');

      // 本进程准备过一次并释放：触发清理的时机，但还没有快照。
      final spec = await l.prepare(1);
      await finish(l, 1);
      for (final f in [f111, f222, legacy, legacyPrep, prep]) {
        expect(f.existsSync(), isTrue, reason: '${f.path} 首个快照之前不能删');
      }

      // 首个权威快照：原生声明它还会读 222。
      await l.observe(kernel(active: 222, retained: [f222.path]));

      expect(f222.existsSync(), isTrue, reason: '原生声明的引用');
      expect(
        File(spec.runtimeConfigPath).existsSync(),
        isTrue,
        reason: '本进程最近准备的',
      );
      expect(f111.existsSync(), isFalse, reason: '没有任何一方引用');
      expect(prep.existsSync(), isFalse);
      expect(legacyPrep.existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse, reason: '旧版 seq 文件同一规则：没被声明就删');
    });

    test('持久化 spec → 停止 → Dart 重建 → stopped 首快照声明该路径：文件保留，磁贴启动读取成功', () async {
      // 进程 1：连接、原生持久化这份 spec，随后断开。
      await l.observe(kernel(status: KernelStatus.stopped));
      final persisted = await l.prepare(1);
      final content = File(persisted.runtimeConfigPath).readAsStringSync();
      await l.bindSeq(1, persisted, 1);
      await l.observe(
        kernel(
          active: persisted.configRevision,
          appliedSeq: 1,
          retained: [persisted.runtimeConfigPath],
        ),
      );
      await l.discard(1);
      l.sendFinished(1);
      await l.observe(
        kernel(
          status: KernelStatus.stopped,
          appliedSeq: 2,
          retained: [persisted.runtimeConfigPath],
        ),
      );
      await l.idle;

      // Dart 重建（新进程 / 新 launcher：没有任何本进程引用）。
      final l2 = launcher();
      await l2.observe(
        kernel(
          status: KernelStatus.stopped,
          appliedSeq: 2,
          retained: [persisted.runtimeConfigPath],
        ),
      );
      await l2.idle;
      expect(File(persisted.runtimeConfigPath).existsSync(), isTrue);

      // 本进程又准备并释放了 4 个别的 revision：最近 3 个里早已没有它。
      for (var i = 1; i <= 4; i++) {
        await prepareRevision(l2, i, 100 + i);
        await finish(l2, i);
      }
      await l2.observe(
        kernel(
          status: KernelStatus.stopped,
          appliedSeq: 2,
          attempt: 2,
          retained: [persisted.runtimeConfigPath],
        ),
      );
      await l2.idle;

      // 磁贴启动（原生，没有 Dart 参与）读取持久化的路径：文件完整可解析。
      final read = File(persisted.runtimeConfigPath).readAsStringSync();
      expect(read, content);
      expect(jsonDecode(read), isA<Map<String, Object?>>());
    });

    test('同 revision 新文件已生成，但请求失败、原生仍引用旧版 seq 路径：旧文件保留', () async {
      final legacy = leftover('runtime-config-5.json');
      // 原生以旧路径运行（同一份配置内容）。
      await l.observe(kernel(appliedSeq: 5, retained: [legacy.path]));

      final spec = await l.prepare(1);
      expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
      await l.observe(
        kernel(
          active: spec.configRevision,
          appliedSeq: 5,
          retained: [legacy.path],
        ),
      );
      // 请求 RPC 失败：从未送达原生，原生的引用不变。
      await l.bindSeq(1, spec, 6);
      await l.discard(1);
      l.sendFinished(1);
      await l.idle;

      expect(legacy.existsSync(), isTrue, reason: '新文件存在不能证明原生放弃了旧路径');
      expect(
        File(spec.runtimeConfigPath).existsSync(),
        isTrue,
        reason: '最近准备的',
      );

      // 只有原生不再声明它之后才删。
      await l.observe(
        kernel(
          active: spec.configRevision,
          appliedSeq: 7,
          retained: [spec.runtimeConfigPath],
        ),
      );
      expect(legacy.existsSync(), isFalse);
      expect(File(spec.runtimeConfigPath).existsSync(), isTrue);
    });

    test('快照没有 retainedConfigPaths 字段（更早的原生）：一个都不删', () async {
      final stray = leftover(
        'runtime-111.json',
        age: const Duration(days: 400),
      );
      final legacy = leftover('runtime-config-5.json');
      final prep = leftover('runtime-prep-old.json');
      final old = KernelSnapshot.fromJson({
        'epoch': 'e-old',
        'version': 3,
        'status': 'stopped',
        'attempt': 1,
        'desired': 'off',
        'source': 'app',
        'appliedSeq': 0,
        'activeConfigRevision': null,
        'selectionsReplayNeeded': false,
        'lastFailure': null,
      });
      expect(old.retainedConfigPaths, isNull);
      await l.observe(old);

      // 准备并释放 5 个 revision：最近 3 个之外的照样不删。
      final specs = <LaunchSpec>[];
      for (var i = 1; i <= 5; i++) {
        specs.add(await prepareRevision(l, i, i));
        await finish(l, i);
      }
      await l.observe(old.copyWith(version: 4, status: KernelStatus.stopped));
      await l.idle;

      for (final f in [stray, legacy, prep]) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
      for (final s in specs) {
        expect(File(s.runtimeConfigPath).existsSync(), isTrue);
      }

      // 之后的快照带上了字段：恢复正常清理。
      await l.observe(kernel(status: KernelStatus.stopped));
      expect(stray.existsSync(), isFalse);
      expect(File(specs[0].runtimeConfigPath).existsSync(), isFalse);
      expect(File(specs[4].runtimeConfigPath).existsSync(), isTrue);
    });

    test('引用按规范化的绝对路径比较：多余的 ./.. 与符号链接前缀都能对上', () async {
      final legacy = leftover('runtime-config-5.json');
      final viaDots = leftover('runtime-config-6.json');
      final stray = leftover('runtime-config-7.json');
      final link = Link('${tmp.path}/alias')..createSync(workDir.path);

      await l.observe(
        kernel(
          status: KernelStatus.stopped,
          retained: [
            '${link.path}/runtime-config-5.json',
            '${workDir.path}/./sub/../runtime-config-6.json',
          ],
        ),
      );

      expect(legacy.existsSync(), isTrue, reason: '经符号链接前缀声明');
      expect(viaDots.existsSync(), isTrue, reason: '未规范化的路径');
      expect(stray.existsSync(), isFalse);
    });

    test('不看文件年龄：很旧但被声明的保留，刚写的但没人引用的照删', () async {
      final ancientActive = leftover(
        'runtime-7.json',
        age: const Duration(days: 400),
      );
      final freshStray = leftover('runtime-8.json');

      await l.observe(kernel(active: 7, retained: [ancientActive.path]));

      expect(ancientActive.existsSync(), isTrue);
      expect(freshStray.existsSync(), isFalse);
    });

    test('revision 变更循环：只留声明的与最近 3 个，其余回收', () async {
      await l.observe(kernel(status: KernelStatus.stopped));
      final specs = <LaunchSpec>[];
      for (var i = 1; i <= 6; i++) {
        final spec = await prepareRevision(l, i, i);
        specs.add(spec);
        if (i == 1) {
          // 第 1 份启动并运行着（原生声明它）。
          await l.observe(
            kernel(
              active: spec.configRevision,
              appliedSeq: 1,
              retained: [spec.runtimeConfigPath],
            ),
          );
        }
        await finish(l, i);
      }
      bool ex(int i) => File(specs[i].runtimeConfigPath).existsSync();

      expect(ex(0), isTrue, reason: '原生声明的，即使早已不在最近 3 个里');
      expect(ex(1), isFalse);
      expect(ex(2), isFalse);
      expect(ex(3) && ex(4) && ex(5), isTrue, reason: '最近 3 个');

      // 原生的引用换成第 6 份：第 1 份释放。
      await l.observe(
        kernel(
          active: specs[5].configRevision,
          appliedSeq: 6,
          attempt: 2,
          retained: [specs[5].runtimeConfigPath],
        ),
      );
      expect(ex(0), isFalse);
      expect(ex(3) && ex(4) && ex(5), isTrue);
    });

    test('首次启动在读文件前悬停，同 revision 的请求被受理：文件不被动、不被删', () async {
      await l.observe(kernel(status: KernelStatus.stopped));
      final first = await l.prepare(1);
      await l.bindSeq(1, first, 1);
      final file = File(first.runtimeConfigPath);
      final past = DateTime(2020, 1, 1);
      file.setLastModifiedSync(past);
      final before = file.readAsStringSync();

      // 执行层还没来得及读文件：快照 starting。
      await l.observe(kernel(status: KernelStatus.starting, appliedSeq: 1));
      // 同 revision 的请求 2 被受理（沿用在途的启动），随后终结。
      final second = await l.prepare(2);
      expect(second.runtimeConfigPath, first.runtimeConfigPath);
      await l.bindSeq(2, second, 2);
      await l.observe(kernel(status: KernelStatus.starting, appliedSeq: 2));
      await l.discard(2);
      l.sendFinished(2);
      await l.idle;

      expect(file.existsSync(), isTrue, reason: '请求 1 尚未终结，文件受保护');
      expect(file.lastModifiedSync(), past, reason: '没有被重写');
      expect(file.readAsStringSync(), before);

      // 请求 1 终结后，只要它还是本进程最近准备的 revision，仍然保留。
      await l.discard(1);
      l.sendFinished(1);
      await l.idle;
      await l.observe(
        kernel(status: KernelStatus.starting, appliedSeq: 2, attempt: 2),
      );
      expect(file.existsSync(), isTrue);
    });
  });
}

Future<LaunchSpec> _noopSpec() async => const LaunchSpec(
  runtimeConfigPath: '',
  optionsJson: '{}',
  profileName: '',
  configRevision: 0,
);

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
