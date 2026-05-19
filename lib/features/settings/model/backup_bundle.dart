class BackupBundle {
  const BackupBundle({
    required this.version,
    required this.profiles,
    this.activeProfileId,
    required this.settings,
    required this.createdAt,
  });

  final String version;
  final List<Map<String, dynamic>> profiles;
  final String? activeProfileId;
  final Map<String, dynamic> settings;
  final int createdAt;

  static const currentVersion = '1.0';

  Map<String, dynamic> toJson() => {
    'version': version,
    'profiles': profiles,
    'activeProfileId': activeProfileId,
    'settings': settings,
    'createdAt': createdAt,
  };

  factory BackupBundle.fromJson(Map<String, dynamic> json) {
    final v = json['version'] as String?;
    if (v != currentVersion) throw Exception('不支持的备份版本: $v');
    return BackupBundle(
      version: v!,
      profiles: (json['profiles'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      activeProfileId: json['activeProfileId'] as String?,
      settings: Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
      createdAt: json['createdAt'] as int,
    );
  }
}
