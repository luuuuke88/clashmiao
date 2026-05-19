class AdvancedConfig {
  const AdvancedConfig({
    this.remoteDnsOverride,
    this.muxEnabled = false,
    this.muxProtocol = 'h2mux',
    this.muxConcurrency = 4,
    this.fragmentEnabled = false,
    this.fragmentRange,
  });

  final String? remoteDnsOverride;
  final bool muxEnabled;
  final String muxProtocol;
  final int muxConcurrency;
  final bool fragmentEnabled;
  final String? fragmentRange;

  Map<String, dynamic> toJson() => {
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
  );
}
