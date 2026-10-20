// `extra` 已弃用但仍会随事件发送，脱敏要覆盖它。
// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:clashmiao/core/logger/sentry_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 崩溃上报发送前的脱敏：订阅地址里的 token 与代理分享链接不能随事件离开设备；
/// request 整块丢弃，contexts 只留白名单；堆栈帧原样保留。
void main() {
  const subUrl = 'https://example.test/sub?token=SECRET';
  const shareLink = 'vmess://eyJhZGQiOiIxLjIuMy40IiwiaWQiOiJ1dWlkIn0=';

  void expectClean(String? text) {
    expect(text, isNot(contains('SECRET')));
    expect(text, isNot(contains(subUrl)));
    expect(text, isNot(contains('eyJhZGQi')));
  }

  test('事件各字段：订阅地址与分享链接都被脱敏，堆栈帧不动', () {
    final frame = SentryStackFrame(
      absPath: 'package:clashmiao/domain/profile/data/profile_repository.dart',
      function: 'ProfileRepository.update',
      lineNo: 512,
    );
    final event = SentryEvent(
      message: SentryMessage(
        'refresh failed for $subUrl',
        template: 'refresh failed for %s',
        params: [subUrl, 42],
      ),
      exceptions: [
        SentryException(
          type: 'DioException',
          value:
              'DioException [unknown]: null\n'
              'Error: HttpException: Connection closed before full header '
              'was received, uri = $subUrl',
          stackTrace: SentryStackTrace(frames: [frame]),
        ),
      ],
      breadcrumbs: [
        Breadcrumb(
          message: 'import $shareLink',
          data: {
            'url': subUrl,
            'nested': {
              'links': [shareLink],
            },
            'count': 3,
          },
        ),
      ],
      tags: {'profile_url': subUrl, 'phase': 'connecting'},
      extra: {
        'last_link': shareLink,
        'attempt': 2,
        'urls': [subUrl],
      },
    );

    final out = redactSentryEvent(event);

    expectClean(out.message!.formatted);
    expect(
      out.message!.formatted,
      'refresh failed for https://example.test/sub?…',
    );
    expect(out.message!.template, 'refresh failed for %s');
    expectClean(out.message!.params!.first as String);
    expect(out.message!.params![1], 42);

    final exception = out.exceptions!.single;
    expectClean(exception.value);
    expect(exception.type, 'DioException');
    expect(exception.value, contains('HttpException: Connection closed'));
    expect(exception.value, contains('uri = https://example.test/sub?…'));
    expect(exception.stackTrace!.frames.single, same(frame));
    expect(frame.absPath, contains('profile_repository.dart'));
    expect(frame.lineNo, 512);

    final crumb = out.breadcrumbs!.single;
    expect(crumb.message, 'import vmess://…');
    expectClean(crumb.data!['url'] as String);
    expect(
      ((crumb.data!['nested'] as Map)['links'] as List).single,
      'vmess://…',
    );
    expect(crumb.data!['count'], 3);

    expectClean(out.tags!['profile_url']);
    expect(out.tags!['phase'], 'connecting');
    expect(out.extra!['last_link'], 'vmess://…');
    expect(out.extra!['attempt'], 2);
    expectClean((out.extra!['urls'] as List).single as String);
  });

  test('结构化裸秘密：按键名整项遮盖，嵌套 Map / List 里同样生效', () {
    final event = SentryEvent(
      tags: {'token': 'hunter2-tag', 'api_key': 'k1', 'phase': 'connecting'},
      extra: {
        'password': 'hunter2',
        'profile': {
          'name': '机场 A',
          'auth': {'user': 'alice', 'pass': 'x'},
          'servers': [
            {'host': 'h.example.test', 'uuid': 1234},
            {'host': 'h2.example.test', 'obfs-password': 'hunter3'},
          ],
        },
        'empty_token': null,
      },
      breadcrumbs: [
        Breadcrumb(
          message: 'login',
          data: {
            'Authorization': 'Bearer abc',
            'headers': [
              {'Cookie': 'sid=abc; theme=dark'},
            ],
            'count': 2,
          },
        ),
      ],
    );

    final out = redactSentryEvent(event);

    expect(out.tags, {'token': '…', 'api_key': '…', 'phase': 'connecting'});
    final extra = out.extra!;
    expect(extra['password'], '…');
    final profile = extra['profile'] as Map;
    expect(profile['name'], '机场 A');
    expect(profile['auth'], '…', reason: '秘密键名下的整个子树都遮盖');
    final servers = profile['servers'] as List;
    expect(servers[0], {'host': 'h.example.test', 'uuid': '…'});
    expect(servers[1], {'host': 'h2.example.test', 'obfs-password': '…'});
    expect(extra.containsKey('empty_token'), isTrue);
    expect(extra['empty_token'], isNull);

    final data = out.breadcrumbs!.single.data!;
    expect(data['Authorization'], '…');
    expect(((data['headers'] as List).single as Map)['Cookie'], '…');
    expect(data['count'], 2);

    final json = jsonEncode(out.toJson());
    for (final secret in ['hunter2', 'hunter3', 'alice', 'Bearer abc', 'k1']) {
      expect(json, isNot(contains(secret)), reason: secret);
    }
  });

  test('contexts 白名单：FlutterError 诊断上下文丢弃，保留项的字符串也脱敏', () {
    // 与 FlutterError 集成构造的上下文同形：诊断信息里可能带订阅地址。
    final contexts = Contexts(
      device: SentryDevice(name: 'Pixel 9', model: 'pixel'),
      operatingSystem: SentryOperatingSystem(name: 'Android', version: '15'),
      app: SentryApp(name: 'ClashMiao', viewNames: ['/profiles?url=$subUrl']),
      culture: SentryCulture(locale: 'zh-CN'),
      runtimes: [SentryRuntime(key: 'dart', name: 'Dart', version: '3.9')],
      trace: SentryTraceContext(
        operation: 'ui.load',
        description: 'load $subUrl',
        sampled: false,
      ),
      browser: SentryBrowser(name: 'webview'),
      response: SentryResponse(statusCode: 500, data: {'token': 'SECRET'}),
    );
    contexts['flutter_error_details'] = {
      'context': 'thrown while importing $subUrl',
      'information': 'subscription: $subUrl',
      'library': 'widgets library',
    };
    contexts['custom'] = {'note': 'anything'};

    final out = redactSentryEvent(SentryEvent(contexts: contexts));
    final json = out.contexts.toJson();

    expect(
      json.keys.toSet(),
      {'device', 'os', 'app', 'culture', 'dart', 'trace'},
      reason: '只留 device / os / app / runtime / culture / trace',
    );
    expect(out.contexts['flutter_error_details'], isNull);
    expect(out.contexts.response, isNull);
    expect(out.contexts.browser, isNull);
    expect(out.contexts.device!.name, 'Pixel 9');
    expect(out.contexts.operatingSystem!.version, '15');
    expect(out.contexts.culture!.locale, 'zh-CN');
    expect(out.contexts.runtimes.single.key, 'dart');
    expect(out.contexts.runtimes.single.version, '3.9');
    expect(out.contexts.trace!.sampled, isFalse);
    expect(out.contexts.trace!.description, 'load https://example.test/sub?…');
    expect(out.contexts.app!.viewNames, [
      '/profiles?url=https://example.test/sub?…',
    ]);
    expectClean(jsonEncode(json));
  });

  test('request 整块丢弃：url、data、env、headers、cookies 都不发送', () {
    final event = SentryEvent(
      request: SentryRequest(
        url: subUrl,
        method: 'POST',
        queryString: 'token=SECRET',
        fragment: 'SECRET',
        cookies: 'sid=SECRET',
        data: {'password': 'SECRET', 'note': subUrl},
        env: {'SUB_URL': subUrl, 'REMOTE_ADDR': '10.0.0.1'},
        headers: {'Authorization': 'Bearer SECRET'},
      ),
    );

    final out = redactSentryEvent(event);

    expect(out.request, isNull);
    final json = out.toJson();
    expect(json.containsKey('request'), isFalse);
    expectClean(jsonEncode(json));
    expect(jsonEncode(json), isNot(contains('10.0.0.1')));
  });

  test('整个事件序列化后任何位置都不出现秘密或完整的敏感地址', () {
    final frame = SentryStackFrame(
      absPath: 'package:clashmiao/features/profile/profiles_page.dart',
      function: '_ProfilesPageState._import',
      lineNo: 88,
    );
    final contexts = Contexts(
      device: SentryDevice(name: 'Pixel 9'),
      app: SentryApp(name: 'ClashMiao', viewNames: ['import $shareLink']),
      trace: SentryTraceContext(operation: 'ui.action', description: subUrl),
    );
    contexts['flutter_error_details'] = {'information': 'url: $subUrl'};
    final event = SentryEvent(
      message: SentryMessage(
        'import failed: $subUrl',
        template: 'import failed: %s',
        params: [
          subUrl,
          {'password': 'SECRET-PARAM'},
        ],
      ),
      transaction: 'import $subUrl',
      culprit: 'fetch $subUrl',
      exceptions: [
        SentryException(
          type: 'HttpException',
          value: 'Connection closed, uri = $subUrl',
          mechanism: Mechanism(
            type: 'FlutterError',
            description: 'while fetching $subUrl',
            data: {'token': 'SECRET-MECH', 'url': subUrl},
          ),
          stackTrace: SentryStackTrace(frames: [frame]),
        ),
      ],
      breadcrumbs: [
        Breadcrumb(
          message: 'GET $subUrl',
          data: {
            'secret': 'SECRET-CRUMB',
            'deep': [
              {
                'list': [
                  {'refresh_token': 'SECRET-DEEP'},
                  'Authorization: Basic SECRET-BASIC',
                ],
              },
            ],
          },
        ),
      ],
      request: SentryRequest(url: subUrl, data: 'password=SECRET-BODY'),
      tags: {'sid': 'SECRET-TAG', 'url': subUrl},
      extra: {
        'cookie': 'SECRET-COOKIE',
        'raw': '{"server":"h.example.test","password":"SECRET JSON"}',
        'object': Uri.parse(subUrl),
      },
      contexts: contexts,
    );

    // 先确认这些秘密在脱敏前真的会被序列化出去，断言才有意义。
    // extra 里的 Uri 不是 JSON 基本类型，这里按 toString 序列化来看原文。
    final before = jsonEncode(
      event.toJson(),
      toEncodable: (Object? o) => o.toString(),
    );
    for (final secret in [
      'SECRET-PARAM',
      'SECRET-MECH',
      'SECRET-CRUMB',
      'SECRET-DEEP',
      'SECRET-BASIC',
      'SECRET-BODY',
      'SECRET-TAG',
      'SECRET-COOKIE',
      'SECRET JSON',
      'flutter_error_details',
      subUrl,
    ]) {
      expect(before, contains(secret), reason: '脱敏前应能序列化出 $secret');
    }

    final out = redactSentryEvent(event);
    final serialized = jsonEncode(out.toJson());

    expect(serialized, isNot(contains('SECRET')));
    expect(serialized, isNot(contains(subUrl)));
    expect(serialized, isNot(contains('eyJhZGQi')));
    expect(serialized, isNot(contains('flutter_error_details')));
    // 排障信息还在：主机、异常类别、堆栈帧。
    expect(serialized, contains('https://example.test/sub?…'));
    expect(serialized, contains('HttpException'));
    expect(serialized, contains('_ProfilesPageState._import'));
    expect(serialized, contains('h.example.test'));
    expect(out.exceptions!.single.stackTrace!.frames.single, same(frame));
  });

  test('性能事务走同一套规则（经真实 Hub 的 beforeSendTransaction）', () async {
    SentryTransaction? captured;
    final options = SentryOptions(dsn: 'https://public@example.test/1')
      ..tracesSampleRate = 1
      ..transport = _DiscardingTransport()
      ..beforeSendTransaction = (transaction, hint) =>
          captured = redactSentryTransaction(transaction);
    final hub = Hub(options);
    addTearDown(hub.close);
    hub.configureScope((scope) {
      scope.setContexts('flutter_error_details', {'information': subUrl});
    });

    final span = hub.startTransaction('import', 'ui.action', bindToScope: true)
      ..setTag('token', 'SECRET')
      ..setTag('phase', 'importing');
    await span.finish();

    final out = captured!;
    expect(out.request, isNull);
    expect(out.tags!['token'], '…');
    expect(out.tags!['phase'], 'importing');
    expect(out.contexts['flutter_error_details'], isNull);
    expect(out.contexts.trace, isNotNull, reason: '事务必须保留 trace 上下文');
    expect(out.contexts.trace!.operation, 'ui.action');
    expect(jsonEncode(out.toJson()), isNot(contains('SECRET')));
  });

  test('抛出物是 Map 时，异常 value 先按键名结构化脱敏', () {
    final thrown = {
      'server': 'h.example.test',
      'password': 'first line\nSECRET second line',
    };
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: '_Map<String, String>',
          value: thrown.toString(),
          throwable: thrown,
        ),
      ],
    );

    final out = redactSentryEvent(event);

    // 结构化后是 `password: …}`，文本规则再按「遮到行尾」收一次，`}` 也一并遮掉。
    expect(
      out.exceptions!.single.value,
      '{server: h.example.test, password: …',
    );
    expect(jsonEncode(out.toJson()), isNot(contains('SECRET')));
  });

  test('循环引用的抛出物、extra、面包屑 data：不抛异常，秘密不残留', () {
    final thrown = <String, Object?>{'password': 'SECRET'};
    thrown['self'] = thrown;
    final list = <Object?>['https://example.test/sub?token=SECRET'];
    list.add(list);
    final crumbData = <String, dynamic>{'token': 'SECRET'};
    crumbData['loop'] = crumbData;
    final event = SentryEvent(
      exceptions: [
        SentryException(type: '_Map', value: 'cyclic', throwable: thrown),
      ],
      extra: {'list': list},
      breadcrumbs: [Breadcrumb(message: 'x', data: crumbData)],
    );

    late SentryEvent out;
    expect(() => out = redactSentryEvent(event), returnsNormally);
    final json = jsonEncode(out.toJson());
    expect(json, isNot(contains('SECRET')));
    expect(json, contains('<cycle>'));
  });

  test('beforeBreadcrumb：消息与 data 脱敏；null 原样返回', () {
    final crumb = redactBreadcrumb(
      Breadcrumb(
        message: 'GET $subUrl',
        category: 'http',
        data: {'url': subUrl, 'status_code': 500, 'token': 'SECRET'},
      ),
    )!;
    expect(crumb.message, 'GET https://example.test/sub?…');
    expect(crumb.data!['url'], 'https://example.test/sub?…');
    expect(crumb.data!['status_code'], 500);
    expect(crumb.data!['token'], '…');
    expect(crumb.category, 'http');
    expect(redactBreadcrumb(null), isNull);
  });

  test('不敏感的事件原样通过', () {
    final event = SentryEvent(
      message: SentryMessage('Bad state: boom'),
      exceptions: [
        SentryException(type: 'StateError', value: 'Bad state: boom'),
      ],
      tags: {'phase': 'connected'},
    );
    final out = redactSentryEvent(event);
    expect(out.message!.formatted, 'Bad state: boom');
    expect(out.exceptions!.single.value, 'Bad state: boom');
    expect(out.tags, {'phase': 'connected'});
  });
}

/// 什么都不发：测试里的 Hub 不能真的联网。
class _DiscardingTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      const SentryId.empty();
}
