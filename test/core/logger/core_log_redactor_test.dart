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
        'INFO router: match[0] domain_suffix=<host> => '
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

  group('所有非白名单主机名换成 <host>', () {
    test('dns 行里的裸域名', () {
      expectCase(
        'INFO [9 0ms] dns: exchange node.example.com. IN A',
        'INFO [9 0ms] dns: exchange <host>. IN A',
      );
      expectCase(
        'ERROR dns: lookup failed for node.example.com: context deadline '
            'exceeded',
        'ERROR dns: lookup failed for <host>: context deadline exceeded',
      );
    });

    test('selector / urltest 消息正文里域名形的节点名', () {
      expectCase(
        'INFO selector[proxy]: selected node.example.com',
        'INFO selector[…]: selected <host>',
      );
      expectCase(
        'INFO urltest[auto]: best node.example.com 53ms, '
            'next node2.example.com 80ms',
        'INFO urltest[…]: best <host> 53ms, next <host> 80ms',
      );
    });

    test('Unicode IDN 与 punycode', () {
      expectCase(
        'INFO dns: exchange 中文.example.cn',
        'INFO dns: exchange <host>',
      );
      expectCase(
        'INFO dns: exchange xn--fiq228c.xn--p1ai and bücher.example',
        'INFO dns: exchange <host> and <host>',
      );
    });

    test('目标域名（带不带端口）属于浏览记录，同样遮盖', () {
      expectCase(
        'INFO outbound/direct[direct]: connection to www.example.org:443',
        'INFO outbound/direct[…]: connection to <addr>',
      );
      expectCase(
        'INFO router: sniffed domain www.example.org',
        'INFO router: sniffed domain <host>',
      );
    });

    test('白名单主机与回环保留', () {
      expectCase(
        'INFO dns: exchange github.com and api.github.com:443 and '
            'clashmiao.com localhost 127.0.0.1:2080',
        'INFO dns: exchange github.com and api.github.com:443 and '
            'clashmiao.com localhost 127.0.0.1:2080',
      );
    });

    test('已有占位符与类型名不被破坏', () {
      expectCase(
        'ERROR outbound/vless[node.example.com]: dial tcp 198.51.100.7:443 '
            'via https://sub.example.org/s/ab12 vless://u@x.example.org:443',
        'ERROR outbound/vless[…]: dial tcp <addr> via <url> vless://…',
      );
      expectCase('INFO <host> <url> <addr> …', 'INFO <host> <url> <addr> …');
    });

    test('版本号、时间戳、时长不是主机名', () {
      const line =
          'INFO [12 3ms] sing-box 1.14.3 started at 12:34:56.789 after 0:00:10.5';
      expectCase(line, line);
    });

    test('过度遮盖可以接受：文件名形态也会被当成主机名', () {
      expectCase('INFO loaded config.json', 'INFO loaded <host>');
    });

    test('白名单主机后的句末点与相邻文本', () {
      expectCase(
        'INFO resolved via github.com. then node.example.com.',
        'INFO resolved via github.com. then <host>.',
      );
    });
  });
}
