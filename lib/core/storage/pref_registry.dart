import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';

/// 偏好值的类型（与 `SharedPreferences` 的存取类型一一对应）。
enum PrefType { boolean, integer, string, stringList }

/// 备份策略。
enum BackupPolicy {
  /// 随备份导出，导入时（校验通过后）写回。
  include,

  /// 运行时 / 派生 / 本机状态：不导出，导入时也一律忽略。
  exclude,

  /// 机密（WARP 凭证等）：不导出，导入时也一律忽略。
  secret,
}

/// 一个偏好键的合法性判定：输入已经通过类型检查，返回值是否可以接受。
typedef PrefValidator = bool Function(Object value);

/// 登记的一个偏好键。
class PrefSpec {
  const PrefSpec(
    this.key,
    this.type,
    this.backup, {
    this.nativeShared = false,
    this.defaultValue,
    this.validator,
  });

  /// Dart 侧键名（原生侧读取时多一个 `flutter.` 前缀）。
  final String key;
  final PrefType type;
  final BackupPolicy backup;

  /// 原生代码（Android Kotlin）也在读写这个键。这些键的名字、类型、默认值
  /// 由契约测试与 `Constants.kt` / `Prefs.kt` 对齐。
  final bool nativeShared;

  /// 仅原生共享键需要：Dart 与原生两侧必须一致的默认值。
  final Object? defaultValue;

  /// 值域校验（端口范围、枚举集合……）；null 表示类型对就行。
  final PrefValidator? validator;

  bool get isIncluded => backup == BackupPolicy.include;
}

/// Flutter `setStringList` 在 Android 上的落盘编码前缀（再接 base64 的序列化列表）。
/// Kotlin `Prefs.AppFilter` 靠它认出并解码名单；契约测试保证两边一致。
const kFlutterStringListPrefix = 'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu';

/// 备份恢复进行中的标记键：值是恢复前快照文件路径。启动时发现它说明上次
/// 恢复被中断，要用快照回到恢复前状态（见 `BackupEngine.recoverInterrupted`）。
const kRestoreMarkerKey = 'clashmiao_restore_in_progress';

const _perAppModes = {'off', 'include', 'exclude'};
const _sortModes = {'unsorted', 'name', 'delay'};

bool _isOneOf(Object value, Set<String> allowed) =>
    value is String && allowed.contains(value);

Set<String> _themeNames() => {for (final m in AppThemeMode.values) m.name};

Set<String> _localeNames() => {
  for (final l in AppLocale.values) l.name,
  'zh', // 旧版本写过的值，读取时按简体中文处理。
};

/// 偏好注册表：只登记**参与备份与原生共享**的键；其余文件里的字面量保持原样，
/// 之后逐步迁移（见 spec §5）。
///
/// 网络设置各键的值域（端口范围、枚举集合）与 `NetworkSettingsNotifier` 的
/// setter 是同一套判据，在 `networkPrefValidators` 里；core 不能依赖 domain，
/// 所以备份导入处把它作为额外校验器传入（[PrefRegistry.validate]）。
class PrefRegistry {
  const PrefRegistry._();

  static const _inc = BackupPolicy.include;
  static const _exc = BackupPolicy.exclude;
  static const _sec = BackupPolicy.secret;

  /// 动态键前缀：每个订阅一份的手选节点 / 延迟缓存。属于订阅的附属数据，不进备份。
  static const excludedPrefixes = ['proxy_selection_', 'proxy_delays_'];

