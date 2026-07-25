import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// prefs 里的"脏标记"：为真表示**我们把系统代理设上了、但还没确认还原过**。
///
/// 连接成功（且启用了系统代理）时置位，断开成功时清除。所以启动时如果发现它
/// 还是真的，说明上一次运行没走完还原流程——崩溃、被强杀、断电。
const kSystemProxyDirtyKey = 'clashmiao_system_proxy_dirty';

/// 执行外部命令。抽成可注入的函数只为测试——真实实现走 [Process.run]，
/// 测试里换成返回固定输出的假实现，不去碰机器的网络设置。
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _defaultRunner(String exe, List<String> args) =>
    Process.run(exe, args);

/// 某个"网络位置"上当前的系统代理状态。
@immutable
class SystemProxyState {
  const SystemProxyState({
    required this.scope,
    required this.enabled,
    required this.host,
    required this.port,
  });

  /// 这条状态属于谁：macOS 上是网络服务名（Wi-Fi / Ethernet…），
  /// Windows/Linux 上是一个固定标识。
  final String scope;
  final bool enabled;
  final String? host;
  final int? port;

  /// 是不是**我们自己**留下的、指向 [ourPort] 的残留。
  ///
  /// 三个条件必须同时满足才认定：启用中 + 回环地址 + 端口等于我们的 mixedPort。
  /// 少任何一条都不能动——用户机器上完全可能配着别的代理（实测就在一台机器上
  /// 看到 `Server: 127.0.0.1 Port: 7897`，那是另一个代理客户端的默认端口）。
  /// 把别人的、尤其是公司强制的代理配置抹掉，比留着我们自己的残留严重得多。
  bool isOurStaleProxy(int ourPort) =>
      enabled && port == ourPort && _isLoopback(host);

  static bool _isLoopback(String? h) =>
      h == '127.0.0.1' || h == '::1' || h == 'localhost';

  @override
  String toString() =>
      'SystemProxyState($scope, enabled=$enabled, $host:$port)';
}

/// 自愈结果，用于日志和给用户的提示。
@immutable
class StaleProxyHealResult {
  const StaleProxyHealResult({
    required this.checked,
    required this.healedScopes,
    required this.skipped,
  });

  /// 是否真的做了检查（脏标记没置位、或平台不支持时为 false）。
  final bool checked;

  /// 实际清理掉的范围。非空表示上一次运行确实留下了残留。
  final List<String> healedScopes;

  /// 发现有代理但**不是**我们的，因此没动的范围。
  final List<String> skipped;

  bool get healedAnything => healedScopes.isNotEmpty;
}

/// 启动自愈**实际清理掉了**残留代理时，把被清理的范围写进这里，供 UI 提示。
///
/// 为什么要提示：用户的体感是"刚才网不通、重开 App 又好了"，如果什么都不说，
/// 下次再遇到同样懵。告诉他们"上次异常退出留下了系统代理设置，已自动清理"，
/// 才能让这件事从玄学变成可理解的一次故障。
///
/// 空列表表示这次启动没清理任何东西（绝大多数情况）。
final staleProxyHealedNoticeProvider = StateProvider<List<String>>((_) => []);

/// 标记"系统代理现在由我们设着"。连接成功后调用。
Future<void> markSystemProxyDirty(SharedPreferences prefs) =>
    prefs.setBool(kSystemProxyDirtyKey, true);

/// 清除脏标记。**只有确认内核已经停下**（也就是 sing-box 已经还原了代理）
/// 之后才能调用——提前清掉的话，下次启动就不会去自愈那个真实存在的残留。
Future<void> clearSystemProxyDirty(SharedPreferences prefs) =>
    prefs.remove(kSystemProxyDirtyKey);

