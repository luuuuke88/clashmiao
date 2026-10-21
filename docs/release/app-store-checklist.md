# App Store 上架材料清单（iOS，首发美国 / 香港）

状态：草稿（2026-10-20，2026-10-22 更新：构建与签名已验证，见 §1；元数据定稿见 `app-store-metadata.md`）。每项标注当前状态：✅ 仓库里已核实 · ⚠️ 需要动手 · ❓ 需要账号持有人决定 · 📱 需要真机。
仓库里能核实的事实写出了来源；App Store Connect 里的操作、截图、测试订阅需要人来做。

## 0. 先决条件（账号 / 标识）

| 项 | 状态 | 说明 |
|---|---|---|
| 组织类型 Apple Developer 账号 | ❌ **阻塞** | 审核指南 5.4 要求 VPN 类 App 由组织账号提交。2026-10-22 实查：本机签名用的团队 `V7HGHN6K8T` 在 Xcode 里是 `teamType = Individual`，团队名与 Distribution 描述文件的 `TeamName` 都是个人姓名——**用这个账号提交会按 5.4 被拒**。解决：注册组织账号（需要法人实体 + D-U-N-S 编号），或联系 Apple 把现有个人会员转为组织（保留 Team ID，App 记录不用迁移）。转好后无需改代码，重新 Archive 即可 |
| App ID（主 App `com.clashmiao.clashmiao`）与扩展 `com.clashmiao.clashmiao.SingBoxPacketTunnel` | ✅ | Bundle id 来自 `ios/Runner.xcodeproj`；扩展 id 必须以主 App id 为前缀 |
| App Group `group.com.clashmiao.shared` | ✅ | 两个 target 的 entitlements 都声明（`Runner.entitlements`） |
| Network Extension 能力（`packet-tunnel-provider`） | ✅ | entitlements 里已有；**发布用的 Distribution 描述文件必须包含该能力**，首次 Archive 上传前确认 | 
| 版本号 | ⚠️ | `pubspec.yaml` 当前 `0.1.0+1`；`FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER` 同时驱动主 App 与扩展（两者必须一致，每次上传 build number 递增） |

## 1. 构建与上传

```bash
flutter build ipa --release            # 需要本机登录组织账号的 Distribution 证书；失败时用 Xcode Archive
# 或：Xcode → Product → Archive → Distribute App → App Store Connect → Upload
```

- ⚠️ 上传前跑一遍全量门：`flutter analyze --fatal-warnings`、`flutter test`、`xcodebuild test`（见 `docs/ARCHITECTURE.md`「测试」）。
- ⚠️ 先发 TestFlight 内部测试，真机走完 `docs/superpowers/research/2026-10-20-ios-device-smoke.md` 的清单再提审。
- 📱 `Libcore.xcframework` 不在 git 里，Archive 前 `bin/fetch-libcore.sh ios`。
- ✅ 2026-10-22 实测：`flutter build ipa --release --build-name 0.3.0 --build-number 1` 一次通过，Xcode 自动签名用云端管理的 Apple Distribution 证书导出了 App Store IPA（`build/ios/ipa/`，60 MB）。主 App 与扩展都是 “iOS Team Store Provisioning Profile”，权限含 `packet-tunnel-provider` 与 `group.com.clashmiao.shared`，`get-task-allow = false`。本机没有 App Store Connect API key，上传用 Transporter 或 Xcode Organizer。

## 2. 出口合规（Export Compliance）

- ❓ `Info.plist` 目前**没有** `ITSAppUsesNonExemptEncryption`，每次上传都会被问。本 App 包含代理协议的加密实现（内核），不是“只用系统加密”，需要账号持有人决定如何答（常见做法：声明使用加密、符合豁免条件的标准算法，并在 App Store Connect 里按提示答 / 视情况提交年度自分类报告）。**不要在没有结论前随手写 `NO`**。决定后把答案固化进 `Info.plist`，避免每次手答。
- 美国 / 香港都需要此声明。

## 3. 隐私

