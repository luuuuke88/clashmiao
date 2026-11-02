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
const kAllowlistCeiling = 0;

/// 页面跳转都经 `AppRouteScope`（app 层统一路由入口），不再需要登记。
const kAllowlist = <AllowedEdge>[];

/// 规则 6（页面只在 app 构造，跨功能跳转走 `AppRouteScope`）的历史欠账：
/// 已全部还清。上限为 0，不得再新增。
const kPageConstructionDebtCeiling = 0;

const kPageConstructionDebt = <AllowedEdge>[];
