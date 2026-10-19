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
        'token=abc123 key: k-1 password=p@ss uuid=1234 secret=s auth=a '
            '{"password":"hunter2","server":"h.example.test"}',
        'token=… key: … password=… uuid=… secret=… auth=… '
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
      '',
    ];
    for (final text in passthrough) {
      test(text.isEmpty ? '(空串)' : text, () {
        expect(redactLogText(text), text);
      });
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
