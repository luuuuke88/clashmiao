import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/profile_harness.dart';

Map<String, dynamic> _pj(String id, {Map<String, dynamic>? more}) => {
  'id': id,
  'name': 'name-$id',
  'url': 'http://sub.test/$id',
  'updateInterval': 1,
  'rev': 1,
  ...?more,
};

void main() {
  late ProfileHarness h;

  setUp(() async {
    h = await ProfileHarness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  group('editProfile 补丁：一次提交、只改被指定的字段', () {
    test('多个字段一次生效，rev 只加一次', () async {
      await h.seedRaw([
        _pj(
          'a',
          more: {
            'customUserAgent': 'old-ua',
            'advancedConfig': {
              'remoteDnsOverride': 'https://dns.example',
              'muxEnabled': false,
              'muxProtocol': 'smux',
              'muxConcurrency': 8,
              'fragmentEnabled': true,
              'fragmentRange': '10-20',
              'futureOption': {'x': 1},
            },
          },
        ),
      ], activeId: 'a');

      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(
          name: Patch.set('  新名字 '),
          url: Patch.set('http://sub.test/a2'),
          updateInterval: Patch.set(Duration(hours: 6)),
          customUserAgent: Patch.clear(),
          advancedConfig: Patch.set(
            AdvancedConfigPatch(muxEnabled: Patch.set(true)),
          ),
        ),
      );

      final e = h.repo.getAll().single;
      expect(e.name, '新名字');
      expect(e.url, 'http://sub.test/a2');
      expect(e.updateInterval, const Duration(hours: 6));
      expect(e.customUserAgent, isNull);
      expect(e.rev, 2, reason: '详情页原来两次整体替换，现在一次补丁只 +1');
      final adv = e.advancedConfig!;
      expect(adv.muxEnabled, isTrue);
      expect(adv.remoteDnsOverride, 'https://dns.example', reason: '没指定的字段保留');
      expect(adv.muxProtocol, 'smux');
      expect(adv.muxConcurrency, 8);
      expect(adv.fragmentEnabled, isTrue);
      expect(adv.fragmentRange, '10-20');
      expect(adv.extra, {
        'futureOption': {'x': 1},
      }, reason: '未知字段保留');
    });

    test('unset 不动、clear 清空、set 覆盖：三态互不串', () async {
      await h.seedRaw([
        _pj('a', more: {'customUserAgent': 'ua-1'}),
      ]);

      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(name: Patch.set('n1')),
      );
      expect(
        h.repo.getAll().single.customUserAgent,
        'ua-1',
        reason: 'unset 不动',
      );

      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(customUserAgent: Patch.set('ua-2')),
      );
      expect(h.repo.getAll().single.customUserAgent, 'ua-2');

      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(customUserAgent: Patch.clear()),
      );
      expect(h.repo.getAll().single.customUserAgent, isNull);
      expect(h.repo.getAll().single.name, 'n1');
    });

    test('高级配置补丁：可清空可空字段；整体 clear 移除高级配置', () async {
      await h.seedRaw([
        _pj(
          'a',
          more: {
            'advancedConfig': {
              'remoteDnsOverride': 'x',
              'fragmentRange': '1-2',
            },
          },
        ),
      ]);
      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(
          advancedConfig: Patch.set(
            AdvancedConfigPatch(remoteDnsOverride: Patch.clear()),
          ),
        ),
      );
      final adv = h.repo.getAll().single.advancedConfig!;
      expect(adv.remoteDnsOverride, isNull);
      expect(adv.fragmentRange, '1-2');

      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(advancedConfig: Patch.clear()),
      );
      expect(h.repo.getAll().single.advancedConfig, isNull);
    });

    test('没有高级配置时用默认值起算再应用补丁', () async {
      await h.seedRaw([_pj('a')]);
      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(
          advancedConfig: Patch.set(
            AdvancedConfigPatch(muxEnabled: Patch.set(true)),
          ),
        ),
      );
      final adv = h.repo.getAll().single.advancedConfig!;
      expect(adv.muxEnabled, isTrue);
      expect(adv.muxProtocol, const AdvancedConfig().muxProtocol);
    });

    test('名称与 URL 的空白值被忽略（与旧 editProfile 一致）', () async {
      await h.seedRaw([_pj('a')]);
      await h.repo.editProfile(
        'a',
        patch: const ProfilePatch(name: Patch.set('   '), url: Patch.set('')),
      );
      final e = h.repo.getAll().single;
      expect(e.name, 'name-a');
      expect(e.url, 'http://sub.test/a');
      expect(e.rev, 1, reason: '什么都没改：不写入、不加 rev');
    });

    test('旧写法 newName / newUrl 仍可用；与 patch 同时给出时 patch 优先', () async {
      await h.seedRaw([_pj('a')]);
      await h.repo.editProfile(
        'a',
        newName: '旧写法',
        newUrl: 'http://sub.test/legacy',
        patch: const ProfilePatch(name: Patch.set('补丁名')),
      );
      final e = h.repo.getAll().single;
      expect(e.name, '补丁名');
      expect(e.url, 'http://sub.test/legacy');
    });

    test('订阅不存在：空操作，不抛', () async {
      await h.repo.editProfile(
        'ghost',
        patch: const ProfilePatch(name: Patch.set('x')),
      );
      expect(h.repo.getAll(), isEmpty);
    });

    test('updateProfile 只应用可编辑字段，不让旧快照改写 lastUpdate / subInfo / inc', () async {
      await h.seedRaw([
        _pj('a', more: {'lastUpdate': '2026-01-02T00:00:00.000', 'inc': 'abc'}),
      ]);
      final stale = h.repo.getAll().single.copyWith(
        name: '页面改的名字',
        lastUpdate: DateTime(2000),
        inc: 'forged',
      );

      await h.repo.updateProfile(stale);

      final e = h.repo.getAll().single;
      expect(e.name, '页面改的名字');
      expect(e.lastUpdate, DateTime(2026, 1, 2));
      expect(e.inc, 'abc');
      expect(e.rev, 2);
    });
  });

  group('未知字段往返保留（前向兼容）', () {
    final future = {
      'futureField': {
        'nested': [1, 2, 3],
      },
      'subInfo': {'upload': 1, 'download': 2, 'total': 3, 'quota': 'gold'},
      'advancedConfig': {'muxEnabled': true, 'newFlag': 'on'},
    };

    test('经过 setActive / 编辑 / 新增 / 刷新之后，未知字段原样还在', () async {
      await h.seedRaw([_pj('a', more: future), _pj('b')], activeId: 'a');

      await h.repo.setActive('b');
      await h.repo.editProfile('a', newName: '改名');
      await h.repo.addByContent('ss://c@h:1#c', name: 'C');
      await h.repo.update('a');

      final a = h.storedJson.firstWhere((j) => j['id'] == 'a');
      expect(a['futureField'], {
        'nested': [1, 2, 3],
      });
      expect((a['subInfo'] as Map<String, dynamic>)['quota'], 'gold');
      expect((a['advancedConfig'] as Map<String, dynamic>)['newFlag'], 'on');
      expect(a['name'], '改名');
    });

    test(
      'ProfileEntity / AdvancedConfig / SubscriptionInfo 的 JSON 往返不丢字段',
      () async {
        await h.seedRaw([_pj('a', more: future)]);
        final e = h.repo.getAll().single;
        expect(e.extra, {
          'futureField': {
            'nested': [1, 2, 3],
          },
        });
        expect(e.subInfo!.extra, {'quota': 'gold'});
        expect(e.advancedConfig!.extra, {'newFlag': 'on'});
        expect(e.toJson()['futureField'], e.extra['futureField']);
        expect(
          (e.toJson()['subInfo'] as Map<String, dynamic>)['quota'],
          'gold',
        );
      },
    );
  });

  group('刷新合并订阅信息：已知字段更新，未知字段保留', () {
    test('响应头带 subscription-userinfo：流量更新，subInfo 里的未知字段仍在', () async {
      h.adapter.headersFor = (url, nth) => {
        'subscription-userinfo': [
          'upload=5;download=6;total=100;expire=2000000000',
        ],
      };
      await h.seedRaw([
        _pj(
          'a',
          more: {
            'subInfo': {
              'upload': 1,
              'download': 2,
              'total': 3,
              'webPageUrl': 'https://old.example/panel',
              'quota': 'gold',
              'nested': {'x': 1},
            },
          },
        ),
      ]);

      final refreshed = await h.repo.update('a');

      final info = refreshed.subInfo!;
      expect(info.upload, 5);
      expect(info.download, 6);
      expect(info.total, 100);
      expect(info.webPageUrl, isNull, reason: '新响应没带管理页面：已知字段以新响应为准');
      expect(info.extra, {
        'quota': 'gold',
        'nested': {'x': 1},
      });

      final stored = h.storedJson.single['subInfo'] as Map<String, dynamic>;
      expect(stored['upload'], 5);
      expect(stored['quota'], 'gold');
      expect(stored['nested'], {'x': 1});
    });

    test('原来没有 subInfo：直接采用响应头里的', () async {
      h.adapter.headersFor = (url, nth) => {
        'subscription-userinfo': ['upload=1;download=2;total=3'],
      };
      await h.seedRaw([_pj('a')]);
      final refreshed = await h.repo.update('a');
      expect(refreshed.subInfo?.total, 3);
    });

    test('响应头没带流量信息：保留旧的 subInfo（含未知字段）', () async {
      await h.seedRaw([
        _pj(
          'a',
          more: {
            'subInfo': {
              'upload': 1,
              'download': 2,
              'total': 3,
              'quota': 'gold',
            },
          },
        ),
      ]);
      final refreshed = await h.repo.update('a');
      expect(refreshed.subInfo?.upload, 1);
      expect(refreshed.subInfo?.extra, {'quota': 'gold'});
    });
  });

  group('补丁 clear：非空字段回落默认值，可空字段置空', () {
    Future<void> seedAdvanced() => h.seedRaw([
      _pj(
        'a',
        more: {
          'advancedConfig': {
            'remoteDnsOverride': 'https://dns.example',
            'muxEnabled': true,
            'muxProtocol': 'smux',
            'muxConcurrency': 9,
            'fragmentEnabled': true,
            'fragmentRange': '1-2',
            'future': 1,
          },
        },
      ),
    ]);

    Future<AdvancedConfig> patchAdvanced(AdvancedConfigPatch patch) async {
      await h.repo.editProfile(
        'a',
        patch: ProfilePatch(advancedConfig: Patch.set(patch)),
      );
      return h.repo.getAll().single.advancedConfig!;
    }

    test('布尔字段 clear 回落 false', () async {
      await seedAdvanced();
      final adv = await patchAdvanced(
        const AdvancedConfigPatch(
          muxEnabled: Patch.clear(),
          fragmentEnabled: Patch.clear(),
        ),
      );
      expect(adv.muxEnabled, isFalse);
      expect(adv.fragmentEnabled, isFalse);
      expect(adv.muxProtocol, 'smux', reason: '没动的字段保持');
    });

    test('字符串字段 clear 回落默认协议', () async {
      await seedAdvanced();
      final adv = await patchAdvanced(
        const AdvancedConfigPatch(muxProtocol: Patch.clear()),
      );
      expect(adv.muxProtocol, const AdvancedConfig().muxProtocol);
      expect(adv.muxConcurrency, 9);
    });

    test('整数字段 clear 回落默认并发数', () async {
      await seedAdvanced();
      final adv = await patchAdvanced(
        const AdvancedConfigPatch(muxConcurrency: Patch.clear()),
      );
      expect(adv.muxConcurrency, const AdvancedConfig().muxConcurrency);
      expect(adv.muxEnabled, isTrue);
    });

    test('可空字段 clear 置空；未知字段始终保留', () async {
      await seedAdvanced();
      final adv = await patchAdvanced(
        const AdvancedConfigPatch(
          remoteDnsOverride: Patch.clear(),
          fragmentRange: Patch.clear(),
        ),
      );
      expect(adv.remoteDnsOverride, isNull);
      expect(adv.fragmentRange, isNull);
      expect(adv.extra, {'future': 1});
    });

    test('unset 与 clear 不同：unset 保持原值', () async {
      await seedAdvanced();
      final adv = await patchAdvanced(const AdvancedConfigPatch());
      expect(adv.muxEnabled, isTrue);
      expect(adv.muxConcurrency, 9);
    });
  });

  group('v0（旧版本）数据可以直接继续使用', () {
    test('老订阅（无 rev / inc，带 active 字段）能刷新、编辑、删除', () async {
      await h.seedRaw([
        {
          'id': 'old',
          'name': '老订阅',
          'url': 'http://sub.test/old',
          'active': true,
          'updateInterval': 2,
        },
      ], activeId: 'old');

      final refreshed = await h.repo.update('old');
      expect(refreshed.rev, 2);
      expect(refreshed.inc, '');
      expect(h.repo.getActive()?.id, 'old');

      await h.repo.editProfile('old', newName: '新名');
      expect(h.repo.getAll().single.name, '新名');
      expect(h.storedJson.single.containsKey('active'), isFalse);

      await h.repo.delete('old');
      expect(h.repo.getAll(), isEmpty);
      expect(h.strayFiles(), isEmpty);
    });
  });
}
