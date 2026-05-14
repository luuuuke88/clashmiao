import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 轮询 [ConnectionController] 状态直到匹配 [T]，否则在 [timeout] 后 fail。
///
/// 不能用 `pumpAndSettle` —— BoxStarting 期间的转场动画无限循环。
Future<void> waitForStatus<T extends BoxStatus>(
  WidgetTester tester,
  ProviderContainer container, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 300),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(interval);
    final s = container.read(connectionControllerProvider).valueOrNull;
    if (s is T) return;
  }
  final last = container.read(connectionControllerProvider).valueOrNull;
  fail('Expected status $T within $timeout, last seen: $last');
}

/// 从 emulator/设备发 HTTPS 请求拿当前出口 IP。
///
/// 强制 DIRECT —— 不读 system proxy，我们要走 TUN 路径，
/// 不被同进程的 mixed inbound 截胡。
Future<String> fetchEgressIp({
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.badCertificateCallback = (_, __, ___) => true;
  client.connectionTimeout = timeout;
  try {
    final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
    final resp = await req.close().timeout(timeout);
    return (await utf8.decodeStream(resp)).trim();
  } finally {
    client.close(force: true);
  }
}
