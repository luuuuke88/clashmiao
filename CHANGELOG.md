# Changelog

ClashMiao（喵速）版本变更记录。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

### 品牌视觉改版

App 图标、启动画面与全局配色统一到新的「闪电猫」品牌标。冷启动加了一段 1.5 秒
的开屏动画，导航改成玻璃材质胶囊，去掉了 onboarding——冷启动直接进主页。

### 订阅导入：面板按 UA 白名单发空配置导致必定失败

有一类订阅面板按 User-Agent 白名单决定返回什么：认得的客户端发完整节点，认不
得的发一份结构合法但 `proxies: []` 的骨架，再不认得的直接发 HTML 拒绝页（状态
码还是 200）。ClashMiao 不在任何一家白名单里，于是这类订阅在别的客户端能用、
在这里只得到一句 `no outbounds found`——而那句话技术上还是对的，用户完全无从
判断该改什么。

现在先用自身 UA 请求，不默认伪装成别人；只有响应明显不可用时才依次换用
`sing-box` → `clash-verge` → `clash.meta` 重试。sing-box 排最前是因为那就是本
项目的内核——面板若认这个 UA 会直接发原生 sing-box 配置，连格式转换都省了。

命中的 UA 会写回订阅的 `customUserAgent`。不记住的话，导入靠回退成功了，下一次
自动刷新又用回自身 UA、面板再发一份空配置，节点列表会被当场清空。

**行为变更**：零节点的订阅现在会报错，不再静默建出一个没有节点的订阅。

### 检查更新：改为优先读官网清单

