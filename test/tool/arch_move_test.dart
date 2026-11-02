import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// tool/arch/move.dart 与 tool/arch/check_pure_move.sh 的黑盒测试：
/// 每个用例在临时目录里 `git init` 一个迷你仓库，再以子进程调用真实脚本。
void main() {
  final repoRoot = Directory.current.path;
  final moveScript = p.join(repoRoot, 'tool', 'arch', 'move.dart');
  final checkScript = p.join(repoRoot, 'tool', 'arch', 'check_pure_move.sh');

  late Directory repo;

  setUp(() {
    repo = Directory.systemTemp.createTempSync('arch_move_test_');
    _git(repo, ['init', '-q']);
    _git(repo, ['config', 'user.email', 'test@example.com']);
    _git(repo, ['config', 'user.name', 'test']);
    _git(repo, ['config', 'commit.gpgsign', 'false']);
    _seed(repo);
    _git(repo, ['add', '-A']);
    _git(repo, ['commit', '-q', '-m', 'base']);
  });

  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+rwx', repo.path]);
    repo.deleteSync(recursive: true);
  });

  ProcessResult move(List<String> args) => Process.runSync('dart', [
    moveScript,
    ...args,
  ], workingDirectory: repo.path);

  ProcessResult check(String base) =>
      Process.runSync('bash', [checkScript, base], workingDirectory: repo.path);

  String read(String rel) => File(p.join(repo.path, rel)).readAsStringSync();
  bool exists(String rel) => File(p.join(repo.path, rel)).existsSync();
  String status() => _git(repo, ['status', '--porcelain']);

  group('move.dart', () {
    test('目录移动：lib 与 test 镜像一起移动，四个根目录的 import 都改写', () {
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');

      expect(exists('lib/domain/config/a.dart'), isFalse);
      expect(exists('lib/features/config/a.dart'), isTrue);
      expect(exists('lib/features/config/sub/b.dart'), isTrue, reason: '保留子结构');
      expect(exists('test/features/config/a_test.dart'), isTrue);
      expect(exists('test/features/config/sub/b_test.dart'), isTrue);
      expect(exists('test/domain/config/a_test.dart'), isFalse);

      for (final f in [
        'lib/features/config/a.dart',
        'lib/domain/other.dart',
        'test/features/config/a_test.dart',
        'test/domain/other_test.dart',
        'integration_test/app_test.dart',
        'tool/uses.dart',
      ]) {
        expect(
          read(f),
          contains("'package:clashmiao/features/config/"),
          reason: f,
        );
        expect(read(f), isNot(contains("'package:clashmiao/domain/config/")));
      }
      // export 与条件 import 的分支也要改写。
      expect(
        read('lib/domain/other.dart'),
        contains("export 'package:clashmiao/features/config/sub/b.dart'"),
      );
      expect(
        read('lib/domain/other.dart'),
        contains(
          "if (dart.library.io) 'package:clashmiao/features/config/a.dart'",
        ),
      );
      // 迁移结果是 git 重命名（保留历史），不是删除加新增。
      expect(
        _git(repo, ['diff', '--cached', '--name-status', '-M']),
        contains('R'),
      );
    });

    test('路径前缀边界：domain/config 不得误伤 domain/configx', () {
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(
        read('lib/domain/other.dart'),
        contains("'package:clashmiao/domain/configx/c.dart'"),
      );
      expect(
        read('lib/domain/other.dart'),
        isNot(contains('features/configx')),
      );
      expect(exists('lib/domain/configx/c.dart'), isTrue);
      expect(exists('test/domain/configx/c_test.dart'), isTrue);
    });

    test('单文件移动：同时移动 test 下对应的 _test.dart', () {
      final r = move(['domain/other.dart', 'features/misc/other.dart']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(exists('lib/features/misc/other.dart'), isTrue);
      expect(exists('lib/domain/other.dart'), isFalse);
      expect(exists('test/features/misc/other_test.dart'), isTrue);
      expect(exists('test/domain/other_test.dart'), isFalse);
      // 其他文件对它的引用被改写。
      expect(
        read('lib/domain/configx/c.dart'),
        contains("'package:clashmiao/features/misc/other.dart'"),
      );
    });

    test('目标已存在：非 0 退出，原文件不动', () {
      final target = File(p.join(repo.path, 'lib/features/other.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// existing\n');
      final r = move(['domain/other.dart', 'features/other.dart']);
      expect(r.exitCode, isNot(0));
      expect(exists('lib/domain/other.dart'), isTrue);
      expect(exists('test/domain/other_test.dart'), isTrue);
      expect(target.readAsStringSync(), '// existing\n');
      expect(read('lib/domain/configx/c.dart'), contains('domain/other.dart'));
      // 唯一的改动是测试自己造的那个目标文件。
      expect(status().trim(), '?? lib/features/');
    });

    test('目录移动撞名：先检查全部再动手，一个文件都不移', () {
      File(p.join(repo.path, 'lib/features/config/sub/b.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('// existing\n');
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, isNot(0));
      expect(exists('lib/domain/config/a.dart'), isTrue);
      expect(exists('lib/domain/config/sub/b.dart'), isTrue);
      expect(exists('lib/features/config/a.dart'), isFalse);
      expect(exists('test/domain/config/a_test.dart'), isTrue);
    });

    test('--dry-run：打印计划，不修改任何文件', () {
      final r = move(['domain/config', 'features/config', '--dry-run']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(status(), isEmpty);
      expect(exists('lib/domain/config/a.dart'), isTrue);
      expect(exists('lib/features/config/a.dart'), isFalse);
      expect(r.stdout, contains('lib/domain/config/a.dart'));
      expect(r.stdout, contains('lib/features/config/a.dart'));
    });

    test('测试文件目录深度改变且含相对 import：非 0 退出，什么都不动', () {
      File(p.join(repo.path, 'test/domain/other_test.dart')).writeAsStringSync(
        "import '../support/helper.dart';\n"
        "import 'package:clashmiao/domain/other.dart';\n",
      );
      _git(repo, ['commit', '-qam', 'rel']);
      final r = move(['domain/other.dart', 'features/misc/other.dart']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('相对'));
      expect(status(), isEmpty);
      expect(exists('lib/domain/other.dart'), isTrue);
    });

    test('相对 import 指向一同移动的文件、相对关系不变：放行', () {
      File(p.join(repo.path, 'test/domain/config/a_test.dart'))
          .writeAsStringSync("import 'sub/b_test.dart';\n");
      _git(repo, ['commit', '-qam', 'rel-ok']);
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });

    test('lib 文件自己含相对 import 且被移动到别的目录：非 0 退出', () {
      File(p.join(repo.path, 'lib/domain/other.dart'))
          .writeAsStringSync("import 'configx/c.dart';\n");
      _git(repo, ['commit', '-qam', 'rel-lib']);
      final r = move(['domain/other.dart', 'features/other.dart']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('lib/domain/other.dart:configx/c.dart'));
      expect(status(), isEmpty);
    });

    test('单文件移动：test/<from> 本身也镜像移动', () {
      _write(repo, 'test/domain/other.dart', 'const helper2 = 1;\n');
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'helper']);
      final r = move(['domain/other.dart', 'features/misc/other.dart']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(exists('test/features/misc/other.dart'), isTrue);
      expect(exists('test/domain/other.dart'), isFalse);
      expect(exists('test/features/misc/other_test.dart'), isTrue);
    });

    test('单文件移动：test/<to> 已存在则整体拒绝，什么都不动', () {
      _write(repo, 'test/domain/other.dart', 'const helper2 = 1;\n');
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'helper']);
      _write(repo, 'test/features/misc/other.dart', '// existing\n');
      final r = move(['domain/other.dart', 'features/misc/other.dart']);
      expect(r.exitCode, isNot(0));
      expect(exists('lib/domain/other.dart'), isTrue);
      expect(exists('test/domain/other_test.dart'), isTrue);
      expect(exists('lib/features/misc/other.dart'), isFalse);
      expect(status().trim(), '?? test/features/');
    });

    test('目录移动：清单外的 <from>/... 引用也按路径段边界改写，configx 不动', () {
      _write(repo, 'lib/domain/uses_gen.dart', '''
import 'package:clashmiao/domain/config/gen/missing.g.dart';
import 'package:clashmiao/domain/configx/missing.g.dart';
''');
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'gen']);
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      final t = read('lib/domain/uses_gen.dart');
      expect(
        t,
        contains("'package:clashmiao/features/config/gen/missing.g.dart'"),
      );
      expect(t, contains("'package:clashmiao/domain/configx/missing.g.dart'"));
    });

    test('相关文件有未暂存修改：拒绝；已暂存的改动允许连续多次运行', () {
      File(p.join(repo.path, 'lib/domain/other.dart'))
          .writeAsStringSync('${read('lib/domain/other.dart')}// hand edit\n');
      var r = move(['domain/other.dart', 'features/other.dart']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('未暂存'));
      expect(exists('lib/domain/other.dart'), isTrue);

      _git(repo, ['checkout', '--', 'lib/domain/other.dart']);
      // 不提交，连续两次移动：第二次要处理第一次改写过的文件。
      r = move(['domain/config/sub/b.dart', 'features/b.dart']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      r = move(['domain/config/a.dart', 'features/a.dart']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(check('HEAD').exitCode, 0);
    });

    test('中途失败：回滚已完成的 git mv 与已改写的文件', () {
      if ((Process.runSync('id', ['-u']).stdout as String).trim() == '0') {
        return; // root 不受目录权限限制，无法制造失败。
      }
      Directory(p.join(repo.path, 'lib/features/config/sub'))
          .createSync(recursive: true);
      Process.runSync('chmod', [
        '555',
        p.join(repo.path, 'lib/features/config/sub'),
      ]);
      final r = move(['domain/config', 'features/config']);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('回滚'));
      expect(exists('lib/domain/config/a.dart'), isTrue);
      expect(exists('lib/domain/config/sub/b.dart'), isTrue);
      expect(exists('lib/features/config/a.dart'), isFalse);
      expect(exists('test/domain/config/a_test.dart'), isTrue);
      expect(read('lib/domain/other.dart'), contains('domain/config/a.dart'));
      expect(read('lib/domain/other.dart'), isNot(contains('features/config')));
      expect(status(), isEmpty);
    });

    test('源路径不存在 / 参数缺失：非 0 退出', () {
      expect(move(['domain/nope', 'features/nope']).exitCode, isNot(0));
      expect(move(['domain/config']).exitCode, isNot(0));
      expect(status(), isEmpty);
    });
  });

  group('check_pure_move.sh', () {
    test('只有重命名与 import 改写：退出码 0', () {
      final r0 = move(['domain/config', 'features/config']);
      expect(r0.exitCode, 0, reason: '${r0.stdout}\n${r0.stderr}');
      final r = check('HEAD');
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });

    test('提交后相对 base 仍为 0', () {
      final base = _git(repo, ['rev-parse', 'HEAD']).trim();
      move(['domain/config', 'features/config']);
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'moved']);
      final r = check(base);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });

    test('多改了一行代码：退出码 1，并打印违规行', () {
      move(['domain/config', 'features/config']);
      File(p.join(repo.path, 'lib/features/config/a.dart')).writeAsStringSync(
        '${read('lib/features/config/a.dart')}const sneaky = 1;\n',
      );
      final r = check('HEAD');
      expect(r.exitCode, 1);
      expect('${r.stdout}${r.stderr}', contains('const sneaky = 1;'));
    });

    test('原地改了一行非 import 代码：退出码 1', () {
      File(p.join(repo.path, 'lib/domain/other.dart')).writeAsStringSync(
        '${read('lib/domain/other.dart')}const sneaky = 1;\n',
      );
      expect(check('HEAD').exitCode, 1);
    });

    test('同一行夹带代码（import 行后接 void changed）：退出码 1', () {
      move(['domain/config', 'features/config']);
      final f = File(p.join(repo.path, 'lib/features/config/a.dart'));
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst(
          "sub/b.dart';",
          "sub/b.dart'; void changed() {}",
        ),
      );
      final r = check('HEAD');
      expect(r.exitCode, 1);
      expect('${r.stdout}${r.stderr}', contains('void changed'));
    });

    test('原地改写的 import 行夹带代码：退出码 1', () {
      final f = File(p.join(repo.path, 'lib/domain/other.dart'));
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst(
          "domain/configx/c.dart';",
          "domain/configx/c.dart'; void changed() {}",
        ),
      );
      expect(check('HEAD').exitCode, 1);
    });

    test('import 行除路径外还改了 as / show：退出码 1', () {
      final f = File(p.join(repo.path, 'lib/domain/configx/c.dart'));
      f.writeAsStringSync(
        f.readAsStringSync().replaceFirst("other.dart';", "other.dart' as o;"),
      );
      final r = check('HEAD');
      expect(r.exitCode, 1);
      expect('${r.stdout}${r.stderr}', contains('除路径外'));
    });

    test('只新增一条 import（没有对应删除）：退出码 1', () {
      final f = File(p.join(repo.path, 'lib/domain/configx/c.dart'));
      f.writeAsStringSync(
        "import 'package:clashmiao/domain/config/a.dart';\n${f.readAsStringSync()}",
      );
      final r = check('HEAD');
      expect(r.exitCode, 1);
      expect('${r.stdout}${r.stderr}', contains('数量不一致'));
    });

    test('低相似度的重命名夹带非 import 改动（小文件）：退出码 1', () {
      _write(
        repo,
        'lib/domain/tiny.dart',
        "import 'package:clashmiao/domain/other.dart';\nconst t = 1;\n",
      );
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'tiny']);
      Directory(p.join(repo.path, 'lib/features')).createSync(recursive: true);
      _git(repo, ['mv', 'lib/domain/tiny.dart', 'lib/features/tiny.dart']);
      _write(
        repo,
        'lib/features/tiny.dart',
        "import 'package:clashmiao/features/other.dart';\nconst t = 2;\n",
      );
      final r = check('HEAD');
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
    });

    test('被识别为重命名、同时改了一行非 import 代码：退出码 1', () {
      final body = [for (var i = 0; i < 30; i++) 'const v$i = $i;'].join('\n');
      _write(
        repo,
        'lib/domain/big.dart',
        "import 'package:clashmiao/domain/other.dart';\n$body\n",
      );
      _git(repo, ['add', '-A']);
      _git(repo, ['commit', '-qm', 'big']);
      Directory(p.join(repo.path, 'lib/features')).createSync(recursive: true);
      _git(repo, ['mv', 'lib/domain/big.dart', 'lib/features/big.dart']);
      _write(
        repo,
        'lib/features/big.dart',
        "import 'package:clashmiao/features/other.dart';\n"
            '${body.replaceFirst('const v7 = 7;', 'const v7 = 8;')}\n',
      );
      // 确认这个用例确实走的是"重命名 + 内容改动"路径。
      final ns = _git(repo, [
        'diff',
        '-M',
        '--find-renames=1%',
        '--name-status',
        'HEAD',
      ]);
      expect(ns, contains('R'));
      final r = check('HEAD');
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect('${r.stdout}${r.stderr}', contains('const v7 = 8;'));
    });

    test('新增文件（哪怕只有 import）：退出码 1', () {
      File(p.join(repo.path, 'lib/domain/new.dart'))
          .writeAsStringSync("import 'package:clashmiao/domain/other.dart';\n");
      _git(repo, ['add', '-A']);
      expect(check('HEAD').exitCode, 1);
    });

    test('未跟踪的新文件：退出码 1', () {
      File(p.join(repo.path, 'lib/domain/stray.dart')).writeAsStringSync('\n');
      expect(check('HEAD').exitCode, 1);
    });

    test('删除文件：退出码 1', () {
      _git(repo, ['rm', '-q', 'lib/domain/configx/c.dart']);
      expect(check('HEAD').exitCode, 1);
    });

    test('无任何改动：退出码 0；缺少参数：退出码 2', () {
      expect(check('HEAD').exitCode, 0);
      final r = Process.runSync('bash', [
        checkScript,
      ], workingDirectory: repo.path);
      expect(r.exitCode, 2);
    });
  });
}

