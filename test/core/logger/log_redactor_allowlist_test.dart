import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:clashmiao/core/logger/public_hosts.dart';
import 'package:clashmiao/features/connection/application/connection_health_monitor.dart'
    show kTunnelProbeUrl;
import 'package:clashmiao/features/connection/application/egress_ip_service.dart'
    show EgressIpService;
import 'package:flutter_test/flutter_test.dart';

/// 白名单脱敏：除公共主机（GitHub、官网、构建期外链、本机回环）外，所有 URL
/// 与节点地址（`host:port`、IP）一律遮盖。示例地址只用文档保留段：
/// RFC 5737（192.0.2.0/24、198.51.100.0/24、203.0.113.0/24）与 RFC 3849
/// （2001:db8::/32），主机名用 example.org / example.net。
void main() {
  void expectAll(List<(String, String, String)> cases) {
    for (final (name, input, expected) in cases) {
      test(name, () {
        final once = redactLogText(input);
        expect(once, expected);
        expect(redactLogText(once), once, reason: '幂等');
      });
    }
  }

  group('订阅地址与其它 URL：非白名单主机整条换成 <url>', () {
    expectAll(const [
      (
        '路径里的短 token',
        'refresh failed: https://sub.example.org/s/ab12cd',
        'refresh failed: <url>',
      ),
      (
        '查询串里的 token',
        'GET https://sub.example.org/api/v1/client/subscribe?token=ab12',
        'GET <url>',
      ),
      (
        'userinfo',
        'connect https://alice:hunter2@panel.example.org:8443/sub failed',
        'connect <url> failed',
      ),
      ('没有路径的 URL，句末标点留在外面', 'see https://sub.example.org.', 'see <url>.'),
      ('ws', 'dial ws://192.0.2.10:8080/ws?path=x', 'dial <url>'),
      ('wss', 'dial wss://cdn.example.net/ws', 'dial <url>'),
      (
        '深链：参数里是编码过的订阅地址',
        'clash://install-config?url=https%3A%2F%2Fsub.example.org%2Fs%2Fab12',
        '<url>',
      ),
      (
        '深链：sing-box scheme',
        'bad link sing-box://import-remote-profile?url=abc#name',
        'bad link <url>',
      ),
      (
        '自定义 DNS / 探测地址也是用户数据',
        'dns https://dns.example.net/dns-query unreachable',
        'dns <url> unreachable',
      ),
      (
        'JSON 里转义斜杠的 URL',
        r'{"u":"https:\/\/sub.example.org\/s\/ab12"}',
        r'{"u":"<url>"}',
      ),
      (
        '官网子域不放行：订阅面板可能在子域上',
        'https://sub.clashmiao.com/api/v1/client/subscribe?token=abc '
            'https://panel.clashmiao.com/s/a1b2c3',
        '<url> <url>',
      ),
      (
        '看起来像白名单、其实不是的主机',
        'https://evilgithub.com/x https://github.com.example.org/x '
            'https://notclashmiao.com/x',
        '<url> <url> <url>',
      ),
    ]);
  });

  group('代理分享链接整条折叠', () {
    expectAll(const [
      (
        'vmess',
        'bad vmess://eyJhZGQiOiJleGFtcGxlLm9yZyJ9 skipped',
        'bad vmess://… skipped',
      ),
      (
        'vless',
        'vless://00000000-0000-4000-8000-000000000000@example.org:443'
            '?security=reality#hk',
        'vless://…',
      ),
      ('trojan', 'trojan://pw@example.org:443', 'trojan://…'),
      ('ss', 'ss://YWVzLTI1Ni1nY206cHc@198.51.100.7:8388#jp', 'ss://…'),
      ('hysteria2', 'hysteria2://pw@example.org:443/?sni=x', 'hysteria2://…'),
      ('tuic', 'tuic://id:pw@example.org:443', 'tuic://…'),
    ]);
  });

  group('节点地址：host:port 与 IP 换成 <addr>', () {
    expectAll(const [
      (
        '主机名:端口',
        'outbound/vless[hk]: dial tcp example.org:443: i/o timeout',
        'outbound/vless[hk]: dial tcp <addr>: i/o timeout',
      ),
      (
        'IPv4:端口',
        'connect to 198.51.100.7:8443 failed',
        'connect to <addr> failed',
      ),
      (
        '方括号 IPv6:端口',
        'connect to [2001:db8::1]:443 failed',
        'connect to <addr> failed',
      ),
      ('方括号 IPv6，无端口', 'peer [2001:db8::1]', 'peer <addr>'),
      ('裸 IPv4', 'resolved 203.0.113.9 via dns', 'resolved <addr> via dns'),
      ('裸 IPv4，句末标点', 'server is 203.0.113.9.', 'server is <addr>.'),
      ('裸 IPv6', 'resolved 2001:db8::1 via dns', 'resolved <addr> via dns'),
      (
        '完整写法的 IPv6',
        'resolved 2001:db8:0:0:0:0:0:1 via dns',
        'resolved <addr> via dns',
      ),
      (
        '键值写法里的节点地址',
        'server=example.org:443 port=443',
        'server=<addr> port=443',
      ),
      (
        'SocketException：address 与 Failed host lookup',
        "SocketException: Failed host lookup: 'sub.example.org' "
            '(OS Error: nodename nor servname provided, errno = 8), '
            'address = sub.example.org, port = 443',
        "SocketException: Failed host lookup: '<addr>' "
            '(OS Error: nodename nor servname provided, errno = 8), '
            'address = <addr>, port = 443',
      ),
      (
        'Dio 连接异常：请求 URI 与 SocketException 一起出现',
        'DioException [connection error]: The connection errored: '
            'Connection refused (OS Error: Connection refused, errno = 111), '
            'address = 198.51.100.7, port = 8443 '
            'uri = https://sub.example.org/s/ab12?flag=android',
        'DioException [connection error]: The connection errored: '
            'Connection refused (OS Error: Connection refused, errno = 111), '
            'address = <addr>, port = 8443 uri = <url>',
      ),
    ]);
  });

  group('补充：短端口、IDN、被当作源码扩展名的真实 TLD', () {
    expectAll(const [
      ('1 位端口', 'dial example.org:8 failed', 'dial <addr> failed'),
      (
        'punycode TLD',
        'dial example.xn--p1ai:443 failed',
        'dial <addr> failed',
      ),
      ('.dev 主机', 'dial server.dev:443 failed', 'dial <addr> failed'),
      (
        '源码扩展名同形的真实 TLD（.rs / .md / .py）在普通文本里仍是主机',
        'dial server.rs:443 and node.md:8080 and x.py:22',
        'dial <addr> and <addr> and <addr>',
      ),
      (
        '括号里只有「名字:一个数字」不算堆栈帧：(server.rs:443) 是主机',
        'dial (server.rs:443) failed',
        'dial (<addr>) failed',
      ),
      (
        '没有路径也没有列号的 main.js:12 会被遮盖（保守，有意的取舍）',
        'error at main.js:12 and see main.dart:12 for details',
        'error at <addr> and see <addr> for details',
      ),
      ('Unicode IDN 主机:端口', 'dial 例子.测试:443 failed', 'dial <addr> failed'),
      (
        '含组合附加符号的 IDN（cafe\u0301.example:443）',
        'dial cafe\u0301.example:443 failed',
        'dial <addr> failed',
      ),
      ('TLD 含组合附加符号', 'dial node.te\u0301st:8443 failed', 'dial <addr> failed'),
      ('Unicode IDN URL', 'fetch https://例子.测试/s/ab12 now', 'fetch <url> now'),
      (
        '混合标签的 IDN（bücher.example:8443）',
        'dial bücher.example:8443 failed',
        'dial <addr> failed',
      ),
    ]);

    test('单标签 node:443 不遮盖：与 key:value 文本无法区分（有意的取舍）', () {
      expect(redactLogText('dial node:443 failed'), 'dial node:443 failed');
      expect(redactLogText('state: 3'), 'state: 3');
    });
  });

  group('编码过的 URL', () {
    expectAll(const [
      (
        '百分号编码，大写',
        'redirect https%3A%2F%2Fsub.example.org%2Fs%2Fab12%3Ftoken%3Dx now',
        'redirect <url> now',
      ),
      (
        '百分号编码，小写',
        'redirect https%3a%2f%2fsub.example.org%2fs%2fab12 now',
        'redirect <url> now',
      ),
      (
        '只编码了斜杠',
        'redirect https:%2F%2Fsub.example.org%2Fs%2Fab12',
        'redirect <url>',
      ),
      (
        '编码里夹着空格（%20）也不留尾巴',
        'u=https%3A%2F%2Fsub.example.org%2Fs%2Fab%20cd12',
        'u=<url>',
      ),
      (
        '编码的白名单 URL：还原后只留主机',
        'open https%3A%2F%2Fgithub.com%2Fluuuuke88%2Fclashmiao%3Fx%3D1 ok',
        'open https://github.com ok',
      ),
      (
        '编码的分享链接',
        'bad vmess%3A%2F%2FeyJhZGQiOiJleGFtcGxlLm9yZyJ9 skipped',
        'bad <url> skipped',
      ),
      (
        'JSON unicode 转义（小写）',
        r'{"u":"https://sub.example.org/s/ab12"}',
        r'{"u":"<url>"}',
      ),
      (
        'JSON unicode 转义（大写）',
        r'{"u":"https://sub.example.org/s/ab12"}',
        r'{"u":"<url>"}',
      ),
      (
        'JSON unicode 转义只转义了斜杠',
        r'{"u":"https://sub.example.org\/s\/ab12"}',
        r'{"u":"<url>"}',
      ),
      (
        '同一段里：编码的白名单 URL 后面跟着编码的分享链接：不留任何尾巴',
        'u=https%3A%2F%2Fgithub.com%2Fo%2Fr%2Cvmess%3A%2F%2FeyJhZGQiOiJ4In0',
        'u=https://github.com',
      ),
      (
        '同一段里：第一个是白名单，第二个是订阅地址：不留任何尾巴',
        'u=https%3A%2F%2Fgithub.com%2Fo%2Fr%2Chttps%3A%2F%2Fsub.example.org'
            '%2Fs%2Fab12',
        'u=https://github.com',
      ),
      (
        '同一段里：编码 URL 后面带编码的节点地址：不留任何尾巴',
        'u=https%3A%2F%2Fgithub.com%2Fo%2Fr%2Cnode.example.org%3A8443',
        'u=https://github.com',
      ),
      (
        '明文白名单 URL 的路径里夹着订阅地址（逗号拼接）',
        'x https://github.com/o/r,https://sub.example.org/s/ab12 y',
        'x https://github.com y',
      ),
      (
        '明文白名单 URL 的路径里夹着编码过的订阅地址',
        'x https://github.com/o/r%2Chttps%3A%2F%2Fsub.example.org%2Fs%2Fab12 y',
        'x https://github.com y',
      ),
      (
        '明文白名单 URL 的路径里夹着分享链接',
        'x https://github.com/o/r,vless://id@x y',
        'x https://github.com y',
      ),
      (
        '明文白名单 URL 的路径里夹着节点地址',
        'x https://github.com/o/r,node.example.org:8443 y',
        'x https://github.com y',
      ),
      (
        '白名单主机后面直接拼别的主机：整条 <url>',
        'x https://github.com,https://sub.example.org/s/ab12 y',
        'x <url> y',
      ),
      (
        'JSON 转义段里的白名单 URL 加分享链接：不留任何尾巴',
        r'{"u":"https\u003a\u002f\u002fgithub.com\u002fo,vless\u003a\u002f\u002fid@x"}',
        r'{"u":"https://github.com"}',
      ),
      (
        '嵌在白名单 URL 的查询里的编码地址随查询串一起去掉',
        'https://github.com/o/r?u=https%3A%2F%2Fsub.example.org%2Fs%2Fab12',
        'https://github.com',
      ),
      (
        '白名单主机的编码路径：只留主机',
        'https://clashmiao.com/a%20b/c%2Fd https://github.com/o%2Fr/x',
        'https://clashmiao.com https://github.com',
      ),
    ]);
  });

  group('file://：空 authority 的本地路径整条 <url>', () {
    expectAll(const [
      (
        '堆栈帧里的 file:///',
        '#0 main (file:///Users/me/code/main.dart:12:7)',
        '#0 main (<url>)',
      ),
      (
        'iOS 容器路径，句末标点留在外面',
        'read file:///var/mobile/Containers/Data/Application/X/Documents/'
            'profiles/a.json.',
        'read <url>.',
      ),
      (
        'file://host/share 走白名单',
        'open file://fileserver.example.org/share/a.txt now',
        'open <url> now',
      ),
      (
        'file://localhost/ 是本机回环：只留主机',
        'open file://localhost/tmp/a.txt now',
        'open file://localhost now',
      ),
    ]);
  });

  group('IPv6 zone id', () {
    expectAll(const [
      (
        '方括号 + 端口',
        'connect [fe80::1234%en0]:443 failed',
        'connect <addr> failed',
      ),
      ('方括号，无端口', 'peer [fe80::1234%eth0]', 'peer <addr>'),
      ('裸地址', 'peer fe80::1%en0 gone', 'peer <addr> gone'),
      ('裸地址，句末标点', 'peer fe80::1%en0.', 'peer <addr>.'),
      ('回环带 zone 不遮盖', 'bind ::1%lo0 ok', 'bind ::1%lo0 ok'),
    ]);
  });

  group('有意保留的取舍', () {
    expectAll(const [
      (
        '分享链接只保留 scheme，内容整段去掉',
        'bad vmess://eyJhZGQiOiJleGFtcGxlLm9yZyJ9 skipped',
        'bad vmess://… skipped',
      ),
      (
        '四段数字的版本号按 IPv4 处理（保守）',
        'kernel 1.14.3.2 started',
        'kernel <addr> started',
      ),
      (
        '换行拆开的 URL 只遮盖第一行（逐行处理，不跨行拼接）',
        'fetch https://sub.example.org/s/\nab12',
        'fetch <url>\nab12',
      ),
    ]);
  });

  group('白名单 URL：只留 scheme + 主机（+ 端口），路径、查询串、片段、userinfo 一律去掉', () {
    expectAll(const [
      (
        'github.com：本项目仓库路径也不留',
        'open https://github.com/luuuuke88/clashmiao/releases/latest'
            '?utm=x#readme now',
        'open https://github.com now',
      ),
      (
        '别人托管订阅的 GitHub 路径只剩主机',
        'fetch https://raw.githubusercontent.com/someone/repo/main/sub.yaml '
            'https://github.com/someone/sub https://gist.github.com/x/0a1b',
        'fetch https://raw.githubusercontent.com https://github.com '
            'https://gist.github.com',
      ),
      (
        'api.github.com',
        'GET https://api.github.com/repos/luuuuke88/clashmiao/releases/latest'
            '?per_page=1',
        'GET https://api.github.com',
      ),
      (
        'objects / release-assets 子域',
        'https://objects.githubusercontent.com/github-production-release-asset'
            '/1?X-Amz-Signature=ab12 '
            'https://release-assets.githubusercontent.com/x/y?sig=ab12',
        'https://objects.githubusercontent.com '
            'https://release-assets.githubusercontent.com',
      ),
      (
        '官网主域与 www：短路径可能就是订阅地址，不留',
        'https://clashmiao.com/privacy?lang=zh https://www.clashmiao.com/sub/short#a',
        'https://clashmiao.com https://www.clashmiao.com',
      ),
      (
        '官网更新清单',
        'GET https://clashmiao.com/api/latest.json?x=1',
        'GET https://clashmiao.com',
      ),
      (
        '公共探测地址',
        'probe http://cp.cloudflare.com/generate_204?a=1 failed, '
            'lookup https://ipwho.is/?x=1',
        'probe http://cp.cloudflare.com failed, lookup https://ipwho.is',
      ),
      (
        'userinfo 一并去掉，端口保留',
        'https://u:p@github.com:443/a?b=c',
        'https://github.com:443',
      ),
      (
        '路径里像 token 的段不需要再猜：路径整个不留',
        'https://clashmiao.com/s/0123456789abcdef0123456789abcdef',
        'https://clashmiao.com',
      ),
      (
        '本机回环的 URL 也只留主机与端口',
        'GET http://localhost:9090/proxies?secret=ab12 '
            'http://localhost:8080/a',
        'GET http://localhost:9090 http://localhost:8080',
      ),
      (
        'JSON 里转义斜杠的白名单 URL',
        r'{"u":"https:\/\/github.com\/o\/r?x=1"}',
        r'{"u":"https:\/\/github.com"}',
      ),
      (
        '路径里夹着别的地址：随路径一起去掉',
        'x https://github.com/o/r,https://sub.example.org/s/ab12 y '
            'z https://clashmiao.com/a,node.example.org:8443 w',
        'x https://github.com y z https://clashmiao.com w',
      ),
    ]);

    test('不在白名单的主机仍整条 <url>，白名单主机的相似域名也是', () {
      expect(
        redactLogText(
          'https://sub.clashmiao.com/s/a1 https://github.com.example.org/x',
        ),
        '<url> <url>',
      );
    });
  });

  group('不该碰的内容原样保留', () {
    const untouched = [
      '12:34:56',
      '[12:34:56] started',
      '2026-11-03T10:20:30.123456',
      '2026-11-03 10:20:30.123 [INFO] up',
      'sing-box 1.14.3 (go1.22.1)',
      'version 1.14.3+7',
      'took 1.5s, retry in 3.25 seconds',
      'timeout after 0:00:10.000000',
      '#0      main (package:clashmiao/main.dart:12:7)',
      '#1      _rootRun (dart:async/zone.dart:1399:19)',
      'package:flutter/src/widgets/framework.dart:5432:15',
      'at lib/features/profile/data/profile_repository.dart:632:11',
      '#2      main (lib/main.dart:12:7)',
      '#3      main (main.dart:12:7)',
      '#4      main (dart:core/x.dart:12)',
      'at (package:clashmiao/a.dart:12)',
      'dart:async',
      'localhost:8080',
      '127.0.0.1',
      '127.0.0.1:7890',
      '127.0.53.1:53',
      '::1',
      '[::1]:7890',
      'github.com:443',
      'api.github.com:443',
      '(OS Error: Connection refused, errno = 111)',
      'status code of 401: Unauthorized',
      'ratio 3:2 and 10:1',
      'MAC aa:bb:cc:dd:ee:ff',
      'v1.2.3.4 build',
      '999.1.1.1 is not an address',
    ];
    for (final text in untouched) {
      test(text, () => expect(redactLogText(text), text));
    }
  });

  group('白名单来源', () {
    test('固定的公共域名与子域（含大小写、末尾点）', () {
      for (final host in [
        'github.com',
        'API.GitHub.com',
        'raw.githubusercontent.com',
        'objects.githubusercontent.com',
        'release-assets.githubusercontent.com',
        'clashmiao.com',
        'www.clashmiao.com',
        'clashmiao.com.',
        'cp.cloudflare.com',
        'ipwho.is',
      ]) {
        expect(isPublicHost(host), isTrue, reason: host);
      }
    });

    test('本机回环', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '127.9.9.9',
        '::1',
        '[::1]',
      ]) {
        expect(isPublicHost(host), isTrue, reason: host);
      }
    });

    test('其它主机一律不在白名单', () {
      for (final host in [
        '',
        'example.org',
        'evilgithub.com',
        'github.com.example.org',
        'notclashmiao.com',
        'sub.clashmiao.com',
        'panel.clashmiao.com',
        'a.b.clashmiao.com',
        'cloudflare.com',
        'api.ipwho.is',
        '192.0.2.1',
        '2001:db8::1',
      ]) {
        expect(isPublicHost(host), isFalse, reason: host);
      }
    });

    test('探测地址的主机与代码里实际使用的常量保持同步', () {
      expect(isPublicHost(Uri.parse(kTunnelProbeUrl).host), isTrue);
      expect(isPublicHost(Uri.parse(EgressIpService.endpoint).host), isTrue);
    });

    test('官网放行精确主机：build_config 的默认外链主机都在白名单里', () {
      expect(isPublicHost(Uri.parse(kDefaultPrivacyPolicyUrl).host), isTrue);
    });

    test('构建期外链主机来自 build_config 的常量，不另抄一份', () {
      final compiled = compiledPublicHosts;
      expect(compiled, contains(Uri.parse(githubRepoUrl).host));
      expect(compiled, contains(Uri.parse(kDefaultPrivacyPolicyUrl).host));
      expect(compiled, containsAll(publicHostsFromUrls([privacyPolicyUrl])));
    });

    test('publicHostsFromUrls：空串与无主机的值忽略，主机名转小写', () {
      expect(
        publicHostsFromUrls(['', 'not a url', 'https://CDN.Example.Net/a']),
        {'cdn.example.net'},
      );
    });
  });
}
