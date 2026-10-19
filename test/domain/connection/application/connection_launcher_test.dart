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

    test('清理：保留最新两份与最近受理的请求引用的文件，其余删除', () async {
      Future<LaunchSpec> accept(int id, int seq, DateTime mtime) async {
        final spec = await l.prepare(id);
        final bound = await l.bindSeq(id, spec, seq);
        File(bound.runtimeConfigPath).setLastModifiedSync(mtime);
        await l.accepted(id, bound);
        return bound;
      }

      final t0 = DateTime(2026, 1, 1);
      final s1 = await accept(1, 1, t0);
      final s2 = await accept(2, 2, t0.add(const Duration(minutes: 1)));
      final s3 = await accept(3, 3, t0.add(const Duration(minutes: 2)));
      final s4 = await accept(4, 4, t0.add(const Duration(minutes: 3)));

      expect(File(s1.runtimeConfigPath).existsSync(), isFalse);
      expect(File(s2.runtimeConfigPath).existsSync(), isFalse);
      expect(File(s3.runtimeConfigPath).existsSync(), isTrue);
      expect(File(s4.runtimeConfigPath).existsSync(), isTrue);
    });

    test('清理不删「最近受理」的文件，即使它的修改时间是最旧的', () async {
      final t0 = DateTime(2026, 1, 1);
      Future<LaunchSpec> accept(int id, int seq, Duration age) async {
        final bound = await l.bindSeq(id, await l.prepare(id), seq);
        File(bound.runtimeConfigPath).setLastModifiedSync(t0.add(age));
        await l.accepted(id, bound);
        return bound;
      }

      final a = await accept(1, 1, const Duration(hours: 3));
      final b = await accept(2, 2, const Duration(hours: 2));
      final c = await accept(3, 3, const Duration(hours: 1));
      // 最后受理的是一份修改时间最旧的文件（例如重放持久化的 spec）。
      final e = await accept(4, 4, const Duration(hours: -1));

      bool exists(LaunchSpec s) => File(s.runtimeConfigPath).existsSync();
      expect(exists(e), isTrue, reason: '最近受理的请求引用它，不能删');
      expect(exists(c), isTrue, reason: '最近两次受理之一');
      expect(exists(a), isTrue, reason: '修改时间最新两份之一');
      expect(exists(b), isTrue, reason: '修改时间最新两份之一');
    });

    test('清理会删除既不新、也不在最近受理里的旧文件', () async {
      final t0 = DateTime(2026, 1, 1);
      Future<LaunchSpec> accept(int id, int seq, Duration age) async {
        final bound = await l.bindSeq(id, await l.prepare(id), seq);
        File(bound.runtimeConfigPath).setLastModifiedSync(t0.add(age));
        await l.accepted(id, bound);
        return bound;
      }

      final old = await accept(1, 1, const Duration(hours: -2));
      await accept(2, 2, const Duration(hours: 2));
      await accept(3, 3, const Duration(hours: 3));
      await accept(4, 4, const Duration(hours: 4));

      expect(File(old.runtimeConfigPath).existsSync(), isFalse);
    });

    test('清理不动仍在途（准备中）的 prep 文件', () async {
      final inflight = await l.prepare(1);
      final x = await l.bindSeq(2, await l.prepare(2), 5);
      await l.accepted(2, x);
      expect(File(inflight.runtimeConfigPath).existsSync(), isTrue);
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
