import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// 全局默认配置选项，ModeSelector 切换模式时也使用
/// [executeConfigAsIs] = true → 全局模式，直接用原始配置
/// [executeConfigAsIs] = false → 智能模式，走规则分流（中国直连）
Map<String, dynamic> getDefaultConfigOptions({bool executeConfigAsIs = false}) {
  // 智能模式下添加中国分流规则
  final rules = executeConfigAsIs
      ? []
      : [
          {
            'domains': 'domain:.cn,geosite:cn',
            'ip': 'geoip:cn',
            'outbound': 'bypass',
          },
        ];
  return {
    'region': executeConfigAsIs ? 'other' : 'cn',
    'block-ads': false,
    'execute-config-as-is': executeConfigAsIs,
    'log-level': 'warn',
    'resolve-destination': false,
    'ipv6-mode': 'ipv4_only',
    'remote-dns-address': 'udp://1.1.1.1',
    'remote-dns-domain-strategy': '',
    'direct-dns-address': '1.1.1.1',
    'direct-dns-domain-strategy': '',
    'mixed-port': 2080,
    'tproxy-port': 2081,
    'local-dns-port': 6450,
    'tun-implementation': 'mixed',
    'mtu': 9000,
    'strict-route': true,
    'connection-test-url': 'http://connectivitycheck.gstatic.com/generate_204',
    'url-test-interval': 600,
    'enable-clash-api': true,
    'clash-api-port': 6756,
    'enable-tun': false,
    'enable-tun-service': false,
    'set-system-proxy': true,
    'bypass-lan': false,
    'allow-connection-from-lan': false,
    'enable-fake-dns': false,
    'enable-dns-routing': true,
    'independent-dns-cache': true,
    'rules': rules,
    'mux': {
      'enable': false,
      'padding': false,
      'max-streams': 8,
      'protocol': 'h2mux',
    },
    'tls-tricks': {
      'enable-fragment': false,
      'fragment-size': '10-100',
      'fragment-sleep': '50-200',
      'mixed-sni-case': false,
      'enable-padding': false,
      'padding-size': '100-200',
    },
    'warp': {
      'enable': false,
      'mode': 'proxy_over_warp',
      'wireguard-config': '',
      'license-key': '',
      'account-id': '',
      'access-token': '',
      'clean-ip': '',
      'clean-port': 0,
      'noise': '10-15',
      'noise-size': '5-10',
      'noise-delay': '1-1',
      'noise-mode': 'm4',
    },
    'warp2': {
      'enable': false,
      'mode': 'proxy_over_warp',
      'wireguard-config': '',
      'license-key': '',
      'account-id': '',
      'access-token': '',
      'clean-ip': '',
      'clean-port': 0,
      'noise': '10-15',
      'noise-size': '5-10',
      'noise-delay': '1-1',
      'noise-mode': 'm4',
    },
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // Ensure shared preferences are loaded before app runs
  await container.read(sharedPreferencesProvider.future);

  // 初始化 BoxService
  final boxService = container.read(boxServiceProvider);
  if (boxService is! StubBoxService) {
    try {
      await boxService.init();
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      final dirs = AppDirectories(
        baseDir: Directory(appDir.path),
        workingDir: Directory(appDir.path),
        tempDir: Directory(tempDir.path),
      );
      await boxService.setup(dirs, debug: true);

      // 传入默认配置（智能模式）
      await boxService.changeConfigOptions(
        jsonEncode(getDefaultConfigOptions()),
      );
      debugPrint('sing-box 核心初始化成功');
    } catch (e) {
      debugPrint('sing-box 初始化失败: $e');
    }
  } else {
    debugPrint('核心库未找到，使用桩实现');
  }

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowSize = Size(420, 850);
    WindowOptions windowOptions = WindowOptions(
      size: windowSize,
      minimumSize: windowSize,
      maximumSize: windowSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle:
          Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClashMiaoApp(),
    ),
  );
}