| 项 | 状态 | 说明 |
|---|---|---|
| 隐私政策 URL | ⚠️ 待上线 | 正文已按 App 实际行为重写（官网仓库 `ClashMiaoWeb` 分支 `feat/website-overhaul`，提交 fae720e，10 种语言）：列出 App 自己发出的请求（订阅、节点检测、出口 IP 查询 ipwho.is、检查更新、WARP）、可选崩溃报告的内容与开关、按平台区分的权限。**该分支尚未部署，线上 `https://clashmiao.com/privacy` 仍是旧文**，提审前必须合并上线 |
| `PrivacyInfo.xcprivacy`（主 App 与扩展） | ✅ | 主 App 声明 `NSPrivacyTracking = false`、Crash Data / Performance Data（不关联身份、不跟踪，用途 App Functionality / Analytics）；扩展声明不收集。与 `app-store-metadata.md` 的隐私问卷答法一致 |
| App 隐私问卷（Nutrition Label） | ❓ | 建议口径：不用于跟踪；**Diagnostics → Crash Data、Performance Data**：收集（仅用户开启后）、不关联身份、不用于跟踪。订阅地址 / 节点 / DNS / 浏览记录：不收集（只存本机）。以账号持有人确认为准 |
| 第三方 SDK 隐私清单 | ⚠️ | 上传后看 App Store Connect 的 “Missing privacy manifest” 邮件；Sentry 自带清单 |
| 相机 / 相册用途文案 | ✅ | `NSCameraUsageDescription`（扫订阅二维码）、`NSPhotoLibraryUsageDescription` 已有 |

## 4. 审核指南 5.4（VPN 类 App）与审核备注

5.4 的要点与现状：

- 必须由组织提交 ✅；必须使用 NetworkExtension API ✅（`NETunnelProviderManager` + Packet Tunnel）。
- 不得出售、使用或披露数据给第三方，必须在应用描述中声明收集哪些数据 ⚠️（见上，描述里要写 “不收集你的流量 / 订阅 / 浏览数据”）。
- 不得违反所在地区法律；首发只选美国、香港，**不要勾选中国大陆** ✅（见 §6）。
- 首次连接时系统会弹“添加 VPN 配置”，这是预期行为，需在备注里说明。

**审核备注（英文，粘贴到 App Review Information → Notes）：**

