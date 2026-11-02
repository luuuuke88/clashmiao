// 页面型功能之间的页面跳转白名单。
//
// 【只减不增】这份名单是技术债的账本，不是通行证：
// - 只允许登记「页面型功能 → 另一个页面型功能」的文件级依赖边（页面跳转）；
//   能力型功能之间、core / shared 之间的越层依赖不能登记，写进来本身就会被判违规。
//   页面型 → 能力型本来就合规，不需要登记。
// - 条数有上限（[kAllowlistCeiling]），上限只能调小，不能调大。
// - 某条依赖在代码里消除后，对应条目必须同步删除，否则「过期条目」断言会失败。
//
// 架构测试（layering_test）失败时：
// 1. 新增的功能间依赖——优先改代码：共享的状态/模型下沉到能力型功能，
//    共享的 UI 下沉到 shared，页面跳转走 app 层的统一路由入口；不要来加白名单。
// 2. 提示「以下白名单条目对应的依赖已经消除」——把那几条删掉即可。
// 3. 提示条数超过上限——说明在往名单里加新条目，回到第 1 条。
//
// 另有一份欠账：[kPageConstructionDebt]（规则 6，页面只在 app 构造），
// 条数上限同样只能调小。规则 4（同功能内部方向）已清零，不再有任何豁免。
import 'layering_rules.dart';

/// 白名单条数上限；只能调小。
const kAllowlistCeiling = 3;

const _navigation = '页面跳转，统一路由后删除';

/// 目前的 3 条全是页面之间的直接跳转：路由集中到统一入口之前，
/// 页面需要持有目标页面的类型，暂时无法解耦。
const kAllowlist = <AllowedEdge>[
  AllowedEdge(
    'features/home/presentation/quick_settings_modal.dart',
    'features/config/presentation/config_options_page.dart',
    _navigation,
  ),
  AllowedEdge(
    'features/config/presentation/config_options_page.dart',
    'features/assets/presentation/assets_page.dart',
    _navigation,
  ),
  AllowedEdge(
    'features/config/presentation/config_options_page.dart',
    'features/logs/presentation/logs_page.dart',
    _navigation,
  ),
];

/// 规则 6（页面只在 app 构造，跨功能跳转走 `AppRouteScope`）的历史欠账：
/// 目前是 3 条页面跳转，加上首页直接构造 `ProfilesPage`。
/// 条数上限等于当前条数，只能调小；Task 15 引入 `AppRouteScope` 后清零，整份删除。
const kPageConstructionDebtCeiling = 4;

const _construct = '直接构造别的功能的页面，待改为通过 AppRouteScope 跳转';

const kPageConstructionDebt = <AllowedEdge>[
  AllowedEdge(
    'features/home/presentation/quick_settings_modal.dart',
    'features/config/presentation/config_options_page.dart',
    _construct,
  ),
  AllowedEdge(
    'features/home/presentation/home_page.dart',
    'features/profile/presentation/profiles_page.dart',
    _construct,
  ),
  AllowedEdge(
    'features/config/presentation/config_options_page.dart',
    'features/logs/presentation/logs_page.dart',
    _construct,
  ),
  AllowedEdge(
    'features/config/presentation/config_options_page.dart',
    'features/assets/presentation/assets_page.dart',
    _construct,
  ),
];
