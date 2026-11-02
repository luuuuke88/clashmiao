import 'package:flutter_test/flutter_test.dart';

import 'import_scanner.dart';
import 'layering_rules.dart';

/// 合成数据里的 import 一律写成 `package:clashmiao/...`，与真实源码一致。
String pkg(String path) => 'package:clashmiao/$path';

Map<String, List<String>> graph(Map<String, List<String>> edges) => {
  for (final e in edges.entries) e.key: [for (final t in e.value) pkg(t)],
};

void main() {
  group('logicalUnitOf：新旧目录都按逻辑功能归位', () {
    void expectUnit(
      String path,
      String feature,
      Tier tier,
      String layer, {
      String? reason,
    }) {
      final u = logicalUnitOf(path);
      expect(u, isNotNull, reason: reason ?? path);
      expect(u!.feature, feature, reason: path);
      expect(u.tier, tier, reason: path);
      expect(u.layer, layer, reason: path);
    }

    test('旧路径 domain/<x>/<layer>：routing 映射为 proxy', () {
      expectUnit(
        'domain/routing/application/x.dart',
        'proxy',
        Tier.capability,
        'application',
      );
      expectUnit(
        'domain/routing/model/m.dart',
        'proxy',
        Tier.capability,
        'model',
      );
      expectUnit(
        'domain/profile/data/migrations/v1_profiles.dart',
        'profile',
        Tier.capability,
        'data',
      );
      expectUnit(
        'domain/connection/application/c.dart',
        'connection',
        Tier.capability,
        'application',
      );
      expectUnit(
        'domain/config/model/m.dart',
        'config',
        Tier.capability,
        'model',
      );
    });

    test('旧路径 features/config 按文件拆成 backup / options / config', () {
      expectUnit(
        'features/config/data/backup_engine.dart',
        'backup',
        Tier.capability,
        'data',
      );
      expectUnit(
        'features/config/application/restore_refresher.dart',
        'backup',
        Tier.capability,
        'application',
      );
      expectUnit(
        'features/config/application/startup_restore_notice.dart',
        'backup',
        Tier.capability,
        'application',
      );
      expectUnit(
        'features/config/data/restore_recovery.dart',
        'backup',
        Tier.capability,
        'data',
      );
      expectUnit(
        'features/config/model/backup_bundle.dart',
        'backup',
        Tier.capability,
        'model',
      );
      expectUnit(
        'features/config/presentation/backup_messages.dart',
        'backup',
        Tier.capability,
        'presentation',
      );
      expectUnit(
        'features/config/presentation/config_options_page.dart',
        'options',
        Tier.page,
        'presentation',
      );
      expectUnit(
        'features/config/presentation/dns_strategy_messages.dart',
        'config',
        Tier.capability,
        'presentation',
      );
    });

    test('新路径 features/<f>/<layer>', () {
      expectUnit(
        'features/profile/presentation/profiles_page.dart',
        'profile',
        Tier.capability,
        'presentation',
      );
      expectUnit(
        'features/proxy/application/row_order.dart',
        'proxy',
        Tier.capability,
        'application',
      );
      expectUnit(
        'features/backup/data/backup_engine.dart',
        'backup',
        Tier.capability,
        'data',
      );
      expectUnit(
        'features/connection/application/c.dart',
        'connection',
        Tier.capability,
        'application',
      );
      expectUnit(
        'features/options/presentation/config_options_page.dart',
        'options',
        Tier.page,
        'presentation',
      );
      expectUnit(
        'features/assets/data/geo_update_service.dart',
        'assets',
        Tier.page,
        'data',
      );
      expectUnit(
        'features/home/presentation/home_page.dart',
        'home',
        Tier.page,
        'presentation',
      );
    });

    test('页面型功能的散文件、非分层子目录按 presentation 处理', () {
      expectUnit('features/home/home.dart', 'home', Tier.page, 'presentation');
      expectUnit(
        'features/splash/widgets/w.dart',
        'splash',
        Tier.page,
        'presentation',
      );
    });

    test('core / shared / app / main.dart 不属于任何功能', () {
      for (final p in [
        'core/storage/a.dart',
        'shared/components/a.dart',
        'app/router/a.dart',
        'main.dart',
      ]) {
        expect(logicalUnitOf(p), isNull, reason: p);
      }
    });

    test('未登记的功能、能力型功能的散文件、domain 下的页面型名字：返回 null', () {
      for (final p in [
        'domain/unknown/model/a.dart',
        'features/unknown/presentation/a.dart',
        'domain/profile/a.dart',
        'features/profile/a.dart',
        'domain/home/presentation/a.dart',
        'features/a.dart',
      ]) {
        expect(logicalUnitOf(p), isNull, reason: p);
      }
    });

    test('kCapabilityOrder 是能力型功能的层级顺序', () {
      expect(kCapabilityOrder, [
        'config',
        'profile',
        'proxy',
        'connection',
        'backup',
      ]);
    });
  });

  group('checkLayering：六条依赖规则', () {
    List<Violation> check(
      Map<String, List<String>> edges, {
      List<AllowedEdge> allowlist = const [],
    }) => checkLayering(graph(edges), allowlist: allowlist);

    group('规则 1：能力型的非页面层只能依赖更低的能力型非页面层与 core', () {
      test('profile application → proxy application：违规', () {
        final bad = check({
          'domain/profile/application/a.dart': [
            'domain/routing/application/b.dart',
          ],
        });
        expect(bad, hasLength(1));
        expect(bad.single.from, 'domain/profile/application/a.dart');
        expect(bad.single.to, 'domain/routing/application/b.dart');
      });

      test('proxy application → profile application：合规', () {
        expect(
          check({
            'domain/routing/application/a.dart': [
              'domain/profile/application/b.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('新旧路径混用同样按逻辑功能判定', () {
        expect(
          check({
            'domain/profile/application/a.dart': [
              'features/proxy/application/b.dart',
            ],
          }),
          hasLength(1),
        );
        expect(
          check({
            'features/proxy/application/a.dart': [
              'domain/profile/application/b.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('各层都按 kCapabilityOrder 判：backup 可依赖全部更低者，反之违规', () {
        expect(
          check({
            'features/config/data/backup_engine.dart': [
              'domain/config/data/a.dart',
              'domain/profile/data/b.dart',
              'domain/routing/data/c.dart',
              'domain/connection/application/d.dart',
              'core/e.dart',
            ],
          }),
          isEmpty,
        );
        expect(
          check({
            'domain/connection/application/a.dart': [
              'features/config/data/backup_engine.dart',
            ],
          }),
          hasLength(1),
        );
      });

      test('非页面层依赖任何 presentation / 页面型功能 / shared：违规', () {
        for (final target in [
          'features/profile/presentation/p.dart',
          'features/home/presentation/p.dart',
          'shared/components/a.dart',
          'app/a.dart',
        ]) {
          expect(
            check({
              'domain/routing/application/a.dart': [target],
            }),
            hasLength(1),
            reason: target,
          );
        }
      });

      test('非页面层依赖 core 合规', () {
        expect(
          check({
            'domain/profile/data/a.dart': ['core/b.dart'],
          }),
          isEmpty,
        );
      });
    });

    group('规则 2：能力型的 presentation 可依赖任意能力型非页面层、本功能页面层、shared、core', () {
      test('profile presentation → proxy application：合规', () {
        expect(
          check({
            'features/profile/presentation/a.dart': [
              'domain/routing/application/b.dart',
              'domain/connection/model/c.dart',
              'features/config/data/backup_engine.dart',
              'features/profile/presentation/d.dart',
              'shared/components/e.dart',
              'core/f.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('profile presentation → proxy presentation：违规', () {
        final bad = check({
          'features/profile/presentation/a.dart': [
            'features/proxy/presentation/b.dart',
          ],
        });
        expect(bad, hasLength(1));
        expect(bad.single.to, 'features/proxy/presentation/b.dart');
      });

      test('能力型 presentation → 页面型功能：违规', () {
        expect(
          check({
            'features/profile/presentation/a.dart': [
              'features/settings/presentation/b.dart',
            ],
          }),
          hasLength(1),
        );
      });
    });

    group('规则 3：页面型可依赖任意能力型的任何一层；页面型之间不能互相依赖', () {
      test('home presentation → profile presentation（对话框）：合规', () {
        expect(
          check({
            'features/home/presentation/home_page.dart': [
              'features/profile/presentation/profile_form_dialog.dart',
              'domain/connection/application/c.dart',
              'features/proxy/presentation/p.dart',
              'shared/components/s.dart',
              'core/c.dart',
              'features/home/presentation/other.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('home → settings：违规', () {
        final bad = check({
          'features/home/presentation/a.dart': [
            'features/settings/presentation/b.dart',
          ],
        });
        expect(bad, hasLength(1));
        expect(bad.single.hint, isNot(contains('白名单')));
        expect(bad.single.hint, contains('路由入口解耦'));
      });

      test('页面型之间的跳转写进白名单后合规', () {
        final edges = {
          'features/home/presentation/quick_settings_modal.dart': [
            'features/config/presentation/config_options_page.dart',
          ],
        };
        expect(check(edges), hasLength(1));
        expect(
          check(
            edges,
            allowlist: const [
              AllowedEdge(
                'features/home/presentation/quick_settings_modal.dart',
                'features/config/presentation/config_options_page.dart',
                '页面跳转',
              ),
            ],
          ),
          isEmpty,
        );
      });

      test('白名单不能豁免能力型功能之间的违规', () {
        final bad = check(
          {
            'domain/profile/application/a.dart': [
              'domain/routing/application/b.dart',
            ],
          },
          allowlist: const [
            AllowedEdge(
              'domain/profile/application/a.dart',
              'domain/routing/application/b.dart',
              '企图夹带',
            ),
          ],
        );
        expect(bad, hasLength(2));
        expect(bad.where((v) => v.rule == '白名单条目非法'), hasLength(1));
      });
    });

    group('规则 4 不在 checkLayering 里判（单独的 checkIntraFeatureDirection）', () {
      test('同功能内 data → application 不算层间违规', () {
        expect(
          check({
            'domain/profile/data/a.dart': ['domain/profile/application/b.dart'],
          }),
          isEmpty,
        );
      });
    });

    group('core / shared / app 的原有规则', () {
      test('core → 非 core 违规；core → core 合规', () {
        final bad = check({
          'core/a.dart': ['domain/profile/model/b.dart'],
        });
        expect(bad, hasLength(1));
        expect(bad.single.from, 'core/a.dart');
        expect(bad.single.to, 'domain/profile/model/b.dart');
        expect(
          check({
            'core/a.dart': ['core/b.dart'],
          }),
          isEmpty,
        );
        expect(
          check({
            'core/a.dart': ['features/home/presentation/b.dart'],
          }),
          hasLength(1),
        );
      });

      test('shared → 功能 / app 违规；shared → core / shared 合规', () {
        for (final target in [
          'features/home/presentation/b.dart',
          'domain/profile/model/b.dart',
          'app/b.dart',
        ]) {
          expect(
            check({
              'shared/a.dart': [target],
            }),
            hasLength(1),
            reason: target,
          );
        }
        expect(
          check({
            'shared/a.dart': ['core/b.dart', 'shared/c.dart'],
          }),
          isEmpty,
        );
      });

      test('app 与 main.dart 依赖任意层都合规', () {
        expect(
          check({
            'app/x.dart': [
              'core/a.dart',
              'shared/b.dart',
              'domain/connection/application/c.dart',
              'features/home/presentation/d.dart',
              'app/y.dart',
            ],
            'main.dart': [
              'app/app.dart',
              'core/a.dart',
              'features/home/presentation/d.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('功能 → app 违规', () {
        expect(
          check({
            'features/home/presentation/a.dart': ['app/x.dart'],
          }),
          hasLength(1),
        );
      });

      test('非项目内 URI（flutter / dart:）不参与层间判定', () {
        expect(
          checkLayering({
            'core/a.dart': ['package:flutter/material.dart', 'dart:io'],
          }, allowlist: const []),
          isEmpty,
        );
      });

      test('*.g.dart 按所在目录归层，不豁免', () {
        expect(
          check({
            'core/a.g.dart': ['domain/profile/model/b.dart'],
          }),
          hasLength(1),
        );
      });
    });

    group('不认识的位置：报违规，不静默放过', () {
      test('不在已知层里的文件与目标', () {
        expect(
          check({
            'stray/a.dart': ['core/b.dart'],
          }),
          hasLength(1),
        );
        expect(
          check({
            'core/a.dart': ['stray/b.dart'],
          }),
          hasLength(1),
        );
      });

      test('未登记的功能连依赖 core 也不放过', () {
        expect(
          check({
            'domain/unknown/model/a.dart': ['core/b.dart'],
            'features/unknown/presentation/a.dart': ['core/b.dart'],
          }),
          hasLength(2),
        );
      });

      test('能力型功能的散文件（不在分层目录里）：违规', () {
        expect(
          check({
            'domain/profile/a.dart': ['core/b.dart'],
          }),
          hasLength(1),
        );
      });

      test('依赖目标是未登记的功能：违规', () {
        expect(
          check({
            'features/home/presentation/a.dart': [
              'domain/unknown/model/b.dart',
            ],
          }),
          hasLength(1),
        );
      });
    });

    test('Violation.toString 形如 from → to · rule · hint', () {
      const v = Violation('a.dart', 'b.dart', '规则', '提示');
      expect(v.toString(), 'a.dart → b.dart · 规则 · 提示');
    });
  });

  group('checkIntraFeatureDirection：规则 4 同功能内部方向', () {
    List<Violation> intra(Map<String, List<String>> edges) =>
        checkIntraFeatureDirection(graph(edges));

    test('x/data → x/application：违规', () {
      final bad = intra({
        'domain/profile/data/a.dart': ['domain/profile/application/b.dart'],
      });
      expect(bad, hasLength(1));
      expect(bad.single.from, 'domain/profile/data/a.dart');
      expect(bad.single.to, 'domain/profile/application/b.dart');
    });

    test('model → 任何更高层、application → presentation：违规', () {
      expect(
        intra({
          'domain/profile/model/a.dart': ['domain/profile/data/b.dart'],
          'domain/profile/application/c.dart': [
            'features/profile/presentation/d.dart',
          ],
        }),
        hasLength(2),
      );
    });

    test('presentation → application → data → model，含跨层与同层：合规', () {
      expect(
        intra({
          'features/profile/presentation/a.dart': [
            'domain/profile/application/b.dart',
            'domain/profile/data/c.dart',
            'domain/profile/model/d.dart',
            'features/profile/presentation/e.dart',
          ],
          'domain/profile/application/b.dart': [
            'domain/profile/data/c.dart',
            'domain/profile/model/d.dart',
          ],
          'domain/profile/data/c.dart': ['domain/profile/model/d.dart'],
        }),
        isEmpty,
      );
    });

    test('只判同一个逻辑功能：跨功能的反向不归它管', () {
      expect(
        intra({
          'domain/profile/model/a.dart': ['domain/routing/application/b.dart'],
        }),
        isEmpty,
      );
    });

    test('features/config 拆出的 backup 与 config 是两个功能', () {
      expect(
        intra({
          'features/config/data/backup_engine.dart': [
            'domain/config/application/a.dart',
          ],
        }),
        isEmpty,
      );
    });

    test('非项目内 URI、不认识的位置不报（交给 checkLayering）', () {
      expect(
        checkIntraFeatureDirection({
          'domain/profile/data/a.dart': [
            'package:flutter/material.dart',
            'dart:io',
          ],
          'stray/a.dart': [pkg('domain/profile/application/b.dart')],
        }),
        isEmpty,
      );
    });
  });

  group('欠账登记：withoutDebt / staleDebt', () {
    const v1 = Violation('a.dart', 'b.dart', '规则', '提示');
    const v2 = Violation('c.dart', 'd.dart', '规则', '提示');
    const d1 = AllowedEdge('a.dart', 'b.dart', '欠账');
    const gone = AllowedEdge('x.dart', 'y.dart', '已还清');

    test('已登记的违规被扣掉，其余保留', () {
      expect(withoutDebt(const [v1, v2], const [d1]), [v2]);
      expect(withoutDebt(const [v1, v2], const []), [v1, v2]);
    });

    test('登记了但代码里已不再违规的条目被返回（棘轮）', () {
      expect(staleDebt(const [v1, v2], const [d1, gone]), [gone]);
      expect(staleDebt(const [v1], const [d1]), isEmpty);
    });
  });

  group('checkModelPurity：R1 模型纯净', () {
    const model = 'domain/profile/model/m.dart';

    test('传递依赖到 flutter 报违规', () {
      final bad = checkModelPurity({
        model: [pkg('core/u.dart')],
        'core/u.dart': ['package:flutter/material.dart'],
      });
      expect(bad, hasLength(1));
      expect(bad.single.from, model);
      expect(bad.single.to, 'package:flutter/material.dart');
      // 提示里要有传递链，便于定位是哪一环引入的。
      expect(bad.single.hint, contains('core/u.dart'));
    });

    test('只依赖 dart:convert 与纯模型合规', () {
      expect(
        checkModelPurity({
          model: ['dart:convert', pkg('domain/profile/model/n.dart')],
          'domain/profile/model/n.dart': ['dart:core'],
        }),
        isEmpty,
      );
    });

    test('直接 import 各类禁用包均报', () {
      for (final forbidden in [
        'dart:io',
        'dart:ui',
        'package:flutter/widgets.dart',
        'package:hooks_riverpod/hooks_riverpod.dart',
        'package:riverpod/riverpod.dart',
        'package:flutter_riverpod/flutter_riverpod.dart',
      ]) {
        final bad = checkModelPurity({
          model: [forbidden],
        });
        expect(bad, hasLength(1), reason: forbidden);
        expect(bad.single.to, forbidden);
      }
    });

    test('触达 data / application 报违规', () {
      final d = checkModelPurity({
        model: [pkg('domain/profile/data/d.dart')],
        'domain/profile/data/d.dart': [],
      });
      expect(d, hasLength(1));
      expect(d.single.to, 'domain/profile/data/d.dart');

      final a = checkModelPurity({
        model: [pkg('domain/config/application/x.dart')],
      });
      expect(a, hasLength(1));
      expect(a.single.to, 'domain/config/application/x.dart');
    });

    test('经由中间文件传递触达 data 同样报', () {
      final bad = checkModelPurity({
        model: [pkg('core/u.dart')],
        'core/u.dart': [pkg('domain/profile/data/d.dart')],
      });
      expect(bad, hasLength(1));
    });

    test('data 一侧再引 flutter：只在 data 这一环止步报一次，不重复刷屏', () {
      final bad = checkModelPurity({
        model: [pkg('domain/profile/data/d.dart')],
        'domain/profile/data/d.dart': ['package:flutter/material.dart'],
      });
      expect(bad, hasLength(1));
    });

    test('循环依赖不会死循环', () {
      expect(
        checkModelPurity({
          model: [pkg('core/a.dart')],
          'core/a.dart': [pkg(model), pkg('core/a.dart')],
        }),
        isEmpty,
      );
    });

    test('新路径与页面型功能的 model 同样适用；触达任何功能的 data / application 都报', () {
      for (final m in [
        'features/assets/model/geo_asset.dart',
        'features/backup/model/backup_bundle.dart',
        'features/config/model/backup_bundle.dart',
      ]) {
        expect(
          checkModelPurity({
            m: ['package:flutter/material.dart'],
          }),
          hasLength(1),
          reason: m,
        );
      }
      for (final target in [
        'features/assets/data/g.dart',
        'features/proxy/application/g.dart',
        'features/config/data/backup_engine.dart',
      ]) {
        final bad = checkModelPurity({
          'features/assets/model/geo_asset.dart': [pkg(target)],
        });
        expect(bad, hasLength(1), reason: target);
        expect(bad.single.to, target);
      }
    });

    test('非 model 文件即使依赖 flutter 也不属于 R1', () {
      expect(
        checkModelPurity({
          'domain/profile/application/a.dart': [
            'package:flutter/material.dart',
          ],
        }),
        isEmpty,
      );
    });
  });

  group('staleEntries：白名单棘轮', () {
    const live = AllowedEdge('features/a/x.dart', 'features/b/y.dart', '在用');
    const dead = AllowedEdge('features/a/x.dart', 'features/c/z.dart', '已过期');
    const gone = AllowedEdge('features/q/x.dart', 'features/b/y.dart', '文件已删');

    test('白名单里有、代码里已不存在的边被返回', () {
      final uris = graph({
        'features/a/x.dart': ['features/b/y.dart'],
      });
      expect(staleEntries(uris, const [live, dead, gone]), [dead, gone]);
    });

    test('全部仍在用则为空', () {
      final uris = graph({
        'features/a/x.dart': ['features/b/y.dart'],
      });
      expect(staleEntries(uris, const [live]), isEmpty);
    });
  });

  group('checkAllowlist：白名单自身校验（数字均写死，不依赖 kAllowlistCeiling）', () {
    AllowedEdge feat(int i) => AllowedEdge(
      'features/home/presentation/p$i.dart',
      'features/logs/presentation/q$i.dart',
      '合成',
    );

    test('恰好 5 条、上限 5：通过', () {
      expect(
        checkAllowlist([for (var i = 0; i < 5; i++) feat(i)], ceiling: 5),
        isEmpty,
      );
    });

    test('手写第 6 条：超限失败', () {
      final problems = checkAllowlist([
        feat(0),
        feat(1),
        feat(2),
        feat(3),
        feat(4),
        const AllowedEdge(
          'features/home/presentation/extra.dart',
          'features/logs/presentation/extra.dart',
          '第六条',
        ),
      ], ceiling: 5);
      expect(problems, hasLength(1));
      expect(problems.single, contains('6'));
    });

    test('core → domain 条目：失败', () {
      final problems = checkAllowlist(const [
        AllowedEdge('core/a.dart', 'domain/x/b.dart', '越层'),
      ], ceiling: 5);
      expect(problems, hasLength(1));
      expect(problems.single, contains('白名单条目非法'));
    });

    test('超限与非法同时存在：两类问题都报', () {
      final problems = checkAllowlist([
        for (var i = 0; i < 5; i++) feat(i),
        const AllowedEdge('core/a.dart', 'domain/x/b.dart', '越层'),
      ], ceiling: 5);
      expect(problems, hasLength(2));
    });

    test('能力型功能之间、页面型 → 能力型、同一页面型内部的条目：失败', () {
      for (final e in const [
        AllowedEdge(
          'domain/profile/application/a.dart',
          'domain/routing/application/b.dart',
          '能力型之间',
        ),
        AllowedEdge(
          'features/home/presentation/a.dart',
          'features/profile/presentation/b.dart',
          '页面型 → 能力型本来就合规',
        ),
        AllowedEdge(
          'features/home/presentation/a.dart',
          'features/home/presentation/b.dart',
          '同一功能内部',
        ),
        AllowedEdge(
          'features/home/presentation/a.dart',
          'features/unknown/presentation/b.dart',
          '未登记',
        ),
      ]) {
        final problems = checkAllowlist([e], ceiling: 5);
        expect(problems, hasLength(1), reason: e.toString());
        expect(problems.single, contains('白名单条目非法'));
      }
    });

    test('页面型 → 页面型（新旧路径）的条目：通过', () {
      expect(
        checkAllowlist(const [
          AllowedEdge(
            'features/home/presentation/quick_settings_modal.dart',
            'features/config/presentation/config_options_page.dart',
            '旧路径',
          ),
          AllowedEdge(
            'features/options/presentation/config_options_page.dart',
            'features/logs/presentation/logs_page.dart',
            '新路径',
          ),
        ], ceiling: 5),
        isEmpty,
      );
    });

    test('空名单合法', () {
      expect(checkAllowlist(const [], ceiling: 0), isEmpty);
    });
  });

  group('相对 URI：扫描源码 → 规则判定（端到端）', () {
    /// 把 {文件路径: 源码} 扫描成 uris，再交给规则。
    Map<String, List<String>> scan(Map<String, String> sources) => {
      for (final e in sources.entries) e.key: extractDirectiveUris(e.value),
    };

    test('(a) core 里相对 export 到 domain：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/a.dart': "export '../../domain/profile/model/m.dart';",
          'domain/profile/model/m.dart': '',
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/a.dart');
      expect(bad.single.to, 'domain/profile/model/m.dart');
    });

    test('(b) 条件导入的相对 if 分支 core → domain：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/a.dart': """
import 'package:clashmiao/core/storage/stub.dart'
    if (dart.library.io) '../../domain/profile/model/m.dart';
""",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.to, 'domain/profile/model/m.dart');
    });

    test('(c) R1：模型经相对 export 链触达 application：被报并带传递链', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart': "export '../../../core/u.dart';",
          'core/u.dart': "export '../domain/profile/application/svc.dart';",
          'domain/profile/application/svc.dart': '',
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'domain/profile/model/m.dart');
      expect(bad.single.to, 'domain/profile/application/svc.dart');
      expect(
        bad.single.hint,
        contains(
          'domain/profile/model/m.dart → core/u.dart → domain/profile/application/svc.dart',
        ),
      );
    });

    test('(c2) R1：相对 export 链通到 flutter 也被报', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart': "export './n.dart';",
          'domain/profile/model/n.dart':
              "import 'package:flutter/material.dart';",
        }),
      );
      // m 与 n 都是模型，各自触达 flutter 一次；m 的那条要带上经过 n 的链。
      final fromM = bad.where((v) => v.from == 'domain/profile/model/m.dart');
      expect(fromM, hasLength(1));
      expect(fromM.single.to, 'package:flutter/material.dart');
      expect(
        fromM.single.hint,
        contains('model/m.dart → domain/profile/model/n.dart'),
      );
    });

    test('(d) 同层内的相对 import 仍合规', () {
      expect(
        checkLayering(
          scan({
            'core/storage/a.dart':
                "import './b.dart'; export '../utils/c.dart';",
            'core/storage/b.dart': '',
            'core/utils/c.dart': '',
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('反斜杠写法 core → domain：被报（不再漏）', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              r"export r'..\..\domain\profile\model\profile_entity.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/x.dart');
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.hint, contains('请改用 package:clashmiao/ 导入'));
      expect(bad.single.hint, contains(r'..\..\domain'));
    });

    test('百分号转义 %2e%2e 写法：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              "export '%2e%2e/%2e%2e/domain/profile/model/m.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.to, contains('%2e%2e'));
    });

    test('多余的 .. 越出 lib/：被报，不是跳过', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              "export '../../../domain/profile/model/m.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.hint, contains('../../../domain/profile/model/m.dart'));
    });

    test('query / fragment / 空段 / 绝对路径写法：被报', () {
      for (final uri in ['a.dart?x=1', 'a.dart#f', 'b//a.dart', '/a.dart']) {
        final bad = checkLayering(
          scan({'core/x.dart': "export '$uri';"}),
          allowlist: const [],
        );
        expect(bad, hasLength(1), reason: uri);
      }
    });

    test('package URI 含 .. 点段 core → domain：被报（不再被当作 core）', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart': "export 'package:clashmiao/core/../domain/profile/application/profile_providers.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/x.dart');
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.hint, contains('core/../domain'));
    });

    test('package URI 的 . 段、空段、转义、query/fragment、反斜杠：都被报', () {
      for (final uri in [
        'package:clashmiao/core/./a.dart',
        'package:clashmiao/core//a.dart',
        'package:clashmiao/core/%2e%2e/domain/a.dart',
        'package:clashmiao/core/a.dart?x=1',
        'package:clashmiao/core/a.dart#f',
        r'package:clashmiao/core\\a.dart',
        'package:clashmiao/',
      ]) {
        final bad = checkLayering(
          scan({'core/x.dart': "export '$uri';"}),
          allowlist: const [],
        );
        expect(bad, hasLength(1), reason: uri);
        expect(bad.single.rule, '非规范 URI', reason: uri);
      }
    });

    test('app / main 里的 package 点段 URI 同样被报', () {
      final bad = checkLayering(
        scan({
          'app/x.dart': "export 'package:clashmiao/core/../domain/a.dart';",
          'main.dart': "import 'package:clashmiao/app/../core/a.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(2));
      expect(bad.every((v) => v.rule == '非规范 URI'), isTrue);
    });

    test('package 规范写法照常放行', () {
      expect(
        checkLayering(
          scan({
            'core/x.dart': "export 'package:clashmiao/core/storage/a.dart';",
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('R1：模型经 package 点段 URI 引用 application：被报，不是跳过', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart': "export 'package:clashmiao/domain/profile/model/../application/profile_providers.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'domain/profile/model/m.dart');
      expect(bad.single.hint, contains('model/../application'));
    });

    test('R1：传递链中途出现 package 点段 URI：被报', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart':
              "export 'package:clashmiao/core/u.dart';",
          'core/u.dart': "export 'package:clashmiao/core/../domain/x.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('core/u.dart'));
    });

    test('package 点段 URI 不会让 staleEntries 崩溃，也不会让白名单条目显得「在用」', () {
      final uris = scan({
        'features/a/x.dart':
            "import 'package:clashmiao/features/a/../b/y.dart';",
      });
      expect(
        staleEntries(uris, const [
          AllowedEdge('features/a/x.dart', 'features/b/y.dart', '点段'),
        ]),
        hasLength(1),
      );
    });

    test('feature 间依赖的失败提示引导解耦，不引导登记白名单', () {
      final bad = checkLayering(
        scan({
          'features/home/presentation/x.dart':
              "import 'package:clashmiao/features/logs/presentation/y.dart';",
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('路由入口解耦'));
      expect(bad.single.hint, isNot(contains('白名单')));
    });

    test('R1：模型引用 ../../../../core/u.dart 越出 lib/：被报，不是跳过', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart': "export '../../../../core/u.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'domain/profile/model/m.dart');
      expect(bad.single.to, '../../../../core/u.dart');
      expect(bad.single.hint, contains('请改用 package:clashmiao/ 导入'));
    });

    test('R1：传递链中途出现反斜杠写法：被报', () {
      final bad = checkModelPurity(
        scan({
          'domain/profile/model/m.dart':
              "export 'package:clashmiao/core/u.dart';",
          'core/u.dart': r"export r'..\core\v.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('core/u.dart'));
    });

    test('非规范 URI 不会让 staleEntries 崩溃，也不会让白名单条目显得「在用」', () {
      final uris = scan({'features/a/x.dart': r"import r'..\b\y.dart';"});
      expect(
        staleEntries(uris, const [
          AllowedEdge('features/a/x.dart', 'features/b/y.dart', '反斜杠'),
        ]),
        hasLength(1),
      );
    });

    test('app / main 只豁免依赖方向：非规范 URI 同样被报', () {
      final sources = {
        'app/x.dart': r"export r'..\core\a.dart';",
        'app/y.dart': "export '../../core/u.dart';", // 越出 lib/
        'main.dart': "export '../core/u.dart';", // 越出 lib/
      };
      final bad = checkLayering(scan(sources), allowlist: const []);
      expect(bad.map((v) => v.from).toSet(), sources.keys.toSet());
      expect(bad, hasLength(3));
      expect(bad.every((v) => v.rule == '非规范 URI'), isTrue);
    });

    test('app / main 的规范 package: 导入依赖任意层仍合规', () {
      expect(
        checkLayering(
          scan({
            'app/x.dart': """
import 'package:clashmiao/core/a.dart';
import 'package:clashmiao/shared/b.dart';
import 'package:clashmiao/domain/connection/c.dart';
import 'package:clashmiao/features/home/d.dart';
import './y.dart';
""",
            'main.dart': "import 'package:clashmiao/app/app.dart';",
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('白名单条目对应的依赖写成相对 URI 时不算过期', () {
      final uris = scan({'features/a/x.dart': "import '../b/y.dart';"});
      expect(
        staleEntries(uris, const [
          AllowedEdge('features/a/x.dart', 'features/b/y.dart', '相对写法'),
        ]),
        isEmpty,
      );
    });
  });
}
