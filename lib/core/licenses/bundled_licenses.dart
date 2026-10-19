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
/// ## 来源核实记录（2026-10-20，读取 GitHub 上的固定提交所得）
///
/// 随包的两个规则集快照记录在 `assets/rule-sets/VERSION`：
/// sing-geoip `7a098b8`、sing-geosite `d7259bb`（都是各自 `rule-set` 分支上由
/// GitHub Actions 生成的孤立提交）。核对链路：
///
/// 1. 快照提交的时间与同一时刻的 Actions 运行记录（`Release`，schedule 触发）
///    一一对应；运行记录给出所用生成程序的提交（`head_sha`）。
/// 2. 在那个生成程序提交上读 `main.go`，确认数据源：geoip 读
///    `Dreamacro/maxmind-geoip`、geosite 读 `v2fly/domain-list-community`。
/// 3. 随包 `.srs` 的 SHA-256 与快照提交里同名文件逐字节一致（见常量
///    `geoipCnSha256` / `geositeCnSha256`，测试会拿随包文件重新计算比对）。
/// 4. 数据源许可：domain-list-community 的 `LICENSE` 自 2019-01-01 未改动，
///    为 MIT；maxmind-geoip 的发布流程自 2025-05-09 起未改动，下载 MaxMind
///    GeoLite2-Country。
///
/// 仍未核实的内容见各条目文本末尾（原样写入登记文本，不在这里重复）。
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

// ---- 随包快照与许可记录的对应关系（固定提交，测试会校验） ----

/// sing-geoip `rule-set` 分支快照提交（`assets/rule-sets/VERSION` 记 `7a098b8`）。
const geoipSnapshotCommit = '7a098b8b8fc97bf47bab4706d5a049fba2a52c91';

/// 生成该快照的 sing-geoip 程序提交（Actions 运行 24302879958 的 head_sha）。
const geoipGeneratorCommit = 'ecd02c178af5efbac38d427a8d178f940327de1f';

/// geoip 快照所用的上游数据发布（Dreamacro/maxmind-geoip，发布于 2026-04-12）。
const geoipDataRelease = '20260412';

/// sing-geosite `rule-set` 分支快照提交（`VERSION` 记 `d7259bb`）。
const geositeSnapshotCommit = 'd7259bba0b1655fdabd84532744ea80ede3c0ac5';

/// 生成该快照的 sing-geosite 程序提交（Actions 运行 25649435000 的 head_sha）。
const geositeGeneratorCommit = 'dd64ae0ebf2ee69166c0510042b3e96c085f27df';

/// geosite 快照所用的 domain-list-community 提交（2026-05-10 10:33:27 UTC，
/// 快照生成时它是 master 最新提交）。
const dlcCommit = '0fc69c67a5a5c784e4f9da1a5e110fdb4e7d666a';

/// 随包 `assets/rule-sets/geoip-cn.srs` 的 SHA-256，与快照提交里的同名文件一致。
const geoipCnSha256 =
    '07be358f32017cc4649cd6b69946e3206ce54faa5f50eb88624927e2cb380d00';

