import 'package:flutter/foundation.dart';

/// 登记随包分发、但不在 pub 依赖树里的组件的许可信息。
///
/// Flutter 的 `showLicensePage` 只会自动收集 pub 包的许可证。真正承载代理能力
/// 的 sing-box 内核（以原生库形式随包）和 `assets/rule-sets/` 里的规则集不在
/// 其中，不登记就会让「开源许可」页漏掉这两项——而这两项恰恰是用户最该能查到
/// 来源与许可的部分。
///
/// 必须在 `runApp` 之前调用一次（见 `main.dart`）。重复调用会重复登记。
void registerBundledLicenses() {
  LicenseRegistry.addLicense(_bundledLicenses);
}

/// sing-box 内核许可条目的包名（公开仅为让测试能按名查找）。
const singBoxLicensePackage = 'sing-box';

/// 规则集资源许可条目的包名（同上）。
const ruleSetLicensePackage = 'sing-geoip / sing-geosite';

Stream<LicenseEntry> _bundledLicenses() async* {
  yield const LicenseEntryWithLineBreaks(
    [singBoxLicensePackage],
    '''sing-box: the universal proxy platform
https://github.com/SagerNet/sing-box

ClashMiao 使用 sing-box 作为代理内核，以原生库形式随应用分发。
sing-box 按 GNU General Public License v3.0（GPL-3.0）授权，并附带其作者在
许可证文件中声明的附加条款。完整条款以项目仓库中的许可证文件为准：
https://github.com/SagerNet/sing-box/blob/dev-next/LICENSE

GPL-3.0 全文：https://www.gnu.org/licenses/gpl-3.0.html

ClashMiao uses sing-box as its proxy core, distributed with the app as a native
library. sing-box is licensed under the GNU General Public License v3.0
(GPL-3.0) together with the additional terms its authors state in the license
file of the project repository, which is the authoritative text.''',
  );
  yield const LicenseEntryWithLineBreaks(
    [ruleSetLicensePackage],
    '''sing-geoip: https://github.com/SagerNet/sing-geoip
sing-geosite: https://github.com/SagerNet/sing-geosite

随应用打包的 geoip-cn.srs 与 geosite-cn.srs 规则集取自上述两个项目的
rule-set 分支，并在构建期转换为内置的分流规则列表。各数据的授权条款以对应
仓库中的许可证文件为准，请在使用或再分发前自行查阅。

The geoip-cn.srs and geosite-cn.srs rule sets bundled with the app are taken
from the rule-set branches of the projects above and converted at build time
into the built-in routing rule lists. The license terms of the data are those
stated in each repository's license file; please consult them before reusing
or redistributing the data.''',
  );
}
