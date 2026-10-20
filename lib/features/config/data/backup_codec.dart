import 'dart:convert';

import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/domain/config/data/migrations/v2_direct_dns.dart';
import 'package:clashmiao/domain/config/model/dns_defaults.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';

/// 校验通过、可以直接应用的恢复计划。**不含任何副作用**：解析与校验阶段
/// 不写磁盘、不写偏好（spec §6.2 第 1 步）。
class RestorePlan {
  const RestorePlan({
    required this.profiles,
    required this.activeId,
    required this.configs,
    required this.needsFetch,
    required this.prefs,
    required this.skippedPrefKeys,
    required this.profilesDropped,
    required this.warpDisabled,
    required this.exactPrefs,
    this.auxPrefs = const {},
  });

  /// 最终订阅集合（已换发新的本机 `inc`，`active` 一律 false）。
  final List<ProfileEntity> profiles;

  /// 最终激活订阅；列表为空则为 null。
  final String? activeId;

  /// 订阅 id → 配置文件内容。只含最终订阅集合内、内容合法的条目；
  /// 信任模式（快照）下还包含游离配置文件（隔离 / 孤儿），它们同样要原样装回。
  final Map<String, String> configs;

  /// 远程订阅里备份没带（或带的不合法）配置文件的 id：导入后后台补拉。
  final List<String> needsFetch;

  /// 要写入的偏好（已通过类型与值域校验；`enableWarp` 已按规则压成 false）。
  final Map<String, Object> prefs;

  /// 被跳过的偏好键（本机现值保留）。
  final List<String> skippedPrefKeys;

  /// 备份里被丢弃的订阅数。
  final int profilesDropped;

  /// 备份里 `enableWarp=true`，已导入为 false。
  final bool warpDisabled;

  /// 偏好按「精确」语义应用：注册表 `include` 里本机有、计划里没有的键会被删除。
  /// 只有用恢复前快照回到原状时才为 true；用户导入的备份只覆盖它带的键。
  final bool exactPrefs;

  /// 订阅名下的附属偏好（仅恢复前快照有；见 [BackupBundle.auxPreferences]）。
  /// 键已核对：形如 `proxy_selection_<id>` / `proxy_delays_<id>` 且 id 在最终集合内。
  final Map<String, String> auxPrefs;
}

/// 备份文件的编解码与校验。纯函数。
class BackupCodec {
  const BackupCodec._();

  static String encode(BackupBundle bundle) => jsonEncode(bundle.toJson());

