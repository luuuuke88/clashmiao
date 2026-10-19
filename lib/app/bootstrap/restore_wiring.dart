import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/features/settings/application/app_filter_notifier.dart';
import 'package:clashmiao/features/settings/application/setting_toggles.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 备份恢复后需要失效、但属于其它 feature 的 provider。
///
/// `features/config` 不能依赖别的 feature（架构规则、白名单只减不增），所以这份
/// 清单由 app 层持有，通过 [restoreWiringOverrides] 注入。新增「读偏好的 provider」
/// 时记得补到这里；`restore_wiring_test` 会核对清单没有遗漏已知项。
List<ProviderOrFamily> restoreExtraInvalidations() => [
  boolPreferenceProvider, // 设置页各开关（整个 family）
  appFilterProvider, // 分应用代理
  proxiesSortProvider, // 节点排序
];

/// 放进根 `ProviderContainer(overrides: …)` 的覆盖项。
List<Override> restoreWiringOverrides() => [
  restoreExtraInvalidationsProvider.overrideWithValue(
    restoreExtraInvalidations(),
  ),
];
