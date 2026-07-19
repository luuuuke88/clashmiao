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
  void Function()? onTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(interval);
    final s = container.read(connectionControllerProvider).valueOrNull;
    if (s is T) return;
  }
  onTimeout?.call();
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
  final endpoints = [
    Uri.parse('https://api.ipify.org'),
    Uri.parse('https://ifconfig.me/ip'),
    Uri.parse('https://icanhazip.com'),
    Uri.parse('https://checkip.amazonaws.com'),
  ];
  final errors = <String>[];

  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.badCertificateCallback = (_, __, ___) => true;
  client.connectionTimeout = timeout;
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      for (final endpoint in endpoints) {
        try {
          final req = await client.getUrl(endpoint).timeout(timeout);
          final resp = await req.close().timeout(timeout);
          final body = (await utf8.decodeStream(resp)).trim();
          if (resp.statusCode == HttpStatus.ok && body.isNotEmpty) {
            return body;
          }
          errors.add('${endpoint.host}: HTTP ${resp.statusCode} "$body"');
        } catch (error) {
          errors.add('${endpoint.host}: $error');
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    throw SocketException(
      'All egress IP endpoints failed: ${errors.join(' | ')}',
    );
  } finally {
    client.close(force: true);
  }
}
