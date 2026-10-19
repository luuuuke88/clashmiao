// 崩溃上报发送前的脱敏：与 app.log 同一个脱敏器（[redactLogText]），同一类隐私
// 风险——异常文本里的订阅地址（带 token）、代理分享链接，不能随上报离开设备。
//
// 能整块不要的一律白名单式丢弃，剩下的再过脱敏器：
// - `request`：整个丢掉。App 不上报任何 HTTP 请求，崩溃报告里不需要它；
//   SDK 却会序列化 url / data / env / headers / cookies。
// - `contexts`：只留 device / os / app / runtime / culture / trace，其余（包括
//   FlutterError 集成写入的 `flutter_error_details`、response、feedback 以及任何
//   自定义上下文）全部丢弃；留下的几项把字符串值过一遍脱敏器。
// - tags / extra / 面包屑 data / 异常 mechanism data：递归遍历 Map 与 List，
//   键名是秘密字段（[isSecretFieldName]：token / password / key / cookie …）的
//   整项遮盖，其余字符串过脱敏器；非 JSON 基本类型的对象转成字符串后再过。
// - 事件消息、异常 value、面包屑 message、transaction / culprit：过脱敏器。
// - **不动**堆栈帧：排障要靠它，帧里只有代码位置。
//
// 只在用户主动开启「数据分析」时才会初始化 Sentry（见 main.dart 的门控）；
// 这里保证开启之后发出去的内容同样干净。
//
// `SentryEvent.extra` 已被 SDK 标为弃用，但仍会随事件发送（集成或旧代码可能
// 写入），所以照样要脱敏。
// ignore_for_file: deprecated_member_use

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
    if (params != null) message.params = [for (final p in params) _scrub(p)];
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = redactLogText(value);
    final mechanism = exception.mechanism;
    if (mechanism != null) {
      final description = mechanism.description;
      if (description != null) {
        mechanism.description = redactLogText(description);
      }
      if (mechanism.data.isNotEmpty) {
        mechanism.data = _scrubMap(mechanism.data);
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
  if (extra != null) event.extra = _scrubMap(extra);

  final transaction = event.transaction;
  if (transaction != null) event.transaction = redactLogText(transaction);
  final culprit = event.culprit;
  if (culprit != null) event.culprit = redactLogText(culprit);
  return event;
}

/// `beforeSendTransaction`：性能事务也是一个事件（tags / extra / contexts /
/// request 同样会发送），按同一套规则处理。
SentryTransaction redactSentryTransaction(SentryTransaction transaction) {
  redactSentryEvent(transaction);
  return transaction;
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
  if (data != null) crumb.data = _scrubMap(data);
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
    return fromJson(_scrubMap(toJson(value)));
  } catch (_) {
    return null;
  }
}

// ─── 结构化数据 ───────────────────────────────────────────────────────

Map<String, dynamic> _scrubMap(Map<String, dynamic> map) => {
  for (final entry in map.entries)
    entry.key: _scrubEntry(entry.key, entry.value),
};

Object? _scrubEntry(Object? key, Object? value) {
  if (value == null) return null;
  if (key is String && isSecretFieldName(key)) return kRedacted;
  return _scrub(value);
}

/// 字符串过脱敏器；Map / List 递归；数字、布尔、null 原样；其它对象转成
/// 字符串再过脱敏器（它们序列化时同样会变成文本）。
Object? _scrub(Object? value) => switch (value) {
  null || bool() || num() => value,
  final String s => redactLogText(s),
  final Map<String, dynamic> m => _scrubMap(m),
  final Map<dynamic, dynamic> m => {
    for (final entry in m.entries)
      entry.key: _scrubEntry(entry.key, entry.value),
  },
  final Iterable<dynamic> l => [for (final v in l) _scrub(v)],
  _ => redactLogText(value.toString()),
};