/// 启动时检查并清理上一次运行残留的系统代理。
///
/// ## 为什么需要它
///
/// 桌面端默认开启 `set-system-proxy`，而三个平台的实现写的都是**持久化的系统
/// 设置**，只在优雅关闭时还原：
///
/// - macOS：`networksetup -setwebproxy <服务> 127.0.0.1 <端口>`
/// - Windows：WinINET（`HKCU\...\Internet Settings` 的 ProxyEnable/ProxyServer）
/// - Linux：`gsettings set org.gnome.system.proxy mode manual`
///
/// 进程被强杀 / 崩溃 / 断电时没有任何清理机会，代理就永久指向一个已经没人监听
/// 的本地端口。用户的表现是"浏览器全都打不开网页"，而 App 界面显示"未连接"——
/// 两个信息互相矛盾，几乎不可能自己定位到是代理设置残留。
///
/// macOS 上的 Cmd+Q 那条路已经在原生侧拦住了（见
/// `macos/Runner/AppDelegate.swift`），这里覆盖的是**操作系统根本不给清理机会**
/// 的那半边。
///
/// ## 为什么用"脏标记 + 读取校验"两道，而不是无条件清一次
///
/// 只靠脏标记就清：会把用户自己配的代理一起抹掉（首次运行、或者标记因为别的
/// 原因残留时）。只靠读取校验：每次启动都要跑几条外部命令，而绝大多数启动都是
/// 干净的，纯浪费。两道合起来——标记决定"要不要查"，读取决定"能不能动"。
Future<StaleProxyHealResult> healStaleSystemProxyIfNeeded({
  required SharedPreferences prefs,
  required int expectedPort,
  ProcessRunner runner = _defaultRunner,
}) async {
  const nothing = StaleProxyHealResult(
    checked: false,
    healedScopes: [],
    skipped: [],
  );

  if (!(prefs.getBool(kSystemProxyDirtyKey) ?? false)) return nothing;

  final healed = <String>[];
  final skipped = <String>[];
  try {
    final states = await probeSystemProxy(runner: runner);
    for (final state in states) {
      if (state.isOurStaleProxy(expectedPort)) {
        await clearSystemProxy(state.scope, runner: runner);
        healed.add(state.scope);
      } else if (state.enabled) {
        skipped.add(state.scope);
      }
    }
    // 查完就清标记：不管有没有清理到东西，这一次的检查已经做过了。
    // 清理失败的情况下留着标记会让每次启动都重跑一遍外部命令，而失败的原因
    // （权限、命令不存在）下次也不会自己变好。
    await clearSystemProxyDirty(prefs);
  } catch (e) {
    debugPrint('[SystemProxyGuard] 检查残留代理失败: $e');
    return StaleProxyHealResult(
      checked: true,
      healedScopes: healed,
      skipped: skipped,
    );
  }

  if (healed.isNotEmpty) {
    debugPrint('[SystemProxyGuard] 清理了上次异常退出残留的系统代理: ${healed.join(", ")}');
  }
  if (skipped.isNotEmpty) {
    debugPrint('[SystemProxyGuard] 这些范围有代理但不是我们设的，未改动: ${skipped.join(", ")}');
  }
  return StaleProxyHealResult(
    checked: true,
    healedScopes: healed,
    skipped: skipped,
  );
}

/// 读取当前系统代理状态。桌面三端各一套命令；其它平台返回空。
@visibleForTesting
Future<List<SystemProxyState>> probeSystemProxy({
  ProcessRunner runner = _defaultRunner,
}) async {
  if (Platform.isMacOS) return _probeMacos(runner);
  if (Platform.isWindows) return _probeWindows(runner);
  if (Platform.isLinux) return _probeLinux(runner);
  return const [];
}

/// 关掉 [scope] 上的系统代理。
@visibleForTesting
Future<void> clearSystemProxy(
  String scope, {
  ProcessRunner runner = _defaultRunner,
}) async {
  if (Platform.isMacOS) {
    // 三种都要关。sing-box 的 Enable() 会同时设 web / securewebproxy
    // （supportSOCKS 时还有 socksfirewallproxy），只关一种等于没关。
    for (final flag in const [
      '-setwebproxystate',
      '-setsecurewebproxystate',
      '-setsocksfirewallproxystate',
    ]) {
      await runner('networksetup', [flag, scope, 'off']);
    }
    return;
  }
  if (Platform.isWindows) {
    await runner('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
      '/t',
      'REG_DWORD',
      '/d',
      '0',
      '/f',
    ]);
    return;
  }
  if (Platform.isLinux) {
    await runner('gsettings', [
      'set',
      'org.gnome.system.proxy',
      'mode',
      'none',
    ]);
    return;
  }
}

// ───────────────────────────── macOS ─────────────────────────────

Future<List<SystemProxyState>> _probeMacos(ProcessRunner runner) async {
  final list = await runner('networksetup', ['-listallnetworkservices']);
  final out = <SystemProxyState>[];
  // 第一行是说明文字（"An asterisk (*) denotes that a network service is
  // disabled."），不是服务名；被停用的服务名前面带 `*`。
  for (final raw in _lines(list.stdout).skip(1)) {
    final name = raw.startsWith('*') ? raw.substring(1).trim() : raw;
    if (name.isEmpty) continue;
    final r = await runner('networksetup', ['-getwebproxy', name]);
    final state = parseMacosWebProxy(name, r.stdout);
    if (state != null) out.add(state);
  }
  return out;
}

