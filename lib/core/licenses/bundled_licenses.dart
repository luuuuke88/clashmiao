import 'package:flutter/foundation.dart';

/// 登记随包分发、但不在 pub 依赖树里的组件的许可信息。
///
/// Flutter 的 `showLicensePage` 只会自动收集 pub 包的许可证。真正承载代理能力
/// 的 sing-box 内核（以原生库形式随包）和 `assets/rule-sets/` 里的规则集不在
/// 其中，不登记就会让「开源许可」页漏掉这几项——而它们恰恰是用户最该能查到
/// 来源与许可的部分。
///
/// 必须在 `runApp` 之前调用一次（见 `main.dart`）。重复调用会重复登记。
///
/// ## 来源核实记录（2026-10-20，读取上游文件所得）
///
/// - sing-box：随包版本 v1.8.9 的 `LICENSE`：GPL-3.0 或其后版本，外加一条
///   「衍生作品未经同意不得使用本应用名称或暗示关联」的附加条件。
/// - geosite-cn.srs：由 SagerNet/sing-geosite 的生成程序读取 v2fly/domain-list-community
///   的 `dlc.dat` 转换而来；domain-list-community 的 `LICENSE` 为 MIT。
/// - geoip-cn.srs：由 SagerNet/sing-geoip 的生成程序读取 Dreamacro/maxmind-geoip
///   发布的 `Country.mmdb` 转换而来；该仓库的发布流程下载 MaxMind
///   `GeoLite2-Country`，其 README 声明包含 MaxMind 创建的 GeoLite2 数据。
///   MaxMind GeoLite EULA 要求署名，并把可版权部分纳入 CC BY-SA 4.0。
/// - 未核实：生成程序是按 `main` 分支当前内容读的，没有逐个检出
///   `assets/rule-sets/VERSION` 记录的那两个快照提交时的生成程序版本；
///   所以「该快照确由上述来源生成」是依据生成程序现状与仓库说明的推断，
///   不是对快照二进制本身的校验。这一点也写进了登记文本里。
void registerBundledLicenses() {
  LicenseRegistry.addLicense(_bundledLicenses);
}

/// sing-box 内核许可条目的包名（公开仅为让测试能按名查找）。
const singBoxLicensePackage = 'sing-box';

/// geosite-cn.srs 许可条目的包名（同上）。
const geositeLicensePackage = 'sing-geosite (geosite-cn.srs)';

/// geoip-cn.srs 许可条目的包名（同上）。
const geoipLicensePackage = 'sing-geoip (geoip-cn.srs)';

/// MaxMind 要求的署名句，取自 GeoLite EULA 里的署名示例原句。
/// 测试会断言它原样出现在登记文本里。
const maxMindAttribution =
    'This product includes GeoLite Data created by MaxMind, available from '
    'https://www.maxmind.com';