  static final List<PrefSpec> specs = List.unmodifiable([
    // ── 网络设置（NetworkSettingsNotifier）。值域校验见 networkPrefValidators ──
    const PrefSpec('clashmiao_mixed_port', PrefType.integer, _inc),
    const PrefSpec('clashmiao_region', PrefType.string, _inc),
    const PrefSpec('clashmiao_block_ads', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_log_level', PrefType.string, _inc),
    const PrefSpec('clashmiao_bypass_lan', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_resolve_destination', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_ipv6_mode', PrefType.string, _inc),
    const PrefSpec('clashmiao_set_system_proxy', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_enable_tun', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_allow_lan', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_enable_dns_routing', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_enable_fake_dns', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_independent_dns_cache', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_remote_dns_address', PrefType.string, _inc),
    const PrefSpec(
      'clashmiao_remote_dns_domain_strategy',
      PrefType.string,
      _inc,
    ),
    const PrefSpec('clashmiao_direct_dns_address', PrefType.string, _inc),
    const PrefSpec(
      'clashmiao_direct_dns_domain_strategy',
      PrefType.string,
      _inc,
    ),
    const PrefSpec('clashmiao_tun_implementation', PrefType.string, _inc),
    const PrefSpec('clashmiao_strict_route', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_mtu', PrefType.integer, _inc),
    const PrefSpec('clashmiao_clash_api_port', PrefType.integer, _inc),
    const PrefSpec('clashmiao_tproxy_port', PrefType.integer, _inc),
    const PrefSpec('clashmiao_local_dns_port', PrefType.integer, _inc),
    const PrefSpec('clashmiao_enable_tls_fragment', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_tls_fragment_size', PrefType.string, _inc),
    const PrefSpec('clashmiao_tls_fragment_sleep', PrefType.string, _inc),
    const PrefSpec('clashmiao_enable_tls_padding', PrefType.boolean, _inc),
    const PrefSpec(
      'clashmiao_enable_tls_mixed_sni_case',
      PrefType.boolean,
      _inc,
    ),
    const PrefSpec('clashmiao_tls_padding_size', PrefType.string, _inc),
    const PrefSpec('clashmiao_mux_padding', PrefType.boolean, _inc),
    // WARP：开关与用户可调项随备份，但导入时 enable_warp 一律落为 false
    // （凭证不在备份里，必须在本机重新生成后再启用）。凭证类是机密，永不导出。
    const PrefSpec('clashmiao_enable_warp', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_warp_consent_given', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_warp_detour_mode', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_license_key', PrefType.string, _sec),
    const PrefSpec('clashmiao_warp_clean_ip', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_port', PrefType.integer, _inc),
    const PrefSpec('clashmiao_warp_noise', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_noise_size', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_noise_mode', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_noise_delay', PrefType.string, _inc),
    const PrefSpec('clashmiao_warp_account_id', PrefType.string, _sec),
    const PrefSpec('clashmiao_warp_access_token', PrefType.string, _sec),
    const PrefSpec('clashmiao_warp_wireguard_config', PrefType.string, _sec),
    const PrefSpec('clashmiao_connection_test_url', PrefType.string, _inc),
    const PrefSpec(
      'clashmiao_url_test_interval_seconds',
      PrefType.integer,
      _inc,
    ),

    // ── 其它用户设置 ──
    PrefSpec(
      'clashmiao_proxy_mode', // 0=全局 1=智能
      PrefType.integer,
      _inc,
      validator: (v) => v == 0 || v == 1,
    ),
    // 数据分析同意是每台设备各自的决定：导入备份不得替用户改它，也不随备份导出。
    const PrefSpec('clashmiao_analytics_enabled', PrefType.boolean, _exc),
    const PrefSpec('clashmiao_auto_ip_check', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_haptic_feedback', PrefType.boolean, _inc),
    const PrefSpec('clashmiao_silent_start', PrefType.boolean, _inc),
    const PrefSpec(
      'clashmiao_experimental_notice_dismissed',
      PrefType.boolean,
      _inc,
    ),
    PrefSpec(
      'theme_mode',
      PrefType.string,
      _inc,
      validator: (v) => _isOneOf(v, _themeNames()),
    ),
    PrefSpec(
      'locale',
      PrefType.string,
      _inc,
      validator: (v) => _isOneOf(v, _localeNames()),
    ),
    PrefSpec(
      'proxies_sort_mode',
      PrefType.string,
      _inc,
      validator: (v) => _isOneOf(v, _sortModes),
    ),

    // ── 原生共享键（Kotlin `PrefsKey` / `Prefs`，键名多一个 `flutter.` 前缀）──
    PrefSpec(
      'per_app_proxy_mode',
      PrefType.string,
      _inc,
      nativeShared: true,
      defaultValue: 'off',
      validator: (v) => _isOneOf(v, _perAppModes),
    ),
    const PrefSpec(
      'per_app_proxy_include_list',
      PrefType.stringList,
      _inc,
      nativeShared: true,
      defaultValue: <String>[],
    ),
    const PrefSpec(
      'per_app_proxy_exclude_list',
      PrefType.stringList,
      _inc,
      nativeShared: true,
      defaultValue: <String>[],
    ),
    const PrefSpec(
      'dynamic_notification',
      PrefType.boolean,
      _inc,
      nativeShared: true,
      defaultValue: true,
    ),

    // ── 原生拥有的运行时 / 本机状态：Dart 不写，备份既不导出也不导入 ──
    const PrefSpec(
      'service-mode',
      PrefType.string,
      _exc,
      nativeShared: true,
      defaultValue: 'vpn',
    ),
    const PrefSpec(
      'debug_mode',
      PrefType.boolean,
      _exc,
      nativeShared: true,
      defaultValue: false,
    ),
    const PrefSpec(
      'disable_memory_limit',
      PrefType.boolean,
      _exc,
      nativeShared: true,
      defaultValue: false,
    ),
    const PrefSpec(
      'system_proxy_enabled',
      PrefType.boolean,
      _exc,
      nativeShared: true,
      defaultValue: true,
    ),
    const PrefSpec(
      'started_by_user',
      PrefType.boolean,
      _exc,
      nativeShared: true,
      defaultValue: false,
    ),
    const PrefSpec(
      'active_config_path',
      PrefType.string,
      _exc,
      nativeShared: true,
      defaultValue: '',
    ),
    const PrefSpec(
      'active_profile_name',
      PrefType.string,
      _exc,
      nativeShared: true,
      defaultValue: '',
    ),

    // ── 存储本身的结构键与运行时状态：永不进备份 ──
    const PrefSpec('clashmiao_profiles', PrefType.string, _exc),
    const PrefSpec('clashmiao_active_profile', PrefType.string, _exc),
    const PrefSpec('clashmiao_profiles_quarantine', PrefType.string, _exc),
    const PrefSpec('clashmiao_profiles_corrupt', PrefType.string, _exc),
    const PrefSpec('clashmiao_storage_schema', PrefType.integer, _exc),
    const PrefSpec('clashmiao_migration_backup_v0', PrefType.string, _exc),
    const PrefSpec(kRestoreMarkerKey, PrefType.string, _exc),
    const PrefSpec('clashmiao_system_proxy_dirty', PrefType.boolean, _exc),
    const PrefSpec('clashmiao_store_review_requested', PrefType.boolean, _exc),
    const PrefSpec('update_last_check_ms', PrefType.integer, _exc),
    const PrefSpec('update_latest_tag', PrefType.string, _exc),
  ]);

  static final Map<String, PrefSpec> _byKey = {
    for (final spec in specs) spec.key: spec,
  };

  /// 精确登记的键；动态前缀键与未登记的键返回 null。
  static PrefSpec? lookup(String key) => _byKey[key];

  /// 动态前缀键（手选节点、延迟缓存）。
  static bool isExcludedPrefixKey(String key) =>
      excludedPrefixes.any(key.startsWith);

  /// 进入备份的全部键。
  static Iterable<PrefSpec> get included => specs.where((s) => s.isIncluded);

  /// 原生共享键。
  static Iterable<PrefSpec> get nativeShared =>
      specs.where((s) => s.nativeShared);

  /// [value] 的运行时类型是否符合 [type]。
  static bool matchesType(PrefType type, Object? value) {
    switch (type) {
      case PrefType.boolean:
        return value is bool;
      case PrefType.integer:
        return value is int;
      case PrefType.string:
        return value is String;
      case PrefType.stringList:
        return value is List && value.every((e) => e is String);
    }
  }

  /// 一个备份里的偏好值能否导入：键必须登记且为 `include`、类型对、值域合法。
  ///
  /// [extraValidators] 按键补充值域判据（网络设置的那一套，见类注释）；
  /// 与登记项自带的 validator 都要通过。
  static PrefCheck validate(
    String key,
    Object? value, {
    Map<String, PrefValidator> extraValidators = const {},
  }) {
    final spec = lookup(key);
    if (spec == null) return PrefCheck.unknownKey;
    if (!spec.isIncluded) return PrefCheck.notBackedUp;
    if (value == null || !matchesType(spec.type, value)) {
      return PrefCheck.wrongType;
    }
    final own = spec.validator;
    if (own != null && !own(value)) return PrefCheck.outOfRange;
    final extra = extraValidators[key];
    if (extra != null && !extra(value)) return PrefCheck.outOfRange;
    return PrefCheck.ok;
  }
}

/// [PrefRegistry.validate] 的结论。
enum PrefCheck { ok, unknownKey, notBackedUp, wrongType, outOfRange }
