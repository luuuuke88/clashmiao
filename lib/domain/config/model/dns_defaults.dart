/// 直连 DNS 的默认值：阿里公共 DNS（AliDNS）。
///
/// 智能分流里命中国内直连规则的域名由内核的 `dns-direct` 解析，地址就是这个
/// 设置（`direct-dns-address`）。它必须是国内解析器：以前的默认 `1.1.1.1` 在
/// 境外节点上解析、不带用户所在网络的位置，国内站点拿到的是海外 / 边缘 IP
/// （真机：baidu → 103.235.x 香港、taobao → 43.109.x，首包要 9 s 以上），
/// 直连反而绕远路。
///
/// 没动过这项的用户（偏好里没有这个键）读出来就是它；旧版本替用户自动写下的
/// `1.1.1.1` 由存储迁移 v2 改回跟随默认值（见 [kLegacyDirectDnsDefaults]）；
/// 任何别的值都是用户自己填的，原样保留。
const String kDefaultDirectDnsAddress = '223.5.5.5';

/// 直连 DNS 设置在偏好里的键。
const String kDirectDnsAddressPrefKey = 'clashmiao_direct_dns_address';

/// 旧版本**自动**写进这个键的默认值写法（不是用户填的）。
///
/// 来源（git 历史核实，直连 DNS 的默认值从来只有这一种写法）：
/// - 设置页 / 旧引导页的地区选择：选中国以外的地区时顺带写入 `1.1.1.1`；
/// - 配置选项 JSON 导出总是带上当时的直连 DNS（未改过就是 `1.1.1.1`），
///   导入时原样写回；schema 1 及更早的备份同理。
///
/// 存储迁移 v2 与旧备份恢复把恰好等于这些写法的值视为「没动过」，改回跟随
/// 默认值。代价：当年**主动**填了 `1.1.1.1` 的用户也会被迁移（已接受）。
const Set<String> kLegacyDirectDnsDefaults = {'1.1.1.1'};

/// [value] 是不是旧版本自动写入的直连 DNS 默认值（逐字比较，不做裁剪 / 大小写
/// 归一——任何别的写法都当作用户自定义，原样保留）。
bool isLegacyDirectDnsDefault(Object? value) =>
    value is String && kLegacyDirectDnsDefaults.contains(value);
