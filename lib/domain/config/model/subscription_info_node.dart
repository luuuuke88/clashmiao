/// 订阅里的「信息条目」：机场把官网地址、剩余流量、到期时间、重置日之类的
/// 提示写成节点名，混在真实节点里下发（常见如「🌐 官网地址：xxx」「剩余流量：
/// 12.3 GB」「套餐到期：2026-12-01」）。它们有时指向一台能用的服务器，有时
/// 根本连不上，但都不是用户该选的线路。
///
/// 这里是这条规则的**唯一**来源，四处共用：
/// - 运行时配置构建器：给信息条目的 tag 加上内核认的隐藏标记 [kHideNodeMarker]，
///   内核重建主选择组 / 自动选择组时据此跳过它们——成员资格是内核决定的，
///   不加标记，自动选择就会测它、选它；
/// - 运行时选择组默认值（`runtimeSelectorDefaults`）：与内核的成员口径保持一致；
/// - 线路页与自动测速：离线分组（直接解析或编译订阅配置，还没加标记）里同样
///   不展示、不计入；
/// - 订阅导入时修复出的选择组：默认值不落在信息条目上。
///
/// 信息条目一律隐藏，不做「不可选的信息行」：订阅的流量与到期已经由订阅卡片
/// （订阅响应头）展示，节点名里的同一份信息不必再占一行。
library;

/// 节点 tag 带这个标记时，内核不把它放进主选择组 / 自动选择组。
const String kHideNodeMarker = '§hide§';

/// tag 是否带内核隐藏标记。
bool hasHideMarker(String tag) => tag.contains(kHideNodeMarker);

// ── 判定：整个名字符合「标签 + 分隔 + 值」的模板，不按关键词 ──
//
// 只出现关键词不算：真实线路名里会有「官网优化」「Official」「Traffic 10Gbps」
// 「Reset 01-02」这类写法。只有**整个名字**（去掉首尾装饰后）恰好是：
//
//   [≤4 个汉字的前缀] 已知标签 [短修饰] 分隔 值 [收尾标点]
//
// 才是信息条目；值必须是地址 / 日期 / 带单位的数量 / 百分比之一，并且一直到
// 名字结尾（只允许跟着收尾标点）。整个名字只是一个网址或域名也算。拿不准的
// 一律当真实节点保留。

/// 中文标签。长的写在前面（正则按顺序尝试）。
const List<String> _kCjkLabels = [
  '官网地址',
  '官网',
  '网址',
  '剩余流量',
  '已用流量',
  '总流量',
  '套餐到期',
  '到期时间',
  '过期时间',
  '距离下次重置',
  '重置',
  '公告',
];

/// 英文标签（按小写比较；`expir` 同时覆盖 expire / expires / expiration / expiry）。
const List<String> _kAsciiLabels = [
  r'expir[a-z]*',
  'traffic',
  'remaining',
  'reset',
  'website',
  'url',
];

/// 中文标签前允许的短前缀（「**最新**网址」「**流量**重置日」），只能是汉字。
const String _kCjkPrefix = r'[一-鿿]{0,4}';

/// 冒号形式里，标签与冒号之间允许的短修饰（「距离下次重置**剩余**：」
/// 「流量重置**日**：」「Expire **date**:」）。空白分隔的形式不允许修饰。
const String _kCjkQualifier = r'[一-鿿]{0,4}';
const String _kAsciiQualifier = r'(?:\s+[a-z]+){0,2}';

/// 带单位的数量：流量（GB/MB/TB/KB/PB、GiB…、G/M/T）与时长（天/日/小时/
/// days/hours）。单位后面不能再跟字母或数字：「10Gbps」不是「10 GB」。
const String _kQuantity =
    r'\d+(?:\.\d+)?\s*(?:[kmgtp]i?b|[kmgtp]|天|日|小时|days?|hours?)'
    r'(?![a-z0-9])';

/// 值：必须一直延续到名字结尾（之后只允许 [_kTail]）。
final String _kValue = [
  // 网址 / 域名（可带端口与路径）
  r'(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:/\S*)?',
  // 日期 / 日期时间：2026-12-01、2026/12/01、2026年12月1日、可跟 12:00[:00]
  r'\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?'
      r'(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?',
  // 月-日：12-01、12月1日
  r'\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?',
  // 每月 1 日 / 每月 1 号
  r'每月\s*\d{1,2}\s*[日号]',
  // 百分比
  r'\d+(?:\.\d+)?\s*%',
  // 数量，或「已用 / 总量」
  '$_kQuantity(?:\\s*/\\s*$_kQuantity)?',
].join('|');

/// 值之后允许的收尾：空白与收尾标点（括号、句读）。别的任何字符都说明名字
/// 里还有线路描述（「Reset 01-02 IEPL」），不是信息条目。
const String _kTail = r'[\s)\]）】」》>.,;。，；!！]*';