  /// 解析并校验 [raw]（v2 或旧的 `1.0`），返回恢复计划。
  ///
  /// [trusted] 为 true 时用于「用恢复前快照回到原状」：快照是本机自己导出的，
  /// 不套用导入规则（不压 `enableWarp`、不查值域、不因配置缺失丢订阅、不排队补拉），
  /// 只保留路径安全与类型检查。
  ///
  /// 校验不通过的**单条**订阅 / 偏好被丢弃并计数，不影响其余条目；
  /// 文件整体不可用时抛 [BackupFormatException]。
  static RestorePlan parse(
    String raw, {
    required int currentSchema,
    Map<String, PrefValidator> extraValidators = const {},
    String Function()? newInc,
    bool trusted = false,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw BackupFormatException(BackupErrorKind.invalidFile, e.message);
    }
    if (decoded is! Map) {
      throw const BackupFormatException(BackupErrorKind.invalidFile, '顶层不是对象');
    }

    final version = decoded['version'];
    final Object? rawProfiles = decoded['profiles'];
    final Object? activeRaw = decoded['activeProfileId'];
    final Object? rawConfigs;
    final Object? rawPrefs;
    // 备份导出时的存储 schema；旧格式（1.0）与没写 schema 的视为 0。
    var bundleSchema = 0;
    if (version == BackupBundle.legacyVersion) {
      final settings = decoded['settings'];
      final map = settings is Map ? settings : const <Object?, Object?>{};
      rawConfigs = map['profileConfigs'];
      rawPrefs = map['preferences'];
    } else if (version == BackupBundle.currentVersion || version == '2') {
      final schema = decoded['schema'];
      if (schema is int && schema > currentSchema) {
        throw BackupFormatException(
          BackupErrorKind.newerSchema,
          'schema $schema > $currentSchema',
        );
      }
      if (schema is int && schema > 0) bundleSchema = schema;
      rawConfigs = decoded['profileConfigs'];
      rawPrefs = decoded['preferences'];
    } else {
      throw BackupFormatException(
        BackupErrorKind.unsupportedVersion,
        '$version',
      );
    }
    if (rawProfiles is! List) {
      throw const BackupFormatException(
        BackupErrorKind.invalidFile,
        'profiles 不是数组',
      );
    }

    final makeInc = newInc ?? ProfileStore.randomInc;
    final Map<Object?, Object?> configSource = rawConfigs is Map
        ? rawConfigs
        : const <Object?, Object?>{};

    // ── 订阅 ──
    final profiles = <ProfileEntity>[];
    final configs = <String, String>{};
    final needsFetch = <String>[];
    final seen = <String>{};
    for (final item in rawProfiles) {
      final entity = _parseProfile(item);
      if (entity == null ||
          !ProfileStore.isValidId(entity.id) ||
          !seen.add(entity.id)) {
        continue;
      }
      final content = configSource[entity.id];
      final text = content is String ? content : null;
      final usable = text != null && (trusted ? true : _isUsableConfig(text));
      if (usable) {
        // 只有 configSource 里确有这个 id 才会走到这里：额外的键天然被忽略。
        configs[entity.id] = text;
      } else if (!trusted) {
        if (_isRemote(entity.url)) {
          needsFetch.add(entity.id);
        } else {
          // 本地订阅（content://）没有可重新获取的来源：没有配置就没有用。
          seen.remove(entity.id);
          continue;
        }
      }
      profiles.add(entity.copyWith(inc: makeInc(), active: false));
    }
    final dropped = rawProfiles.length - profiles.length;
    if (!trusted && rawProfiles.isNotEmpty && profiles.isEmpty) {
      throw const BackupFormatException(BackupErrorKind.noUsableProfiles);
    }

    // 激活 id：必须指向最终集合里的条目；否则取第一条；列表为空则置空。
    final ids = {for (final p in profiles) p.id};
    final String? activeId = activeRaw is String && ids.contains(activeRaw)
        ? activeRaw
        : (profiles.isEmpty ? null : profiles.first.id);

    // ── 偏好 ──
    final prefs = <String, Object>{};
    final skipped = <String>[];
    var warpDisabled = false;
    if (rawPrefs is Map) {
      for (final entry in rawPrefs.entries) {
        final key = entry.key;
        if (key is! String) continue;
        final Object? value = entry.value;
        final spec = PrefRegistry.lookup(key);
        if (trusted) {
          if (spec != null &&
              spec.isIncluded &&
              value != null &&
              PrefRegistry.matchesType(spec.type, value)) {
            prefs[key] = _copy(value);
          }
          continue;
        }
        final check = PrefRegistry.validate(
          key,
          value,
          extraValidators: extraValidators,
        );
        if (check != PrefCheck.ok) {
          skipped.add(key);
          continue;
        }
        if (key == _enableWarpKey && value == true) {
          warpDisabled = true;
          prefs[key] = false;
          continue;
        }
        prefs[key] = _copy(value!);
      }
    }

    // 存储迁移 v2 之前的备份：里面的直连 DNS 若恰好是旧版本自动写入的默认值
    // 写法，与迁移同口径视为「没动过」——不写回，本机现值（跟随默认或用户自定义）
    // 保留。见 v2_direct_dns.dart。
    if (bundleSchema < directDnsV2Migration().toVersion &&
        isLegacyDirectDnsDefault(prefs[kDirectDnsAddressPrefKey])) {
      prefs.remove(kDirectDnsAddressPrefKey);
    }

    // 游离配置文件（订阅被隔离 / 孤儿）：只认快照，id 必须合法且不与列表订阅重名。
    // 并进 configs：回滚时与订阅配置一起暂存、安装，「保留集合」也由此而来。
    final rawOrphans = decoded['orphanConfigs'];
    if (trusted && rawOrphans is Map) {
      for (final entry in rawOrphans.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String) continue;
        if (!ProfileStore.isValidId(key) || ids.contains(key)) continue;
        configs[key] = value;
      }
    }

    // 附属偏好只认快照（trusted），且键必须是最终订阅集合内某个 id 的附属键。
    final aux = <String, String>{};
    final rawAux = decoded['auxPreferences'];
    if (trusted && rawAux is Map) {
      for (final entry in rawAux.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! String) continue;
        for (final id in ids) {
          if (key == ProfileStore.selectionKey(id) ||
              key == ProfileStore.delaysKey(id)) {
            aux[key] = value;
            break;
          }
        }
      }
    }

    return RestorePlan(
      profiles: List.unmodifiable(profiles),
      activeId: activeId,
      configs: Map.unmodifiable(configs),
      needsFetch: List.unmodifiable(needsFetch),
      prefs: Map.unmodifiable(prefs),
      skippedPrefKeys: List.unmodifiable(skipped),
      profilesDropped: dropped,
      warpDisabled: warpDisabled,
      exactPrefs: trusted,
      auxPrefs: Map.unmodifiable(aux),
    );
  }

  static const _enableWarpKey = 'clashmiao_enable_warp';

  static Object _copy(Object value) =>
      value is List ? List<String>.from(value) : value;

  static ProfileEntity? _parseProfile(Object? item) {
    if (item is! Map) return null;
    try {
      return ProfileEntity.fromJson(Map<String, dynamic>.from(item));
    } catch (_) {
      return null;
    }
  }

  static bool _isRemote(String url) =>
      url.isNotEmpty &&
      !url.startsWith('content://') &&
      Uri.tryParse(url)?.hasScheme == true;

  /// 订阅配置必须是含 `outbounds` 数组的 JSON 对象。
  static bool _isUsableConfig(String text) {
    if (text.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map && decoded['outbounds'] is List;
    } catch (_) {
      return false;
    }
  }
}
