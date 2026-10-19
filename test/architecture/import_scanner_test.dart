import 'package:flutter_test/flutter_test.dart';

import 'import_scanner.dart';

void main() {
  group('extractDirectiveUris', () {
    test('普通 import：单引号与双引号都能提取', () {
      expect(extractDirectiveUris("import 'package:clashmiao/a/b.dart';"), [
        'package:clashmiao/a/b.dart',
      ]);
      expect(extractDirectiveUris('import "package:clashmiao/a/b.dart";'), [
        'package:clashmiao/a/b.dart',
      ]);
    });

    test('同一行两条指令：两个都提取', () {
      expect(
        extractDirectiveUris(
          "import 'package:clashmiao/a.dart'; import 'package:clashmiao/b.dart';",
        ),
        ['package:clashmiao/a.dart', 'package:clashmiao/b.dart'],
      );
    });

    test('条件分支混用单双引号：每个分支都提取', () {
      expect(
        extractDirectiveUris(
          "import 'package:clashmiao/a.dart' "
          'if (dart.library.io) "package:clashmiao/b.dart" '
          "if (dart.library.html) 'package:clashmiao/c.dart';",
        ),
        [
          'package:clashmiao/a.dart',
          'package:clashmiao/b.dart',
          'package:clashmiao/c.dart',
        ],
      );
    });

    test('字符串里的伪指令不提取', () {
      expect(
        extractDirectiveUris('''
const s = "import 'package:clashmiao/fake.dart';";
const t = 'export "package:clashmiao/fake2.dart";';
'''),
        isEmpty,
      );
    });

    test('library 指令：不提取、不报错', () {
      expect(extractDirectiveUris('library foo;'), isEmpty);
    });

    test('跨多行并带 show / hide / as / deferred as 的 import', () {
      expect(
        extractDirectiveUris('''
import 'package:clashmiao/a.dart'
    show
        X,
        Y;
import 'package:clashmiao/b.dart'
    hide Z;
import 'package:clashmiao/c.dart' as p;
import 'package:clashmiao/d.dart'
    deferred as d;
'''),
        [
          'package:clashmiao/a.dart',
          'package:clashmiao/b.dart',
          'package:clashmiao/c.dart',
          'package:clashmiao/d.dart',
        ],
      );
    });

    test('export 也提取', () {
      expect(extractDirectiveUris("export 'package:clashmiao/c.dart';"), [
        'package:clashmiao/c.dart',
      ]);
    });

    test('import 条件分支：主 URI 与全部配置 URI 都提取', () {
      expect(
        extractDirectiveUris(
          "import 'package:clashmiao/a.dart' "
          "if (dart.library.io) 'package:clashmiao/b.dart' "
          "if (dart.library.html) 'package:clashmiao/c.dart';",
        ),
        [
          'package:clashmiao/a.dart',
          'package:clashmiao/b.dart',
          'package:clashmiao/c.dart',
        ],
      );
    });

    test('export 条件分支同样提取', () {
      expect(
        extractDirectiveUris(
          "export 'package:clashmiao/a.dart' "
          "if (dart.library.io) 'package:clashmiao/b.dart';",
        ),
        ['package:clashmiao/a.dart', 'package:clashmiao/b.dart'],
      );
    });

    test('part / part of 不提取', () {
      expect(extractDirectiveUris("part 'x.g.dart';"), isEmpty);
      expect(extractDirectiveUris("part of 'y.dart';"), isEmpty);
    });

    test('行注释与块注释里的 import 不提取', () {
      expect(
        extractDirectiveUris('''
// import 'package:clashmiao/fake.dart';
/* import 'package:clashmiao/fake2.dart'; */
/*
import 'package:clashmiao/fake3.dart';
*/
'''),
        isEmpty,
      );
    });

    test('混合场景：只返回真实指令，按出现顺序', () {
      expect(
        extractDirectiveUris('''
// import 'package:clashmiao/fake.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:clashmiao/a.dart';
part 'a.g.dart';
'''),
        [
          'dart:io',
          'package:flutter/material.dart',
          'package:clashmiao/a.dart',
        ],
      );
    });
  });

  group('projectPath', () {
    test('package:clashmiao/ 前缀被剥掉', () {
      expect(projectPath('package:clashmiao/x/y.dart'), 'x/y.dart');
    });

    test('其他 URI 返回 null', () {
      expect(projectPath('package:flutter/material.dart'), isNull);
      expect(projectPath('dart:io'), isNull);
      expect(projectPath('relative.dart'), isNull);
    });
  });

  group('projectPath：相对 URI 按导入方解析', () {
    test('同目录与上级目录', () {
      expect(projectPath('./b.dart', from: 'core/a.dart'), 'core/b.dart');
      expect(projectPath('b.dart', from: 'core/x/a.dart'), 'core/x/b.dart');
      expect(
        projectPath('../../domain/p/m.dart', from: 'core/storage/a.dart'),
        'domain/p/m.dart',
      );
    });

    test('跳出 lib/ 返回 null（规则层会把它报为违规，不是放过）', () {
      expect(projectPath('../../x.dart', from: 'core/a.dart'), isNull);
      expect(
        nonCanonicalRelativeUriReason('../../x.dart', from: 'core/a.dart'),
        contains('越出'),
      );
    });

    test('非规范写法：反斜杠、百分号、query/fragment、空段都有原因', () {
      for (final uri in [
        r'..\a.dart',
        '%2e%2e/a.dart',
        'a.dart?x',
        'a.dart#f',
        'b//a.dart',
        '/a.dart',
      ]) {
        expect(
          nonCanonicalRelativeUriReason(uri, from: 'core/x/a.dart'),
          isNotNull,
          reason: uri,
        );
        expect(projectPath(uri, from: 'core/x/a.dart'), isNull, reason: uri);
      }
    });

    test('规范写法与带 scheme 的 URI 没有「非规范」原因', () {
      for (final uri in [
        './b.dart',
        '../b.dart',
        'x/y.dart',
        '../../core/b.dart',
        'dart:io',
        'package:flutter/material.dart',
        'package:clashmiao/a.dart',
      ]) {
        expect(
          nonCanonicalRelativeUriReason(uri, from: 'core/x/a.dart'),
          isNull,
          reason: uri,
        );
      }
    });

    test('没有导入方路径的相对 URI、绝对路径、其他 scheme 返回 null', () {
      expect(projectPath('../a.dart'), isNull);
      expect(projectPath('/a.dart', from: 'core/a.dart'), isNull);
      expect(projectPath('dart:io', from: 'core/a.dart'), isNull);
      expect(
        projectPath('package:flutter/a.dart', from: 'core/a.dart'),
        isNull,
      );
      expect(projectPath('file:///x/a.dart', from: 'core/a.dart'), isNull);
    });
  });
}
