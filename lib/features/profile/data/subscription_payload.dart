/// 订阅响应体的**廉价分类**。
///
/// 目的不是替代 native parse，而是在拿到响应之后、送去解析之前回答两个问题：
///
/// 1. 这压根不是配置（订阅面板常见的做法：UA 不在白名单时返回一个 HTTP 200
///    的 HTML「访问已拒绝」页——状态码骗不了人，只能靠内容判断）。
/// 2. 这是一份结构合法、但**节点列表是空的**配置（同样是 UA 白名单的产物：
///    面板认得这是个客户端、但不认得是哪个，于是发一份没有节点的骨架）。
///
/// 这两种情况送进 native parse 都会得到同一句 `no outbounds found`，用户完全
/// 无从判断该怎么办。分开之后才能给出可操作的提示。
///
/// **保守原则**：只有在能确信的情况下才报 [nodeCount] == 0；任何拿不准的输入
/// 一律返回 [unknownNodeCount]，交给 native parse 决定。宁可漏判，不可误判——
/// 误判会把一份好订阅挡在门外。
library;

import 'dart:convert';

enum SubscriptionPayloadKind {
  /// sing-box 原生 JSON 配置。
  singboxJson,

  /// Clash / Clash.Meta YAML 配置。
  clashYaml,

  /// HTML 页面——不是配置。
  html,

  /// 其它（base64 节点列表、单条 vless:// 链接等），交给 native parse。
  unknown,
}

/// [SubscriptionPayloadAnalysis.nodeCount] 的哨兵值：数不出来，别据此下结论。
const int unknownNodeCount = -1;

class SubscriptionPayloadAnalysis {
  const SubscriptionPayloadAnalysis({
    required this.kind,
    required this.nodeCount,
  });

  final SubscriptionPayloadKind kind;

  /// 能确信数出来的节点数；数不出来时为 [unknownNodeCount]。
  final int nodeCount;

  /// 明确是「拿到了东西，但里面一个节点都没有」。
  bool get isDefinitelyEmpty => nodeCount == 0;

  /// 明确不是配置文件。
  bool get isNotAConfig => kind == SubscriptionPayloadKind.html;

  /// 值得拿去 native parse 的响应。
  bool get looksUsable => !isNotAConfig && !isDefinitelyEmpty;
}

/// 顶层 `proxies:` 后面直接跟一个空列表。用行锚定，避免匹配到嵌套在
/// proxy-groups 里的同名键（那些必然有缩进）。
final _emptyClashProxies = RegExp(r'^proxies:\s*\[\s*\]\s*$', multiLine: true);

/// 正文开头的 HTML 特征。只看开头：配置文件里出现 `<html` 的可能性不为零
/// （比如某个节点名里带尖括号），但它不会出现在第一个非空白字符处。
final _htmlPrefix = RegExp(
  r'^\s*(<!doctype\s+html|<html[\s>])',
  caseSensitive: false,
);

SubscriptionPayloadAnalysis analyzeSubscriptionPayload(
  String body, {
  String? contentType,
}) {
  final declaredHtml =
      contentType != null && contentType.toLowerCase().contains('text/html');
  if (declaredHtml || _htmlPrefix.hasMatch(body)) {
    return const SubscriptionPayloadAnalysis(
      kind: SubscriptionPayloadKind.html,
      nodeCount: 0,
    );
  }

  final trimmed = body.trimLeft();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final outbounds = decoded['outbounds'];
        if (outbounds is List) {
          return SubscriptionPayloadAnalysis(
            kind: SubscriptionPayloadKind.singboxJson,
            nodeCount: outbounds.length,
          );
        }
      }
    } catch (_) {
      // 不是合法 JSON——可能是 base64 或别的东西，交给下面的分支。
    }
  }

  if (_emptyClashProxies.hasMatch(body)) {
    return const SubscriptionPayloadAnalysis(
      kind: SubscriptionPayloadKind.clashYaml,
      nodeCount: 0,
    );
  }

  return const SubscriptionPayloadAnalysis(
    kind: SubscriptionPayloadKind.unknown,
    nodeCount: unknownNodeCount,
  );
}
