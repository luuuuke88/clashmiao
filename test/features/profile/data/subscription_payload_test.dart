import 'package:clashmiao/features/profile/data/subscription_payload.dart';
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
