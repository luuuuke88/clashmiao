import 'dart:convert';

import 'package:clashmiao/core/logger/sentry_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _dsn = 'https://public@example.test/1';
const _subUrl = 'https://sub.example.test/api/v1/client/subscribe?token=SECRET';

SentryFlutterOptions _production() {
  final options = SentryFlutterOptions();
  configureSentryOptions(options, dsn: _dsn);
  return options;
}

/// 用生产配置建一个真实 Hub，跑一个事务，返回 beforeSendTransaction 的产物；
/// 事务没有经过 beforeSendTransaction 时返回 null。
Future<SentryTransaction?> _sendTransaction(
  SentryFlutterOptions options,
) async {
  SentryTransaction? captured;
  final production = options.beforeSendTransaction!;
  options
    // 只为让这一个事务必定被采样；其余保持生产配置。
    ..tracesSampleRate = 1
    ..transport = _DiscardingTransport()
    ..beforeSendTransaction = (transaction, hint) async =>
        captured = await production(transaction, hint);
  final hub = Hub(options);
  addTearDown(hub.close);

  final span = hub.startTransaction('import', 'ui.action', bindToScope: true)
    ..setTag('token', 'SECRET')
    ..setData('url', _subUrl);
  await span.finish();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生产配置：traceLifecycle 必须是 static，否则事务脱敏会被绕过', () {
    expect(_production().traceLifecycle, SentryTraceLifecycle.static);
  });

  test('生产配置：脱敏回调全部挂上，不带个人信息与截图', () {
    final options = _production();
    expect(options.dsn, _dsn);
    expect(options.beforeSend, isNotNull);
    expect(options.beforeSendTransaction, isNotNull);
    expect(options.beforeBreadcrumb, isNotNull);
    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.tracesSampleRate, 0.05);
  });

  test('生产配置经真实 Hub：事务会经过 beforeSendTransaction 并被脱敏', () async {
    final out = await _sendTransaction(_production());

    expect(out, isNotNull, reason: '事务没有走到 beforeSendTransaction');
    expect(out!.tags!['token'], '…');
    expect(jsonEncode(out.toJson()), isNot(contains('SECRET')));
  });

  test('生产配置经真实 Hub：子 span 的描述 / data / tags 也脱敏，序列化后的信封里没有凭据', () async {
    final options = _production();
    final transport = _CapturingTransport(options);
    options
      // 只为让这一个事务必定被采样；其余（含 static 与脱敏回调）保持生产配置。
      ..tracesSampleRate = 1
      ..transport = transport;
    final hub = Hub(options);
    addTearDown(hub.close);

    final root = hub.startTransaction('import', 'ui.action', bindToScope: true);
    final child =
        root.startChild(
            'http.client',
            description:
                'GET https://sub.example.test/api/v1/sub?token=CHILD_SECRET',
          )
          ..setData('token', 'DATA_SECRET')
          ..setData('http.method', 'GET')
          ..setTag('password', 'TAG_SECRET')
          ..setTag('region', 'hk');
    await child.finish();
    await root.finish();
    await pumpEventQueue();

    expect(transport.envelopes, hasLength(1), reason: '事务应当被发送一次');
    final sent = transport.envelopes.single;
    expect(sent, contains('"type":"transaction"'));
    for (final secret in ['CHILD_SECRET', 'DATA_SECRET', 'TAG_SECRET']) {
      expect(sent, isNot(contains(secret)), reason: '子 span 漏出了 $secret');
    }
    // 无害字段原样保留：脱敏不能把子 span 整个抹掉。
    expect(sent, contains('"op":"http.client"'));
    expect(sent, contains('sub.example.test'));
    expect(sent, contains('"http.method":"GET"'));
    expect(sent, contains('"region":"hk"'));
  });

  test('父事务先结束、子 span 仍开着：脱敏之后再写进子 span 的凭据也不会进信封', () async {
    final options = _production();
    late ISentrySpan child;
    var lateWrites = 0;
    // 脱敏回调已经跑完、信封还没序列化：在这个空档往仍开着的子 span 里写凭据。
    final transport = _CapturingTransport(
      options,
      beforeSerialize: () {
        child
          ..setData('token', 'LATE_DATA_SECRET')
          ..setTag('password', 'LATE_TAG_SECRET');
        lateWrites++;
      },
    );
    options
      ..tracesSampleRate = 1
      ..transport = transport;
    final hub = Hub(options);
    addTearDown(hub.close);

    final root = hub.startTransaction('import', 'ui.action', bindToScope: true);
    child = root.startChild('http.client', description: 'GET /sub');
    final done = root.startChild('db', description: 'select')
      ..setTag('region', 'hk');
    await done.finish();
    // sentry 10 默认不等子 span：父事务先结束，事务照常发送。
    await root.finish();
    await pumpEventQueue();
    addTearDown(child.finish);

    expect(lateWrites, 1, reason: '前提：迟到的写入确实发生在序列化之前');
    expect(child.finished, isFalse, reason: '前提：子 span 在发送时仍未结束');
    final sent = transport.envelopes.single;
    expect(sent, isNot(contains('LATE_DATA_SECRET')));
    expect(sent, isNot(contains('LATE_TAG_SECRET')));
    // 已结束的子 span 照常发送。
    expect(sent, contains('"op":"db"'));
    expect(sent, contains('"region":"hk"'));
  });

  test('对照：改成 stream 时事务根本不经过 beforeSendTransaction', () async {
    // 锁住「为什么必须是 static」：sentry 10 的默认值 stream 下，事务 API 不再
    // 产生经 beforeSendTransaction 的事务。哪天 SDK 行为变了，这条会提醒重新评估。
    final options = _production()..traceLifecycle = SentryTraceLifecycle.stream;
    expect(await _sendTransaction(options), isNull);
  });
}

/// 什么都不发：测试里的 Hub 不能真的联网。
class _DiscardingTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async =>
      const SentryId.empty();
}

/// 把信封按 SDK 的线上格式完整序列化下来（不联网），供断言「最终发出去的内容」。
class _CapturingTransport implements Transport {
  _CapturingTransport(this._options, {this.beforeSerialize});

  final SentryOptions _options;

  /// 在序列化信封之前调用：模拟脱敏回调之后、真正编码之前的空档。
  final void Function()? beforeSerialize;
  final envelopes = <String>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    beforeSerialize?.call();
    final bytes = <int>[];
    await for (final chunk in envelope.envelopeStream(_options)) {
      bytes.addAll(chunk);
    }
    envelopes.add(utf8.decode(bytes));
    return const SentryId.empty();
  }
}
