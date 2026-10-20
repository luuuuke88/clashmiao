// 崩溃上报发送前的脱敏：与 app.log 同一个脱敏器（[redactLogText]），同一类隐私
// 风险——异常文本里的订阅地址（带 token）、代理分享链接，不能随上报离开设备。
//
// 能整块不要的一律白名单式丢弃，剩下的再过脱敏器：
// - `request`：整个丢掉。App 不上报任何 HTTP 请求，崩溃报告里不需要它；
//   SDK 却会序列化 url / data / env / headers / cookies。
// - `contexts`：只留 device / os / app / runtime / culture / trace，其余（包括
//   FlutterError 集成写入的 `flutter_error_details`、response、feedback 以及任何
//   自定义上下文）全部丢弃；留下的几项把字符串值过一遍脱敏器。
// - tags / extra / 面包屑 data / 异常 mechanism data / 消息参数：递归遍历 Map 与
//   List（[redactStructuredValue]），键名是秘密字段（[isSecretFieldName]：token /
//   password / key / cookie …）的整项遮盖，其余字符串过脱敏器；非 JSON 基本类型
//   的对象转成字符串后再过。
// - 事件消息、异常 value、面包屑 message、transaction / culprit：过脱敏器。抛出
//   的是 Map / List 时，异常 value 先按键名结构化脱敏再转文本。
// - 性能事务的子 span：没结束的整个移除（脱敏后它仍可能被写入）；已结束的按
//   白名单脱敏后换成与原对象脱钩的冻结快照（见 [redactSentryTransaction]）。
// - **不动**堆栈帧：排障要靠它，帧里只有代码位置。
//
// 只在用户主动开启「数据分析」时才会初始化 Sentry（见 main.dart 的门控）；
// 这里保证开启之后发出去的内容同样干净。
//
// `SentryEvent.extra` 已被 SDK 标为弃用，但仍会随事件发送（集成或旧代码可能
// 写入），所以照样要脱敏。
// ignore_for_file: deprecated_member_use

import 'dart:convert';

import 'package:clashmiao/core/logger/log_redactor.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// `beforeSend`：原地脱敏后返回同一个事件。
SentryEvent redactSentryEvent(SentryEvent event) {
  event.request = null;
  event.contexts = _keepAllowedContexts(event.contexts);

  final message = event.message;
  if (message != null) {
    message.formatted = redactLogText(message.formatted);
    final template = message.template;
    if (template != null) message.template = redactLogText(template);
    final params = message.params;
    if (params != null) {
      message.params = [for (final p in params) redactStructuredValue(p)];
    }
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final throwable = exception.throwable;
    if (throwable is Map || throwable is Iterable) {
      // 结构化的抛出物：先按键名脱敏再转文本，不靠事后从文本里猜边界。
      exception.value = redactLogText('${redactStructuredValue(throwable)}');
    } else {
      final value = exception.value;
      if (value != null) exception.value = redactLogText(value);
    }
    final mechanism = exception.mechanism;
    if (mechanism != null) {
      final description = mechanism.description;
      if (description != null) {
        mechanism.description = redactLogText(description);
      }
      if (mechanism.data.isNotEmpty) {
        mechanism.data = redactStructuredMap(mechanism.data);
      }
    }
  }

  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    for (final crumb in breadcrumbs) {
      _redactBreadcrumbInPlace(crumb);
    }
  }

  final tags = event.tags;
  if (tags != null) {
    event.tags = {
      for (final entry in tags.entries)
        entry.key: isSecretFieldName(entry.key)
            ? kRedacted
            : redactLogText(entry.value),
    };
  }

  final extra = event.extra;
  if (extra != null) event.extra = redactStructuredMap(extra);

  final transaction = event.transaction;
  if (transaction != null) event.transaction = redactLogText(transaction);
  final culprit = event.culprit;
  if (culprit != null) event.culprit = redactLogText(culprit);
  return event;
}

