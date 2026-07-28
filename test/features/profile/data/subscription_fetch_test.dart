import 'package:clashmiao/features/profile/data/subscription_fetch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fetchSubscriptionWithUserAgentFallback', () {
    test('自身 UA 拿到空配置时，改用回退 UA 并返回有节点的那份', () async {
      // 复现真实故障：面板按 UA 白名单分发，认不出 ClashMiao 就发一份
      // 结构合法但 `proxies: []` 的骨架配置。
      const emptyClash = 'mixed-port: 7890\nproxies: []\n';
      const fullSingbox =
          '{"outbounds":[{"tag":"HK-01","type":"vless"},'
          '{"tag":"JP-01","type":"vless"}]}';

      final attempted = <String>[];

      final result = await fetchSubscriptionWithUserAgentFallback(
        primaryUserAgent: 'ClashMiao/0.1.0 (Dio)',
        fallbackUserAgents: const ['sing-box/1.11.0'],
        fetch: (userAgent) async {
          attempted.add(userAgent);
          return SubscriptionResponse(
            body: userAgent.startsWith('sing-box') ? fullSingbox : emptyClash,
          );
        },
      );

      expect(attempted, ['ClashMiao/0.1.0 (Dio)', 'sing-box/1.11.0']);
      expect(result.userAgent, 'sing-box/1.11.0');
      expect(result.response.body, fullSingbox);
    });

    test('所有 UA 都只拿到空配置时，抛出「零节点」错误并附上试过的 UA', () async {
      expect(
        () => fetchSubscriptionWithUserAgentFallback(
          primaryUserAgent: 'ClashMiao/0.1.0 (Dio)',
          fallbackUserAgents: const ['sing-box/1.11.0'],
          fetch: (_) async => const SubscriptionResponse(body: 'proxies: []\n'),
        ),
        throwsA(
          isA<SubscriptionFetchException>()
              .having(
                (e) => e.reason,
                'reason',
                SubscriptionFetchFailure.noNodes,
              )
              .having((e) => e.attemptedUserAgents, 'attemptedUserAgents', [
                'ClashMiao/0.1.0 (Dio)',
                'sing-box/1.11.0',
              ]),
        ),
      );
    });

    test('所有 UA 都只拿到网页时，报「不是配置」而不是「零节点」', () async {
      expect(
        () => fetchSubscriptionWithUserAgentFallback(
          primaryUserAgent: 'ClashMiao/0.1.0 (Dio)',
          fallbackUserAgents: const ['sing-box/1.11.0'],
          fetch: (_) async => const SubscriptionResponse(
            body: '<!doctype html><html><body>访问已拒绝</body></html>',
            contentType: 'text/html; charset=UTF-8',
          ),
        ),
        throwsA(
          isA<SubscriptionFetchException>().having(
            (e) => e.reason,
            'reason',
            SubscriptionFetchFailure.notAConfig,
          ),
        ),
      );
    });
  });
}
