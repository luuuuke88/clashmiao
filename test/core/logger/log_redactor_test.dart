import 'dart:convert';
import 'dart:math';

import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 落盘 / 导出日志的脱敏：抹掉订阅凭据、键值秘密与代理分享链接，保留排障需要的
/// 异常类名、错误码、主机与端口、堆栈帧。
///
/// 键值规则：识别出秘密字段后从值开头遮到行尾，不猜值的边界。
void main() {
  void expectCase(String input, String expected) {
    final once = redactLogText(input);
    expect(once, expected);
    expect(redactLogText(once), once, reason: '幂等');
  }

  group('URL 与分享链接', () {
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
        '编码的路径分隔符 %2F 把 UUID 和普通段粘成一段：整段遮盖',
        'https://example.test/s/3f2504e0%2D4f89%2D11d3%2D9a0c%2D0305e82c3301%2Fclash',
        'https://example.test/s/…',
      ),
      (
        '重复编码的路径分隔符 %252F',
        'https://example.test/s/clash%252F3f2504e0-4f89-11d3-9a0c-0305e82c3301',
        'https://example.test/s/…',
      ),
      (
        '三层编码的分隔符与连字符',
        'https://example.test/s/a%25252F3f2504e0%25252D4f89%25252D11d3'
            '%25252D9a0c%25252D0305e82c3301',
        'https://example.test/s/…',
      ),
      (
        '含编码 / 的 base64 段（%2F）：整段解码后仍要查',
        'https://example.test/s/AbCdEfGhIjK%2FMnOpQrStUvW%2FYz0123456789',
        'https://example.test/s/…',
      ),
      (
        '含编码 / 的 base64 段（%252F，两层）',
        'https://example.test/s/AbCdEfGhIjK%252FMnOpQrStUvW%252FYz0123456789',
        'https://example.test/s/…',
      ),
      (
        '含编码 / 的 base64 段（%25252F，三层）',
        'https://example.test/s/AbCdEfGhIjK%25252FMnOpQrStUvW%25252FYz0123456789',
        'https://example.test/s/…',
      ),
      (
        '转义斜杠的 http URL：userinfo 与路径 token',
        r'{"u":"http:\/\/u:p@example.test\/s\/'
            r'3f2504e0-4f89-11d3-9a0c-0305e82c3301\/clash"}',
        r'{"u":"http:\/\/example.test\/s\/…\/clash"}',
      ),
      (
        '转义斜杠的分享链接',
        r'{"u":"vless:\/\/uuid@1.2.3.4:443#hk"}',
        r'{"u":"vless:\/\/…"}',
      ),
      (
        '游离的 Bearer token',
        'retry with Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln failed',
        'retry with Bearer … failed',
      ),
    ];
    for (final (name, input, expected) in cases) {
      test(name, () => expectCase(input, expected));
    }
  });

  group('键值：识别出秘密字段即遮到行尾', () {
    const cases = <(String, String, String)>[
      (
        '平铺 key=value：强弱字段都遮到行尾',
        'retry token=abc123 server=h.example.test',
        'retry token=…',
      ),
      ('弱字段 key=', 'lookup key=k-1 next=1', 'lookup key=…'),
      (
        '头部写法的 Authorization / Proxy-Authorization',
        'Authorization: Basic dXNlcjpwYXNz\nProxy-Authorization: Basic x',
        'Authorization: …\nProxy-Authorization: …',
      ),
      (
        'Cookie 与 Set-Cookie 头',
        'Cookie: sid=abc123; theme=dark\n'
            'Set-Cookie: session=SECRET; Path=/; HttpOnly',
        'Cookie: …\nSet-Cookie: …',
      ),
      (
        '复合字段名：obfs-password、x-api-key',
        'obfs-password: hunter2 and more\nx-api-key: k1',
        'obfs-password: …\nx-api-key: …',
      ),
      (
        '弱字段在自然语言里：值像凭据时也遮',
        'Invalid key: 0123456789abcdef0123',
        'Invalid key: …',
      ),
      (
        '弱字段：值包在转义引号里也识别',
        r'Invalid key: \"0123456789abcdef0123\"',
        'Invalid key: …',
      ),
      (
        '弱字段：值包在方括号里也识别',
        'Invalid key: [0123456789abcdef0123]',
        'Invalid key: …',
      ),
      (
        '弱字段：值包在圆括号、尖括号、单引号里也识别',
        "sid: (0123456789abcdef0123)\nsig: <0123456789abcdef0123>\n"
            "auth: '0123456789abcdef0123'",
        'sid: …\nsig: …\nauth: …',
      ),
      (
        '强字段在自然语言里同样遮到行尾（偏安全的过度遮盖）',
        'Invalid token: expired at 12:00',
        'Invalid token: …',
      ),
      (
        '只遮到行尾，下一行照常保留',
        '{"password":"hello\nnext line',
        '{"password":…\nnext line',
      ),
      (
        '嵌在字符串里、转义过一次的 JSON',
        r'body: "{\"server\":\"h\",\"password\":\"x\"}"',
        r'body: "{\"server\":\"h\",\"password\":…',
      ),
    ];
    for (final (name, input, expected) in cases) {
      test(name, () => expectCase(input, expected));
    }
  });

  group('复审反例：用真实的 jsonEncode / Map.toString 输出构造', () {
    void expectNoSecret(String input, {List<String> secrets = const []}) {
      final once = redactLogText(input);
      for (final s in ['SECRET', ...secrets]) {
        expect(once, isNot(contains(s)), reason: '$input\n→ $once');
      }
      expect(redactLogText(once), once, reason: '幂等');
    }

    test('JSON 列表值里的 ] 不再截断遮盖', () {
      final input = jsonEncode({
        'set-cookie': ['session=abc]SECRET; Path=/'],
      });
      expect(redactLogText(input), '{"set-cookie":…');
      expectNoSecret(input);
    });

    test('JSON 秘密字段下的嵌套对象整个遮盖', () {
      final input = jsonEncode({
        'server': 'h.example.test',
        'secret': {'value': 'SECRET'},
      });
      expect(redactLogText(input), '{"server":"h.example.test","secret":…');
      expectNoSecret(input);
    });

    test('JSON：值里有空白、逗号、转义引号', () {
      expectNoSecret(jsonEncode({'password': 'hello, "SECRET" world'}));
      expectNoSecret(jsonEncode({'token': 'abc,SECRET'}));
      expectNoSecret(jsonEncode({'Authorization': 'Bearer SECRET'}));
      expectNoSecret(jsonEncode({'secret': r'abc\SECRET'}));
      expectNoSecret(
        jsonEncode({
          'servers': [
            {'host': 'h', 'uuid': 'SECRET'},
          ],
        }),
      );
    });

    test('Map 打印：值里的逗号空格不再当作边界', () {
      final input = {'password': 'hello, SECRET', 'server': 'h'}.toString();
      expect(input, '{password: hello, SECRET, server: h}');
      expect(redactLogText(input), '{password: …');
      expectNoSecret(input);
    });

    test('Map 打印：值里的右括号不再当作边界', () {
      final input = {'password': 'abc}SECRET', 'server': 'h'}.toString();
      expect(redactLogText(input), '{password: …');
      expectNoSecret(input);
    });

    test('Map 打印：值以引号开头', () {
      expectNoSecret({'password': '"abc"SECRET', 'server': 'h'}.toString());
    });

    test('Map 打印：弱字段 key / pwd / auth 也算结构化字段', () {
      final input = {'key': 'k-1', 'pwd': 'hunter2', 'server': 'h'}.toString();
      expect(redactLogText(input), '{key: …');
      expectNoSecret(input, secrets: ['k-1', 'hunter2']);
      expectNoSecret(
        {'server': 'h', 'auth': 'SECRET'}.toString(),
        secrets: ['SECRET'],
      );
    });

    test('Map 打印：秘密字段排在前面的值里有右括号之后', () {
      expectNoSecret({'note': 'a}b', 'pwd': 'SECRET'}.toString());
    });

    test('Map 打印：嵌套 Map、List、Set 里的 Map', () {
      expectNoSecret(
        {
          'profile': {
            'name': '机场 A',
            'auth': {'user': 'alice', 'password': 'hello world SECRET'},
          },
          'port': 443,
        }.toString(),
      );
      expectNoSecret(
        [
          {'host': 'h'},
          {'password': 'SECRET, x: 1'},
        ].toString(),
      );
      expectNoSecret(
        {
          {'token': 'SECRET'},
        }.toString(),
      );
      expectNoSecret({'secret': '{a: SECRET}'}.toString());
    });

    test('Map 打印：值里带冒号', () {
      expectNoSecret({'token': 'a:b SECRET:c', 'port': 443}.toString());
    });

    test('Map 打印：行尾没有右括号', () {
      const line = '{server: h, password: hello SECRET';
      expect(redactLogText('$line\nnext'), '{server: h, password: …\nnext');
    });

    test('Map 外的自然语言照常保留', () {
      expect(redactLogText('Invalid key: profiles'), 'Invalid key: profiles');
      expect(
        redactLogText('[ERROR] profiles.update: Invalid key: profiles'),
        '[ERROR] profiles.update: Invalid key: profiles',
      );
    });
  });

  group('结构化值先按键名脱敏再转文本', () {
    test('Map / List 里的秘密键整项遮盖，其余字符串过文本脱敏', () {
      final out = redactStructuredValue({
        'password': 'hello, SECRET',
        'servers': [
          {'host': 'h.example.test', 'uuid': 1234},
        ],
        'url': 'https://example.test/sub?token=SECRET',
        'count': 2,
      });
      expect(out, {
        'password': '…',
        'servers': [
          {'host': 'h.example.test', 'uuid': '…'},
        ],
        'url': 'https://example.test/sub?…',
        'count': 2,
      });
    });
  });

  group('结构化遍历防循环引用', () {
    void expectSafe(Object root) {
      late Object? out;
      expect(() => out = redactStructuredValue(root), returnsNormally);
      final text = jsonEncode(out); // 结果里不再有环，能序列化
      expect(text, isNot(contains('SECRET')));
      expect(text, contains(kCyclePlaceholder));
      expect(redactLogText('$out'), isNot(contains('SECRET')));
    }

    test('自引用 Map', () {
      final map = <String, Object?>{'password': 'SECRET', 'server': 'h'};
      map['self'] = map;
      expectSafe(map);
      expect((redactStructuredValue(map)! as Map)['self'], kCyclePlaceholder);
    });

    test('自引用 List', () {
      final list = <Object?>[
        {'token': 'SECRET'},
        'https://example.test/sub?token=SECRET',
      ];
      list.add(list);
      expectSafe(list);
    });

    test('两个结构互相引用', () {
      final a = <String, Object?>{'password': 'SECRET'};
      final b = <Object?>[a, 'https://example.test/sub?token=SECRET'];
      a['b'] = b;
      expectSafe(a);
      expectSafe(b);
    });

    test('共享但无环的子结构照常展开，不当成循环', () {
      final shared = {'host': 'h.example.test', 'uuid': 'SECRET'};
      final out = redactStructuredValue([shared, shared])! as List;
      expect(out, [
        {'host': 'h.example.test', 'uuid': '…'},
        {'host': 'h.example.test', 'uuid': '…'},
      ]);
    });

    test('toString 抛异常的对象换成占位，不往外抛', () {
      expect(redactStructuredValue({'value': _ThrowingToString()}), {
        'value': kUnprintablePlaceholder,
      });
    });

    test('随机带环的嵌套 Map / List：从不抛异常，秘密不残留', () {
      const secretKeys = ['password', 'token', 'key', 'uuid', 'auth'];
      const plainKeys = ['host', 'name', 'items', 'next', 'meta'];
      for (var seed = 0; seed < 400; seed++) {
        final r = Random(seed);
        final nodes = <Object>[
          for (var i = r.nextInt(6) + 1; i > 0; i--)
            r.nextBool() ? <String, Object?>{} : <Object?>[],
        ];
        Object? child({required bool underSecret}) {
          switch (r.nextInt(4)) {
            case 0:
            case 1:
              return nodes[r.nextInt(nodes.length)]; // 可能指回祖先或自己
            case 2:
              return underSecret ? 'SECRET ${r.nextInt(9)}' : 'plain';
            default:
              return r.nextInt(100);
          }
        }

        for (final node in nodes) {
          final n = r.nextInt(4);
          for (var i = 0; i < n; i++) {
            if (node is Map<String, Object?>) {
              final secret = r.nextInt(3) == 0;
              final key = secret
                  ? secretKeys[r.nextInt(secretKeys.length)]
                  : '${plainKeys[r.nextInt(plainKeys.length)]}$i';
              node[key] = child(underSecret: secret);
            } else if (node is List<Object?>) {
              node.add(child(underSecret: false));
            }
          }
        }

        late Object? out;
        expect(
          () => out = redactStructuredValue(nodes.first),
          returnsNormally,
          reason: 'seed $seed',
        );
        final text = jsonEncode(out);
        expect(text, isNot(contains('SECRET')), reason: 'seed $seed');
      }
    });
  });

  test('随机生成的 Map / JSON：秘密值由任意标点、括号、引号组成也不泄露', () {
    const secretKeys = [
      'password',
      'token',
      'secret',
      'uuid',
      'Authorization',
      'set-cookie',
      'obfs-password',
      'api_key',
      'key',
      'pwd',
      'auth',
      'sid',
    ];
    const pieces = [
      ', ',
      ',',
      '{',
      '}',
      '[',
      ']',
      '"',
      "'",
      ':',
      ': ',
      '=',
      ' ',
      r'\',
      '&',
      ';',
      '#',
      'a',
      'Z',
      '9',
      'SECRET',
    ];
    String randomText(Random r, {required bool allowSecret}) {
      final buffer = StringBuffer();
      final n = r.nextInt(8) + 1;
      for (var i = 0; i < n; i++) {
        final piece = pieces[r.nextInt(pieces.length)];
        if (piece == 'SECRET' && !allowSecret) continue;
        buffer.write(piece);
      }
      return buffer.toString();
    }

    for (var seed = 0; seed < 600; seed++) {
      final r = Random(seed);
      final secretValue =
          '${randomText(r, allowSecret: true)}SECRET'
          '${randomText(r, allowSecret: true)}';
      final map = <String, Object?>{};
      for (var i = r.nextInt(3); i > 0; i--) {
        map['field$i'] = randomText(r, allowSecret: false);
      }
      final secretKey = secretKeys[r.nextInt(secretKeys.length)];
      Object? container = {secretKey: secretValue};
      // 随机套一层 Map / List，并把秘密项放到普通字段前后。
      switch (r.nextInt(3)) {
        case 0:
          map['nested'] = container;
        case 1:
          map['list'] = [container];
        default:
          map.addAll(container as Map<String, Object?>);
      }
      for (var i = r.nextInt(2); i > 0; i--) {
        map['tail$i'] = randomText(r, allowSecret: false);
      }
      container = map;

      for (final rendered in [container.toString(), jsonEncode(container)]) {
        final once = redactLogText(rendered);
        expect(
          once,
          isNot(contains('SECRET')),
          reason: 'seed $seed\n$rendered\n→ $once',
        );
        expect(redactLogText(once), once, reason: 'seed $seed 幂等');
      }
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
      'Invalid key: [profiles]',
      r'Invalid key: \"profiles\"',
      '[ERROR] profiles.update: Invalid key: profiles',
      'Missing key: "selected_outbound"',
      'SharedPreferences key: clashmiao_analytics_enabled',
      'Invalid signature: expected 3 parts',
      'auth: handshake finished',
      'sid: 12',
      'pwd: /Users/me/code',
      'Bearer realm="clashmiao"',
      // 路径段：普通段、带编码的普通段、编码的分隔符、畸形转义原样保留。
      'https://example.test/api/v1/profiles/%E9%A6%99%E6%B8%AF',
      'https://example.test/api/v1%2Fprofiles%252Fclash',
      'https://example.test/files/100%zz/abc%',
      'https://example.test/s/%E0%A4%A',
      r'{"url":"https:\/\/example.test\/api\/v1\/profiles"}',
      'route: domain_suffix=example.test outbound=proxy',
      'dns: exchange example.test: context deadline exceeded',
      'outbound/vless[hk]: dial tcp 1.2.3.4:443: i/o timeout',
      'inbound/tun[tun-in]: started at 172.19.0.1/30',
      'FormatException: Unexpected character (at character 1)',
      "type 'Null' is not a subtype of type 'String' in type cast",
      'Exception: profile not found (id=7)',
      'status code of 401: Unauthorized',
      '{"server":"h.example.test","port":443,"tag":"hk-01"}',
      '{server: h.example.test, port: 443, tag: hk-01}',
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
    expect(once, isNot(contains('token=t')));
  });
}

class _ThrowingToString {
  @override
  String toString() => throw StateError('no');
}
