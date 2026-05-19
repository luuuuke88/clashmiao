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

      final url = await SubscriptionSource.resolve();
      final container = ProviderContainer();

      // 初始化真实 BoxService（不 mock）
      final boxService = container.read(boxServiceProvider);
      expect(
        boxService is StubBoxService,
        isFalse,
        reason: 'expected real BoxService on Android',
      );

      await boxService.init();
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      await boxService.setup(
        AppDirectories(
          baseDir: Directory(appDir.path),
          workingDir: Directory(appDir.path),
          tempDir: Directory(tempDir.path),
        ),
        debug: true,
      );

      // 注入测试订阅（绕开 UI 添加流程）
      final repo = await container.read(profileRepositoryProvider.future);
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
          await repo.addByContent(url, name: 'e2e-test');
        } else {
          await repo.addByUrl(url, customName: 'e2e-test');
        }
      }

      // 锁定智能模式（index=1）
      await container.read(proxyModeProvider.notifier).updateMode(1);

      // 启动 app
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ClashMiaoApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // baseline IP（VPN 未开）
      final baselineIp = await fetchEgressIp();
      expect(
        baselineIp,
        matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')),
        reason: 'baseline must be IPv4, got: $baselineIp',
      );

      // 点连接
      final connectFinder = find.byType(ConnectionButton);
      expect(connectFinder, findsOneWidget);
      await tester.tap(connectFinder);
      await tester.pump();

      // 等 BoxStarted（90s 超时，含 1.5s 连接动画 + 可能的 VPN dialog 等待 + sing-box bootstrap）
      await waitForStatus<BoxStarted>(
        tester,
        container,
        timeout: const Duration(seconds: 90),
        onTimeout: () {
          final err = container.read(connectionErrorProvider);
          if (err != null) debugPrint('[e2e] connection error: $err');
        },
      );

      // BoxStarted 后 sing-box 还在 VPN CONNECTING 阶段（节点 URLTest 没完），
      // 出口 IP 可能还是直连。最多 retry 8 次（每次 4s），任何一次拿到 ≠ baseline
      // 的合法 IPv4 就过。
      String proxiedIp = baselineIp;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(seconds: 4));
        try {
          proxiedIp = await fetchEgressIp(timeout: const Duration(seconds: 8));
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

      // 断开
      await tester.tap(connectFinder);
      await tester.pump();
      await waitForStatus<BoxStopped>(
        tester,
        container,
        timeout: const Duration(seconds: 30),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
