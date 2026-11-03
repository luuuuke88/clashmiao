import 'package:flutter_test/flutter_test.dart';

import 'import_scanner.dart';
import 'layering_rules.dart';

/// 合成数据里的 import 一律写成 `package:clashmiao/...`，与真实源码一致。
String pkg(String path) => 'package:clashmiao/$path';

Map<String, List<String>> graph(Map<String, List<String>> edges) => {
  for (final e in edges.entries) e.key: [for (final t in e.value) pkg(t)],
};

void main() {
  group('logicalUnitOf：按逻辑功能归位', () {
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

    test('features/config 下一律是 config，不再按文件名拆分', () {
      for (final f in [
        'features/config/data/backup_engine.dart',
        'features/config/application/restore_refresher.dart',
        'features/config/presentation/config_options_page.dart',
        'features/config/presentation/dns_strategy_messages.dart',
      ]) {
        expect(logicalUnitOf(f)!.feature, 'config', reason: f);
      }
    });

    test('features/<f>/<layer>', () {
      expectUnit(
        'features/profile/data/migrations/v1_profiles.dart',
        'profile',
        Tier.capability,
        'data',
      );
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

    test('未登记的功能、能力型功能的散文件、lib/domain/ 下的一切：返回 null', () {
      for (final p in [
        'features/unknown/model/a.dart',
        'features/unknown/presentation/a.dart',
        'features/profile/a.dart',
        'features/a.dart',
        'domain/profile/model/a.dart',
        'domain/routing/application/a.dart',
        'domain/home/presentation/a.dart',
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
    List<Violation> check(Map<String, List<String>> edges) =>
        checkLayering(graph(edges));

    group('规则 1：能力型的非页面层只能依赖更低的能力型非页面层与 core', () {
      test('profile application → proxy application：违规', () {
        final bad = check({
          'features/profile/application/a.dart': [
            'features/proxy/application/b.dart',
          ],
        });
        expect(bad, hasLength(1));
        expect(bad.single.from, 'features/profile/application/a.dart');
        expect(bad.single.to, 'features/proxy/application/b.dart');
      });

      test('proxy application → profile application：合规', () {
        expect(
          check({
            'features/proxy/application/a.dart': [
              'features/profile/application/b.dart',
            ],
          }),
          isEmpty,
        );
      });

      test('各层都按 kCapabilityOrder 判：backup 可依赖全部更低者，反之违规', () {
        expect(
          check({
            'features/backup/data/backup_engine.dart': [
              'features/config/data/a.dart',
              'features/profile/data/b.dart',
              'features/proxy/data/c.dart',
              'features/connection/application/d.dart',
              'core/e.dart',
            ],
          }),
          isEmpty,
        );
        expect(
          check({
            'features/connection/application/a.dart': [
              'features/backup/data/backup_engine.dart',
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
              'features/proxy/application/a.dart': [target],
            }),
            hasLength(1),
            reason: target,
          );
        }
      });

      test('非页面层依赖 core 合规', () {
        expect(
          check({
            'features/profile/data/a.dart': ['core/b.dart'],
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
              'features/proxy/application/b.dart',
              'features/connection/model/c.dart',
              'features/backup/data/backup_engine.dart',
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
              'features/connection/application/c.dart',
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
        expect(bad.single.hint, contains('AppRouteScope'));
      });
    });

    group('规则 4 不在 checkLayering 里判（单独的 checkIntraFeatureDirection）', () {
      test('同功能内 data → application 不算层间违规', () {
        expect(
          check({
            'features/profile/data/a.dart': [
              'features/profile/application/b.dart',
            ],
          }),
          isEmpty,
        );
      });
    });

    group('core / shared / app 的原有规则', () {
      test('core → 非 core 违规；core → core 合规', () {
        final bad = check({
          'core/a.dart': ['features/profile/model/b.dart'],
        });
        expect(bad, hasLength(1));
        expect(bad.single.from, 'core/a.dart');
        expect(bad.single.to, 'features/profile/model/b.dart');
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
          'features/profile/model/b.dart',
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
              'features/connection/application/c.dart',
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
          }),
          isEmpty,
        );
      });

      test('*.g.dart 按所在目录归层，不豁免', () {
        expect(
          check({
            'core/a.g.dart': ['features/profile/model/b.dart'],
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
            'features/unknown/model/a.dart': ['core/b.dart'],
            'features/unknown/presentation/a.dart': ['core/b.dart'],
          }),
          hasLength(2),
        );
      });

      test('能力型功能的散文件（不在分层目录里）：违规', () {
        expect(
          check({
            'features/profile/a.dart': ['core/b.dart'],
          }),
          hasLength(1),
        );
      });

      test('lib/domain/ 下的任何文件即违规（不论内容、不论是否有 import）', () {
        for (final path in [
          'domain/profile/model/a.dart',
          'domain/routing/application/b.dart',
          'domain/x.dart',
        ]) {
          final bad = check({path: <String>[]});
          expect(bad, hasLength(1), reason: path);
          expect(bad.single.from, path);
          expect(bad.single.hint, contains('lib/domain/'), reason: path);
        }
        // 依赖 lib/domain/ 下的目标同样违规。
        final dep = check({
          'features/profile/application/a.dart': [
            'domain/profile/model/m.dart',
          ],
        });
        expect(dep, hasLength(1));
        expect(dep.single.hint, contains('lib/domain/'));
        // 只要文件位于 lib/domain/ 下即违规，与它引用什么无关。
        expect(
          check({
            'domain/a.dart': ['core/b.dart'],
          }),
          hasLength(1),
        );
      });

      test('依赖目标是未登记的功能：违规', () {
        expect(
          check({
            'features/home/presentation/a.dart': [
              'features/unknown/model/b.dart',
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
        'features/profile/data/a.dart': ['features/profile/application/b.dart'],
      });
      expect(bad, hasLength(1));
      expect(bad.single.from, 'features/profile/data/a.dart');
      expect(bad.single.to, 'features/profile/application/b.dart');
    });

    test('model → 任何更高层、application → presentation：违规', () {
      expect(
        intra({
          'features/profile/model/a.dart': ['features/profile/data/b.dart'],
          'features/profile/application/c.dart': [
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
            'features/profile/application/b.dart',
            'features/profile/data/c.dart',
            'features/profile/model/d.dart',
            'features/profile/presentation/e.dart',
          ],
          'features/profile/application/b.dart': [
            'features/profile/data/c.dart',
            'features/profile/model/d.dart',
          ],
          'features/profile/data/c.dart': ['features/profile/model/d.dart'],
        }),
        isEmpty,
      );
    });

    test('只判同一个逻辑功能：跨功能的反向不归它管', () {
      expect(
        intra({
          'features/profile/model/a.dart': [
            'features/proxy/application/b.dart',
          ],
        }),
        isEmpty,
      );
    });

    test('backup 与 config 是两个功能', () {
      expect(
        intra({
          'features/backup/data/backup_engine.dart': [
            'features/config/application/a.dart',
          ],
        }),
        isEmpty,
      );
    });

    test('非项目内 URI、不认识的位置不报（交给 checkLayering）', () {
      expect(
        checkIntraFeatureDirection({
          'features/profile/data/a.dart': [
            'package:flutter/material.dart',
            'dart:io',
          ],
          'stray/a.dart': [pkg('features/profile/application/b.dart')],
        }),
        isEmpty,
      );
    });
  });

  group('checkPageConstruction：规则 6 页面只在 app 构造', () {
    const settingsPage = 'features/settings/presentation/settings_page.dart';
    const optionsPage =
        'features/options/presentation/config_options_page.dart';
    const defs = {
      settingsPage: 'class SettingsPage extends StatelessWidget {}',
      optionsPage: 'class ConfigOptionsPage extends StatelessWidget {}',
    };

    List<Violation> page(Map<String, String> more) =>
        checkPageConstruction({...defs, ...more});

    test('home 构造 SettingsPage：违规', () {
      final bad = page({
        'features/home/presentation/home_page.dart':
            'void f() { push(const SettingsPage()); }',
      });
      expect(bad, hasLength(1));
      expect(bad.single.from, 'features/home/presentation/home_page.dart');
      expect(bad.single.to, settingsPage);
    });

    test('app/router 构造 SettingsPage：合规', () {
      expect(
        page({'app/router/routes.dart': 'final p = const SettingsPage();'}),
        isEmpty,
      );
    });

    test('页面所在功能自己引用自己的页面与子组件：合规', () {
      expect(
        page({
          'features/settings/presentation/per_app_proxy_page.dart':
              'void f() { push(const SettingsPage()); }',
          'features/options/presentation/sub.dart': 'class OptionsSection {}',
          optionsPage: 'class ConfigOptionsPage { Widget b() => const OptionsSection(); }',
        }),
        isEmpty,
      );
    });

    test('功能按逻辑功能判定（config_options_page 属于 options）', () {
      final bad = checkPageConstruction({
        'features/options/presentation/options_page.dart':
            'class OptionsPage {}',
        'features/home/presentation/a.dart': 'OptionsPage();',
        optionsPage: 'class ConfigOptionsPage {}',
        'features/logs/presentation/b.dart': 'ConfigOptionsPage();',
        // 同属 options 功能：合规。
        'features/options/presentation/c.dart': 'ConfigOptionsPage();',
      });
      expect(bad.map((v) => v.from).toSet(), {
        'features/home/presentation/a.dart',
        'features/logs/presentation/b.dart',
      });
    });

    test('core / shared / 能力型功能的非页面层引用别的功能的页面：同样违规', () {
      final bad = page({
        'core/a.dart': 'SettingsPage();',
        'shared/b.dart': 'SettingsPage();',
        'features/profile/application/c.dart': 'SettingsPage();',
        'main.dart': 'SettingsPage();',
      });
      expect(bad, hasLength(4));
    });

    test('只算 Page 结尾的公开类，且必须声明在 presentation 层', () {
      expect(
        checkPageConstruction({
          'features/settings/presentation/x.dart':
              'class _HiddenPage {} class SettingsSection {}',
          'features/settings/application/y.dart': 'class HelperPage {}',
          'features/home/presentation/h.dart':
              '_HiddenPage(); SettingsSection(); HelperPage();',
        }),
        isEmpty,
      );
    });

    test('注释里提到页面名不算引用；标识符必须整词匹配', () {
      expect(
        page({
          'features/home/presentation/a.dart': '''
// 跳转到 SettingsPage
/// 见 [SettingsPage]
/* SettingsPage */
final url = 'https://x.test'; // SettingsPageExtra
class MySettingsPageHelper {}
''',
        }),
        isEmpty,
      );
    });

    test('同一文件对同一页面只报一次', () {
      expect(
        page({
          'features/home/presentation/a.dart':
              'SettingsPage(); SettingsPage();',
        }),
        hasLength(1),
      );
    });
  });

  group('checkModelPurity：R1 模型纯净', () {
    const model = 'features/profile/model/m.dart';

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
          model: ['dart:convert', pkg('features/profile/model/n.dart')],
          'features/profile/model/n.dart': ['dart:core'],
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
        model: [pkg('features/profile/data/d.dart')],
        'features/profile/data/d.dart': [],
      });
      expect(d, hasLength(1));
      expect(d.single.to, 'features/profile/data/d.dart');

      final a = checkModelPurity({
        model: [pkg('features/config/application/x.dart')],
      });
      expect(a, hasLength(1));
      expect(a.single.to, 'features/config/application/x.dart');
    });

    test('经由中间文件传递触达 data 同样报', () {
      final bad = checkModelPurity({
        model: [pkg('core/u.dart')],
        'core/u.dart': [pkg('features/profile/data/d.dart')],
      });
      expect(bad, hasLength(1));
    });

    test('data 一侧再引 flutter：只在 data 这一环止步报一次，不重复刷屏', () {
      final bad = checkModelPurity({
        model: [pkg('features/profile/data/d.dart')],
        'features/profile/data/d.dart': ['package:flutter/material.dart'],
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
        'features/backup/data/backup_engine.dart',
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
          'features/profile/application/a.dart': [
            'package:flutter/material.dart',
          ],
        }),
        isEmpty,
      );
    });
  });

  group('相对 URI：扫描源码 → 规则判定（端到端）', () {
    /// 把 {文件路径: 源码} 扫描成 uris，再交给规则。
    Map<String, List<String>> scan(Map<String, String> sources) => {
      for (final e in sources.entries) e.key: extractDirectiveUris(e.value),
    };

    test('(a) core 里相对 export 到 features：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/a.dart':
              "export '../../features/profile/model/m.dart';",
          'features/profile/model/m.dart': '',
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/a.dart');
      expect(bad.single.to, 'features/profile/model/m.dart');
    });

    test('(b) 条件导入的相对 if 分支 core → features：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/a.dart': """
import 'package:clashmiao/core/storage/stub.dart'
    if (dart.library.io) '../../features/profile/model/m.dart';
""",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.to, 'features/profile/model/m.dart');
    });

    test('(c) R1：模型经相对 export 链触达 application：被报并带传递链', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart': "export '../../../core/u.dart';",
          'core/u.dart': "export '../features/profile/application/svc.dart';",
          'features/profile/application/svc.dart': '',
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'features/profile/model/m.dart');
      expect(bad.single.to, 'features/profile/application/svc.dart');
      expect(
        bad.single.hint,
        contains(
          'features/profile/model/m.dart → core/u.dart → features/profile/application/svc.dart',
        ),
      );
    });

    test('(c2) R1：相对 export 链通到 flutter 也被报', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart': "export './n.dart';",
          'features/profile/model/n.dart':
              "import 'package:flutter/material.dart';",
        }),
      );
      // m 与 n 都是模型，各自触达 flutter 一次；m 的那条要带上经过 n 的链。
      final fromM = bad.where((v) => v.from == 'features/profile/model/m.dart');
      expect(fromM, hasLength(1));
      expect(fromM.single.to, 'package:flutter/material.dart');
      expect(
        fromM.single.hint,
        contains('model/m.dart → features/profile/model/n.dart'),
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
        ),
        isEmpty,
      );
    });

    test('反斜杠写法 core → features：被报（不再漏）', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              r"export r'..\..\features\profile\model\profile_entity.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/x.dart');
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.hint, contains('请改用 package:clashmiao/ 导入'));
      expect(bad.single.hint, contains(r'..\..\features'));
    });

    test('百分号转义 %2e%2e 写法：被报', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              "export '%2e%2e/%2e%2e/features/profile/model/m.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.to, contains('%2e%2e'));
    });

    test('多余的 .. 越出 lib/：被报，不是跳过', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart':
              "export '../../../features/profile/model/m.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.rule, '非规范 URI');
      expect(
        bad.single.hint,
        contains('../../../features/profile/model/m.dart'),
      );
    });

    test('query / fragment / 空段 / 绝对路径写法：被报', () {
      for (final uri in ['a.dart?x=1', 'a.dart#f', 'b//a.dart', '/a.dart']) {
        final bad = checkLayering(scan({'core/x.dart': "export '$uri';"}));
        expect(bad, hasLength(1), reason: uri);
      }
    });

    test('package URI 含 .. 点段 core → features：被报（不再被当作 core）', () {
      final bad = checkLayering(
        scan({
          'core/storage/x.dart': "export 'package:clashmiao/core/../features/profile/application/profile_providers.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/storage/x.dart');
      expect(bad.single.rule, '非规范 URI');
      expect(bad.single.hint, contains('core/../features'));
    });

    test('package URI 的 . 段、空段、转义、query/fragment、反斜杠：都被报', () {
      for (final uri in [
        'package:clashmiao/core/./a.dart',
        'package:clashmiao/core//a.dart',
        'package:clashmiao/core/%2e%2e/features/a.dart',
        'package:clashmiao/core/a.dart?x=1',
        'package:clashmiao/core/a.dart#f',
        r'package:clashmiao/core\\a.dart',
        'package:clashmiao/',
      ]) {
        final bad = checkLayering(scan({'core/x.dart': "export '$uri';"}));
        expect(bad, hasLength(1), reason: uri);
        expect(bad.single.rule, '非规范 URI', reason: uri);
      }
    });

    test('app / main 里的 package 点段 URI 同样被报', () {
      final bad = checkLayering(
        scan({
          'app/x.dart': "export 'package:clashmiao/core/../features/a.dart';",
          'main.dart': "import 'package:clashmiao/app/../core/a.dart';",
        }),
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
        ),
        isEmpty,
      );
    });

    test('R1：模型经 package 点段 URI 引用 application：被报，不是跳过', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart': "export 'package:clashmiao/features/profile/model/../application/profile_providers.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'features/profile/model/m.dart');
      expect(bad.single.hint, contains('model/../application'));
    });

    test('R1：传递链中途出现 package 点段 URI：被报', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart':
              "export 'package:clashmiao/core/u.dart';",
          'core/u.dart': "export 'package:clashmiao/core/../features/x.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('core/u.dart'));
    });

    test('feature 间依赖的失败提示引导走 AppRouteScope 解耦，没有白名单可登记', () {
      final bad = checkLayering(
        scan({
          'features/home/presentation/x.dart':
              "import 'package:clashmiao/features/logs/presentation/y.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('AppRouteScope'));
      expect(bad.single.hint, isNot(contains('白名单')));
    });

    test('R1：模型引用 ../../../../core/u.dart 越出 lib/：被报，不是跳过', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart': "export '../../../../core/u.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'features/profile/model/m.dart');
      expect(bad.single.to, '../../../../core/u.dart');
      expect(bad.single.hint, contains('请改用 package:clashmiao/ 导入'));
    });

    test('R1：传递链中途出现反斜杠写法：被报', () {
      final bad = checkModelPurity(
        scan({
          'features/profile/model/m.dart':
              "export 'package:clashmiao/core/u.dart';",
          'core/u.dart': r"export r'..\core\v.dart';",
        }),
      );
      expect(bad, hasLength(1));
      expect(bad.single.hint, contains('core/u.dart'));
    });

    test('app / main 只豁免依赖方向：非规范 URI 同样被报', () {
      final sources = {
        'app/x.dart': r"export r'..\core\a.dart';",
        'app/y.dart': "export '../../core/u.dart';", // 越出 lib/
        'main.dart': "export '../core/u.dart';", // 越出 lib/
      };
      final bad = checkLayering(scan(sources));
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
import 'package:clashmiao/features/connection/c.dart';
import 'package:clashmiao/features/home/d.dart';
import './y.dart';
""",
            'main.dart': "import 'package:clashmiao/app/app.dart';",
          }),
        ),
        isEmpty,
      );
    });
  });
}
