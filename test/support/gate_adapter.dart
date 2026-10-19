import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 可控的假网络：能让指定 URL 的请求「卡住」，直到测试放行。
///
/// 订阅刷新的丢更新问题都发生在「网络请求进行中」这段窗口里，真实 socket 的
/// 时序不可控；这里用 [Completer] 精确卡住请求，再在窗口内执行别的操作，
/// 之后放行，断言最终状态。完全确定、无墙钟依赖。
class GateAdapter implements HttpClientAdapter {
  /// 每次请求到达时记录的 URL（按到达顺序）。
  final List<String> requests = [];

  final Map<String, List<Completer<void>>> _holds = {};
  final Map<String, int> _counts = {};

  /// 自定义响应体；默认给一份带一个节点的 sing-box JSON，且每次内容不同。
  String Function(String url, int nth)? bodyFor;

  /// 自定义响应头。
  Map<String, List<String>> Function(String url, int nth)? headersFor;

  /// 卡住 [url] 的**下一次**请求，返回放行用的 Completer。
  Completer<void> hold(String url) {
    final gate = Completer<void>();
    _holds.putIfAbsent(url, () => []).add(gate);
    return gate;
  }

  int countFor(String url) => _counts[url] ?? 0;

  /// 等到累计至少收到 [count] 次请求。
  Future<void> waitForRequests(int count) async {
    for (var i = 0; i < 5000 && requests.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (requests.length < count) {
      throw StateError('只收到 ${requests.length} 次请求，期望 $count');
    }
  }

  static String defaultBody(String url, int nth) => jsonEncode({
    'outbounds': [
      {'type': 'vless', 'tag': 'node-$nth'},
    ],
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    final nth = _counts.update(url, (n) => n + 1, ifAbsent: () => 1);
    final queue = _holds[url];
    if (queue != null && queue.isNotEmpty) {
      await queue.removeAt(0).future;
    }
    final body = (bodyFor ?? defaultBody)(url, nth);
    return ResponseBody.fromString(
      body,
      HttpStatus.ok,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...?headersFor?.call(url, nth),
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
