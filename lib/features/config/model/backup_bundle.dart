/// 备份文件（v2）的内容。
///
/// ```json
/// {
///   "version": 2, "schema": 1, "createdAt": 1700000000000,
///   "profiles": [ {订阅 JSON，不含 inc / active} ],
///   "activeProfileId": "…",
///   "profileConfigs": { "<id>": "<订阅配置文件内容>" },
///   "preferences": { "<键>": <值> }
/// }
/// ```
///
/// 导出时 `preferences` 只含偏好注册表里 `include` 的键；机密与运行时键、
/// 订阅的本机代际 `inc` 一律不导出。
class BackupBundle {
  const BackupBundle({
    required this.schema,
    required this.createdAt,
    required this.profiles,
    required this.activeProfileId,
    required this.profileConfigs,
    required this.preferences,
    this.auxPreferences = const {},
    this.orphanConfigs = const {},
  });

  /// 当前（也是唯一会导出的）备份格式版本。
  static const currentVersion = 2;

  /// 旧格式（嵌套 `settings` 结构）的版本串，只在导入时识别。
  static const legacyVersion = '1.0';

  /// 导出时本机的存储 schema。
  final int schema;
  final int createdAt;
  final List<Map<String, dynamic>> profiles;
  final String? activeProfileId;
  final Map<String, String> profileConfigs;
  final Map<String, Object> preferences;

  /// 订阅名下的附属偏好（手选节点 `proxy_selection_<id>`、延迟缓存
  /// `proxy_delays_<id>`）。**只在恢复前快照里出现**——用户导出的备份不含它们；
  /// 快照带上它们，是因为恢复会删除「不在备份中的订阅」的附属键，失败回滚时要能还原。
  final Map<String, String> auxPreferences;

  /// 恢复前快照专属：`profiles/` 里存在、却不属于任何列表订阅的 `<id>.json`
  /// （订阅被隔离、或遗留的孤儿文件）的 id → 内容。回滚要**原样保留**它们——
  /// 只有「这次恢复新装进来」的文件才能删。用户导出的备份不含。
  final Map<String, String> orphanConfigs;

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'schema': schema,
    'createdAt': createdAt,
    'profiles': profiles,
    'activeProfileId': activeProfileId,
    'profileConfigs': profileConfigs,
    'preferences': preferences,
    if (auxPreferences.isNotEmpty) 'auxPreferences': auxPreferences,
    if (orphanConfigs.isNotEmpty) 'orphanConfigs': orphanConfigs,
  };
}

/// 备份文件不能导入的原因。
enum BackupErrorKind {
  /// 不是 JSON、顶层不是对象、关键字段形状不对。
  invalidFile,

  /// 备份格式版本不认识。
  unsupportedVersion,

  /// 备份由更新版本的应用生成（schema 高于本机支持的版本）。
  newerSchema,

  /// 备份里有订阅，但没有任何一条能导入。
  noUsableProfiles,
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.kind, [this.detail]);

  final BackupErrorKind kind;
  final String? detail;

  @override
  String toString() =>
      'BackupFormatException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// 一次恢复的结果。UI 据此给用户提示。
class RestoreReport {
  const RestoreReport({
    required this.profilesImported,
    required this.profilesDropped,
    required this.profilesRemoved,
    required this.prefsImported,
    required this.prefsSkipped,
    required this.refreshQueued,
    required this.warpDisabled,
    required this.snapshotPath,
    this.skippedPrefKeys = const [],
  });

  /// 导入的订阅数。
  final int profilesImported;

  /// 因校验不通过被丢弃的备份内订阅数。
  final int profilesDropped;

  /// 本机原有、备份里没有、因此被移除的订阅数。
  final int profilesRemoved;

  /// 写入的偏好数。
  final int prefsImported;

  /// 因未登记 / 类型不对 / 值域非法而跳过的偏好数（本机现值保留）。
  final int prefsSkipped;

  /// 备份里缺配置文件、排队在后台补拉的远程订阅数。
  final int refreshQueued;

  /// 备份里 `enableWarp=true`，已按规则导入为 false；需在本机重新启用。
  final bool warpDisabled;

  /// 恢复前快照文件路径（成功后保留最近 3 份）。
  final String snapshotPath;

  final List<String> skippedPrefKeys;
}
