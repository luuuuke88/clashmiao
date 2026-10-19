import 'package:flutter_test/flutter_test.dart';

import 'allowlist.dart';
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

  group('白名单上限', () {
    test('超过 kAllowlistCeiling 的比较逻辑成立', () {
      final six = [
        for (var i = 0; i < kAllowlistCeiling + 1; i++)
          AllowedEdge('features/a/$i.dart', 'features/b/$i.dart', '合成'),
      ];
      expect(six.length <= kAllowlistCeiling, isFalse);
      expect(six.take(kAllowlistCeiling).length <= kAllowlistCeiling, isTrue);
    });
  });
}
