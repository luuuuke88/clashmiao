// 纯移动工具：把 lib/<from> 移到 lib/<to>，并同步改写全仓的 package import。
//
// 用法（在仓库任意子目录执行均可，路径相对 lib/）：
//   dart run tool/arch/move.dart <from> <to> [--dry-run]
//   dart run tool/arch/move.dart domain/config features/config
//   dart run tool/arch/move.dart features/config/data/backup_engine.dart \
//       features/backup/data/backup_engine.dart
//
// 做什么：
//   1. `<from>` 是文件或目录（相对 lib/，目录整体移动并保留子结构）。用 `git mv`，
//      保留历史。
//   2. test/ 下的镜像一起移动：目录对应 test/<from>/；文件 x.dart 对应
//      test/x_test.dart（`_test.dart` 同步处理）。镜像不存在就跳过。
//   3. lib/ test/ integration_test/ tool/ 里所有 `import|export|part` 指令中的
//      `package:clashmiao/<旧路径>` 改写为新路径。按**完整文件路径**精确匹配，
//      所以移动 domain/config 不会误伤 domain/configx。条件 import 的
//      `if (...) '...'` 分支同样处理。
//   4. 相对路径 import / part：移动后相对关系变了（含指向被移动文件的、以及被移动文件
//      自己的）就报错退出，要求人工处理，不做猜测。
//
// 安全：
//   - 先做完全部检查再动手；任何一项不通过都是"什么都没改"就退出。
//   - 目标文件已存在 -> 报错，绝不覆盖。目录移动时目标目录可以已存在（合并），
//     但只要有一个同名文件就整体拒绝。
//   - 只移动 git 已跟踪的文件；未跟踪 / 被忽略的文件留在原地并提示。
//   - `--dry-run` 只打印计划。
//
// 退出码：0 成功；1 检查不通过；2 参数错误。
//
// 只依赖 dart:core / dart:io，可以在任意工作目录用 `dart <脚本路径>` 直接运行。
import 'dart:convert';
import 'dart:io';

const _usage =
    '用法：dart run tool/arch/move.dart <from> <to> [--dry-run]\n'
    '  <from> <to> 均为相对 lib/ 的路径（文件或目录）。';

/// 要扫描并改写 import 的顶层目录。
const _scanRoots = ['lib', 'test', 'integration_test', 'tool'];

final _directiveStart = RegExp(r'^\s*(import|export|part)\b');
final _quoted = RegExp('([\'"])([^\'"\\n]+)\\1');
const _pkgPrefix = 'package:clashmiao/';

class _Fail implements Exception {
  _Fail(this.message, [this.code = 1]);
  final String message;
  final int code;
}

void main(List<String> args) {
  try {
    _run(args);
  } on _Fail catch (e) {
    stderr.writeln(e.message);
    exit(e.code);
  }
}

