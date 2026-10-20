/// 订阅配置（sing-box JSON）里「有哪些实体」的两个视图。
///
/// 新内核把 WireGuard 节点放进顶层 `endpoints`，而不是 `outbounds`。凡是只读
/// `outbounds` 的地方，遇到「只有端点」的订阅就会判空、丢默认值、认不出类型。
/// 但「认端点」不等于「所有人都换成同一份节点列表」：分组遍历如果用了叶子视图
/// 就会丢光分组，计数如果用了完整集合就会把分组算成节点。所以这里给两个视图，
/// **按用途选，不得混用**：
///
/// - [profileEntities] 完整集合：所有 `outbounds`（含 `selector` / `urltest` /
///   `direct` / `block` / `dns`）加上所有 `endpoints`。用于分组遍历、tag → 类型
///   索引、引用重写。
/// - [profileLeafNodes] 叶子视图：完整集合去掉分组与直连 / 阻断 / DNS，即真正
///   可连的节点（含端点）。用于节点计数与候选筛选。
///
/// 纯 Dart、无 IO：放在 domain 最靠前的 config 模型层，profile / routing /
/// features 都能依赖它。
library;

/// 实体来自哪个数组。
enum EntitySource { outbound, endpoint }

/// 配置里的一个实体（出站或端点）。[raw] 是原始 Map，调用方需要改写引用时
/// 直接改它。
class ConfigEntity {
  const ConfigEntity({
    required this.tag,
    required this.type,
    required this.source,
    required this.raw,
  });

  final String tag;
  final String type;
  final EntitySource source;
  final Map<dynamic, dynamic> raw;

  bool get isEndpoint => source == EntitySource.endpoint;

  /// 是不是真实可连的叶子节点（见 [isLeafType]）。
  bool get isLeaf => isLeafType(type);
}

/// 不是叶子节点的类型：分组、直连、阻断、DNS、内核自定义出站。与内核重建主
/// 选择组 / 自动选择组时跳过的类型一致；其余（各种代理协议与 WireGuard 端点）
/// 都是叶子。
const Set<String> _kNonLeafTypes = {
  'direct',
  'block',
  'dns',
  'selector',
  'select',
  'urltest',
  'custom',
};

/// 类型 [type] 是不是叶子节点（大小写、`-` / `_` 不敏感：`url-test`、`url_test`
/// 都是分组）。
bool isLeafType(String type) => !_kNonLeafTypes.contains(
  type.trim().toLowerCase().replaceAll('-', '').replaceAll('_', ''),
);

Iterable<ConfigEntity> _read(Object? list, EntitySource source) sync* {
  if (list is! List) return;
  for (final item in list) {
    if (item is! Map) continue;
    final type = item['type'];
    if (type is! String) continue;
    final tag = item['tag'];
    yield ConfigEntity(
      tag: tag is String ? tag : '',
      type: type,
      source: source,
      raw: item,
    );
  }
}

/// 完整实体集合：`outbounds` 在前、`endpoints` 在后，各自保持原有顺序。
List<ConfigEntity> profileEntities(Map<dynamic, dynamic> profile) => [
  ..._read(profile['outbounds'], EntitySource.outbound),
  ..._read(profile['endpoints'], EntitySource.endpoint),
];

/// 叶子节点视图：真实可连的节点（含端点），顺序同 [profileEntities]。
List<ConfigEntity> profileLeafNodes(Map<dynamic, dynamic> profile) => [
  for (final e in profileEntities(profile))
    if (e.isLeaf) e,
];

/// 叶子视图的节点数。分组、直连、阻断、DNS 不计入；`outbounds` 为空而端点非空
/// 也是非零。
int profileNodeCount(Map<dynamic, dynamic> profile) =>
    profileLeafNodes(profile).length;

/// 出站 [outbound] 是否带「需要清洗的旧形态」。口径是固定清单，与 Go 的
/// `legacy.NeedsCleaning` 共用夹具 `kernel/testdata/shared/legacy-shapes.json`：
///
/// - `type` 为 `wireguard` / `dns` / `block`；
/// - 顶层出现 `tls_fragment` / `domain_strategy` / `sniff` /
///   `sniff_override_destination`，或 `tls` 里出现 `tls_tricks`。
///
/// 订阅自带的 `selector` / `urltest` / `direct` 不在清单里（它们由构建器按规则
/// 重建，不阻止直通）。
bool outboundNeedsCleaning(Map<dynamic, dynamic> outbound) {
  switch (outbound['type']) {
    case 'wireguard' || 'dns' || 'block':
      return true;
  }
  for (final field in const [
    'tls_fragment',
    'domain_strategy',
    'sniff',
    'sniff_override_destination',
  ]) {
    if (outbound.containsKey(field)) return true;
  }
  final tls = outbound['tls'];
  return tls is Map && tls.containsKey('tls_tricks');
}

/// 配置 [profile] 里是否有任何出站带旧形态（只看 `outbounds`：端点是新形态）。
bool profileNeedsCleaning(Map<dynamic, dynamic> profile) {
  final outbounds = profile['outbounds'];
  if (outbounds is! List) return false;
  return outbounds.any((o) => o is Map && outboundNeedsCleaning(o));
}