原来只问 GitHub API。未认证的 GitHub API 是 60 次/小时/**IP**——同一运营商 NAT
后面的用户共用出口 IP，用户一多就集体被限流，而限流的表现是"检查更新永远失败"，
完全静默。现在优先读官网的 `/api/latest.json`（在 CDN 上，随发版自动重建），
GitHub 降为兜底。地址走编译期参数 `UPDATE_MANIFEST_URL`，不写死域名。

### 关于页标题硬编码英文

标题原本写死 `About ClashMiao`，没走 i18n，结果中文环境下「线路」「设置」都是
中文标题，只有关于页顶着英文。改用已有的 `about.pageTitle`（11 种语言都有译文）。

### CI/CD 出包：四平台可下载安装包 + 校验和 + 安装说明

此前 GitHub Releases 上只有 `libcore v1.11.0`（核心库），**没有任何可下载的应用
安装包**。这次把发布产物补成开源项目该有的样子：

- **新增 Linux job 与打包**。`release.yml` 原本只有 android/macos/windows 三个
  平台，Linux 完全没有出包路径。新增 `bin/package-linux.sh` 产出 `.deb`
  （Debian/Ubuntu 双击安装，带 `.desktop` 与多尺寸图标）和 `tar.gz`
  （其它发行版，解开即用）。打包后会**校验** deb 里真的有主程序、`libcore.so`
  和 `.desktop`——结构错了也能"打包成功"，不校验等于没验。
- **Android 产物改成可辨识命名 + 按 ABI 拆分**。原来叫 `app-release.apk`，
  用户下载下来认不出是什么应用、什么版本，两个版本还会撞名。现在是
  `ClashMiao-Android-arm64-v8a-<ver>.apk` 等；通用包把四种架构的 native lib
  全塞进去（150MB+），而任何一台手机只用得上一种，拆分后多数用户只需下 1/3 体积。
- **AAB 从公开下载里移出**。它是 Play Store 上传格式，终端用户下了装不上，
  放在 release 资产里只造成困惑。改为单独的 workflow artifact。
- **新增 `SHA256SUMS.txt`**。开源项目标配，让用户能校验下载完整性。生成时
  刻意不带路径前缀，用户在下载目录里直接 `sha256sum -c` 就能用（已实测）。
- **release 正文改为生成式**（`bin/make-release-notes.sh`）。原来只有
  `--generate-notes`，用户点进去看到十几个文件不知道该下哪个；而这个项目还有
  两个绕不开的坑必须写在下载页上——macOS 未公证会被 Gatekeeper 拦、Windows
  未签名会触发 SmartScreen，用户不知道怎么绕会直接以为软件坏了。
- **缺一个平台不再阻断其余平台出包**。`publish` 原本硬 `needs: [android, ...]`，
  结果 Android 缺 keystore 就一个包都不发、连桌面端都没有，用户打开 release
  页面看到的是空的。改成 `if: always()` 发布已成功的平台，并在正文里**显式
  警告**缺了哪个平台、为什么缺；整个 run 仍标记失败，不掩盖问题。

### 三端可发布专项：发布基建 + VPN 失败模式防护

一次全项目体检后的集中修复。定性：代码质量本身没问题（651→694 测试全绿、
analyze 零告警），真正的坑集中在**发布基建基本是空的**和**VPN 最关键的失败
模式没有任何防护**这两块。

#### 发布基建

- **缺签名不再静默降级成 debug 签名**，改成 release 构建直接失败。降级会产出
  一个"构建成功"但无法上架、且签名 key 无法事后更换的废包——比构建失败糟糕
  得多。`docs/RELEASE.md` 补齐 keystore 生成步骤。
- **产物版本改为从 tag 推导**（`--build-name` / `--build-number`）。此前不管打
  什么 tag，产物版本都是 pubspec 里写死的 `0.1.0+1`，两个硬后果：versionCode
  恒为 1 → Play Store 传不了第二个包；App 报的版本永远比 tag 旧 → 「检查更新」
  对所有用户永久误报（更新完还是提示）。
- **构建期参数集中到 `lib/core/config/build_config.dart`** 并由 CI 注入。此前
  8 个 `String.fromEnvironment` 散落在 6 个文件、`release.yml` 一个
  `--dart-define` 都没传，导致 Sentry 在所有正式包里永不初始化。
- **未配置的外链从"静默无效"改成隐藏入口**。引导页那句"继续即表示您同意条款"
  在拿不出条款文档时也一并隐藏——那不是缺个链接，是在声称一份不存在的协议
  已经生效。
- macOS 签名 + 公证、Windows 签名流程写入 CI（缺凭据时告警跳过，不阻断出包）。
- **macOS 产物改为 universal**：`core/build.sh` 的 `build_macos()` 日志写着
  "arm64, amd64"但只编 arm64，谁照这脚本重建 libcore 就会静默丢掉 Intel 支持。
  现在真编两个架构 + `lipo`，脚本内和 CI 都强制校验。

#### VPN 可靠性

- **新增"已连接但实际不通"（黑洞）检测**。此前内核报 `BoxStarted` 之后 UI 就
  一直显示已连接，哪怕整机流量早已被黑洞。复用既有的出口 IP 查询作探针（它本
  来就走隧道），提到 App 生命周期级，连续 3 次失败判 degraded 并明确告知用户。
  **不自动拆隧道**——误杀一条健康连接比让用户自己决定糟糕得多。
- **连接失败不再是死键**。`connect()` 的 4 个前置校验此前只 `debugPrint` 就
  返回，用户点了没有任何反应。全部改成可见的分类提示；"配置文件不存在"额外
  先自愈重拉一次订阅再报错。
- **桌面 libcore 加载失败不再静默变空壳**：界面照常渲染但点什么都不工作。
  新增 `StubReason` 区分真故障与测试替身，首页出阻断页。
- **批量导入配置不再触发 N 次并发重连**。设置变更监听改为 400ms 防抖——
  `importJson` 逐字段应用，一份完整导出约 30 个字段就是 30 次 reconnect 互相
  踩踏 + 30 条 toast。

#### 桌面端边界

- **移除必定失败的 TUN 服务模式**：仓库无 wintun 驱动、macOS 无网络扩展权限，
  选了只会让内核起 tun 失败。
- 在配置页明确告知泄漏面：系统代理模式下，不遵循系统代理的程序会直连并暴露
  真实 IP。README 同步说明。

#### 分流准确度

- **智能分流域名覆盖从 66 条手写扩到 8068 条**（631 精确 + 7437 后缀），完整
  反编译自 bundle 的 geosite 规则库。此前只有国内 IP 上的站能被兜住。
- 删除 `RuleSetProvisioner`：侦查证实内核在 `region:"other"` 下物理上不支持
  任何形式的 rule-set，它不是暂时的死代码，是架构上不可能有用的代码。

#### 其它

- **补齐 10 个语言全部缺失的 UI 文案**（126 个 key），并加完整性门禁测试。
- 修掉一个会让 CI 随机变红的 flaky test（两个测试共享真实网络栈争用）。
- 电池优化原生桥的单槽竞态：覆盖 / activity 为 null / 解绑三条路径都会让
  Dart Future 永久挂起。
- 统一订阅到期显示：详情页判"无限期"的标准跟其它两处不一致，且日期是硬编码
  中文。
- 删除三个零引用的数据库依赖（其中 `sqlite3_flutter_libs` 会打进原生库）和
  `notes` 死字段。

### libcore 二进制分发：LFS → GitHub Release tag

之前所有平台的 libcore 走 Git LFS，仓库 LFS 占 ~420MB。CI 多 job 并行 checkout 拉 LFS 约 3.4GB / run，GitHub Free Plan 1GB/月 bandwidth 配额被打爆，CI 全员 fail in `git lfs fetch`。

改走 GitHub Release：

- 创建 tag `libcore-v1.11.0`，把 5 个平台的核心库作为 release asset 上传
  （`libcore-android.aar` 115M / `libcore-macos-arm64.dylib` 44M / `libcore-windows-amd64.dll` 41M / `libcore-linux-amd64.so` 45M / `Libcore.xcframework.zip` 143M）
- 仓库不再 track 任何 lib 二进制，`.gitattributes` 清空 LFS rule，`.gitignore` 让本地下载的 lib 落地但不入 git
- `bin/fetch-libcore.sh` 用 `gh release download` 把对应平台 lib 拉到 build 期望路径
- CI ci.yml / release.yml 改成：`actions/checkout` 不带 lfs，每个 build job 加 fetch 步骤拉自己需要的 lib（释放 LFS bandwidth 压力）
- Windows / Linux 升 release build gate，build 后校验 libcore 真被装到产物且 FFI 符号导出

历史 LFS object 暂未清理（不影响新流程，但占静态 storage 配额）。后续可以 `git filter-repo` 收尾。

### Windows / Linux libcore 二进制就位（amd64 c-shared）

用 docker `golang:1.22-bookworm` linux/amd64 容器交叉编两个产物：

- Linux：`CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -buildmode=c-shared`，45M
- Windows：装 `gcc-mingw-w64-x86-64`，`CC=x86_64-w64-mingw32-gcc CGO_ENABLED=1 GOOS=windows GOARCH=amd64`，41M
- 都用同套 build tags：`with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc`

`nm -D` 验证 FFI 符号齐全：`setup` / `setupOnce` / `start` / `stop` / `parse` / `generateConfig` / `selectOutbound` / `urlTest` / `changeConfigOptions` / `startCommandClient` / `stopCommandClient`。

五平台 lib 全到位；iOS 仍卡 Apple Developer 账号 + 真机签名，Windows / Linux 进入"待真机点连接 smoke"。

### Android Kotlin 端 clean-room 重写（Phase 1-7，本地分阶段验证）

为远离 GPL-3 衍生品风险，把整个 Android Kotlin 层按"看代码理解 → 关掉文件 → 自己写"
的原则重新组织。每阶段单独 `flutter build apk` + 单测 + 装机 smoke 验证。

#### Changed —— 文件 / 包结构（Kotlin 端）

- `constant/` (6 文件) + `ktx/` (2 文件) → `core/Constants.kt` + `core/LibboxAdapters.kt`
  类型重命名：`Action` → `BroadcastIntents`，`Status` → `KernelStatus`，`Alert` → `AlertCode`，
  `PerAppProxyMode` → `AppFilterMode`，`ServiceMode` → `EngineMode`，`SettingsKey` → `PrefsKey`。
  enum case 名 / 字段值字符串（wire format）全保留 —— Dart EventChannel 协议不破。
- 7 个独立 `*Handler` / `*Channel` FlutterPlugin → `bridge/MethodBridge.kt` +
  `bridge/StreamBridge.kt`，dispatch 从 big-`when` 改成 name→suspend handler map。
- `bg/` 12 文件 → `engine/` 10 文件：`BoxService` → `KernelHost`，`VPNService` → `TunnelService`，
  `ProxyService` → `PlainService`，`PlatformInterfaceWrapper` → `LibboxHost`（abstract class），
  `DefaultNetworkListener`+`DefaultNetworkMonitor` → `NetworkWatcher`，
  `ServiceNotification` → `ForegroundNotice`，`ServiceConnection` → `KernelConnection`（Sink 接口替代 Callback），
  `ServiceBinder` → `KernelBinder`，`LocalResolver` → `SystemDnsBridge`。
  删 `AppChangeReceiver`（body 全注释）+ `BootReceiver`（未注册）。
- `Settings.kt` → `core/Prefs.kt`，按职责分 `Profile / Engine / Notice / AppFilter` 4 个 group。
- `MainActivity.logList: LinkedList + logCallback: var` → `engine/LogBuffer` 类（thread-safe，capacity bound）。
- `AndroidManifest.xml` service class 名同步更新。

#### Added

- **Kotlin host JVM 单测**（17 个）：
  - `ConstantsTest` 6 条：守 wire-format 字符串值（enum name / prefs key / broadcast action）。
    任何人 IDE refactor 改了 `KernelStatus.Started` → `Activated`，这里先红。
  - `LogBufferTest` 7 条：append / 超 capacity 丢最旧 / subscriber 触发 / snapshot 隔离。
  - `KernelConnectionDecodeTest` 4 条：AIDL ordinal → enum 越界 fallback。
  - 跑法：`cd android && JAVA_HOME=$(Android Studio JBR) ./gradlew :app:testDebugUnitTest`
- **Dart widget test**（2 条）：`proxies_page_tap_test.dart` 覆盖 ss-node tile 两条 isConnected 分支，
  守住用户报过的"Lines 页 tap 崩溃"回归。
- **Pigeon 第一条 method 迁移试水**：`bridge/PigeonBridge.kt` 实现 `BoxHostApi`，
  `validateConfig` 走 Pigeon 强类型路径（替代 `_methodChannel.invokeMethod('parse_config', map)`）；
  其余 10 个 method 暂留 stub（Result.failure），Dart 端继续走 `MethodBridge`，逐条迁。

#### Fixed（前一批，保留记录）

- **Android 单 SS URI DNS 不通**根因：sing-box fork 在 `enable-full-config=true` 时
  强制把 `dns-remote` 改成 `udp://1.1.1.1` 经代理转发，但 SS 协议很多服务器不支持 UDP
  → DNS 包丢 → Chrome DNS_PROBE_FINISHED。改默认 `remoteDnsAddress` 为 DoH
  (`https://1.1.1.1/dns-query`)，走 TCP 通道，所有 SS / Trojan 服务都支持 TCP
- **Smart 模式 rule-set 解不到根因**：`RuntimeConfigBuilder._injectSmartCnRouting` 用相对路径
  `./geoip-cn.srs`，但 Android 上 sing-box CWD 是 external files (`/storage/.../files/`)，
  跟 Flutter workingDir (`app_flutter/`) 不一致 → 静默失败 → smart 表现得跟 global 一样。
  改成绝对路径 + 单测断言 `path.startsWith('/')`。
- **Mixed inbound 端口冲突**：profile 自带的 mixed inbound 跟 fork 自己 inject 的 mixed:MixedPort
  撞 2080 → `bind: address already in use`。所有平台都剥 profile 自带 mixed（之前只剥桌面端）。
- **"已连接"卡死**：sing-box 启动失败时 watchStatus 在 `_transitioning` 期间被忽略，UI 还显示已连接。
  `ConnectionController` 现在监听 `BoxAlert`，遇到启动失败 alert 强制回 BoxStopped。
- **mode pill 文案换行**：英文 "Smart Routing" 在 180px 滑块里挤成 3 行带孤儿 "g"。改 i18n
  到单词级（en: "Global"/"Smart"，zh-CN: "全局"/"智能"）。
- **Git LFS** 入库 `android/app/libs/libcore.aar`（120MB），CI 能编 Android release APK。

### Added
- iOS NetworkExtension 脚手架（PacketTunnelProvider + Runner VPNManager + Handlers）
- Windows / Linux libcore 集成的 CMake 配置 + SCAFFOLDING 文档
- macOS 系统托盘图标 + 连接/断开/退出快捷菜单
- 关窗口前自动停 sing-box（避免系统代理残留）
- 主页 options 按钮跳设置 tab
- 删除订阅二次确认 AlertDialog
- 日志页接 box.log tail 流（1.5s poll）按 error/warn/debug 着色
- NetworkSettings 持久化层 + SettingsPage 4 个开关 + port / DNS editor 全部接真
- 连接时长显示（"已连接 5m 32s"）
- 启动自动按 updateInterval 更新过期订阅
- ss:// / vless:// 等 7 种代理 URI 直接导入（`addByContent`）
- 自动 dns.servers + tun inbound 补齐（让 single-URI profile 在 Android 上 TUN 可用）

### Fixed
- `reconnect()` 用 RuntimeConfigBuilder 拼好的 runtime-config（之前用原始 profile 导致分流失效）
- 切换"全局/智能"模式时如果连着会自动 reconnect
- connect 失败时把错误写到 `connectionErrorProvider` → HomePage listen 弹 toast

### Tests
- 92 个 unit + widget 测试全绿（覆盖 NotifierState、ProfileRepository CRUD、ConnectionController、formatters、SubscriptionInfo、ConfigParser、ProfileParser、BoxAlertType、ModeSelector、SettingsPage、ProfilesPage）
- Android emulator integration_test 验证 ss:// 单节点路由

### Engineering
- GitHub Actions CI：analyze + unit test 在 PR / push 上跑，~2 分钟
- 仓库 luke501/clashmiao (private)，CI Secret CLASHMIAO_TEST_SUB_URL 已配
- `bin/test-all.sh` 本地一键全套（并行 Android E2E + macOS 烟雾）
- 公开文档完全脱敏，不出现具体上游项目名

## [0.1.0] - 2026-03-01

### Added
- Flutter 3.41 + Riverpod + go_router 基础架构
- sing-box 内核接入（Android VpnService + macOS FFI）
- 订阅管理（Clash YAML / base64 / sing-box JSON 三种格式）
- 智能 / 全局两种代理模式
- 节点列表 + 延迟测试 + 排序
- 主题（明/暗/跟随系统）+ 10 种语言翻译
