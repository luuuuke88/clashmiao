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
}
