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

// ── 判定：按「标签 + 分隔 + 值」的模板，不按关键词 ──
//
// 只出现关键词不算：真实线路名里会有「官网优化」「Official」「Traffic」这类
// 词。只有「已知标签」后面紧跟分隔符、再跟一个形状符合预期的值（地址 / 日期 /
// 带单位的数量 / 百分比）才是信息条目；整个名字只是一个网址或域名也算。拿不准
// 的一律当真实节点保留。

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

/// 冒号形式里，标签与冒号之间允许的短修饰（「距离下次重置**剩余**：」
/// 「流量重置**日**：」「Expire **date**:」）。空格分隔的形式不允许修饰，
/// 否则「HK Traffic IEPL 10G」会被当成「Traffic … 10G」。
const String _kCjkQualifier = r'[一-鿿]{0,4}';
const String _kAsciiQualifier = r'(?:\s+[a-z]+){0,2}';

/// 值的形状，必须出现在分隔符之后的开头。
final String _kValue = [
  // 网址 / 域名
  r'(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?![a-z0-9-])',
  // 日期 / 日期时间：2026-12-01、2026/12/01、2026年12月1日、12-01、每月 1 日
  r'\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}',
  r'\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?(?!\d)',
  r'每月\s*\d{1,2}\s*[日号]',
  // 百分比
  r'\d+(?:\.\d+)?\s*%',
  // 带单位的数量：流量（GB/MB/TB/KB/PB、G/M/T、GiB…）与时长（天/日/小时/days/hours）
  r'\d+(?:\.\d+)?\s*(?:[kmgtp]i?b|[kmgtp](?![a-z])|天|日|小时|days?(?![a-z])|hours?(?![a-z]))',
].join('|');

final RegExp _kInfoTemplate = () {
  final cjk = _kCjkLabels.join('|');
  final ascii = _kAsciiLabels.join('|');
  // 冒号形式：标签 + 短修饰 + 冒号 + 值；空格形式：标签 + 空白 + 值。
  // 英文标签前不能紧挨字母（preset 里的 reset 不算）。
  return RegExp(
    '(?:(?:$cjk)$_kCjkQualifier|(?<![a-z])(?:$ascii)$_kAsciiQualifier)'
    r'\s*[:：]\s*'
    '(?:$_kValue)'
    '|'
    '(?:(?:$cjk)|(?<![a-z])(?:$ascii))'
    r'\s+'
    '(?:$_kValue)',
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

/// 首尾的装饰：emoji、空白、各种括号与标点（不含字母、数字、汉字）。
final RegExp _kEdgeDecoration = RegExp(
  r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}/]+$',
  unicode: true,
);

/// [tag] 是不是订阅信息条目（不看隐藏标记，隐藏标记由 [hasHideMarker] 判断）。
bool isSubscriptionInfoTag(String tag) {
  final markerIndex = tag.indexOf('§');
  final name = (markerIndex == -1 ? tag : tag.substring(0, markerIndex))
      .toLowerCase()
      .trim();
  if (_kInfoTemplate.hasMatch(name)) return true;
  final bare = name.replaceAll(_kEdgeDecoration, '');
  return _kOnlyUrl.hasMatch(bare) || _kOnlyDomain.hasMatch(bare);
}

/// 整份订阅应当按信息条目排除的 tag。
///
/// [leafTags] 必须是**整份订阅**的全部候选叶子节点（不是某一个分组的）：构建器
/// 与线路页都按整份订阅算一次，再套用到每个分组，离线与运行时结果一致。
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
