import 'package:flutter_test/flutter_test.dart';

import 'import_scanner.dart';
import 'layering_rules.dart';

/// 合成数据里的 import 一律写成 `package:clashmiao/...`，与真实源码一致。
String pkg(String path) => 'package:clashmiao/$path';

Map<String, List<String>> graph(Map<String, List<String>> edges) => {
  for (final e in edges.entries) e.key: [for (final t in e.value) pkg(t)],
};

void main() {
  group('checkLayering：层间规则', () {
    test('core → domain 违规；core → core 合规', () {
      final bad = checkLayering(
        graph({
          'core/a.dart': ['domain/x/b.dart'],
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'core/a.dart');
      expect(bad.single.to, 'domain/x/b.dart');

      expect(
        checkLayering(
          graph({
            'core/a.dart': ['core/b.dart'],
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('shared → features 违规；shared → core / shared 合规', () {
      expect(
        checkLayering(
          graph({
            'shared/a.dart': ['features/x/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
      expect(
        checkLayering(
          graph({
            'shared/a.dart': ['core/b.dart', 'shared/c.dart'],
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('shared → domain 违规（shared 只能依赖 core / shared）', () {
      expect(
        checkLayering(
          graph({
            'shared/a.dart': ['domain/profile/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
    });

    test('domain 顺序倒置违规；顺序正确合规', () {
      final bad = checkLayering(
        graph({
          'domain/profile/a.dart': ['domain/routing/b.dart'],
        }),
        allowlist: const [],
      );
      expect(bad, hasLength(1));
      expect(bad.single.from, 'domain/profile/a.dart');
      expect(bad.single.to, 'domain/routing/b.dart');

      expect(
        checkLayering(
          graph({
            'domain/routing/a.dart': ['domain/profile/b.dart'],
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('domain 顺序：同一概念内部、依赖 core 都合规', () {
      expect(
        checkLayering(
          graph({
            'domain/profile/a.dart': [
              'domain/profile/model/b.dart',
              'core/c.dart',
              'domain/config/d.dart',
            ],
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('domain → features / shared / app 违规', () {
      for (final target in [
        'features/x/b.dart',
        'shared/b.dart',
        'app/b.dart',
      ]) {
        expect(
          checkLayering(
            graph({
              'domain/config/a.dart': [target],
            }),
            allowlist: const [],
          ),
          hasLength(1),
          reason: target,
        );
      }
    });

    test('features → 其他 feature 违规；在白名单里则合规', () {
      final uris = graph({
        'features/home/a.dart': ['features/config/b.dart'],
      });
      expect(checkLayering(uris, allowlist: const []), hasLength(1));
      expect(
        checkLayering(
          uris,
          allowlist: const [
            AllowedEdge('features/home/a.dart', 'features/config/b.dart', '测试'),
          ],
        ),
        isEmpty,
      );
    });

    test('features → 自己 / domain / core / shared 合规', () {
      expect(
        checkLayering(
          graph({
            'features/home/a.dart': [
              'features/home/b.dart',
              'domain/profile/c.dart',
              'core/d.dart',
              'shared/e.dart',
            ],
          }),
          allowlist: const [],
        ),
        isEmpty,
      );
    });

    test('features → app 违规', () {
      expect(
        checkLayering(
          graph({
            'features/home/a.dart': ['app/x.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
    });

    test('白名单只豁免 feature 之间的边：非 feature 条目仍报违规，并额外报条目非法', () {
      final bad = checkLayering(
        graph({
          'core/a.dart': ['domain/x/b.dart'],
        }),
        allowlist: const [
          AllowedEdge('core/a.dart', 'domain/x/b.dart', '企图夹带'),
        ],
      );
      expect(bad, hasLength(2));
      expect(bad.where((v) => v.rule == '白名单条目非法'), hasLength(1));
      expect(
        bad.where((v) => v.rule != '白名单条目非法' && v.from == 'core/a.dart'),
        hasLength(1),
      );
    });

    test('白名单条目只有一端在 features 下同样非法', () {
      final bad = checkLayering(
        graph({
          'features/home/a.dart': ['app/x.dart'],
        }),
        allowlist: const [
          AllowedEdge('features/home/a.dart', 'app/x.dart', '企图夹带'),
        ],
      );
      expect(bad.where((v) => v.rule == '白名单条目非法'), hasLength(1));
      // features → app 本身仍然违规，没有被豁免。
      expect(bad, hasLength(2));
    });

    test('app 与 main.dart 依赖任意层都合规', () {
      expect(
        checkLayering(
          graph({
            'app/x.dart': [
              'core/a.dart',
              'shared/b.dart',
              'domain/connection/c.dart',
              'features/home/d.dart',
              'app/y.dart',
            ],
            'main.dart': [
              'app/app.dart',
              'core/a.dart',
              'features/home/d.dart',
            ],
          }),
          allowlist: const [],
        ),
        isEmpty,
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
        checkLayering(
          graph({
            'core/a.g.dart': ['domain/x/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
    });

    test('不在已知层里的文件与目标：报违规，不静默放过', () {
      expect(
        checkLayering(
          graph({
            'stray/a.dart': ['core/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
      expect(
        checkLayering(
          graph({
            'core/a.dart': ['stray/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
    });

    test('domain 概念不在固定顺序里：报违规', () {
      expect(
        checkLayering(
          graph({
            'domain/unknown/a.dart': ['core/b.dart'],
          }),
          allowlist: const [],
        ),
        hasLength(1),
      );
    });

    test('Violation.toString 形如 from → to · rule · hint', () {
      const v = Violation('a.dart', 'b.dart', '规则', '提示');
      expect(v.toString(), 'a.dart → b.dart · 规则 · 提示');
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
    AllowedEdge feat(int i) =>
        AllowedEdge('features/a/p$i.dart', 'features/b/q$i.dart', '合成');

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
          'features/a/extra.dart',
          'features/b/extra.dart',
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
          'features/a/x.dart': "import 'package:clashmiao/features/b/y.dart';",
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
