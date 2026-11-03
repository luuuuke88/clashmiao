import 'package:clashmiao/core/logger/core_log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内核日志导出：出站 / 分组标签（节点名，常是裸域名）整个换成 `…`，inbound 标签
/// 是应用内部固定名，保留。示例名只用 example.com / example.org。
void main() {
  void expectCase(String input, String expected) {
    final once = redactCoreLogText(input);
    expect(once, expected);
    expect(redactCoreLogText(once), once, reason: '幂等');
  }

  group('出站标签', () {
    test('outbound/<type>[tag]：裸域名节点名', () {
      expectCase(
        'INFO [1 2ms] outbound/vless[node.example.com]: connection ok',
        'INFO [1 2ms] outbound/vless[…]: connection ok',
      );
    });

    test('endpoint/<type>[tag]', () {
      expectCase(
        'INFO endpoint/wireguard[node.example.com]: started',
        'INFO endpoint/wireguard[…]: started',
      );
    });

    test('路由匹配行：=> outbound/<type>[tag]（行尾）', () {
      expectCase(
        'INFO router: match[0] domain_suffix=example.org => '
            'outbound/trojan[node.example.com]',
        'INFO router: match[0] domain_suffix=example.org => '
            'outbound/trojan[…]',
      );
    });

    test('标签里带方括号与空格：[HK] node-01.example.com', () {
      expectCase(
        'INFO outbound/vmess[[HK] node-01.example.com]: dial failed',
        'INFO outbound/vmess[…]: dial failed',
      );
      expectCase(
        'INFO router: match[0] => outbound/vmess[[HK] node-01.example.com]',
        'INFO router: match[0] => outbound/vmess[…]',
      );
    });

    test('标签是中文 / 带空格 / 带 emoji', () {
      expectCase(
        'INFO outbound/shadowsocks[香港 01 ⚡]: ok',
        'INFO outbound/shadowsocks[…]: ok',
      );
    });

    test('同一行里多处标签都遮', () {
      expectCase(
        'INFO outbound/selector[a.example.com]: switch to '
            'outbound/vless[b.example.com]',
        'INFO outbound/selector[…]: switch to outbound/vless[…]',
      );
    });
  });

  group('分组标签', () {
    test('selector[...] / urltest[...]', () {
      expectCase(
        'INFO selector[proxy.example.com]: switched, '
            'urltest[auto.example.com]: tested',
        'INFO selector[…]: switched, urltest[…]: tested',
      );
    });
  });

  group('保留与叠加', () {
    test('inbound 标签保留', () {
      expectCase(
        'INFO inbound/mixed[mixed-in]: started at 127.0.0.1:2080',
        'INFO inbound/mixed[mixed-in]: started at 127.0.0.1:2080',
      );
    });

    test('标签遮盖后仍过通用脱敏器：订阅地址、分享链接、host:port', () {
      expectCase(
        'ERROR outbound/vless[node.example.com]: dial tcp example.org:443 '
            'via https://example.test/sub?token=SECRET vless://u@example.org:443',
        'ERROR outbound/vless[…]: dial tcp <addr> via <url> vless://…',
      );
    });

    test('没有标签的行原样', () {
      expectCase(
        'INFO router: sniffed protocol: tls',
        'INFO router: sniffed protocol: tls',
      );
    });

    test('多行文本逐行处理', () {
      expectCase(
        'a outbound/vless[x.example.com]: 1\nb outbound/vless[y.example.com]: 2',
        'a outbound/vless[…]: 1\nb outbound/vless[…]: 2',
      );
    });
  });
}