/// 解析 `networksetup -getwebproxy <服务>` 的输出：
///
///     Enabled: No
///     Server: 127.0.0.1
///     Port: 7897
///     Authenticated Proxy Enabled: 0
@visibleForTesting
SystemProxyState? parseMacosWebProxy(String scope, Object? stdout) {
  bool? enabled;
  String? host;
  int? port;
  for (final line in _lines(stdout)) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final key = line.substring(0, i).trim();
    final value = line.substring(i + 1).trim();
    switch (key) {
      case 'Enabled':
        enabled = value.toLowerCase() == 'yes';
      case 'Server':
        host = value.isEmpty ? null : value;
      case 'Port':
        port = int.tryParse(value);
    }
  }
  if (enabled == null) return null;
  return SystemProxyState(
    scope: scope,
    enabled: enabled,
    host: host,
    port: port,
  );
}

// ──────────────────────────── Windows ────────────────────────────

const _kWindowsScope = 'WinINET (HKCU Internet Settings)';

Future<List<SystemProxyState>> _probeWindows(ProcessRunner runner) async {
  const key =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  final enableRes = await runner('reg', ['query', key, '/v', 'ProxyEnable']);
  final serverRes = await runner('reg', ['query', key, '/v', 'ProxyServer']);
  final state = parseWindowsRegistry(enableRes.stdout, serverRes.stdout);
  return state == null ? const [] : [state];
}

/// 解析 `reg query` 的输出。形如：
///
///     HKEY_CURRENT_USER\...\Internet Settings
///         ProxyEnable    REG_DWORD    0x1
///     HKEY_CURRENT_USER\...\Internet Settings
///         ProxyServer    REG_SZ    127.0.0.1:2080
@visibleForTesting
SystemProxyState? parseWindowsRegistry(Object? enableOut, Object? serverOut) {
  bool? enabled;
  for (final line in _lines(enableOut)) {
    final m = RegExp(
      r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
    ).firstMatch(line);
    if (m != null) enabled = int.parse(m.group(1)!, radix: 16) != 0;
  }
  if (enabled == null) return null;

  String? host;
  int? port;
  for (final line in _lines(serverOut)) {
    final m = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch(line);
    if (m == null) continue;
    // 可能是 `127.0.0.1:2080`，也可能是 `http=host:port;https=host:port`。
    // 后者说明不是我们设的（我们只设一个整体地址），host 留 null 即可，
    // isOurStaleProxy 会因为回环判定失败而拒绝动手。
    final v = m.group(1)!;
    final idx = v.lastIndexOf(':');
    if (idx > 0 && !v.contains('=')) {
      host = v.substring(0, idx);
      port = int.tryParse(v.substring(idx + 1));
    }
  }
  return SystemProxyState(
    scope: _kWindowsScope,
    enabled: enabled,
    host: host,
    port: port,
  );
}

// ───────────────────────────── Linux ─────────────────────────────

const _kLinuxScope = 'GNOME (org.gnome.system.proxy)';

Future<List<SystemProxyState>> _probeLinux(ProcessRunner runner) async {
  final mode = await runner('gsettings', [
    'get',
    'org.gnome.system.proxy',
    'mode',
  ]);
  final host = await runner('gsettings', [
    'get',
    'org.gnome.system.proxy.http',
    'host',
  ]);
  final port = await runner('gsettings', [
    'get',
    'org.gnome.system.proxy.http',
    'port',
  ]);
  final state = parseLinuxGsettings(mode.stdout, host.stdout, port.stdout);
  return state == null ? const [] : [state];
}

/// 解析 gsettings 输出。字符串值带单引号：`'manual'` / `'127.0.0.1'`；
/// 数字裸给：`2080`。
@visibleForTesting
SystemProxyState? parseLinuxGsettings(
  Object? modeOut,
  Object? hostOut,
  Object? portOut,
) {
  final mode = _unquote(_firstLine(modeOut));
  if (mode.isEmpty) return null;
  return SystemProxyState(
    scope: _kLinuxScope,
    enabled: mode == 'manual',
    host: _unquote(_firstLine(hostOut)).isEmpty
        ? null
        : _unquote(_firstLine(hostOut)),
    port: int.tryParse(_firstLine(portOut)),
  );
}

// ───────────────────────────── 工具 ──────────────────────────────

Iterable<String> _lines(Object? stdout) => (stdout is String ? stdout : '')
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty);

String _firstLine(Object? stdout) {
  final it = _lines(stdout);
  return it.isEmpty ? '' : it.first;
}

String _unquote(String v) {
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.substring(1, v.length - 1);
  }
  return v;
}
