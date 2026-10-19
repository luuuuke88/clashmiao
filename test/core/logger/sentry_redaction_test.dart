// `extra` 已弃用但仍会随事件发送，脱敏要覆盖它。
// ignore_for_file: deprecated_member_use

import 'package:clashmiao/core/logger/sentry_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// 崩溃上报发送前的脱敏：订阅地址里的 token 与代理分享链接不能随事件离开设备；
/// 堆栈帧原样保留。
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
      request: SentryRequest(
        url: subUrl,
        queryString: 'token=SECRET',
        fragment: 'SECRET',
        headers: {
          'Authorization': 'Bearer SECRET',
          'X-Trace': 'link $shareLink',
        },
      ),
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

    final request = out.request!;
    expect(request.url, 'https://example.test/sub?…');
    expect(request.queryString, '…');
    expect(request.fragment, '…');
    expect(request.headers['Authorization'], '…');
    expect(request.headers['X-Trace'], 'link vmess://…');

    expectClean(out.tags!['profile_url']);
    expect(out.tags!['phase'], 'connecting');
    expect(out.extra!['last_link'], 'vmess://…');
    expect(out.extra!['attempt'], 2);
    expectClean((out.extra!['urls'] as List).single as String);
  });

  test('beforeBreadcrumb：消息与 data 脱敏；null 原样返回', () {
    final crumb = redactBreadcrumb(
      Breadcrumb(
        message: 'GET $subUrl',
        category: 'http',
        data: {'url': subUrl, 'status_code': 500},
      ),
    )!;
    expect(crumb.message, 'GET https://example.test/sub?…');
    expect(crumb.data!['url'], 'https://example.test/sub?…');
    expect(crumb.data!['status_code'], 500);
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