final RegExp _kInfoTemplate = () {
  final cjk = '$_kCjkPrefix(?:${_kCjkLabels.join('|')})';
  final ascii = '(?:${_kAsciiLabels.join('|')})';
  return RegExp(
    '^(?:'
    // 冒号形式：标签 + 短修饰 + 冒号 + 值
    '(?:$cjk$_kCjkQualifier|$ascii$_kAsciiQualifier)'
    r'\s*[:：]\s*'
    '(?:$_kValue)'
    '|'
    // 空白形式：标签 + 空白 + 值
    '(?:$cjk|$ascii)'
    r'\s+'
    '(?:$_kValue)'
    ')$_kTail\$',
    unicode: true,
  );
}();

/// 整个名字只是一个网址（带 scheme）。
final RegExp _kOnlyUrl = RegExp(r'^https?://\S+$');

/// 整个名字只是一个域名，且顶级域是常见的那些。不收任意字母顶级域：
/// 「JP.Tokyo」「HK.IEPL」这类线路名长得也像域名。
final RegExp _kOnlyDomain = RegExp(
  r'^(?:[a-z0-9-]+\.)+'
  r'(?:com|net|org|cc|io|me|co|xyz|top|info|cn|hk|tw|jp|us|uk|sg|cloud|site|'
  r'online|link|club|vip|app|dev|pro|ltd|one|fun|icu|shop|store|best|life|'
  r'live|world|today|plus|work|tech|space|website|ink|run|biz|win)'
  r'(?::\d+)?(?:/\S*)?$',
);

/// 开头的装饰：emoji、空白、各种括号与标点（不含字母、数字、汉字）。
final RegExp _kLeadingDecoration = RegExp(r'^[^\p{L}\p{N}]+', unicode: true);

/// 结尾的装饰（只用于「整个名字只是网址 / 域名」的判断）。
final RegExp _kTrailingDecoration = RegExp(r'[^\p{L}\p{N}/]+$', unicode: true);

/// [tag] 是不是订阅信息条目（不看隐藏标记，隐藏标记由 [hasHideMarker] 判断）。
bool isSubscriptionInfoTag(String tag) {
  final markerIndex = tag.indexOf('§');
  final name = (markerIndex == -1 ? tag : tag.substring(0, markerIndex))
      .toLowerCase()
      .trim();
  final body = name.replaceFirst(_kLeadingDecoration, '');
  if (_kInfoTemplate.hasMatch(body)) return true;
  final bare = body.replaceFirst(_kTrailingDecoration, '');
  return _kOnlyUrl.hasMatch(bare) || _kOnlyDomain.hasMatch(bare);
}

// ── 候选叶子节点：构建器、线路页、默认值推导共用同一个定义 ──

/// 不是候选叶子节点的出站类型：分组、直连、阻断、DNS、内核自定义出站。与内核
/// 重建主选择组 / 自动选择组时跳过的类型一致；其余（各种代理协议）都是候选。
const Set<String> _kNonCandidateTypes = {
  'direct',
  'block',
  'dns',
  'selector',
  'select',
  'urltest',
  'custom',
};

/// 出站类型 [type] 是不是候选叶子节点（大小写、`-` / `_` 不敏感：
/// `url-test`、`url_test` 都是分组）。
bool isCandidateLeafType(String type) => !_kNonCandidateTypes.contains(
  type.trim().toLowerCase().replaceAll('-', '').replaceAll('_', ''),
);

/// 配置 [cfg]（sing-box JSON）里**全部**候选叶子节点的 tag，按出现顺序；包括
/// 没被任何分组引用的叶子。
List<String> candidateLeafTags(Map<String, dynamic> cfg) => [
  for (final o in (cfg['outbounds'] as List?) ?? const [])
    if (o is Map && o['tag'] is String && o['type'] is String)
      if (isCandidateLeafType(o['type'] as String)) o['tag'] as String,
];

/// 一份订阅配置的信息条目排除集：在 [candidateLeafTags] 上算
/// [subscriptionInfoTagsToExclude]。构建器（加隐藏标记）与线路页（离线分组）
/// 都只用它，订阅级的「不能排空」保护也因此一致。
Set<String> subscriptionInfoExclusionsForConfig(Map<String, dynamic> cfg) =>
    subscriptionInfoTagsToExclude(candidateLeafTags(cfg));

/// 整份订阅应当按信息条目排除的 tag。
///
/// [leafTags] 必须是**整份订阅**的全部候选叶子节点（[candidateLeafTags]，不是
/// 某一个分组的）；一般直接用 [subscriptionInfoExclusionsForConfig]。
///
/// 已带隐藏标记的不在结果里（它们本来就被排除）。保护：排除之后整份订阅一个
/// 可选节点都不剩时返回空集——宁可把信息条目留着，也不能让主选择组只剩一个
/// 空的自动选择组、整份订阅不可用。
Set<String> subscriptionInfoTagsToExclude(Iterable<String> leafTags) {
  final info = <String>{};
  var hasRealNode = false;
  for (final tag in leafTags) {
    if (hasHideMarker(tag)) continue;
    if (isSubscriptionInfoTag(tag)) {
      info.add(tag);
    } else {
      hasRealNode = true;
    }
  }
  return hasRealNode ? info : const {};
}
