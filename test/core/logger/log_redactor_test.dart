import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 落盘 / 导出日志的脱敏：抹掉订阅凭据、键值秘密与代理分享链接，保留排障需要的
/// 异常类名、错误码、主机与端口、堆栈帧。
void main() {
  group('脱敏用例表', () {
    const cases = <(String, String, String)>[
      // (说明, 输入, 期望)
      (
        '查询串整体折叠，scheme 与主机保留',
        'GET https://example.test/sub?token=SECRET&flag=1',
        'GET https://example.test/sub?…',
      ),
      (
        '去掉 userinfo，端口保留',
        'connect https://alice:hunter2@panel.example.test:8443/api/v1/sub failed',
        'connect https://panel.example.test:8443/api/v1/sub failed',
      ),
      (
        '路径里的长十六进制 token',
        'https://example.test/link/0123456789abcdef0123456789abcdef',
        'https://example.test/link/…',
      ),
      (
        '路径里的 UUID',
        'https://example.test/s/3f2504e0-4f89-11d3-9a0c-0305e82c3301/clash',
        'https://example.test/s/…/clash',
      ),
      (
        '路径里的长 base64',
        'https://example.test/api/c2VjcmV0LXN1YnNjcmlwdGlvbi10b2tlbg==',
        'https://example.test/api/…',
      ),
      (
        '路径里 16 位以上字母数字混排',
        'https://example.test/sub/Ab12Cd34Ef56Gh78',
        'https://example.test/sub/…',
      ),
      (
        '片段同样折叠；末尾标点留在外面',
        'see (https://example.test/x#frag-secret), then retry.',
        'see (https://example.test/x#…), then retry.',
      ),
      (
        'vmess 分享链接整条折叠',
        'bad link vmess://eyJhZGQiOiIxLjIuMy40IiwiaWQiOiJ1dWlkIn0= skipped',
        'bad link vmess://… skipped',
      ),
      (
        'vless / trojan / ss / hysteria2 / tuic',
        'vless://uuid@1.2.3.4:443?security=reality#hk '
            'trojan://pass@h.example.test:443 '
            'ss://YWVzLTI1Ni1nY206cGFzcw@1.2.3.4:8388#jp '
            'hysteria2://pw@h.example.test:443/?sni=x '
            'tuic://uuid:pw@h.example.test:443',
        'vless://… trojan://… ss://… hysteria2://… tuic://…',
      ),
      (
        '键值秘密：= 与 : 两种写法、JSON 引号写法',
        'token=abc123 key=k-1 password: p@ss uuid=1234 secret=s auth=a '
            '{"password":"hunter2","server":"h.example.test"}',
        'token=… key=… password: … uuid=… secret=… auth=… '
            '{"password":"…","server":"h.example.test"}',
      ),
      (
        'Authorization 头整行折叠',
        'request headers: Authorization: Bearer eyJhbGciOi.payload.sig',
        'request headers: Authorization: …',
      ),
      (
        'Proxy-Authorization 头',
        'Proxy-Authorization: Basic dXNlcjpwYXNz',
        'Proxy-Authorization: …',
      ),
    ];
    for (final (name, input, expected) in cases) {
      test(name, () => expect(redactLogText(input), expected));
    }
  });

  group('复审反例：引号值、授权头、Cookie、编码路径、弱字段', () {
    const cases = <(String, String, String)>[
      ('引号值里有空白', '{"password":"hello world"}', '{"password":"…"}'),
      (
        '引号值里有逗号等分隔符',
        '{"token":"abc,SECRET","server":"h.example.test"}',
        '{"token":"…","server":"h.example.test"}',
      ),
      (
        'JSON 写法的 Authorization',
        '{"Authorization":"Bearer SECRET","Accept":"application/json"}',
        '{"Authorization":"…","Accept":"application/json"}',
      ),
      (
        '引号值里有转义引号',
        r'{"password":"pa\"ss, wo\"rd","next":1}',
        r'{"password":"…","next":1}',
      ),
      (
        '引号值以转义反斜杠结尾',
        r'{"secret":"abc\\","next":"keep"}',
        r'{"secret":"…","next":"keep"}',
      ),
      (
        '嵌在字符串里、转义过一次的 JSON',
        r'body: "{\"password\":\"hello \\\"world\",\"server\":\"h\"}"',
        r'body: "{\"password\":\"…\",\"server\":\"h\"}"',
      ),
      (
        '单引号字段名与值、分隔符两侧有空格',
        "{'password' : 'hello world', 'server': 'h'}",
        "{'password' : '…', 'server': 'h'}",
      ),
      (
        '同一行没有收尾引号：遮到行尾',
        '{"password":"hello world\nnext line',
        '{"password":"…\nnext line',
      ),
      (
        '头部写法的 Authorization: Basic',
        'Authorization: Basic dXNlcjpwYXNz\nnext: 1',
        'Authorization: …\nnext: 1',
      ),
      (
        'Cookie 与 Set-Cookie 头',
        'Cookie: sid=abc123; theme=dark\n'
            'Set-Cookie: session=SECRET; Path=/; HttpOnly',
        'Cookie: …\nSet-Cookie: …',
      ),
      (
        'JSON 里的 cookie 与 set-cookie 列表',
        '{"cookie":"a=b; c=d","set-cookie":["s=SECRET; Path=/","t=2"]}',
        '{"cookie":"…","set-cookie":[…]}',
      ),
      (
        '编码过的 UUID 路径段：整段遮盖',
        'GET https://example.test/s/3f2504e0%2D4f89%2D11d3%2D9a0c%2D0305e82c3301/clash',
        'GET https://example.test/s/…/clash',
      ),
      (
        '编码过的十六进制 token 路径段',
        'https://example.test/link/%30%31%32%33456789abcdef0123456789abcdef',
        'https://example.test/link/…',
      ),
      (
        '重复编码的 UUID 路径段',
        'https://example.test/s/3f2504e0%252D4f89%252D11d3%252D9a0c%252D0305e82c3301',
        'https://example.test/s/…',
      ),
      (
        '复合字段名：obfs-password、access_token、x-api-key',
        'obfs-password: hunter2 access_token=abc x-api-key: k1',
        'obfs-password: … access_token=… x-api-key: …',
      ),
      (
        '弱字段 key：结构化写法遮盖',
        'key=k-1 "key":"k-1" {"key": 42}',
        'key=… "key":"…" {"key": …}',
      ),
      (
        '弱字段 key：值像凭据时冒号写法也遮盖',
        'Invalid key: 0123456789abcdef0123',
        'Invalid key: …',
      ),
      (
        '游离的 Bearer token',
        'retry with Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln failed',
        'retry with Bearer … failed',
      ),
    ];
    for (final (name, input, expected) in cases) {
      test(name, () {
        final once = redactLogText(input);
        expect(once, expected);
        expect(redactLogText(once), once, reason: '幂等');
      });
    }
  });

  group('不敏感的内容原样通过', () {
    const passthrough = <String>[
      'Bad state: boom',
      'HttpException: Connection closed before full header was received',
      'DioException [connection timeout]: The request connection took longer '
          'than 0:00:15.000000',
      'SocketException: Connection refused (OS Error: Connection refused, '
          'errno = 61), address = 127.0.0.1, port = 2080',
      'PlatformException(stale, attempt mismatch, null, null)',
      'TimeoutException after 0:00:20.000000: Future not completed',
      'https://example.test/api/v1/profiles',
      '[ERROR] profiles.update: Exception: upstream exploded',
      '#0      ScriptedProfileRepository.update (file:///Users/me/code/'
          'clashmiao/test/support/scripted_profile_repository.dart:38:24)',
      '#1      _ProfilesPageState._updateProfile '
          '(package:clashmiao/features/profile/presentation/profiles_page.dart:428:7)',
      '<asynchronous suspension>',
      'selected outbound 香港 01 for group proxy',
      // 普通诊断里的弱字段名不算凭据。
      'Invalid key: profiles',
      'Missing key: "selected_outbound"',
      'SharedPreferences key: clashmiao_analytics_enabled',
      'Invalid signature: expected 3 parts',
      'auth: handshake finished',
      'sid: 12',
      'pwd: /Users/me/code',
      'Bearer realm="clashmiao"',
      // 路径段：普通段、带编码的普通段、畸形转义原样保留。
      'https://example.test/api/v1/profiles/%E9%A6%99%E6%B8%AF',
      'https://example.test/files/100%zz/abc%',
      'https://example.test/s/%E0%A4%A',
      'route: domain_suffix=example.test outbound=proxy',
      'dns: exchange example.test: context deadline exceeded',
      'outbound/vless[hk]: dial tcp 1.2.3.4:443: i/o timeout',
      'inbound/tun[tun-in]: started at 172.19.0.1/30',
      'FormatException: Unexpected character (at character 1)',
      "type 'Null' is not a subtype of type 'String' in type cast",
      'Exception: profile not found (id=7)',
      'status code of 401: Unauthorized',
      '{"server":"h.example.test","port":443,"tag":"hk-01"}',
      'keys: 3, tokens: 12',
      '',
    ];
    for (final text in passthrough) {
      test(text.isEmpty ? '(空串)' : text, () {
        expect(redactLogText(text), text);
      });
    }
  });

  test('畸形输入不抛异常', () {
    for (final input in [
      '{"password":"',
      'token=',
      'Authorization:',
      'https://example.test/%',
      'https://example.test/%E',
      r'"key":\',
      '"password":"\\',
    ]) {
      expect(() => redactLogText(input), returnsNormally, reason: input);
    }
  });

  test('幂等：重复过滤结果不变', () {
    const input =
        'uri = https://u:p@example.test/sub/0123456789abcdef0123?token=S '
        'vmess://abc token=t Authorization: Bearer x';
    final once = redactLogText(input);
    expect(redactLogText(once), once);
    expect(once, isNot(contains('token=S')));
    expect(once, isNot(contains('u:p@')));
  });
}
