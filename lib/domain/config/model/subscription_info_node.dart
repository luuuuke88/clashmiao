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

/// 只要出现就足以判定为信息条目的关键词（英文按小写比较）。
///
/// 只收「真实线路名里不会出现」的词：线路名常带「倍率」「中继」「专线」，
/// 但不会写「官网」「到期」「套餐」。
const List<String> _kInfoKeywords = [
  '官网',
  '官方',
  '网址',
  '订阅',
  '剩余',
  '到期',
  '过期',
  '有效期',
  '套餐',
  '重置',
  'expir',
  'remaining',
  'traffic',
  'website',
  'official',
];

/// 「流量」本身不够：真实线路可能叫「0.5 倍流量」。只有和冒号或带单位的
/// 数量一起出现（「流量：100GB」「已用流量 12.3 GB」）才算信息条目。
final RegExp _kTrafficAmount = RegExp(
  r'\d+(\.\d+)?\s*(b|kb|mb|gb|tb|kib|mib|gib|tib)\b',
);

/// [tag] 是不是订阅信息条目（不看隐藏标记，隐藏标记由 [hasHideMarker] 判断）。
bool isSubscriptionInfoTag(String tag) {
  final name = tag.toLowerCase();
  for (final keyword in _kInfoKeywords) {
    if (name.contains(keyword)) return true;
  }
  if (name.contains('流量')) {
    return name.contains('：') ||
        name.contains(':') ||
        _kTrafficAmount.hasMatch(name);
  }
  return false;
}

/// 一组叶子节点 tag 里应当按信息条目排除的那些。
///
/// 已带隐藏标记的不在结果里（它们本来就被排除）。保护：排除之后一个可选节点
/// 都不剩时返回空集——宁可把信息条目留在列表里，也不能让主选择组只剩一个
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