void _run(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final pos = args.where((a) => a != '--dry-run').toList();
  if (pos.length != 2 || pos.any((a) => a.startsWith('-'))) {
    throw _Fail(_usage, 2);
  }
  final from = _cleanArg(pos[0]);
  final to = _cleanArg(pos[1]);
  if (from == to) throw _Fail('错误：<from> 与 <to> 相同。', 2);

  final root = _git([
    'rev-parse',
    '--show-toplevel',
  ], Directory.current.path).trim();
  final tracked = _gitList(root, ['ls-files', '-z']);
  final trackedSet = tracked.toSet();

  // ── 1. 确定要移动的 lib 文件 ───────────────────────────────────────
  final libFrom = 'lib/$from';
  final libIsDir = Directory('$root/$libFrom').existsSync();
  final libIsFile = File('$root/$libFrom').existsSync();
  if (!libIsDir && !libIsFile) {
    throw _Fail('错误：lib/$from 不存在。');
  }
  if (libIsFile) {
    if (!from.endsWith('.dart') || !to.endsWith('.dart')) {
      throw _Fail('错误：移动单个文件时，<from> 与 <to> 都必须是 .dart 文件路径。', 2);
    }
  } else {
    if (to.endsWith('.dart')) {
      throw _Fail('错误：<from> 是目录，<to> 也必须是目录路径。', 2);
    }
    if (to.startsWith('$from/')) {
      throw _Fail('错误：不能把目录移动到它自己的子目录里。', 2);
    }
  }

  final moves = <String, String>{}; // 仓库相对路径：旧 -> 新
  final skipped = <String>[];

  void collect(String oldBase, String newBase, {required bool isDir}) {
    if (!isDir) {
      if (trackedSet.contains(oldBase)) {
        moves[oldBase] = newBase;
      }
      return;
    }
    final prefix = '$oldBase/';
    for (final f in tracked) {
      if (f.startsWith(prefix)) {
        moves[f] = '$newBase/${f.substring(prefix.length)}';
      }
    }
    for (final e in Directory('$root/$oldBase').listSync(recursive: true)) {
      if (e is File) {
        final rel = e.path.substring(root.length + 1);
        if (!trackedSet.contains(rel)) skipped.add(rel);
      }
    }
  }

  if (libIsDir) {
    collect(libFrom, 'lib/$to', isDir: true);
    collect(
      'test/$from',
      'test/$to',
      isDir: Directory('$root/test/$from').existsSync(),
    );
  } else {
    collect(libFrom, 'lib/$to', isDir: false);
    final fromT = '${from.substring(0, from.length - 5)}_test.dart';
    final toT = '${to.substring(0, to.length - 5)}_test.dart';
    collect('test/$fromT', 'test/$toT', isDir: false);
  }
  if (!moves.keys.any((k) => k.startsWith('lib/'))) {
    throw _Fail('错误：lib/$from 下没有 git 已跟踪的文件可移动。');
  }

  // ── 2. 目标冲突检查（全部检查完才会动手）────────────────────────────
  final problems = <String>[];
  for (final e in moves.entries) {
    final dst = e.value;
    if (FileSystemEntity.typeSync('$root/$dst') !=
        FileSystemEntityType.notFound) {
      problems.add('目标已存在：$dst（来自 ${e.key}）');
      continue;
    }
    var dir = _dirname(dst);
    while (dir.isNotEmpty) {
      if (File('$root/$dir').existsSync()) {
        problems.add('目标的上级路径是一个文件：$dir（来自 ${e.key}）');
        break;
      }
      dir = _dirname(dir);
    }
  }
  if (problems.isNotEmpty) {
    throw _Fail('${problems.join('\n')}\n拒绝覆盖，未做任何修改。');
  }

  // ── 3. 计算 import 改写，并检查相对路径 ────────────────────────────
  final libMap = <String, String>{}; // package 路径（相对 lib/）：旧 -> 新
  for (final e in moves.entries) {
    if (e.key.startsWith('lib/')) {
      libMap[e.key.substring(4)] = e.value.substring(4);
    }
  }
  final scan =
      <String>{
        ..._gitList(root, ['ls-files', '-z', '-co', '--exclude-standard']),
      }.where(
        (f) =>
            f.endsWith('.dart') && _scanRoots.any((r) => f.startsWith('$r/')),
      );

  final newContent = <String, String>{}; // 旧路径 -> 新内容（仅有变化的）
  final rewriteCounts = <String, int>{};
  final relProblems = <String>[];
  for (final f in scan) {
    final file = File('$root/$f');
    if (!file.existsSync()) continue;
    final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    final newF = moves[f] ?? f;
    var count = 0;
    var inDirective = false;
    final out = <String>[];
    for (final line in text.split('\n')) {
      var l = line;
      final starts = _directiveStart.hasMatch(l);
      final inConditional = inDirective || starts;
      if (inConditional) {
        l = l.replaceAllMapped(_quoted, (m) {
          final q = m[1]!;
          final uri = m[2]!;
          if (uri.startsWith(_pkgPrefix)) {
            final target = uri.substring(_pkgPrefix.length);
            final moved = libMap[target];
            if (moved == null) return m[0]!;
            count++;
            return '$q$_pkgPrefix$moved$q';
          }
          if (!uri.contains(':') && uri.endsWith('.dart')) {
            final oldTarget = _resolve(_dirname(f), uri);
            final newTarget = moves[oldTarget] ?? oldTarget;
            if (_resolve(_dirname(newF), uri) != newTarget) {
              relProblems.add('$f:$uri');
            }
          }
          return m[0]!;
        });
        inDirective = !l.contains(';');
      }
      out.add(l);
    }
    if (count > 0) {
      newContent[f] = out.join('\n');
      rewriteCounts[f] = count;
    }
  }
  if (relProblems.isNotEmpty) {
    throw _Fail(
      '错误：下列文件含相对路径 import/part，移动后相对关系会失效，'
      '请人工处理后再移动：\n  ${relProblems.toSet().join('\n  ')}\n'
      '未做任何修改。',
    );
  }

  // ── 4. 打印计划 / 执行 ─────────────────────────────────────────────
  final plan = moves.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  stdout.writeln(dryRun ? '计划（--dry-run，不会修改任何文件）：' : '执行：');
  for (final e in plan) {
    stdout.writeln('  git mv ${e.key} ${e.value}');
  }
  final rewritten = rewriteCounts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final e in rewritten) {
    stdout.writeln('  改写 import ${moves[e.key] ?? e.key}（${e.value} 处）');
  }
  for (final s in skipped) {
    stdout.writeln('  提示：未跟踪文件留在原地：$s');
  }
  if (dryRun) return;

  for (final e in plan) {
    Directory('$root/${_dirname(e.value)}').createSync(recursive: true);
    _git(['mv', e.key, e.value], root);
  }
  for (final e in newContent.entries) {
    final dst = moves[e.key] ?? e.key;
    File('$root/$dst').writeAsBytesSync(utf8.encode(e.value));
  }
  // 清掉移空的旧目录（还有别的文件的目录不会被删）。
  final oldDirs = {for (final e in plan) _dirname(e.key)}.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final d in oldDirs) {
    var cur = d;
    while (cur.isNotEmpty && cur != 'lib' && cur != 'test') {
      final dir = Directory('$root/$cur');
      if (!dir.existsSync() || dir.listSync().isNotEmpty) break;
      dir.deleteSync();
      cur = _dirname(cur);
    }
  }
  stdout.writeln(
    '完成：移动 ${plan.length} 个文件，改写 ${rewritten.length} 个文件的 import。',
  );
}

String _cleanArg(String a) {
  var s = a;
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty ||
      s.startsWith('/') ||
      s.startsWith('lib/') ||
      s.contains(':') ||
      s.split('/').any((seg) => seg == '..' || seg == '.' || seg.isEmpty)) {
    throw _Fail('错误：路径必须是相对 lib/ 的干净相对路径，收到 "$a"。', 2);
  }
  return s;
}

String _dirname(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// 把相对 import `uri` 按 `dir`（仓库相对目录）解析成仓库相对路径。
String _resolve(String dir, String uri) {
  final base = dir.isEmpty ? Uri(path: '/') : Uri(path: '/$dir/');
  return base.resolve(uri).path.substring(1);
}

String _git(List<String> args, String cwd) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (r.exitCode != 0) {
    throw _Fail('git ${args.join(' ')} 失败：${r.stderr}'.trimRight());
  }
  return r.stdout as String;
}

/// 以 `-z` 运行 git，返回 NUL 分隔的路径列表。
List<String> _gitList(String cwd, List<String> args) =>
    _git(args, cwd).split('\u0000').where((s) => s.isNotEmpty).toList();
