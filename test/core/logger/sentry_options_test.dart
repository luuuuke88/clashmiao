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
