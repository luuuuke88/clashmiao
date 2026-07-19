import 'package:clashmiao/core/utils/formatters.dart' as formatters;
import 'package:clashmiao/features/profile/model/advanced_config.dart';

/// 订阅配置实体
class ProfileEntity {
  const ProfileEntity({
    required this.id,
    required this.name,
    required this.url,
    this.active = false,
    this.lastUpdate,
    this.subInfo,
    this.updateInterval = const Duration(hours: 1),
    this.notes,
    this.customUserAgent,
    this.advancedConfig,
  });

  final String id;
  final String name;
  final String url;
  final bool active;
  final DateTime? lastUpdate;
  final SubscriptionInfo? subInfo;
  final Duration updateInterval;
  final String? notes;
  final String? customUserAgent;
  final AdvancedConfig? advancedConfig;

  static const _sentinel = Object();

  ProfileEntity copyWith({
    String? id,
    String? name,
    String? url,
    bool? active,
    DateTime? lastUpdate,
    SubscriptionInfo? subInfo,
    Duration? updateInterval,
    Object? notes = _sentinel,
    Object? customUserAgent = _sentinel,
    Object? advancedConfig = _sentinel,
  }) {
    return ProfileEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      active: active ?? this.active,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      subInfo: subInfo ?? this.subInfo,
      updateInterval: updateInterval ?? this.updateInterval,
      notes: notes == _sentinel ? this.notes : notes as String?,
      customUserAgent: customUserAgent == _sentinel
          ? this.customUserAgent
          : customUserAgent as String?,
      advancedConfig: advancedConfig == _sentinel
          ? this.advancedConfig
          : advancedConfig as AdvancedConfig?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'active': active,
    'lastUpdate': lastUpdate?.toIso8601String(),
    'updateInterval': updateInterval.inHours,
    'subInfo': subInfo?.toJson(),
    'notes': notes,
    'customUserAgent': customUserAgent,
    if (advancedConfig != null) 'advancedConfig': advancedConfig!.toJson(),
  };

  factory ProfileEntity.fromJson(Map<String, dynamic> json) {
    return ProfileEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      active: json['active'] as bool? ?? false,
      lastUpdate: json['lastUpdate'] != null
          ? DateTime.parse(json['lastUpdate'] as String)
          : null,
      updateInterval: Duration(hours: json['updateInterval'] as int? ?? 1),
      subInfo: json['subInfo'] != null
          ? SubscriptionInfo.fromJson(json['subInfo'] as Map<String, dynamic>)
          : null,
      notes: json['notes'] as String?,
      customUserAgent: json['customUserAgent'] as String?,
      advancedConfig: json['advancedConfig'] != null
          ? AdvancedConfig.fromJson(
              json['advancedConfig'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// 订阅信息（流量、有效期等）
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.upload,
    required this.download,
    required this.total,
    this.expire,
    this.webPageUrl,
    this.supportUrl,
  });

  /// 已用上行流量 (bytes)
  final int upload;

  /// 已用下行流量 (bytes)
  final int download;

  /// 总流量 (bytes)
  final int total;

  /// 过期时间
  final DateTime? expire;

  /// 管理页面
  final String? webPageUrl;

  /// 客服链接
  final String? supportUrl;

  /// 已用总流量
  int get used => upload + download;

  /// 剩余流量
  int get remaining => total - used;

  /// 使用百分比 (0.0 ~ 1.0)
  double get usageRatio => total > 0 ? used / total : 0;

  /// 是否已过期
  bool get isExpired => expire != null && expire!.isBefore(DateTime.now());

  /// 格式化流量显示
  ///
  /// 曾经和 `lib/core/utils/formatters.dart` 里的顶层 [formatters.formatBytes]
  /// 是两份逐字节相同的重复实现。单位/进制规则已对照参考项目的 humanizer
  /// 用法核实过：两边都是二进制进制（1024），跟 humanizer 默认的
  /// `InformationUnits.iecBytes` 一致；humanizer 的默认格式是无空格 + 严格
  /// IEC 单位名（`KiB`/`MiB`/`GiB`），而这里保留的是本项目一直在用、且被
  /// `test/features/profile/model/subscription_info_test.dart` 锁定的
  /// "数字 + 空格 + KB/MB/GB" 展示格式——这是既有 UI 文案，不属于这次去重
  /// 该动的范围，所以只做"删重复实现改调用"，不改单位/空格展示规则。
  /// 这里只保留一个函数体、转调用顶层实现，避免两边以后各改各的再次漂移。
  static String formatBytes(int bytes) => formatters.formatBytes(bytes);

  SubscriptionInfo copyWith({
    int? upload,
    int? download,
    int? total,
    DateTime? expire,
    String? webPageUrl,
    String? supportUrl,
  }) {
    return SubscriptionInfo(
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
      webPageUrl: webPageUrl ?? this.webPageUrl,
      supportUrl: supportUrl ?? this.supportUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire?.millisecondsSinceEpoch,
    'webPageUrl': webPageUrl,
    'supportUrl': supportUrl,
  };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      upload: json['upload'] as int? ?? 0,
      download: json['download'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
      expire: json['expire'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['expire'] as int)
          : null,
      webPageUrl: json['webPageUrl'] as String?,
      supportUrl: json['supportUrl'] as String?,
    );
  }
}