/// `beforeSendTransaction`：性能事务也是一个事件（tags / extra / contexts /
/// request 同样会发送），按同一套规则处理。事务里的子 span 也会随事务一起序列化
/// 发送，处理分三步：
///
/// 1. **移除还没结束的子 span**。sentry 10 允许父事务先于子 span 结束，事务里
///    保存的是子 span 本身；信封要到稍后才序列化，没结束的子 span 在这期间仍能
///    被 `setData` / `setTag` 写入，脱敏之后再写进去的内容会原样发出。它们的
///    时间本来就不完整，丢掉不损失什么。
/// 2. 已结束的子 span 取一次 JSON，按白名单逐字段脱敏（见 [_redactSpanJson]）。
/// 3. 用 [_RedactedSpanSnapshot] 换掉事务里的原对象：快照只会序列化这份脱敏后的
///    JSON，与原 span 完全脱钩，之后谁再改原 span 都进不了信封。原 span 本身
///    不改动。
///
/// 某个子 span 取不到 JSON 或脱敏失败时只丢掉它；事务的 span 列表改不了时整个
/// 事务都不发（返回 null）——宁可少一条性能数据，也不发出没过滤的内容。
SentryTransaction? redactSentryTransaction(SentryTransaction transaction) {
  redactSentryEvent(transaction);
  final spans = transaction.spans;
  try {
    spans.removeWhere((span) => !span.finished);
    for (var i = spans.length - 1; i >= 0; i--) {
      final span = spans[i];
      if (span is _RedactedSpanSnapshot) continue;
      final snapshot = _RedactedSpanSnapshot.tryCapture(span);
      if (snapshot == null) {
        spans.removeAt(i);
      } else {
        spans[i] = snapshot;
      }
    }
  } catch (_) {
    return null;
  }
  return transaction;
}

/// 子 span 序列化后各键的处理：id、时间戳、状态、来源原样保留；op / description
/// 过脱敏器；data 按键名结构化脱敏；tags 键名是秘密字段的整项遮盖、其余过
/// 脱敏器。白名单以外的键（SDK 以后新增的字段）一律丢弃。
Map<String, dynamic> _redactSpanJson(Map<String, dynamic> json) {
  final out = <String, dynamic>{};
  for (final entry in json.entries) {
    final value = entry.value;
    switch (entry.key) {
      case 'span_id' ||
          'trace_id' ||
          'parent_span_id' ||
          'start_timestamp' ||
          'timestamp' ||
          'status' ||
          'origin':
        out[entry.key] = value is String ? value : '$value';
      case 'op' || 'description':
        if (value != null) out[entry.key] = redactLogText('$value');
      case 'data':
        if (value is Map) {
          out['data'] = redactStructuredMap(Map<String, dynamic>.from(value));
        }
      case 'tags':
        if (value is Map) {
          out['tags'] = <String, String>{
            for (final tag in value.entries)
              '${tag.key}': isSecretFieldName('${tag.key}')
                  ? kRedacted
                  : redactLogText('${tag.value}'),
          };
        }
    }
  }
  return out;
}

/// 已结束、已脱敏的子 span 的冻结快照：序列化时只吐出构造时那份 JSON 的拷贝。
///
/// 发送管线拿到事务后只会读 span 个数和逐个 `toJson()`；其余成员照接口给出
/// 合理的只读值，写操作一律忽略。
class _RedactedSpanSnapshot implements SentrySpan {
  _RedactedSpanSnapshot._(this._source, this._encoded);

  /// 取 [span] 当下的 JSON 并脱敏、编码成字符串定格；任何一步失败返回 null。
  static _RedactedSpanSnapshot? tryCapture(SentrySpan span) {
    try {
      return _RedactedSpanSnapshot._(
        span,
        jsonEncode(_redactSpanJson(span.toJson())),
      );
    } catch (_) {
      return null;
    }
  }

  final SentrySpan _source;
  final String _encoded;

  Map<String, dynamic> get _json =>
      jsonDecode(_encoded) as Map<String, dynamic>;

  @override
  Map<String, dynamic> toJson() => _json;