Stream<LicenseEntry> _bundledLicenses() async* {
  yield const LicenseEntryWithLineBreaks(
    [singBoxLicensePackage],
    '''sing-box: the universal proxy platform
https://github.com/SagerNet/sing-box

ClashMiao 使用 sing-box（随包版本 v1.8.9）作为代理内核，以原生库形式随应用分发。

许可证：GNU General Public License 第 3 版，或（由您选择）其后任一版本
（GPL-3.0-or-later），并附带一条附加条件：衍生作品未经事先同意，不得使用
该应用的名称或暗示与其有关联。
许可证原文（对应随包版本）：
https://github.com/SagerNet/sing-box/blob/v1.8.9/LICENSE
GPL-3.0 全文：https://www.gnu.org/licenses/gpl-3.0.html

ClashMiao uses sing-box (shipped version v1.8.9) as its proxy core, distributed
with the app as a native library.

License: GNU General Public License version 3, or (at your option) any later
version (GPL-3.0-or-later), with one additional condition: no derivative work
may use the name of the application or imply association with it without prior
consent. The license text for the shipped version:
https://github.com/SagerNet/sing-box/blob/v1.8.9/LICENSE
Full text of the GPL-3.0: https://www.gnu.org/licenses/gpl-3.0.html''',
  );

  yield const LicenseEntryWithLineBreaks(
    [geositeLicensePackage],
    '''geosite-cn.srs（assets/rule-sets/）

来源：由 SagerNet/sing-geosite（https://github.com/SagerNet/sing-geosite ，
rule-set 分支）的生成程序，读取 v2fly/domain-list-community
（https://github.com/v2fly/domain-list-community）发布的 dlc.dat 转换而成。
转换程序本身以 GPL-3.0 授权；规则数据来自 domain-list-community，其许可证为
MIT License，原文如下：

MIT License

Copyright (c) 2018-2019 V2Ray

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

未核实事项：上述来源依据的是生成程序当前主分支的内容与上游仓库说明，没有逐个
检出随包快照（见 assets/rule-sets/VERSION）对应时刻的生成程序，也没有对规则集
二进制本身做来源校验。

Source: converted from the dlc.dat release of v2fly/domain-list-community by
the generator in SagerNet/sing-geosite (rule-set branch). The generator is
GPL-3.0; the rule data comes from domain-list-community, licensed under the MIT
License reproduced above.

Unverified: the source above is taken from the generator's current main branch
and the upstream READMEs. We did not check out the generator as it was at the
time of each bundled snapshot (see assets/rule-sets/VERSION), nor verify the
rule-set binary itself against its source.''',
  );

  yield const LicenseEntryWithLineBreaks(
    [geoipLicensePackage],
    '''geoip-cn.srs（assets/rule-sets/）

$maxMindAttribution

来源：由 SagerNet/sing-geoip（https://github.com/SagerNet/sing-geoip ，
rule-set 分支）的生成程序，读取 Dreamacro/maxmind-geoip
（https://github.com/Dreamacro/maxmind-geoip）发布的 Country.mmdb 转换而成；
该仓库的发布流程下载的是 MaxMind 的 GeoLite2-Country 数据库，并在 README 中
声明包含 MaxMind 创建的 GeoLite2 数据。转换程序本身以 GPL-3.0 授权。

数据许可：MaxMind GeoLite End User License Agreement
https://www.maxmind.com/en/geolite2/eula
该协议要求对 MaxMind 署名（见上方署名句），并把数据中可版权的部分纳入
Creative Commons Attribution-ShareAlike 4.0 International License（CC BY-SA 4.0）：
https://creativecommons.org/licenses/by-sa/4.0/
再分发或基于本数据派生时须遵守署名与相同方式共享的要求。

未核实事项：上述来源依据的是生成程序当前主分支的内容与上游仓库说明，没有逐个
检出随包快照（见 assets/rule-sets/VERSION）对应时刻的生成程序，也没有对规则集
二进制本身做来源校验；快照取自 GeoLite2 的哪一期也未核实。

$maxMindAttribution

Source: converted from the Country.mmdb release of Dreamacro/maxmind-geoip by
the generator in SagerNet/sing-geoip (rule-set branch). That repository's
release workflow downloads MaxMind's GeoLite2-Country database, and its README
states that it includes GeoLite2 data created by MaxMind. The generator is
GPL-3.0.

Data license: the MaxMind GeoLite End User License Agreement
(https://www.maxmind.com/en/geolite2/eula). It requires attribution to MaxMind
(see the sentence above) and applies the Creative Commons Attribution-ShareAlike
4.0 International License (CC BY-SA 4.0,
https://creativecommons.org/licenses/by-sa/4.0/) to the copyrightable elements
of the data. Redistribution or derivatives must comply with the attribution and
share-alike terms.

Unverified: the source above is taken from the generator's current main branch
and the upstream READMEs. We did not check out the generator as it was at the
time of each bundled snapshot (see assets/rule-sets/VERSION), nor verify the
rule-set binary itself against its source, nor determine which GeoLite2 release
the snapshot was built from.''',
  );
}
