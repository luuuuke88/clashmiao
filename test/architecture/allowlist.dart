// feature → feature 依赖白名单。
//
// 【只减不增】这份名单是技术债的账本，不是通行证：
// - 只允许登记 `features/<F> → features/<G>` 的文件级依赖边；
//   core / shared / domain 之间的越层依赖不能登记，写进来本身就会被判违规。
// - 条数有上限（[kAllowlistCeiling]），上限只能调小，不能调大。
// - 某条依赖在代码里消除后，对应条目必须同步删除，否则「过期条目」断言会失败。
//
// 架构测试（layering_test）失败时：
// 1. 新增的 feature 间依赖——优先改代码：共享的状态/模型下沉到 domain，
//    共享的 UI 下沉到 shared；不要来加白名单。
// 2. 提示「以下白名单条目对应的依赖已经消除」——把那几条删掉即可。
// 3. 提示条数超过上限——说明在往名单里加新条目，回到第 1 条。
import 'layering_rules.dart';

/// 白名单条数上限；只能调小。
const kAllowlistCeiling = 5;

const _navigation = '页面跳转，子项目 E 统一路由后删除';

/// 目前的 5 条全是页面之间的直接跳转：路由集中到统一入口之前，
/// 页面需要持有目标页面的类型，暂时无法解耦。
const kAllowlist = <AllowedEdge>[
  AllowedEdge(
    'features/home/presentation/home_page.dart',
    'features/profile/presentation/profile_form_dialog.dart',
    _navigation,
  ),
  AllowedEdge(
    'features/home/presentation/home_page.dart',
    'features/profile/presentation/profiles_page.dart',
    _navigation,
  ),
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
