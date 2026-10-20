import 'dart:typed_data';

import 'package:clashmiao/core/auto_start/windows_run_key.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内存注册表：按「键路径 → 值名 → 值」存。值保留原始 Dart 类型，
/// getString / getBinary 遇到类型不符时返回 null，与真实实现一致。
class _MemoryRegistry implements RunKeyRegistry {
  final keys = <String, Map<String, Object>>{};
  final removed = <(String, String)>[];

  @override
  String? getString(String keyPath, String name) {
    final v = keys[keyPath]?[name];
    return v is String ? v : null;
  }

  @override
  Uint8List? getBinary(String keyPath, String name) {
    final v = keys[keyPath]?[name];
    return v is Uint8List ? v : null;
  }

  @override
  bool hasValue(String keyPath, String name) =>
      keys[keyPath]?.containsKey(name) ?? false;

  @override
  void setString(String keyPath, String name, String value) =>
      (keys[keyPath] ??= {})[name] = value;

  @override
  void setBinary(String keyPath, String name, Uint8List value) =>
      (keys[keyPath] ??= {})[name] = value;

  @override
  void removeValue(String keyPath, String name) {
    final key = keys[keyPath];
    if (key == null || !key.containsKey(name)) {
      // 真实 RegDeleteValue 对不存在的值会报错，调用方必须先判断。
      throw StateError('value $keyPath\\$name does not exist');
    }
    key.remove(name);
    removed.add((keyPath, name));
  }
}

const _run = WindowsRunKeyLauncher.runKeyPath;
const _approved = WindowsRunKeyLauncher.startupApprovedKeyPath;
const _exe = r'C:\Program Files\ClashMiao\clashmiao.exe';