/// 随包 `assets/rule-sets/geosite-cn.srs` 的 SHA-256，与快照提交里的同名文件一致。
const geositeCnSha256 =
    '1cecd95e88fa29f66e8d82b2129cf52408998a7892e83f7ff3bcc0ec2a4ccdf9';

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
    '''geosite-cn.srs（assets/rule-sets/geosite-cn.srs）

随包快照：sing-geosite rule-set 分支提交 $geositeSnapshotCommit
（2026-05-11 03:55 UTC，assets/rule-sets/VERSION 记为 d7259bb）
https://github.com/SagerNet/sing-geosite/commit/$geositeSnapshotCommit
随包文件 SHA-256：$geositeCnSha256（与该提交里的 geosite-cn.srs 逐字节一致）

生成程序：sing-geosite 提交 $geositeGeneratorCommit（生成该快照的 GitHub Actions
运行 25649435000 所用的提交），其 main.go 读取 v2fly/domain-list-community 发布的
dlc.dat：
https://github.com/SagerNet/sing-geosite/blob/$geositeGeneratorCommit/main.go
转换程序本身以 GPL-3.0 授权。

数据来源：v2fly/domain-list-community 提交 $dlcCommit
（2026-05-10 10:33:27 UTC，快照生成时的 master 最新提交）：
https://github.com/v2fly/domain-list-community/tree/$dlcCommit
数据许可：MIT License（该提交处的 LICENSE，自 2019-01-01 未改动）：
https://github.com/v2fly/domain-list-community/blob/$dlcCommit/LICENSE
原文如下：

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

未能确认的事项：生成程序读取的 dlc.dat 具体是 domain-list-community 的哪一个
发布（发布名）没能直接读到——该发布与 sing-geosite 当时的发布均已被清理，
GitHub API 查不到。上面的 dlc 提交是根据「快照生成时 master 最新提交」及
sing-geosite 的发布命名规则（以来源发布时间戳命名，当时的 20260510103350 与
该提交的 10:33 UTC 吻合）推断的，不是直接读到的记录。

Snapshot: sing-geosite rule-set branch commit $geositeSnapshotCommit
(2026-05-11 03:55 UTC; recorded as d7259bb in assets/rule-sets/VERSION).
The bundled file's SHA-256 ($geositeCnSha256) is byte-identical to
geosite-cn.srs in that commit.
Generator: sing-geosite commit $geositeGeneratorCommit (the commit used by the
GitHub Actions run that produced the snapshot); its main.go reads dlc.dat from
v2fly/domain-list-community. The generator is GPL-3.0.
Data source: v2fly/domain-list-community commit $dlcCommit (2026-05-10 10:33:27
UTC, master head when the snapshot was built), licensed under the MIT License
reproduced above (LICENSE unchanged since 2019-01-01).

Not confirmed: which domain-list-community release (its release name) the
generator consumed. That release and sing-geosite's own release from that day
have been pruned and are not retrievable through the GitHub API. The dlc commit
above is inferred from "master head at build time" and sing-geosite's tag
naming (tags are named after the source release timestamp; 20260510103350 at
that time matches the commit's 10:33 UTC); it is not a directly read record.''',
  );

  yield const LicenseEntryWithLineBreaks(
    [geoipLicensePackage],
    '''geoip-cn.srs（assets/rule-sets/geoip-cn.srs）

$maxMindAttribution

随包快照：sing-geoip rule-set 分支提交 $geoipSnapshotCommit
（2026-04-12 08:53 UTC，assets/rule-sets/VERSION 记为 7a098b8）
https://github.com/SagerNet/sing-geoip/commit/$geoipSnapshotCommit
随包文件 SHA-256：$geoipCnSha256（与该提交里的 geoip-cn.srs 逐字节一致）

生成程序：sing-geoip 提交 $geoipGeneratorCommit（生成该快照的 GitHub Actions
运行 24302879958 所用的提交；sing-geoip 的 20260412 发布标签也指向它），其
main.go 读取 Dreamacro/maxmind-geoip 的最新发布，并生成 geoip-cn：
https://github.com/SagerNet/sing-geoip/blob/$geoipGeneratorCommit/main.go
转换程序本身以 GPL-3.0 授权。

数据来源：Dreamacro/maxmind-geoip 发布 $geoipDataRelease（2026-04-12 00:28 UTC，
资产 Country.mmdb）：
https://github.com/Dreamacro/maxmind-geoip/releases/tag/$geoipDataRelease
该发布由其月度工作流下载 MaxMind GeoLite2-Country 构建（工作流自 2025-05-09
起未改动），仓库 README 声明包含 MaxMind 创建的 GeoLite2 数据。

数据许可：MaxMind GeoLite End User License Agreement
https://www.maxmind.com/en/geolite2/eula
该协议要求对 MaxMind 署名（见上方署名句），并把数据中可版权的部分纳入
Creative Commons Attribution-ShareAlike 4.0 International License（CC BY-SA 4.0）：
https://creativecommons.org/licenses/by-sa/4.0/
再分发或基于本数据派生时须遵守署名与相同方式共享的要求。

未能确认的事项：
1. 协议文本的版本：上面的条款是 2026-10-20 读取 MaxMind 网站当前页面所得；
   2026-04-12（快照生成时）生效的版本没能取得——网页存档只保存到页面外壳，
   不含协议正文。
2. Country.mmdb 内部的 GeoLite2 数据库期号没有解析确认（发布名 20260412 是
   Dreamacro 的发布日期，不一定等于 MaxMind 的数据库期号）。
3. 「生成程序读取的就是 20260412 这个发布」来自两点：该运行是定时触发（没有
   指定固定发布，程序取最新发布），且当时最新发布就是 20260412，同时 sing-geoip
   的发布标签按来源发布名命名、20260412 标签指向该生成程序提交；没有读到运行
   日志本身（日志需要登录才能取）。

$maxMindAttribution

Snapshot: sing-geoip rule-set branch commit $geoipSnapshotCommit
(2026-04-12 08:53 UTC; recorded as 7a098b8 in assets/rule-sets/VERSION).
The bundled file's SHA-256 ($geoipCnSha256) is byte-identical to
geoip-cn.srs in that commit.
Generator: sing-geoip commit $geoipGeneratorCommit (the commit used by the
GitHub Actions run that produced the snapshot; the sing-geoip tag 20260412 also
points to it). Its main.go consumes the latest release of
Dreamacro/maxmind-geoip and produces geoip-cn. The generator is GPL-3.0.
Data source: Dreamacro/maxmind-geoip release $geoipDataRelease (2026-04-12
00:28 UTC, asset Country.mmdb), built by that repository's monthly workflow
from MaxMind GeoLite2-Country (workflow unchanged since 2025-05-09); its README
states that it includes GeoLite2 data created by MaxMind.
Data license: the MaxMind GeoLite End User License Agreement
(https://www.maxmind.com/en/geolite2/eula). It requires attribution to MaxMind
(see the sentence above) and applies the Creative Commons Attribution-ShareAlike
4.0 International License (CC BY-SA 4.0,
https://creativecommons.org/licenses/by-sa/4.0/) to the copyrightable elements
of the data. Redistribution or derivatives must comply with the attribution and
share-alike terms.

Not confirmed:
1. The EULA version: the terms above were read from MaxMind's current web page
   on 2026-10-20. The version in force on 2026-04-12 could not be retrieved; the
   web archive only kept the page shell, not the agreement body.
2. The GeoLite2 database edition date inside Country.mmdb was not parsed
   (the release name 20260412 is Dreamacro's release date, not necessarily
   MaxMind's database date).
3. That the generator consumed release 20260412 is inferred: the run was
   scheduled (no pinned release, so the program takes the latest release), the
   latest release then was 20260412, and the sing-geoip tag 20260412 (named
   after the source release) points to the generator commit. The run log itself
   was not read (logs require sign-in).''',
  );
}