String _git(Directory repo, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: repo.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} 失败：${r.stderr}');
  }
  return r.stdout as String;
}

void _write(Directory repo, String rel, String content) {
  File(p.join(repo.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

void _seed(Directory repo) {
  _write(repo, 'lib/domain/config/a.dart', '''
import 'package:clashmiao/domain/config/sub/b.dart';
import 'package:clashmiao/domain/configx/c.dart';

const a = 1;
''');
  _write(repo, 'lib/domain/config/sub/b.dart', 'const b = 2;\n');
  _write(repo, 'lib/domain/configx/c.dart', '''
import 'package:clashmiao/domain/other.dart';

const c = 3;
''');
  _write(repo, 'lib/domain/other.dart', '''
import 'package:clashmiao/domain/config/a.dart';
import 'package:clashmiao/domain/configx/c.dart';
export 'package:clashmiao/domain/config/sub/b.dart'
    show b;
import 'dart:async'
    if (dart.library.io) 'package:clashmiao/domain/config/a.dart';

const other = 4;
''');
  _write(repo, 'test/domain/config/a_test.dart', '''
import 'package:clashmiao/domain/config/a.dart';

void main() {}
''');
  _write(repo, 'test/domain/config/sub/b_test.dart', '''
import 'package:clashmiao/domain/config/sub/b.dart';

void main() {}
''');
  _write(repo, 'test/domain/configx/c_test.dart', '''
import 'package:clashmiao/domain/configx/c.dart';

void main() {}
''');
  _write(repo, 'test/domain/other_test.dart', '''
import 'package:clashmiao/domain/config/a.dart';
import 'package:clashmiao/domain/other.dart';

void main() {}
''');
  _write(repo, 'test/support/helper.dart', 'const helper = 1;\n');
  _write(repo, 'integration_test/app_test.dart', '''
import 'package:clashmiao/domain/config/a.dart';

void main() {}
''');
  _write(repo, 'tool/uses.dart', '''
import 'package:clashmiao/domain/config/sub/b.dart';

void main() {}
''');
}
