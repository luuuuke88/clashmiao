class AdvancedConfig {
  const AdvancedConfig({
    this.remoteDnsOverride,
    this.muxEnabled = false,
    this.muxProtocol = 'h2mux',
    this.muxConcurrency = 4,
    this.fragmentEnabled = false,
    this.fragmentRange,
    this.extra = const {},
  });

  final String? remoteDnsOverride;
  final bool muxEnabled;
  final String muxProtocol;
  final int muxConcurrency;
  final bool fragmentEnabled;
  final String? fragmentRange;

  /// 本版本不认识的字段，原样保留、原样写回（前向兼容：新版本写入的字段
  /// 不会被旧版本的一次保存永久抹掉）。
  final Map<String, dynamic> extra;

  static const _knownKeys = {
    'remoteDnsOverride',
    'muxEnabled',
    'muxProtocol',
    'muxConcurrency',
    'fragmentEnabled',
    'fragmentRange',
  };

  Map<String, dynamic> toJson() => {
    ...extra,
    if (remoteDnsOverride != null) 'remoteDnsOverride': remoteDnsOverride,
    'muxEnabled': muxEnabled,
    'muxProtocol': muxProtocol,
    'muxConcurrency': muxConcurrency,
    'fragmentEnabled': fragmentEnabled,
    if (fragmentRange != null) 'fragmentRange': fragmentRange,
  };

  factory AdvancedConfig.fromJson(Map<String, dynamic> json) => AdvancedConfig(
    remoteDnsOverride: json['remoteDnsOverride'] as String?,
    muxEnabled: json['muxEnabled'] as bool? ?? false,
    muxProtocol: json['muxProtocol'] as String? ?? 'h2mux',
    muxConcurrency: json['muxConcurrency'] as int? ?? 4,
    fragmentEnabled: json['fragmentEnabled'] as bool? ?? false,
    fragmentRange: json['fragmentRange'] as String?,
    extra: Map.unmodifiable({
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    }),
  );
}