> ClashMiao is a network client for sing-box-compatible proxy configurations that the user already owns (a subscription URL or a configuration file supplied by the user's own provider). The app does not operate any servers, does not sell or bundle a VPN service, and does not collect or transmit the user's traffic, DNS queries, browsing history or subscription contents. All configuration is stored on the device.
>
> The app uses the NetworkExtension Packet Tunnel API (`NEPacketTunnelProvider`). On first connect iOS shows the standard "Add VPN Configurations" prompt; please tap Allow.
>
> To test: open the app → Profiles → Add → paste the subscription URL below → select the imported profile → tap the large connect button on Home. The home screen then shows the connected state and the egress IP changes. Disconnect with the same button.
>
> Reviewer subscription URL: `[REVIEWER_SUBSCRIPTION_URL]` (valid until `[DATE]`)
>
> Optional crash/performance reporting is off by default and can be enabled in Settings → General; it never includes subscription URLs, node configuration or traffic.

- ⚠️ **`[REVIEWER_SUBSCRIPTION_URL]` 必须是一份长期有效、只给审核用的订阅**（不要用个人测试订阅；本清单不记录真实地址）。订阅过期会直接导致 2.1 被拒。
- ⚠️ 备注里的操作路径要与最终 UI 文案一致，提审前对照一遍。
- 📱 录一段 30–60 秒的屏幕录制（导入订阅 → 授权 → 连接 → 出口 IP 变化 → 断开）作为附件，VPN 类审核常要求演示。

## 5. 应用信息（App Store Connect）

| 项 | 状态 | 建议 / 说明 |
|---|---|---|
| 名称 / 副标题 | ❓ | 品牌名 ClashMiao（喵速）；副标题强调“代理配置客户端”，**避免**“翻墙 / 绕过封锁”类措辞 |
| 分类 | ❓ | 主：Utilities；备选：Productivity |
| 本地化 | ⚠️ | 至少 en-US 与 zh-Hans；香港店面建议加 zh-Hant。App 本身已内置 10 种语言（ar / en / es / fa / id / pt-BR / ru / tr / zh-CN / zh-TW），商店元数据按需补 |
| 描述 / 关键词 / 更新说明 | ⚠️ | 描述要包含 5.4 要求的数据声明；关键词不要出现竞品名 / 上游项目名 |
| 技术支持 URL / 营销 URL | ⚠️ | `https://clashmiao.com`；支持邮箱 `support@clashmiao.com`（`ClashMiaoWeb/src/data/links.ts`） |
| 版权 | ⚠️ | `© 2026 <组织法定名称>` |
| 年龄分级问卷 | ❓ | 按实际回答；“不受限的网页访问”类问题要如实选择（代理可访问任意网站），以问卷结果为准 |
| 价格与可用性 | ❓ | 首发免费；**销售范围只勾美国、香港** |
| 登录 | ✅ | App 不需要账号，无需提供测试账号 |

## 6. 店面（美国 / 香港）

- 只在 App Store Connect → Pricing and Availability 勾选 **United States** 与 **Hong Kong**，其余（尤其 China mainland）不选。
- 香港店面语言：建议 zh-Hant（繁体）+ en。
- 提审时各店面共用同一份审核备注。

## 7. 截图

App 同时支持 iPhone 与 iPad（`TARGETED_DEVICE_FAMILY = "1,2"`），所以两类设备的截图都要提供。按 App Store Connect 当前规格上传（最新规格以后台提示为准）：

| 设备 | 像素（竖屏） |
|---|---|
| iPhone 6.9" | 1320 × 2868 |
| iPhone 6.5"（若后台仍要求） | 1284 × 2778 |
| iPad 13" | 2064 × 2752 |

建议每套 5–6 张，zh-Hans 与 en 各一套（zh-Hant 复用 zh-Hans 之外的必要差异）：

1. 首页·已连接（出口 IP、节点、速度）📱 真机（模拟器无法建立 VPN）
2. 订阅导入（粘贴 / 扫码）
3. 节点列表与延迟 📱
4. 智能 / 全局模式
5. 设置页（含“不收集数据”相关开关）
6. （可选）iPad 横屏的首页

⚠️ 截图里**不要出现真实订阅地址、真实出口 IP 之外的个人信息**；演示订阅用审核专用订阅。

2026-10-22 已在模拟器上拍好一组（`build/store-screenshots/`，不进 git）：`iphone-zh` / `iphone-en`（1320 × 2868：首页、线路、添加订阅）、`ipad-zh` / `ipad-en`（2064 × 2752：首页、线路）。用 debug 演示数据（`--dart-define=CLASHMIAO_DEBUG_HOME_PROFILE=true --dart-define=CLASHMIAO_DEBUG_PROXY_FIXTURE=true`），订阅名是中性的 “My Subscription”，节点是演示节点，不含私人订阅。**模拟器无法建立 VPN，“已连接”状态的首页截图需要真机补拍**；不补也能提审（首页未连接态足以展示功能）。

## 8. 提审前总检

- [ ] `docs/superpowers/research/2026-10-20-ios-device-smoke.md` 全部勾完（导入订阅、连接、出口 IP 变化、延迟列表、切节点、后台 / 前台、杀进程重开）
- [ ] 隐私政策页已更新并上线，`PrivacyInfo.xcprivacy` 与问卷一致
- [ ] 出口合规已决定并固化
- [ ] 审核订阅有效期覆盖整个审核周期
- [ ] TestFlight 外部测试至少一轮
- [ ] 描述 / 副标题 / 关键词不出现上游项目名与“翻墙”类措辞
- [ ] 店面只选美国、香港
