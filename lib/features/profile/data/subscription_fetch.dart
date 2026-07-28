/// 订阅抓取的 User-Agent 回退。
///
/// 背景：相当一部分订阅面板按 User-Agent **白名单**决定发什么内容——认得的
/// 客户端发完整节点，认不得的发一份结构合法但节点为空的骨架，再不认得的直接
/// 发一张 HTML 拒绝页（而且状态码往往还是 200）。ClashMiao 不在任何一家的
/// 白名单里，所以这类订阅在别的客户端能用、在我们这儿只会得到一句
/// `no outbounds found`。
///
/// 处理方式：**先用自己的 UA 请求**——我们不默认伪装成别人；只有当响应明显
/// 不可用（不是配置、或节点为空）时，才依次换用几个通用客户端 UA 重试。
library;

import 'package:clashmiao/features/profile/data/subscription_payload.dart';

/// 回退时依次尝试的 User-Agent。
///
/// `sing-box` 排在最前：ClashMiao 的内核就是 sing-box，面板若认这个 UA，会直接
/// 发一份原生 sing-box 配置，连格式转换都省了。
const List<String> kSubscriptionUserAgentFallbacks = <String>[
  'sing-box/1.11.0',
  'clash-verge/v1.5.0',
  'clash.meta/v1.18.0',
];

class SubscriptionResponse {
  const SubscriptionResponse({
    required this.body,
    this.contentType,
    this.headers = const {},
  });

  final String body;
  final String? contentType;
  final Map<String, List<String>> headers;
}

class SubscriptionFetchResult {
  const SubscriptionFetchResult({
    required this.response,
    required this.userAgent,
    required this.attemptedUserAgents,
  });

  final SubscriptionResponse response;

  /// 最终取用的那次请求所用的 UA。
  final String userAgent;

  /// 本次抓取实际发出过的所有 UA，按顺序。
  final List<String> attemptedUserAgents;
}

/// 抓取失败的原因。分开是为了让上层能给出**可操作**的提示，而不是把三种
/// 完全不同的问题都说成 `no outbounds found`。
enum SubscriptionFetchFailure {
  /// 服务器返回的是网页（多半是拒绝页），根本不是配置文件。
  notAConfig,

  /// 拿到了合法配置，但里面一个节点都没有。
  noNodes,
}

class SubscriptionFetchException implements Exception {
  const SubscriptionFetchException({
    required this.reason,
    required this.attemptedUserAgents,
  });

  final SubscriptionFetchFailure reason;

  /// 已经试过的所有 UA——提示用户"这些都试过了"，也方便贴日志排障。
  final List<String> attemptedUserAgents;

  @override
  String toString() =>
      'SubscriptionFetchException(${reason.name}, tried: ${attemptedUserAgents.join(", ")})';
}

typedef SubscriptionFetcher =
    Future<SubscriptionResponse> Function(String userAgent);

Future<SubscriptionFetchResult> fetchSubscriptionWithUserAgentFallback({
  required String primaryUserAgent,
  required SubscriptionFetcher fetch,
  List<String> fallbackUserAgents = kSubscriptionUserAgentFallbacks,
}) async {
  final attempted = <String>[];
  var sawConfigWithNoNodes = false;

  for (final userAgent in [primaryUserAgent, ...fallbackUserAgents]) {
    attempted.add(userAgent);
    final response = await fetch(userAgent);
    final analysis = analyzeSubscriptionPayload(
      response.body,
      contentType: response.contentType,
    );
    if (analysis.looksUsable) {
      return SubscriptionFetchResult(
        response: response,
        userAgent: userAgent,
        attemptedUserAgents: attempted,
      );
    }
    if (analysis.isDefinitelyEmpty && !analysis.isNotAConfig) {
      sawConfigWithNoNodes = true;
    }
  }

  // 只要曾经拿到过一份"真的是配置、只是没节点"的响应，就按零节点报——那比
  // "服务器返回了网页"更接近用户实际该处理的问题。
  throw SubscriptionFetchException(
    reason: sawConfigWithNoNodes
        ? SubscriptionFetchFailure.noNodes
        : SubscriptionFetchFailure.notAConfig,
    attemptedUserAgents: attempted,
  );
}