void main() {
  late _MemoryRegistry reg;
  late WindowsRunKeyLauncher launcher;

  setUp(() {
    reg = _MemoryRegistry();
    launcher = WindowsRunKeyLauncher(
      appName: 'ClashMiao',
      appPath: _exe,
      registry: reg,
    );
  });

  test('注册表路径与旧实现一致（老用户升级后能读到已写入的值）', () {
    expect(_run, r'Software\Microsoft\Windows\CurrentVersion\Run');
    expect(
      _approved,
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    );
  });

  test('什么都没写时 isEnabled 为 false', () {
    expect(launcher.isEnabled(), isFalse);
  });

  test('enable 写入带引号的命令行和 12 字节、首字节为 2 的启用标记', () {
    launcher.enable();

    expect(reg.keys[_run], {'ClashMiao': '"$_exe"'});
    final marker = reg.keys[_approved]!['ClashMiao']! as Uint8List;
    expect(marker.length, 12);
    expect(marker[0], 2);
    expect(marker.skip(1), everyElement(0));
    expect(launcher.isEnabled(), isTrue);
  });

  test('只有 Run 值、没有 StartupApproved 标记（旧版或手工添加）视为已启用', () {
    reg.setString(_run, 'ClashMiao', '"$_exe"');
    expect(launcher.isEnabled(), isTrue);
  });

  test('StartupApproved 标记为空也视为已启用', () {
    reg
      ..setString(_run, 'ClashMiao', _exe)
      ..setBinary(_approved, 'ClashMiao', Uint8List(0));
    expect(launcher.isEnabled(), isTrue);
  });

  test('任务管理器禁用后（首字节为奇数）isEnabled 为 false', () {
    launcher.enable();
    reg.setBinary(_approved, 'ClashMiao', Uint8List(12)..[0] = 3);
    expect(launcher.isEnabled(), isFalse);
  });

  test('偶数首字节（不只是 2）都视为允许', () {
    reg
      ..setString(_run, 'ClashMiao', _exe)
      ..setBinary(_approved, 'ClashMiao', Uint8List(12)..[0] = 6);
    expect(launcher.isEnabled(), isTrue);
  });

  test('Run 里的路径与当前可执行文件不一致（例如 App 被挪动过）视为未启用', () {
    reg.setString(_run, 'ClashMiao', r'D:\old\clashmiao.exe');
    expect(launcher.isEnabled(), isFalse);
  });

  group('Run 值兼容：只认指向同一个可执行文件', () {
    WindowsRunKeyLauncher at(String exe) => WindowsRunKeyLauncher(
      appName: 'ClashMiao',
      appPath: exe,
      registry: reg,
    );

    for (final exe in const [
      r'C:\Program Files\ClashMiao\clashmiao.exe', // 含空格
      r'D:\软件\喵速 ClashMiao\clashmiao.exe', // 中文 + 空格
      r'C:\ClashMiao\clashmiao.exe', // 无空格
    ]) {
      test('旧包写下的裸路径仍视为已启用：$exe', () {
        reg.setString(_run, 'ClashMiao', exe);
        expect(at(exe).isEnabled(), isTrue);
      });

      test('带引号的命令行视为已启用：$exe', () {
        reg.setString(_run, 'ClashMiao', '"$exe"');
        expect(at(exe).isEnabled(), isTrue);
      });

      test('enable 后读回为已启用，且写的是带引号的形式：$exe', () {
        final launcher = at(exe)..enable();
        expect(reg.getString(_run, 'ClashMiao'), '"$exe"');
        expect(launcher.isEnabled(), isTrue);
      });
    }

    test('大小写不同的同一路径视为同一个程序（Windows 路径不区分大小写）', () {
      reg.setString(
        _run,
        'ClashMiao',
        r'"c:\program files\CLASHMIAO\ClashMiao.EXE"',
      );
      expect(launcher.isEnabled(), isTrue);
    });

    test('带引号的程序后面跟参数：程序相同即视为已启用', () {
      reg.setString(_run, 'ClashMiao', '"$_exe" --silent');
      expect(launcher.isEnabled(), isTrue);
    });

    test('指向别的程序一律不算：不同目录、同目录不同文件名、带引号的别处路径', () {
      for (final other in const [
        r'D:\old\clashmiao.exe',
        r'C:\Program Files\ClashMiao\updater.exe',
        r'"C:\Program Files\Other App\clashmiao.exe"',
        r'"C:\Program Files\ClashMiao\clashmiao.exe.bak"',
      ]) {
        reg.setString(_run, 'ClashMiao', other);
        expect(launcher.isEnabled(), isFalse, reason: other);
      }
    });

    test('裸路径后面多了参数：无法确定是同一个程序，不算', () {
      reg.setString(_run, 'ClashMiao', '$_exe --silent');
      expect(launcher.isEnabled(), isFalse);
    });

    test('缺右引号、空串、只有空白：视为损坏，不算', () {
      for (final broken in ['"$_exe', '', '   ', '""']) {
        reg.setString(_run, 'ClashMiao', broken);
        expect(launcher.isEnabled(), isFalse, reason: broken);
      }
    });
  });

  test('executableOf：带引号取引号内、裸值整体即路径', () {
    expect(WindowsRunKeyLauncher.executableOf('"$_exe" -a'), _exe);
    expect(WindowsRunKeyLauncher.executableOf('  "$_exe"  '), _exe);
    expect(WindowsRunKeyLauncher.executableOf(_exe), _exe);
    expect(WindowsRunKeyLauncher.executableOf('"$_exe'), isNull);
    expect(WindowsRunKeyLauncher.executableOf(''), isNull);
  });

  test('Run 里同名值不是字符串类型时视为未启用', () {
    reg.setBinary(_run, 'ClashMiao', Uint8List.fromList([1, 2]));
    expect(launcher.isEnabled(), isFalse);
  });

  test('disable 删除两处的同名值，且不碰其它应用的值', () {
    reg
      ..setString(_run, 'Other', r'C:\other.exe')
      ..setBinary(_approved, 'Other', Uint8List(12)..[0] = 2);
    launcher.enable();

    launcher.disable();

    expect(reg.removed, [(_run, 'ClashMiao'), (_approved, 'ClashMiao')]);
    expect(reg.keys[_run], {'Other': r'C:\other.exe'});
    expect(reg.keys[_approved]!.keys, ['Other']);
    expect(launcher.isEnabled(), isFalse);
  });

  test('disable 在值不存在时跳过删除，不抛异常', () {
    expect(launcher.disable, returnsNormally);
    expect(reg.removed, isEmpty);
  });

  test('disable 只存在 Run 值时只删 Run', () {
    reg.setString(_run, 'ClashMiao', _exe);
    launcher.disable();
    expect(reg.removed, [(_run, 'ClashMiao')]);
  });
}
