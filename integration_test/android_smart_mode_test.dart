import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '_fixtures/subscription_source.dart';
import '_fixtures/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android smart mode: connect → traffic proxied → disconnect',
    (tester) async {
      if (!Platform.isAndroid) {
        markTestSkipped('android-only E2E');
        return;
      }

      final url = await _step('resolve subscription', () {
        return SubscriptionSource.resolve();
      });
      final container = ProviderContainer();

      // 初始化真实 BoxService（不 mock）
      final boxService = container.read(boxServiceProvider);
      expect(
        boxService is StubBoxService,
        isFalse,
        reason: 'expected real BoxService on Android',
      );

      await _step('boxService.init', () => boxService.init());
      final appDir = await _step(
        'getApplicationDocumentsDirectory',
        getApplicationDocumentsDirectory,
      );
      final tempDir = await _step(
        'getTemporaryDirectory',
        getTemporaryDirectory,
      );
      await _step(
        'boxService.setup',
        () => boxService.setup(
          AppDirectories(
            baseDir: Directory(appDir.path),
            workingDir: Directory(appDir.path),
            tempDir: Directory(tempDir.path),
          ),
          debug: true,
        ),
      );

      // 注入测试订阅（绕开 UI 添加流程）
      final repo = await _step(
        'profileRepositoryProvider',
        () => container.read(profileRepositoryProvider.future),
      );
      if (repo.getAll().isEmpty) {
        const proxyUriSchemes = [
          'ss',
          'vless',
          'vmess',
          'trojan',
          'hysteria',
          'hysteria2',
          'tuic',
        ];
        final isProxyUri = proxyUriSchemes.any((s) => url.startsWith('$s://'));
        if (isProxyUri) {
          await _step(
            'repo.addByContent',
            () => repo.addByContent(url, name: 'e2e-test'),
            timeout: const Duration(seconds: 45),
          );
        } else {
          await _step(
            'repo.addByUrl',
            () => repo.addByUrl(url, customName: 'e2e-test'),
            timeout: const Duration(seconds: 75),
          );
        }
      } else {
        debugPrint('[e2e] existing profiles: ${repo.getAll().length}');
      }
      await _step('skip onboarding', () async {
        final prefs = container.read(sharedPreferencesProvider).requireValue;
        await prefs.setBool('onboarding_done', true);
      });

      // 锁定智能模式（index=1）
      await _step(
        'proxyMode.updateMode',
        () => container.read(proxyModeProvider.notifier).updateMode(1),
      );

      // 启动 app
      await _step(
        'pumpWidget',
        () => tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ClashMiaoApp(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // baseline IP（VPN 未开）
      final baselineIp = await _step('fetch baseline IP', fetchEgressIp);
      expect(
        baselineIp,
        matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')),
        reason: 'baseline must be IPv4, got: $baselineIp',
      );

      // 点连接
      final connectFinder = find.byType(ConnectionButton);
      await _step(
        'wait ConnectionButton',
        () => _waitForFinder(tester, connectFinder),
        timeout: const Duration(seconds: 15),
      );
      debugPrint('[e2e] tap connect');
      await tester.tap(connectFinder);
      await tester.pump();

      // 等 BoxStarted（120s 超时，含 VPN consent dialog 等待 + sing-box bootstrap）
      await waitForStatus<BoxStarted>(
        tester,
        container,
        timeout: const Duration(seconds: 120),
        onTimeout: () {
          final err = container.read(connectionErrorProvider);
          if (err != null) debugPrint('[e2e] connection error: $err');
        },
      );
      debugPrint('[e2e] BoxStarted');

      // BoxStarted 后 sing-box 还在 VPN CONNECTING 阶段（节点 URLTest 没完），
      // 出口 IP 可能还是直连。最多 retry 8 次（每次 4s），任何一次拿到 ≠ baseline
      // 的合法 IPv4 就过。
      String proxiedIp = baselineIp;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 4));
        try {
          proxiedIp = await _step(
            'fetch proxied IP attempt ${i + 1}',
            () => fetchEgressIp(timeout: const Duration(seconds: 8)),
            timeout: const Duration(seconds: 12),
          );
          if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(proxiedIp) &&
              proxiedIp != baselineIp) {
            break;
          }
        } catch (_) {
          // 等的过程中 socket 可能因 TUN route 切换被 reset，吞掉继续 retry
        }
      }
      expect(proxiedIp, matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')));
      expect(
        proxiedIp,
        isNot(equals(baselineIp)),
        reason:
            'expected egress IP to change after VPN within ~32s, '
            'baseline=$baselineIp, last proxied=$proxiedIp',
      );

      // 断开 — 触发后短暂等待让 TUN 路由清理完毕，但不阻塞到 BoxStopped：
      // VPN 拆 TUN 时 Android 路由表瞬时切换会断 ADB TCP 连接，
      // 若继续 pump(300ms×N) 会让 flutter test 在结果回传时拿到 device offline (exit 79)。
      debugPrint('[e2e] tap disconnect');
      await tester.tap(connectFinder);
      await tester.pump(const Duration(seconds: 2));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<T> _step<T>(
  String name,
  Future<T> Function() action, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  debugPrint('[e2e] START $name');
  try {
    final result = await action().timeout(timeout);
    debugPrint('[e2e] DONE $name');
    return result;
  } catch (error, stackTrace) {
    debugPrint('[e2e] FAIL $name: $error\n$stackTrace');
    rethrow;
  }
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().length == 1) return;
  }
  expect(finder, findsOneWidget);
}
