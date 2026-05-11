/// 出站代理节点
class OutboundProxy {
  const OutboundProxy({
    required this.tag,
    required this.type,
    this.delay = 0,
    this.isSelected = false,
  });

  final String tag;
  final String type;
  final int delay;
  final bool isSelected;

  /// 解析核心库推送的 JSON（kebab-case 字段名）
  factory OutboundProxy.fromJson(Map<String, dynamic> json) {
    return OutboundProxy(
      tag: json['tag'] as String? ?? '',
      type: json['type'] as String? ?? '',
      // sing-box 推送的是 url-test-delay
      delay:
          json['url-test-delay'] as int? ??
          json['urlTestDelay'] as int? ??
          json['delay'] as int? ??
          0,
      isSelected: json['isSelected'] as bool? ?? false,
    );
  }

  OutboundProxy copyWith({
    String? tag,
    String? type,
    int? delay,
    bool? isSelected,
  }) {
    return OutboundProxy(
      tag: tag ?? this.tag,
      type: type ?? this.type,
      delay: delay ?? this.delay,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  /// 延迟文本显示
  String get delayText {
    if (delay <= 0) return '-';
    return '${delay}ms';
  }

  /// 延迟等级
  DelayLevel get delayLevel {
    if (delay <= 0) return DelayLevel.unknown;
    if (delay < 200) return DelayLevel.fast;
    if (delay < 500) return DelayLevel.medium;
    return DelayLevel.slow;
  }
}

enum DelayLevel { unknown, fast, medium, slow }

/// 出站代理组
class OutboundGroup {
  const OutboundGroup({
    required this.tag,
    required this.type,
    required this.selected,
    required this.items,
  });

  final String tag;
  final String type;
  final String selected;
  final List<OutboundProxy> items;

  /// 解析核心库推送的 JSON（kebab-case 字段名）
  factory OutboundGroup.fromJson(Map<String, dynamic> json) {
    return OutboundGroup(
      tag: json['tag'] as String? ?? '',
      type: json['type'] as String? ?? '',
      selected: json['selected'] as String? ?? '',
      items:
          (json['items'] as List<dynamic>?)
              ?.map((e) => OutboundProxy.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
