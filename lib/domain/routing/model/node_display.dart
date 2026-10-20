/// 节点名里旗帜的来源。
enum FlagSource {
  /// 名称开头自带旗帜（订阅给出的，优先于一切推断）。
  leading,

  /// 名称里没有开头旗帜，按关键词（ISO 区域码映射）推断出来的。
  inferred,

  /// 既没有开头旗帜也推断不出：展示层用中性地球图标。
  none,
}

/// 代理节点的展示信息：只用于**展示**。
///
/// 选择、缓存、重放一律用原始 tag，不能拿 [label] 去做键——[label] 丢了开头
/// 旗帜和 `§` 后缀，不同 tag 可能得到同一个 label。
class NodeDisplay {
  const NodeDisplay({
    required this.flag,
    required this.flagSource,
    required this.label,
  });

  /// 旗帜 emoji；[flagSource] 为 [FlagSource.none] 时为 `null`。
  final String? flag;
  final FlagSource flagSource;

  /// 去掉 `§` 后缀、首尾空白，并（若有开头旗帜）去掉开头旗帜后的名称。
  ///
  /// 名字只有一面旗帜时为空串：旗帜已经在 [flag] 里，由展示层在名称位放
  /// 中性占位，而不是把同一面旗帜左右各显示一次。
  final String label;

  /// 解析一个原始 tag。
  ///
  /// - 先去掉 `§` 之后的后缀（订阅里用 `§` 给节点挂内部标记，用户不该看到），
  ///   再裁掉首尾空白——检测开头旗帜和截取剩余名称用的是**同一个**规范化后的
  ///   字符串，前导空格、制表符不会让截取位置错位、切断旗帜的代理对；
  /// - 名称**开头**的旗帜搬到 [flag]，名称里其余位置的旗帜原样保留；
  /// - 没有开头旗帜时按关键词推断；推断不出则 [flag] 为空。
  factory NodeDisplay.parse(String tag) {
    final name = stripSuffix(tag).trim();
    final leading = _leadingFlag(name);
    if (leading != null) {
      return NodeDisplay(
        flag: leading,
        flagSource: FlagSource.leading,
        label: name.substring(leading.length).trimLeft(),
      );
    }
    final inferred = _inferFlag(name);
    if (inferred != null) {
      return NodeDisplay(
        flag: inferred,
        flagSource: FlagSource.inferred,
        label: name,
      );
    }
    return NodeDisplay(flag: null, flagSource: FlagSource.none, label: name);
  }

  /// 去掉第一个 `§` 起的后缀并裁掉右侧空白；旗帜等其余内容原样保留。
  ///
  /// 按名称排序、长按弹出的全名用这个，保持与改动前同一口径。
  static String stripSuffix(String tag) {
    final markerIndex = tag.indexOf('§');
    return (markerIndex == -1 ? tag : tag.substring(0, markerIndex))
        .trimRight();
  }

