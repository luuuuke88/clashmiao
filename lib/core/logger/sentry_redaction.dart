// 崩溃上报发送前的脱敏：与 app.log 同一个脱敏器（[redactLogText]），同一类隐私
// 风险——异常文本里的订阅地址（带 token）、代理分享链接，不能随上报离开设备。
//
// 覆盖：异常的 value、事件消息（formatted / template / 字符串参数）、面包屑的
// message 与 data、请求的 url / query / fragment / headers、tags 与 extra 里的
// 字符串值（递归进 Map / List）。**不动**堆栈帧：排障要靠它，帧里只有代码位置。
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
  final message = event.message;
  if (message != null) {
    message.formatted = redactLogText(message.formatted);
    final template = message.template;
    if (template != null) message.template = redactLogText(template);
    final params = message.params;
    if (params != null) message.params = [for (final p in params) _redact(p)];
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.value;
    if (value != null) exception.value = redactLogText(value);
  }

  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    for (final crumb in breadcrumbs) {
      _redactBreadcrumbInPlace(crumb);
    }
  }

  final request = event.request;
  if (request != null) _redactRequestInPlace(request);

  final tags = event.tags;
  if (tags != null) {
    event.tags = {
      for (final entry in tags.entries) entry.key: redactLogText(entry.value),
    };
  }

  final extra = event.extra;
  if (extra != null) {
    event.extra = {
      for (final entry in extra.entries) entry.key: _redact(entry.value),
    };
  }
  return event;
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
  if (data != null) {
    crumb.data = {
      for (final entry in data.entries) entry.key: _redact(entry.value),
    };
  }
}

const _secretHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
};

void _redactRequestInPlace(SentryRequest request) {
  final url = request.url;
  if (url != null) request.url = redactLogText(url);
  // 查询串与片段整体抹掉：订阅 token 最常放在这里，逐项判断没有意义。
  final query = request.queryString;
  if (query != null && query.isNotEmpty) request.queryString = kRedacted;
  final fragment = request.fragment;
  if (fragment != null && fragment.isNotEmpty) request.fragment = kRedacted;
  final cookies = request.cookies;
  if (cookies != null && cookies.isNotEmpty) request.cookies = kRedacted;
  final headers = request.headers;
  if (headers.isNotEmpty) {
    request.headers = {
      for (final entry in headers.entries)
        entry.key: _secretHeaders.contains(entry.key.toLowerCase())
            ? kRedacted
            : redactLogText(entry.value),
    };
  }
}

/// 字符串脱敏；Map / List 递归；其它类型原样返回。
Object? _redact(Object? value) => switch (value) {
  final String s => redactLogText(s),
  final Map<dynamic, dynamic> m => {
    for (final entry in m.entries) entry.key: _redact(entry.value),
  },
  final List<dynamic> l => [for (final v in l) _redact(v)],
  _ => value,
};