  @override
  Map<String, dynamic> get data => Map.unmodifiable(
    (_json['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
  );

  @override
  Map<String, String> get tags => Map.unmodifiable(
    ((_json['tags'] as Map<String, dynamic>?) ?? const <String, dynamic>{}).map(
      (key, value) => MapEntry(key, '$value'),
    ),
  );

  /// 新建的上下文对象，描述是脱敏后的；改它不影响快照。
  @override
  SentrySpanContext get context {
    final json = _json;
    final source = _source.context;
    return SentrySpanContext(
      traceId: source.traceId,
      spanId: source.spanId,
      parentSpanId: source.parentSpanId,
      operation: json['op'] as String? ?? '',
      description: json['description'] as String?,
      origin: json['origin'] as String?,
    );
  }

  @override
  bool get finished => true;
  @override
  bool get isRootSpan => false;
  @override
  DateTime get startTimestamp => _source.startTimestamp;
  @override
  DateTime? get endTimestamp => _source.endTimestamp;
  @override
  SpanStatus? get status => _source.status;
  @override
  String? get origin => _json['origin'] as String?;
  @override
  dynamic get throwable => null;
  @override
  SentryTracesSamplingDecision? get samplingDecision =>
      _source.samplingDecision;

  @override
  SentryTraceHeader toSentryTrace() => _source.toSentryTrace();
  @override
  SentryBaggageHeader? toBaggageHeader() => _source.toBaggageHeader();
  @override
  SentryTraceContextHeader? traceContext() => _source.traceContext();

  /// 只剩 SDK 内部成员（`tracer`，类型不对外导出）：发送管线不会在子 span 上
  /// 用到它，万一用到就明确报错，而不是悄悄返回原对象。
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('脱敏快照不支持 ${invocation.memberName}');

  // ── 写操作：快照已定格，一律忽略 ──
  @override
  set status(SpanStatus? status) {}
  @override
  set origin(String? origin) {}
  @override
  set throwable(dynamic throwable) {}
  @override
  void setTag(String key, String value) {}
  @override
  void removeTag(String key) {}
  @override
  void setData(String key, dynamic value) {}
  @override
  void removeData(String key) {}
  @override
  void setMeasurement(String name, num value, {SentryMeasurementUnit? unit}) {}
  @override
  void scheduleFinish() {}
  @override
  Future<void> finish({
    SpanStatus? status,
    DateTime? endTimestamp,
    Hint? hint,
  }) async {}
  @override
  ISentrySpan startChild(
    String operation, {
    String? description,
    DateTime? startTimestamp,
  }) => NoOpSentrySpan();
}

/// `beforeBreadcrumb`：原地脱敏后返回同一条面包屑。
Breadcrumb? redactBreadcrumb(Breadcrumb? breadcrumb) {
  if (breadcrumb == null) return null;
  _redactBreadcrumbInPlace(breadcrumb);
  return breadcrumb;
}

void _redactBreadcrumbInPlace(Breadcrumb crumb) {
  final message = crumb.message;
  if (message != null) crumb.message = redactLogText(message);
  final data = crumb.data;
  if (data != null) crumb.data = redactStructuredMap(data);
}

// ─── contexts 白名单 ──────────────────────────────────────────────────

/// 只把 device / os / app / runtime / culture / trace 搬进一个新的
/// [Contexts]；每项经 JSON 往返时把字符串值脱敏。往返失败的项直接丢掉
/// （宁可少一项诊断信息，也不发出没过滤的内容）。
Contexts _keepAllowedContexts(Contexts source) {
  final kept = Contexts();
  kept.device = _roundTrip(
    source.device,
    (v) => v.toJson(),
    SentryDevice.fromJson,
  );
  kept.operatingSystem = _roundTrip(
    source.operatingSystem,
    (v) => v.toJson(),
    SentryOperatingSystem.fromJson,
  );
  kept.app = _roundTrip(source.app, (v) => v.toJson(), SentryApp.fromJson);
  kept.culture = _roundTrip(
    source.culture,
    (v) => v.toJson(),
    SentryCulture.fromJson,
  );

  final trace = source.trace;
  final keptTrace = _roundTrip(
    trace,
    (v) => v.toJson(),
    SentryTraceContext.fromJson,
  );
  // `sampled` 不在 JSON 里，fromJson 一律置 true；照原值还回去。
  if (keptTrace != null) keptTrace.sampled = trace!.sampled;
  kept.trace = keptTrace;

  kept.runtimes = [
    for (final runtime in source.runtimes)
      if (_roundTrip(runtime, (v) => v.toJson(), SentryRuntime.fromJson)
          case final copy?)
        copy..key = runtime.key,
  ];
  return kept;
}

T? _roundTrip<T>(
  T? value,
  Map<String, dynamic> Function(T value) toJson,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value == null) return null;
  try {
    return fromJson(redactStructuredMap(toJson(value)));
  } catch (_) {
    return null;
  }
}