  /// 单行展示名（首页节点胶囊）：旗帜（若有）+ 名称，两者都没有时为 `null`。
  ///
  /// 与代理页同一套解析：`§` 后缀不会出现，开头旗帜不会与名称里的重复。
  String? get capsuleName {
    final parts = [?flag, if (label.isNotEmpty) label];
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// 订阅用 `§hide§` 标记不想让用户看到的节点。
  static bool isHidden(String tag) => tag.contains('§hide§');

  @override
  bool operator ==(Object other) =>
      other is NodeDisplay &&
      other.flag == flag &&
      other.flagSource == flagSource &&
      other.label == label;

  @override
  int get hashCode => Object.hash(flag, flagSource, label);

  @override
  String toString() => 'NodeDisplay($flag, $flagSource, $label)';
}

/// 名称开头的旗帜（一对区域指示符）；没有则 `null`。
///
/// [name] 必须是已经规范化（裁过首尾空白）的字符串，调用方用同一个字符串按
/// 返回值的长度截取。
String? _leadingFlag(String name) {
  final runes = name.runes.take(2).toList();
  if (runes.length < 2 || !runes.every(_isRegionalIndicator)) return null;
  return String.fromCharCodes(runes);
}

bool _isRegionalIndicator(int rune) => rune >= 0x1F1E6 && rune <= 0x1F1FF;

/// ISO 3166-1 alpha-2 区域码 → 旗帜 emoji（两个区域指示符）。
String _flagOf(String iso) => String.fromCharCodes([
  for (final unit in iso.toUpperCase().codeUnits) 0x1F1E6 + (unit - 0x41),
]);

String? _inferFlag(String name) {
  final lower = name.toLowerCase();
  for (final rule in _rules) {
    for (final matcher in rule.matchers) {
      if (matcher.hasMatch(lower)) return _flagOf(rule.iso);
    }
  }
  return null;
}

/// 关键词规则表，顺序即优先级。
///
/// 两个字符及以下的关键词（`hk`、`tw`、`us` ……）必须独立成词（前后不是
/// 小写字母），否则 `transit` 会命中 `tr`。更长的关键词做子串匹配。
const _keywordTable = <({String iso, List<String> keywords})>[
  (iso: 'HK', keywords: ['hk', 'hong kong', 'hongkong', '香港']),
  (
    iso: 'TW',
    keywords: ['tw', 'taiwan', 'tai wan', '台湾', '台北', 'taipei', 'roc'],
  ),
  (iso: 'MO', keywords: ['mo', 'macau', 'macao', '澳门']),
  (iso: 'SG', keywords: ['sg', 'singapore', '新加坡', '狮城']),
  (iso: 'JP', keywords: ['jp', 'japan', '日本', '东京', '大阪', 'tokyo', 'osaka']),
  (iso: 'US', keywords: ['us', 'usa', 'united states', 'america', '美国', '美']),
  (
    iso: 'GB',
    keywords: ['uk', 'united kingdom', 'britain', '英国', '伦敦', 'london'],
  ),
  (iso: 'KR', keywords: ['kr', 'korea', 'south korea', '韩国', '首尔', 'seoul']),
  (iso: 'DE', keywords: ['de', 'germany', 'deutschland', '德国']),
  (iso: 'FR', keywords: ['fr', 'france', '法国']),
  (iso: 'CA', keywords: ['ca', 'canada', '加拿大']),
  (iso: 'AU', keywords: ['au', 'australia', '澳大利亚', '澳洲']),
  (iso: 'RU', keywords: ['ru', 'russia', '俄罗斯']),
  (iso: 'IN', keywords: ['in', 'india', '印度']),
  (iso: 'NL', keywords: ['nl', 'netherlands', '荷兰']),
  (
    iso: 'CN',
    keywords: [
      'cn',
      'china',
      '中国',
      '内地',
      '江苏',
      '北京',
      '上海',
      'beijing',
      'shanghai',
    ],
  ),
  (iso: 'MY', keywords: ['my', 'malaysia', '马来西亚']),
  (iso: 'TH', keywords: ['th', 'thailand', '泰国']),
  (iso: 'VN', keywords: ['vn', 'vietnam', '越南']),
  (iso: 'PH', keywords: ['ph', 'philippines', '菲律宾']),
  (iso: 'ID', keywords: ['id', 'indonesia', '印尼']),
  (iso: 'BR', keywords: ['br', 'brazil', '巴西']),
  (iso: 'IT', keywords: ['it', 'italy', '意大利']),
  (iso: 'ES', keywords: ['es', 'spain', '西班牙']),
  (iso: 'TR', keywords: ['tr', 'turkey', '土耳其']),
  (iso: 'UA', keywords: ['ua', 'ukraine', '乌克兰']),
  (iso: 'CH', keywords: ['ch', 'switzerland', '瑞士']),
  (iso: 'SE', keywords: ['se', 'sweden', '瑞典']),
  (iso: 'NO', keywords: ['no', 'norway', '挪威']),
  (iso: 'FI', keywords: ['fi', 'finland', '芬兰']),
  (iso: 'DK', keywords: ['dk', 'denmark', '丹麦']),
  (iso: 'BE', keywords: ['be', 'belgium', '比利时']),
  (iso: 'IE', keywords: ['ie', 'ireland', '爱尔兰']),
  (iso: 'AT', keywords: ['at', 'austria', '奥地利']),
  (iso: 'PL', keywords: ['pl', 'poland', '波兰']),
  (iso: 'HU', keywords: ['hu', 'hungary', '匈牙利']),
  (iso: 'CZ', keywords: ['cz', 'czech', '捷克']),
  (iso: 'RO', keywords: ['ro', 'romania', '罗马尼亚']),
  (iso: 'GR', keywords: ['gr', 'greece', '希腊']),
  (iso: 'PT', keywords: ['pt', 'portugal', '葡萄牙']),
  (iso: 'ZA', keywords: ['za', 'south africa', '南非']),
  (iso: 'AR', keywords: ['ar', 'argentina', '阿根廷']),
  (iso: 'MX', keywords: ['mx', 'mexico', '墨西哥']),
  (iso: 'CL', keywords: ['cl', 'chile', '智利']),
  (iso: 'CO', keywords: ['co', 'colombia', '哥伦比亚']),
  (iso: 'PE', keywords: ['pe', 'peru', '秘鲁']),
  (
    iso: 'AE',
    keywords: ['ae', 'uae', 'united arab emirates', '阿联酋', '迪拜', 'dubai'],
  ),
  (iso: 'IL', keywords: ['il', 'israel', '以色列']),
  (iso: 'SA', keywords: ['sa', 'saudi arabia', '沙特']),
  (iso: 'BG', keywords: ['bg', 'bulgaria', '保加利亚']),
  (iso: 'HR', keywords: ['hr', 'croatia', '克罗地亚']),
  (iso: 'IR', keywords: ['ir', 'iran', '伊朗']),
  (iso: 'KP', keywords: ['kp', 'north korea', '朝鲜']),
];

class _Rule {
  _Rule(this.iso, List<String> keywords)
    : matchers = [
        for (final keyword in keywords)
          keyword.length <= 2
              ? RegExp('(^|[^a-z])${RegExp.escape(keyword)}([^a-z]|\$)')
              : RegExp(RegExp.escape(keyword)),
      ];

  final String iso;
  final List<RegExp> matchers;
}

final List<_Rule> _rules = [
  for (final entry in _keywordTable) _Rule(entry.iso, entry.keywords),
];
