import 'package:clashmiao/domain/profile/data/subscription_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('analyzeSubscriptionPayload', () {
    test('clash YAML 里 proxies 为空列表时节点数为 0', () {
      // 真实场景：订阅面板按 User-Agent 白名单分发，UA 不在白名单里时
      // 返回一份结构完全合法、但 `proxies: []` 的 clash 配置。
      const body = '''
mixed-port: 7890
mode: rule
proxies: []
proxy-groups:
  - {name: 节点选择, type: select, proxies: [DIRECT]}
rules:
  - MATCH,DIRECT
''';

      final result = analyzeSubscriptionPayload(body);

      expect(result.kind, SubscriptionPayloadKind.clashYaml);
      expect(result.nodeCount, 0);
    });

    test('HTTP 200 的 HTML 拒绝页被判定为「不是配置」', () {
      // 面板对未知 UA 的实际响应：状态码是 200，内容却是一张网页。
      const body =
          '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">'
          '<title>访问已拒绝</title></head><body>请使用受支持的客户端</body></html>';

      final result = analyzeSubscriptionPayload(
        body,
        contentType: 'text/html; charset=UTF-8',
      );

      expect(result.kind, SubscriptionPayloadKind.html);
      expect(result.isNotAConfig, isTrue);
      expect(result.looksUsable, isFalse);
    });

    test('sing-box JSON 里 outbounds 为空列表时节点数为 0', () {
      const body = '{"log":{"level":"info"},"outbounds":[],"route":{}}';

      final result = analyzeSubscriptionPayload(body);

      expect(result.kind, SubscriptionPayloadKind.singboxJson);
      expect(result.nodeCount, 0);
    });

    test('节点数按叶子视图数：outbounds 为空而只有端点，不判空', () {
      const body =
          '{"outbounds":[],"endpoints":[{"type":"wireguard","tag":"wg-hk"}]}';

      final result = analyzeSubscriptionPayload(body);

      expect(result.kind, SubscriptionPayloadKind.singboxJson);
      expect(result.nodeCount, 1);
      expect(result.isDefinitelyEmpty, isFalse);
      expect(result.looksUsable, isTrue);
    });

    test('没有 outbounds 数组、只有 endpoints 数组也是 sing-box JSON', () {
      const body = '{"endpoints":[{"type":"wireguard","tag":"wg-hk"}]}';

      final result = analyzeSubscriptionPayload(body);

      expect(result.kind, SubscriptionPayloadKind.singboxJson);
      expect(result.nodeCount, 1);
    });

    test('只有 direct / 只有分组 / 分组加 direct：确信的零节点（分组不计入）', () {
      const bodies = {
        '只有 direct': '{"outbounds":[{"type":"direct","tag":"direct"}]}',
        '只有分组':
            '{"outbounds":[{"type":"selector","tag":"s","outbounds":["a"]},'
            '{"type":"urltest","tag":"u","outbounds":["a"]}]}',
        '分组加 direct':
            '{"outbounds":[{"type":"selector","tag":"s","outbounds":["a"]},'
            '{"type":"direct","tag":"direct"},'
            '{"type":"block","tag":"block"},{"type":"dns","tag":"d"}]}',
      };
      for (final entry in bodies.entries) {
        final result = analyzeSubscriptionPayload(entry.value);
        expect(
          result.kind,
          SubscriptionPayloadKind.singboxJson,
          reason: entry.key,
        );
        expect(result.nodeCount, 0, reason: entry.key);
        expect(result.isDefinitelyEmpty, isTrue, reason: entry.key);
      }
    });

    test('分组不计入：一个节点加两个分组，节点数是 1', () {
      const body =
          '{"outbounds":[{"type":"selector","tag":"s","outbounds":["a"]},'
          '{"type":"urltest","tag":"u","outbounds":["a"]},'
          '{"type":"vless","tag":"a"}]}';
      expect(analyzeSubscriptionPayload(body).nodeCount, 1);
    });

    test('有节点的 clash YAML 不会被误判为空', () {
      // 防误判是这个分类器最重要的性质：判错一份好订阅，代价远高于漏判一份
      // 空订阅（漏判只是退回原来的 native parse 流程）。
      const body = '''
mixed-port: 7890
proxies:
    - { name: 'HK-01', type: vless, server: example.com, port: 443 }
    - { name: 'JP-01', type: vless, server: example.com, port: 444 }
proxy-groups:
    - { name: 节点选择, type: select, proxies: [HK-01, JP-01] }
''';

      final result = analyzeSubscriptionPayload(body);

      expect(result.isDefinitelyEmpty, isFalse);
      expect(result.looksUsable, isTrue);
    });
  });
}
