import 'dart:io';

import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录调用、按预设返回输出的假 runner。绝不真的碰机器的网络设置。
class _FakeRunner {
  _FakeRunner(this.responses);

  /// key 是 `可执行文件 参数1 参数2 ...`，前缀匹配。
  final Map<String, String> responses;
  final calls = <List<String>>[];

  Future<ProcessResult> call(String exe, List<String> args) async {
    final key = '$exe ${args.join(" ")}';
    calls.add([exe, ...args]);
    for (final entry in responses.entries) {
      if (key.startsWith(entry.key)) {
        return ProcessResult(0, 0, entry.value, '');
      }
    }
    return ProcessResult(0, 0, '', '');
  }

  bool didRun(String needle) => calls.any((c) => c.join(' ').contains(needle));
}

/// 真实 macOS 上 `networksetup -getwebproxy` 的输出格式（照抄实测结果）。
String _macosWebProxy({
  required bool enabled,
  String server = '127.0.0.1',
  int port = 2080,
}) =>
    'Enabled: ${enabled ? "Yes" : "No"}\n'
    'Server: $server\n'
    'Port: $port\n'
    'Authenticated Proxy Enabled: 0\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('macOS 输出解析', () {
    test('照抄真实输出格式能解析出三个字段', () {
      final s = parseMacosWebProxy('Wi-Fi', _macosWebProxy(enabled: true));
      expect(s, isNotNull);
      expect(s!.enabled, isTrue);
      expect(s.host, '127.0.0.1');
      expect(s.port, 2080);
    });

    test('Enabled: No 解析成未启用', () {
      final s = parseMacosWebProxy('Wi-Fi', _macosWebProxy(enabled: false));
      expect(s!.enabled, isFalse);
    });

    test('输出里没有 Enabled 字段时返回 null，而不是当成未启用', () {
      // 服务不存在 / 命令报错时 networksetup 的输出不含这些字段。
      // 返回 null（"读不到"）而不是 false（"没开代理"）——后者会让上层以为
      // 已经确认过状态。
      expect(parseMacosWebProxy('Wi-Fi', 'Error: something'), isNull);
      expect(parseMacosWebProxy('Wi-Fi', ''), isNull);
    });
  });

  group('Windows 注册表解析', () {
    test('ProxyEnable=0x1 + 127.0.0.1:2080', () {
      final s = parseWindowsRegistry(
        r'HKEY_CURRENT_USER\...\Internet Settings'
            '\n    ProxyEnable    REG_DWORD    0x1\n',
        r'HKEY_CURRENT_USER\...\Internet Settings'
            '\n    ProxyServer    REG_SZ    127.0.0.1:2080\n',
      );
      expect(s!.enabled, isTrue);
      expect(s.host, '127.0.0.1');
      expect(s.port, 2080);
    });

    test('ProxyEnable=0x0 解析成未启用', () {
      final s = parseWindowsRegistry(
        '    ProxyEnable    REG_DWORD    0x0\n',
        '    ProxyServer    REG_SZ    127.0.0.1:2080\n',
      );
      expect(s!.enabled, isFalse);
    });

    test('per-protocol 形式（http=..;https=..）不解析出 host，因此不会被当成我们的', () {
      // 我们只会写一个整体地址；带 `=` 的形式说明是别人设的。
      final s = parseWindowsRegistry(
        '    ProxyEnable    REG_DWORD    0x1\n',
        '    ProxyServer    REG_SZ    http=1.2.3.4:8080;https=1.2.3.4:8080\n',
      );
      expect(s!.enabled, isTrue);
      expect(s.host, isNull);
      expect(s.isOurStaleProxy(2080), isFalse);
    });

    test('查不到 ProxyEnable 时返回 null', () {
      expect(parseWindowsRegistry('ERROR: cannot find', ''), isNull);
    });
  });

  group('Linux gsettings 解析', () {
    test("mode 'manual' + 回环 + 端口", () {
      final s = parseLinuxGsettings("'manual'\n", "'127.0.0.1'\n", '2080\n');
      expect(s!.enabled, isTrue);
      expect(s.host, '127.0.0.1');
      expect(s.port, 2080);
    });

    test("mode 'none' 解析成未启用", () {
      final s = parseLinuxGsettings("'none'\n", "''\n", '0\n');
      expect(s!.enabled, isFalse);
    });
  });

  group('isOurStaleProxy —— 绝不能动用户自己的代理', () {
    SystemProxyState st({
      bool enabled = true,
      String? host = '127.0.0.1',
      int? port = 2080,
    }) => SystemProxyState(
      scope: 'Wi-Fi',
      enabled: enabled,
      host: host,
      port: port,
    );

    test('三条都满足才认定是我们的', () {
      expect(st().isOurStaleProxy(2080), isTrue);
    });

    test('端口不同 → 不是我们的（实测有机器上是别的客户端的 7897）', () {
      expect(st(port: 7897).isOurStaleProxy(2080), isFalse);
    });

    test('非回环地址 → 不是我们的（公司代理就长这样）', () {
      expect(st(host: '10.0.0.1').isOurStaleProxy(2080), isFalse);
      expect(st(host: 'proxy.corp.example').isOurStaleProxy(2080), isFalse);
    });

    test('未启用 → 没什么要清的', () {
      expect(st(enabled: false).isOurStaleProxy(2080), isFalse);
    });

    test('host 缺失 → 不认定（宁可不动）', () {
      expect(st(host: null).isOurStaleProxy(2080), isFalse);
    });

    test('::1 和 localhost 也算回环', () {
      expect(st(host: '::1').isOurStaleProxy(2080), isTrue);
      expect(st(host: 'localhost').isOurStaleProxy(2080), isTrue);
    });
  });

  group('healStaleSystemProxyIfNeeded', () {
    Future<SharedPreferences> prefsWith({required bool dirty}) async {
      SharedPreferences.setMockInitialValues(
        dirty ? {kSystemProxyDirtyKey: true} : {},
      );
      return SharedPreferences.getInstance();
    }

    test('没有脏标记时一条命令都不跑', () async {
      final prefs = await prefsWith(dirty: false);
      final runner = _FakeRunner({});
      final r = await healStaleSystemProxyIfNeeded(
        prefs: prefs,
        expectedPort: 2080,
        runner: runner.call,
      );
      expect(r.checked, isFalse);
      expect(runner.calls, isEmpty, reason: '绝大多数启动都是干净的，不该每次都去跑外部命令');
    });

    test('有脏标记 + 残留是我们的 → 清理并记录范围', () async {
      if (!Platform.isMacOS) return; // 这条用例依赖 macOS 分支
      final prefs = await prefsWith(dirty: true);
      final runner = _FakeRunner({
        'networksetup -listallnetworkservices':
            'An asterisk (*) denotes that a network service is disabled.\n'
            'Wi-Fi\n',
        'networksetup -getwebproxy Wi-Fi': _macosWebProxy(enabled: true),
      });

      final r = await healStaleSystemProxyIfNeeded(
        prefs: prefs,
        expectedPort: 2080,
        runner: runner.call,
      );

      expect(r.healedScopes, ['Wi-Fi']);
      expect(
        runner.didRun('-setwebproxystate Wi-Fi off'),
        isTrue,
        reason: 'http 代理没关掉',
      );
      expect(
        runner.didRun('-setsecurewebproxystate Wi-Fi off'),
        isTrue,
        reason: 'https 代理也必须关——sing-box 两个都设了，只关一个等于没关',
      );
      expect(
        prefs.getBool(kSystemProxyDirtyKey),
        isNull,
        reason: '查过之后脏标记要清掉，否则每次启动都白跑一遍',
      );
    });

    test('有脏标记但代理是别人的 → 一个字都不改', () async {
      if (!Platform.isMacOS) return;
      final prefs = await prefsWith(dirty: true);
      final runner = _FakeRunner({
        'networksetup -listallnetworkservices':
            'An asterisk (*) denotes that a network service is disabled.\n'
            'Wi-Fi\n',
        // 别的代理客户端的默认端口，实测在真机上见过
        'networksetup -getwebproxy Wi-Fi': _macosWebProxy(
          enabled: true,
          port: 7897,
        ),
      });

      final r = await healStaleSystemProxyIfNeeded(
        prefs: prefs,
        expectedPort: 2080,
        runner: runner.call,
      );

      expect(r.healedScopes, isEmpty);
      expect(r.skipped, ['Wi-Fi']);
      expect(
        runner.didRun('-setwebproxystate'),
        isFalse,
        reason: '把用户自己（或公司强制）的代理配置抹掉，比留着我们自己的残留严重得多',
      );
    });

    test('被停用的网络服务（名字前带 *）也会被检查，名字里的 * 要剥掉', () async {
      if (!Platform.isMacOS) return;
      final prefs = await prefsWith(dirty: true);
      final runner = _FakeRunner({
        'networksetup -listallnetworkservices':
            'An asterisk (*) denotes that a network service is disabled.\n'
            '*Thunderbolt Bridge\n',
        'networksetup -getwebproxy Thunderbolt Bridge': _macosWebProxy(
          enabled: true,
        ),
      });

      final r = await healStaleSystemProxyIfNeeded(
        prefs: prefs,
        expectedPort: 2080,
        runner: runner.call,
      );

      expect(r.healedScopes, [
        'Thunderbolt Bridge',
      ], reason: '`*` 是"该服务已停用"的标记，不是服务名的一部分');
    });

    test('命令抛异常时不让启动挂掉', () async {
      final prefs = await prefsWith(dirty: true);
      Future<ProcessResult> boom(String exe, List<String> args) async =>
          throw ProcessException(exe, args, '命令不存在');

      // 不抛出才算通过——这段是在启动路径上跑的。
      final r = await healStaleSystemProxyIfNeeded(
        prefs: prefs,
        expectedPort: 2080,
        runner: boom,
      );
      expect(r.healedAnything, isFalse);
    });
  });
}
