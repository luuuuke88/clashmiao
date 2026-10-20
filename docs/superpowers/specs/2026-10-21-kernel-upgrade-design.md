# 内核升级到当前稳定线：设计（v1）

日期：2026-10-21　状态：v1.1（研究定稿，已按评审意见修订；本期只出设计与计划，不改任何产品代码）
事实依据：§2 的清单来自对当前仓库 Kotlin / Dart 源码的逐文件检索；§3–§5 的结论来自对上游源码（官方 sing-box v1.14.3、上游 core v5.0.3、旧内核提交 5098951）的直接阅读，以及我们在本机做的构建与冒烟实验（附录 A）。实验脚本不入库，计划任务 U1 会把同样的构建与冒烟固化进仓库。

## 0. 结论（一屏版）

- **推荐方案（b）**：新建**自有 Go 模块 `kernel/`**，以**官方 sing-box v1.14.3（当前稳定线）**为依赖，`experimental/libbox` 只在 Go 层使用、**不直接绑定给 Java**；对 Kotlin 只暴露一个很窄的 gomobile 门面（`com.clashmiao.libcore.core.*`）。订阅解析（Clash YAML / sing-box JSON / base64 URI 列表）和运行配置构建（旧 `Mobile.parse` / `Mobile.buildConfig` 的职责）由我们自己的 Go 包承担，按新 schema 重写。
- **Go 与构建**：release 构建用**当前通过我们测试矩阵的最新 Go**（实测 Go 1.27.3 与 1.26.3 都能构建、冒烟通过；官方 CI 用 1.26.8，`go.mod` 下限 1.25.5）。不再有「为迁就旧依赖钉死 Go 1.22」这一层；但 sing-box 自己仍依赖少量 `go:linkname`，Android 链接必须带 `-checklinkname=0`（官方构建同样如此），所以**每次升 Go 小版本都要过我们的矩阵**。
- **代价与收益**：Kotlin 侧 libbox 绑定层几乎整体重写（新 libbox 的 API 与 1.8.9 不是同一套东西），但**所有上层契约不动**——`KernelPort`、快照协议、健康探测、选择重放、分组/统计流的线格式、`getDefaultConfigOptions` 的键名。实测 arm64 `.so` 56.9 MB（压缩 19.1 MB），比现在的 65.2 MB（压缩 29.8 MB）更小，16 KB 对齐开箱即得。
- **不选（a）**：最新上游 core 建立在一个与官方分叉很远的 sing-box 1.13 上（其自述为 205 提交领先、454 提交落后，并列有已知构建缺口），`Parse` / `BuildConfig` 已被 gRPC 服务取代，且没有「只编译配置」的出口，离线分组要用的 `generateFullConfig` 无对应物。
- **不选（c）**：1.8.9 + Go 1.22.12 已出 Go 官方支持窗口，依赖钉在 2024-07，协议与安全修复都在断档；留作**回滚备胎**（保留现有 `tools/libcore/build-android.sh` 与 Release tag `libcore-v1.8.9-16k`），不再投入。

## 1. 目标与非目标

目标
1. Android 内核升到官方 sing-box 当前稳定线（v1.14.x），Go 用最新可验证版本。
2. 拿到现代协议（anytls、新版 hy2 / tuic、标准库 ECH 等）与安全修复，之后跟进上游只需「升 `go.mod` + 过测试闸门」。
3. 上层契约稳定：Dart 的 `KernelPort` / 快照协议、`ConnectionHealthMonitor`、选择重放、分组与统计流载荷、`configOptions` 键名，以及 Kotlin 的 `KernelRuntime` 接缝都不改语义。
4. 订阅解析、配置构建都有 Go 侧的黄金文件与夹具测试，**升级内核 = 跑测试看 diff**，不再靠真机试。

非目标（本期不做，单独立项）
- 桌面（macOS / Linux / Windows 的 FFI 动态库）与 iOS（xcframework）。新 Go 包按「核心包 + 平台门面」分层，桌面与 iOS 之后只加门面；本期它们继续用旧库，行为见 §8.3。
- 兑现旧内核没有的新功能（Tailscale、OpenVPN、OpenConnect、USB/IP、cloudflared 等一律不编译进来）。
- 把 Clash API 当产品功能保留（见 §5.4：旧内核开着它但 App 从未使用；新构建**永不生成、也不编译**它）。

## 2. 现状：我们实际用了内核的什么

> 约定：Kotlin 类型的包名是 `io.nekohasekai.libbox`（`Mobile` 在 `io.nekohasekai.mobile`），下文省略；这是唯一不可避免的出现处。路径相对 `android/app/src/main/kotlin/com/clashmiao/clashmiao/`。

### 2.1 Kotlin → 内核（我们主动调用）

| 符号 | 调用点 | 用途 | 新方案归宿 |
|---|---|---|---|
| `Libbox.setup(base, working, temp, false)` | `engine/LibboxKernelRuntime.kt` L58（一次性） | 设置目录 | `Core.setup(SetupOptions)` |
| `Libbox.redirectStderr(path)` | 同上 L59 | Go panic / stderr 落 `working/stderr.log` | 并入 `Core.setup`（libbox `Setup` 自己会重定向 stderr） |
| `Libbox.registerLocalDNSTransport(SystemDnsBridge / null)` | 同上 L119、L193 | 本地 DNS 走系统 `DnsResolver` | `Platform.localDNS()` 由 Platform 提供，随 Engine 生命周期 |
| `Libbox.setMemoryLimit(!disableMemoryLimit)` | 同上 L120 | GC 百分比 10 + 软内存上限 30 MiB + 连接 45 MiB 上限（旧 `memory.go`） | 门面 `SetupOptions.memoryLimited`，由 wrapper 自己调 `runtime/debug`（见 §5.5） |
| `Libbox.newService(content, platform)` / `BoxService.start()/close()/pause()/wake()` | 同上 L125、L133、L213、L226–227 | 创建并启动 box；Doze 暂停 / 唤醒 | `Engine.start(config)` / `stop()` / `pause()` / `wake()` |
| `CommandServer(handler, 300)` + `.start/.setService/.close` | 同上 L156–199 | 命令服务器：给 `CommandClient` 提供分组 / 统计 | 并入 Engine（新 libbox 的 `CommandServer` 自己持有服务生命周期） |
| `CommandClient` + `CommandClientOptions(command, statusInterval)` + `CommandClientHandler` | `engine/LibboxCommandStream.kt`（全文件） | 订阅 STATS / FULL_GROUPS / GROUP_INFO_ONLY 流 | `Engine.subscribeGroups/Stats`，Go 内直接产出线格式 JSON |
| `Libbox.newStandaloneCommandClient().selectOutbound(g, o)` | `engine/AndroidCoordinatorPlatform.kt` L111 | 选择重放与手选 | `Engine.selectOutbound` |
| `Libbox.newStandaloneCommandClient().urlTest(g)` | `bridge/PigeonBridge.kt` L274 | 分组测速 | `Engine.urlTest` |
| `Libbox.formatBytes` | `engine/ForegroundNotice.kt` L151–152 | 通知栏流量文案 | Kotlin 自己实现（不为一个格式化函数留依赖） |
| `Mobile.parse(path, tempPath, debug)` | `engine/LibboxKernelRuntime.kt` L65，由 `bridge/PigeonBridge.kt` L113 `validateConfig` 转入 | 订阅正文 → sing-box JSON | `Core.parse(outPath, inPath, debug)`（签名同序） |
| `Mobile.buildConfig(path, optionsJson)` | 同上 L77（启动）、`bridge/PigeonBridge.kt` L285（`generateFullConfig`，离线分组编译） | profile + configOptions → 最终运行配置 | `Core.buildConfig(profilePath, optionsJson)` |
| `Mobile.generateWarpConfig(key, id, token)` | `bridge/MethodBridge.kt` L168 | 注册 WARP 账号并生成 WireGuard 参数 | `Core.generateWarpConfig`（同签名，见 U13） |
| `Mobile.setup()` | `bridge/PigeonBridge.kt` L127 | 旧 Pigeon `setup`，上游实现是空函数 | 删除调用，Pigeon `setup` 保留为空实现 |
| `go.Seq.setContext` / `Seq.destroyRef` | `Application.kt` L22；`LibboxKernelRuntime.kt` L162/198/215；`LibboxCommandStream.kt` L166 | gomobile 运行时 | 仍然需要（gomobile 自带） |

被消费的内核类型：`StatusMessage`（`ForegroundNotice`、`bridge/StreamBridge.kt` 的 `StatsSubscriber`）、`OutboundGroup` / `OutboundGroupItem` / `OutboundGroupIterator`（`engine/OutboundSnapshot.kt`、`StreamBridge`）、`SystemProxyStatus`、`StringIterator`、`RoutePrefix`（`core/LibboxAdapters.kt`、`engine/TunnelService.kt`）。

### 2.2 内核 → Kotlin（我们实现的回调）

| 接口 | 实现 | 方法 / 字段 |
|---|---|---|
| `PlatformInterface`（1.8.9 共 17 个） | `engine/LibboxHost.kt`（抽象基类）+ `TunnelService` / `PlainService` | `openTun`、`autoDetectInterfaceControl`（`VpnService.protect`）、`useProcFS`、`findConnectionOwner`、`packageNameByUid`、`uidByPackageName`、`startDefaultInterfaceMonitor` / `closeDefaultInterfaceMonitor`、`getInterfaces`、`readWIFIState`、`clearDNSCache`、`writeLog` 与若干「恒为 true/false」的开关 |
| `CommandServerHandler`（4 个） | `LibboxKernelRuntime` | `serviceReload`、`getSystemProxyStatus`、`setSystemProxyEnabled`、`postServiceClose` |
| `LocalDNSTransport` + `ExchangeContext` | `engine/SystemDnsBridge.kt` | `raw` / `exchange` / `lookup`；结果经 `rawSuccess` / `errorCode` / `errnoCode` / `onCancel` 回传 |
| `InterfaceUpdateListener` | `engine/NetworkWatcher.kt` L93–140 | `updateDefaultInterface(name, index)` |
| `TunOptions`（只读） | `engine/TunnelService.kt` `buildTunFd` | `mtu`、`autoRoute`、`dnsServerAddress`、`inet4/6Address`、`inet4/6RouteAddress`、`inet4/6RouteExcludeAddress`、`inet4/6RouteRange`、`includePackage` / `excludePackage`、`isHTTPProxyEnabled`、`httpProxyServer/Port` |

规模对比（`javap -public` 实测）：1.8.9 的 libbox 公共类 41 个、静态原生方法 29 个、`PlatformInterface` 17 个方法；官方 1.14.3 的 libbox 公共类 **152** 个、静态原生方法 **64** 个、`PlatformInterface` **28** 个方法（新增通知、邻居表、SSH/Shell、桥接、Tailscale 主机名等移动端用不到的一堆）。直接绑定它意味着每次升级都要重新对齐一大片我们不用的表面，所以走「自有门面」（§4）。

### 2.3 线上协议（Kotlin → Dart），升级后必须逐字节保持

- **分组流，EventChannel（默认 Standard codec）载荷类型是 `String`**：JSON 文本 `[{"tag","type","selected","items":[{"tag","type","url-test-delay"}]}]`（`engine/OutboundSnapshot.kt` `toWire`，键名是契约，不能靠反射；R8 混淆曾因此出过事）。Dart `platform_box_service.dart`（`_groups`）只接受 `String` 再 `jsonDecode`，别的类型一律当作「没有分组」。
- **统计流，EventChannel（`JSONMethodCodec`，Kotlin `StreamBridge` 与 Dart `platform_box_service` 两端一致）载荷类型是 `Map`**：键 `connections-in`、`connections-out`、`uplink`、`downlink`、`uplink-total`、`downlink-total`，值为整数（`StreamBridge.StatsSubscriber` 现在发的就是 Map）。Dart（`_stats`）**只接受 Map**，收到字符串或其它类型会静默回落成 `BoxStats.empty`（全零），界面不报错、只是速率永远是 0。Dart 的 `is Map<String, dynamic>` 判断只对 JSON codec 解出的 Map 成立（Standard codec 解出的是 `Map<Object?, Object?>`，同样会回落成全零），所以**两条通道的 codec 也不得改动**，测试必须各走各自的真实 codec（§4.2）。升级后**两条流的类型各自保持**：Go 产出 JSON 文本，Kotlin 对分组原样透传 `String`，对统计**解析成数字 Map 再发**；不得对统计也透传字符串（§4.2）。
- 日志流：`LogBuffer` 快照（行文本）。
- 快照协议 / `KernelFailureCode`：`startCommandServer` / `createService` / `startService` 等失败码（`engine/KernelModel.kt`）。新门面要能区分「配置建不出服务」与「启动失败」，见 §4.2。

### 2.4 Dart 侧：谁在调内核

- **订阅解析**：`ProfileRepository._normalizeAndWrite`（`lib/domain/profile/data/profile_repository.dart` L874）。正文是 `{` 开头的 sing-box JSON 且 `outbounds` 非空 → **直接落盘不过内核**；否则 `boxService.validateConfig(out, tmp)`（→ Pigeon → `Mobile.parse`）。调用方：`addByUrl`、`update` / `_refresh`、`addByContent`（剪贴板 / 深链单节点）。
  - 抓取侧 `subscription_fetch.dart` 的 UA 回退与 `subscription_payload.dart` 的 HTML / 空节点判别，**不依赖内核**，保留。
  - 落盘后 `_ensureMinimalProfileStructure`（同文件 L145）补 `direct`、`proxy` 选择组、`route.final`、**旧格式** `dns.servers`（`address` / `address_resolver`）、以及带 `inet4_address` / `sniff` 的标准 inbounds。这些都是为 1.8 内核写的，新内核下 `dns` / `route` / `inbounds` 本来就被构建器丢弃（见下），写进去的旧格式是死数据。
- **运行配置**：`RuntimeConfigBuilder.build`（`lib/domain/config/data/runtime_config_builder.dart`）：剥 `mixed` / `tun` inbound、给订阅信息节点打 `§hide§` 标记、**自足补 `dns` 块并覆盖 remote 地址**（旧格式；内核丢弃整个 `dns`，所以实际无效，`remoteDnsOverride` 因此从未生效，且也没有界面入口）、按订阅注入 `multiplex`。
- **启动选项**：`getDefaultConfigOptions`（`lib/domain/config/data/default_config_options.dart`）产出 kebab-case 的 `configOptions` JSON，经 `changeConfigOptions` 存进 `Prefs.Engine.configOptionsJson`，启动时随 `LaunchSpec.optionsJson` 交给 `Mobile.buildConfig`。键：`region`、`execute-config-as-is`、`enable-full-config`、`block-ads`、`log-level`、`resolve-destination`、`ipv6-mode`、`remote-/direct-dns-address`、`remote-/direct-dns-domain-strategy`、`mixed-port`、`tproxy-port`、`local-dns-port`、`tun-implementation`、`mtu`、`strict-route`、`connection-test-url`、`url-test-interval`、`enable-clash-api`、`clash-api-port`、`enable-tun`、`enable-tun-service`、`set-system-proxy`、`bypass-lan`、`allow-connection-from-lan`、`enable-fake-dns`、`enable-dns-routing`、`independent-dns-cache`、`rules`（`ip` / `domains` / `outbound: bypass`，前缀语法 `full:` `domain:` `regexp:`）、`mux`、`tls-tricks`、`warp`、`warp2`。
- **离线分组**：`offline_proxy_groups_provider.dart` 在 Android 上走 `generateFullConfig(path)`（= `Mobile.buildConfig`）把订阅编译成运行时形态，保证离线与在线的分组 tag 一致。
- **旧内核的隐式契约**（`core/…` 与 Dart 注释里反复出现，升级后构建器必须保持）：主选择组 tag `select`、自动选择组 tag `auto`（`kRuntimeMainSelectorTag` / `kRuntimeAutoGroupTag`）；出站 tag `direct` / `bypass` / `block` / `direct-fragment`；DNS 服务器 tag `dns-remote` / `dns-direct` / `dns-local` / `dns-fake`（测试 `default_config_options_test.dart` 依赖 `dns-direct`）；入站 tag `tun-in` / `mixed-in` / `dns-in`；`route.final = select`（唯一例外：WARP 的 `warp_over_proxy` 模式，见 §5.2.2）、`dns.final = dns-remote`；节点 tag 含 `§hide§` 不进主选择组与自动选择组；订阅里的 selector / urltest 一律丢弃重建。
- **只认 `outbounds` 的 Dart 消费者（端点迁移的暗礁）**：新 `Parse` 会把 WireGuard 节点放进 `endpoints`，而下列读取点现在只看 `outbounds`，不改就会让「只有端点的订阅」被判空、默认选择丢失、离线类型识别失败：`subscription_payload.dart`（L87，节点计数；`outbounds: []` 而端点非空会被判成「无节点」）、`RuntimeConfigBuilder.runtimeSelectorDefaults`（扫 `§default§`）与 `hideSubscriptionInfoOutbounds`、`subscription_info_node.dart` 的 `candidateLeafTags`（L170）、`routing/data/config_parser.dart`（L15–L40，离线类型识别）、`profile_repository.dart`（`_ensureMinimalProfileStructure`、`_normalizeAndWrite` 的 JSON 直通判据）、`backup_codec.dart`（L286，恢复时只校验 `outbounds` 数组）。贯通方案见 §6.5。
- **内核之外、需要它在监听**：健康探测与出口 IP 探测走 `127.0.0.1:<mixed-port>`（`EgressIpService`）或 tun；`mixed-in` 必须按 `mixed-port` 存在。

## 3. 选项评估

### 3.1 对照表

| 维度 | (a) 最新上游 core v5.0.3 | **(b) 官方 sing-box 1.14.3 + 自有 Go 模块** | (c) 留在 1.8.9 fork |
|---|---|---|---|
| 内核基线 | 官方 1.13.0 + 其私有分叉（`replace` 指向子模块；分叉自述 205 提交领先 / 454 落后，rebase 笔记列有已知构建缺口） | 官方 1.14.3（2026-10-09，当前稳定；`1.15.0-alpha` 在预发布） | 2024-07 的 1.8.9 分叉 |
| Go | 1.26.3 | 1.25.5 起；官方 CI 1.26.8；**实测 1.26.3 / 1.27.3 均可构建并冒烟** | 钉死 1.22.12（已出 Go 官方支持窗口；Go 只维护最近两个次版本，现为 1.27 / 1.26） |
| 订阅解析 | 在 gRPC `Parse(ParseRequest{Content, ConfigPath, TempPath})` 里 | 我们自己的 Go 包（见 §6） | `Mobile.parse`（现状） |
| 配置构建 | 内部 `BuildConfig`，**无导出的「只编译」入口**；`GenerateConfig` RPC 在 proto 里已被注释掉 | 我们自己的 Go 包（见 §5） | `Mobile.buildConfig`（现状） |
| 移动端入口 | `platform/mobile`：`Setup(opt, platformInterface)` / `Start` / `Stop` / `GetServerPublicKey` / `AddGrpcClientPublicKey` / `Close` / `Pause` / `Wake` | 我们的门面（§4） | `Mobile.*` + 41 个 libbox 类 |
| 与 Kotlin 契约的距离 | 远：数据面是 gRPC + 客户端公钥交换，Kotlin 要引 gRPC 客户端或绕回 libbox 命令客户端；Parse 变成 RPC | **近**：门面签名刻意与旧入口同形（`parse` / `buildConfig` / `generateWarpConfig`） | 零 |
| 构建复现 | 需要两个子模块（其中一个是 SSH 地址），`go.mod` 多处 `replace` 到本地子模块 | `go.mod` 只依赖官方 tag；一个 `replace` 都不需要 | 现状（钉死 5 个依赖版本） |
| 协议 / 功能 | 超集（含 xray、psiphon、mieru 等），但跟着上游节奏走 | 官方集：anytls、snell、hy2（含 realm / gecko 混淆）、tuic、vless/vmess/trojan/ss、wireguard 端点；**没有** xhttp、mieru、psiphon | 缺 anytls、新 DNS 体系、标准库 ECH 等 |
| 安全修复 | 取决于上游分叉的 rebase 节奏 | 升 tag + 过闸门 | 标准库与依赖都停在 2024 |
| 体积（arm64 `.so`，未压缩 / 压缩） | 未测（依赖面更大） | **56.9 MB / 19.1 MB**（自有门面，推荐 tag 集，Go 1.27.3） | 65.2 MB / 29.8 MB |
| 16 KB 页 | 其 Makefile 带 `max-page-size=16384` | NDK r28 默认 `2**14`，实测 4 个 LOAD 段全部对齐，无需额外参数 | 现已靠 NDK r28 + 自编满足 |
| 授权面 | 依赖上游源码持续可得与其授权条款 | sing-box 为 GPL-3（附「不得用其名义」条款），与本仓库 GPL-3 兼容；上游同源 URI 转换代码为 CC0；Clash 转换库为 MIT | 现状 |
| 工作量 | 大（Kotlin 要接 gRPC；`generateFullConfig` 要给上游加补丁→变成新分叉） | **大但可控**：Kotlin 绑定层重写 + Go 模块（§9 的 18 个任务） | 近零 |
| 回滚 | — | 保留旧 aar / 脚本 / tag | — |

### 3.2 (a) 的细节

- **替代关系**：`Mobile.Parse` → gRPC `Parse`；`Mobile.BuildConfig` → 没有等价导出（构建发生在 `Start` 内）；`Setup` → `mobile.Setup(opt, platformInterface)`，并起 gRPC 服务，带公钥交换；`configOptions` → 一个「改设置」的 RPC（其选项结构与我们现有键名基本同源，这是它唯一的契约优势）。
- **libbox 风格的 Android 绑定**：能用——它的 `make android` 就是对 libbox 与 `./platform/mobile` 一起 `gomobile bind`——但绑的是**它的分叉里的 libbox**，且数据面要么走 gRPC（Kotlin 引 grpc-java + protobuf，包体与方法数都涨），要么绕回 libbox 命令客户端（那就等于选 (b) 再背着它的分叉）。
- **结论**：它没有满足「最新稳定 sing-box」这个目标（基线是 1.13 + 分叉），并且把我们的构建链绑死在一个不稳定的分叉上。

### 3.3 (b) 的两个子决定

- **门面 vs 直接绑 libbox**：门面。直接绑 libbox 要重写 Kotlin 里每个 libbox 引用并背着 152 个类的表面；门面把变动收敛在 Go 一处（见 §4）。实测 gomobile 对「我们的包 import libbox 的 Go 包」这种做法完全支持，Java 侧只生成我们自己的类。
- **基线版本**：1.14.3，而不是 oldstable 1.13.21。理由：1.14 把已弃用字段整批移除（旧 DNS 格式等），现在迁一次到位，不留下「下一版又要迁」的债；1.13 的 libbox 与 1.14 同属 gRPC 架构，迁移成本差不多。**退路**：把所有 libbox 相关调用压在 `kernel/engine` 一个包里；若 1.14 出现阻断性缺陷，可在同一门面下换成 1.13.21（差异主要是 `PlatformInterface` 方法集合与 `Setup` 选项）。本期不实现，只保证隔离。

### 3.4 配置 schema 迁移（1.8 → 1.14）对构建器的影响

> 「实测」表示用 `libbox.CheckConfig` 在 1.14.3 上跑了旧格式夹具，得到下面的拒绝文案（附录 A.3）。**注意 `CheckConfig` 只构造不启动**：有些错误（见第 2 行）只有真正 `Start` 才暴露，所以测试闸门必须包含启动测试（§7）。

| # | 项 | 旧（1.8.9 构建器产出） | 新（1.14.3） | 构建器决定 |
|---|---|---|---|---|
| 1 | DNS 服务器格式 | `{tag, address, address_resolver, strategy, detour}` | `{type, tag, server, server_port, path, domain_resolver, detour…}`；旧格式实测被拒：`legacy DNS server formats … removed in sing-box 1.14.0` | 写**地址解析器**把 `remote-dns-address` / `direct-dns-address` 映射成类型化服务器：裸 IP / `udp://` → `udp`；`tcp://` → `tcp`；`tls://` → `tls`；`https://host/path` → `https`（`path` 默认 `/dns-query`）；`h3://` → `h3`；`quic://` → `quic`；`local` → `local`；`fakeip` → `fakeip` 服务器；域名型地址一律带 `domain_resolver: dns-bootstrap`（独立的 IP-only 自举解析器，见 §5.2.1；**任何 DNS 服务器都不得用自己、或依赖自己的服务器去解析自己的域名**，构建器做依赖环检查）。不支持的（`dhcp://` 等）在选项校验阶段报错，不静默降级 |
| 2 | DNS 默认出口 | 服务器没写 `detour` 时走**默认出站**（`route.final`，即代理） | 新服务器按拨号字段处理，**默认等价于空 direct**（官方文档「与旧 HTTPS 服务器的差异」一节）。另：`detour` 指向一个**没有任何选项的 direct 出站**会在**启动时**被拒：`detour to an empty direct outbound makes no sense`（实测，`CheckConfig` 放行） | `dns-remote` 必须显式 `detour: <业务出口>`（常态为 `select`；`warp_over_proxy` 时为 `warp`，见 §5.2.2），否则远程 DNS 会直连泄漏；`dns-direct` / `dns-local` **不写** `detour`（本身就直连），要走分片再指 `direct-fragment`（它带选项，合法） |
| 3 | 全局 DNS 项 | `independent_cache`、`static_ips`、`rcode://success` 屏蔽服务器 | `independent_cache` 弃用（1.16 移除）；`static_ips` 无对应；屏蔽用规则动作 | 不写 `independent_cache`（`independent-dns-cache` 选项保留键名，构建器忽略并记 warn）；`dns-block` 服务器改为 DNS 规则 `action: predefined, rcode: NOERROR` 或 `reject`；`dns-trick-direct` 与 `static_ips`（指向第三方 DoH 的残留）整体丢弃 |
| 4 | domain strategy | 服务器 `strategy`；inbound `domain_strategy` | DNS 规则动作 `strategy` 在 1.14 弃用（1.16 移除）；全局 `dns.strategy` 可用；dial 字段 `domain_strategy` 仍被接受（实测）但已弃用；入站字段整批移除 | `ipv6-mode` → `dns.strategy`（`ipv4_only` 等）与 TUN 地址族；`remote/direct-dns-domain-strategy` 默认空，**非空时**才在对应 DNS 规则里写 `strategy`（弃用字段，隔离在一个函数里，注释标明 1.16 前要迁走）；`resolve-destination` → 路由规则 `{action: resolve, strategy}` |
| 5 | 出站必须有域名解析器 | 无 | 域名型服务器地址需要 `domain_resolver` 或 `route.default_domain_resolver`；多个 DNS 服务器时缺失会报错 | 写 `route.default_domain_resolver = dns-direct`（节点服务器域名走它）；DNS 服务器**自己**的域名一律 `domain_resolver: dns-bootstrap`（§5.2.1），所以直连 DNS 配成域名 DoH 也不会自举成环 |
| 6 | 特殊出站 | `block`、`dns`（`dns-out`）出站 + 规则 `outbound: block/dns-out` | `dns` 出站实测被拒：`removed in sing-box 1.13.0`；`block` 出站类型仍可用（实测放行）但属弃用写法 | 不再生成 `dns-out`；DNS 劫持用 `hijack-dns` 动作；拦截用 `action: reject`。`block` 出站不再生成（用户规则里 `outbound: block` 映射为 `reject`）；`bypass` 仍是一个**带名字**的 `direct` 出站（用户规则 `bypass` 的目标），要带选项或保持 tag 即可，不能当 DNS 的 `detour` |
| 7 | 路由规则动作 | 规则只有 `outbound` | 规则带 `action`（`route` 默认 / `reject` / `hijack-dns` / `sniff` / `resolve` / `route-options` / …） | 规则序固定：`sniff` → `protocol: dns` → `hijack-dns` → `inbound: dns-in` → `hijack-dns` → `port: 53` → `hijack-dns` → `bypass-lan`（`ip_is_private: true` → `bypass`，替代 `geoip:private`）→ 用户规则 → `final: <业务出口>`（常态 `select`；`warp_over_proxy` 为 `warp`，§5.2.2；用户规则里的 `proxy` 目标同指业务出口）。删除旧的 `clash_mode` Direct/Global 规则（没有任何界面入口） |
| 8 | sniff | 入站字段 `sniff` / `sniff_override_destination` / `domain_strategy` | 入站字段实测被拒（`removed in sing-box 1.13.0`）；`sniff` 变为路由动作；**没有** `override_destination` 的 JSON 键 | 用 `sniff` 动作；**行为变化**：嗅到的域名仍可用于规则匹配，但**不再替换拨号目标**（旧版会把目标改成域名由代理端解析）。需要「域名到代理端解析」的场景靠 `enable-fake-dns`。列为风险 R4，真机对比验证 |
| 9 | geoip / geosite | `region != other` 时拼远程 rule-set；`geoip:` / `geosite:` 规则项 | `geoip` / `geosite` 实测被拒：`removed in sing-box 1.12.0`；`rule_set`（本地 `.srs` 可用，实测加载 `assets/rule-sets/*.srs` 通过） | `region` 保留键名，**恒按 `other` 处理**（不拼任何远程规则集，也不引用 CDN）。规则里的 `geoip:` / `geosite:` 前缀不再识别，解析时报选项错误。智能分流的数据见 §5.3 |
| 10 | TUN 字段 | `inet4_address` / `inet6_address`、`inet4_route_*` | 合并为 `address` / `route_address` / `route_exclude_address`（旧字段实测被拒：`removed in sing-box 1.12.0`）；新增 `dns_mode`（默认 `hijack`）、`dns_address`、UDP NAT 字段 | 用 `address: ["172.19.0.1/28", "fdfe:dcba:9876::1/126"]`（`ipv6-mode = ipv4_only` 时只写 v4）；`stack` / `mtu` / `strict_route` / `auto_route` / `endpoint_independent_nat` 沿用；Android 端的 `openTun` 回调读 `dns_mode`（见 §6.2） |
| 11 | `experimental.clash_api` | `enable-clash-api: true` 时：`external_controller 127.0.0.1:<port>` + 随机 `secret` + `cache_file clash.db` | `clash_api` 里的 `cache_file` / `store_*` 子项弃用并被拒（实测）；`cache_file` 是独立选项（`path`、`store_fakeip`、`store_dns`，`store_rdrc` 弃用）；选择组持久化由 `cache_file.enabled` 驱动 | **永不生成 `clash_api`**（也不编 `with_clash_api`）：App 从未请求过它（Dart 里没有任何调用），开着只增加本机攻击面。`enable-clash-api` / `clash-api-port` / `web-secret` 键保留以兼容旧存档与备份：**值原样保留、不报错、不生效**；任一为非默认值（`enable-clash-api` 为真且端口非默认，或 `web-secret` 非空）时，构建器记一条 warning（`clash-api-unsupported`），不把它变成启动失败。`cache_file` 恒启用（`path: "cache.db"`，开 fake DNS 时 `store_fakeip: true`）。`with_clash_api` tag 因此不编（测试里断言任何选项组合下输出都没有 `clash_api`） |
| 12 | WireGuard | 作为出站（`type: wireguard` + `server` / `local_address` / `peer_public_key`） | 出站被移除（实测：`unknown field "server"`），改为**端点**（`endpoints[]`，`peers[]`） | 订阅解析把 WireGuard 节点放进 `endpoints`；构建器把**订阅端点**当普通节点纳入 `select` / `auto`（tag 同出站）。WARP 也走端点，但它是内部端点 `warp`，**不进** `select` / `auto`（§5.2.2，U13）。Dart 侧所有只读 `outbounds` 的消费者要同步认 `endpoints`（§6.5） |
| 13 | TLS 旁路 | 分叉私有：`tls_fragment {size, sleep}`、`tls_tricks {mixed_case_sni, padding_*}` | 实测被拒：`unknown field "tls_tricks"`。官方有 `tls.fragment` / `record_fragment` / `fragment_fallback_delay`（布尔与延迟，**没有 size / sleep**）；无 mixed-case SNI、无 padding | `enable-fragment` → 对 TLS 出站设 `tls.fragment: true` + `record_fragment: true`；`fragment-size` / `fragment-sleep` 不能兑现；`mixed-sni-case` / `enable-padding` 不能兑现。界面处理见 §5.6 |
| 14 | 多路复用 | `multiplex {enabled, protocol, max_streams, padding}` | 同名保留 | 沿用：仅对 vmess / vless / trojan / shadowsocks 且节点未自带 `multiplex` 时注入；reality 节点跳过（旧逻辑） |
| 15 | 日志 | `log.output = box.log`、`timestamp` | `disable_color` 不是 JSON 字段（实测被拒，它只是 Go 侧字段）；文件输出无上限增长 | 默认不写文件：日志走命令服务器的环形缓冲（`LogMaxLines`）→ `Platform.writeLog` → `LogBuffer`；`Prefs.Engine.debugMode` 时再开 `log.output` |
| 16 | urltest | `url`、`interval`、`idle_timeout` | 同名保留（实测放行） | 沿用 `connection-test-url` / `url-test-interval`；`idle_timeout = interval × 10`（旧值） |
| 17 | 选择组默认值 | 节点 tag 含 `§default§` 时把默认值设成**字面量** `§default§`（只有某节点 tag 恰好等于它才成员有效，否则启动报错） | selector 的 `default` 不是成员时**启动报错**（`CheckConfig` 放行，同第 2 行教训） | 修正：默认值取**含标记的那个节点的真实 tag**，没有则 `auto`。Dart 的 `runtimeSelectorDefaults` 同步改成同一口径，并同时扫描 `endpoints`（U16，§6.5） |
| 18 | `enable-full-config` | 沿用订阅自带的 inbounds | — | **不再沿用**：构建器只读取 profile 的 `outbounds` 与 `endpoints`，`inbounds` / `dns` / `route` 一律忽略（旧内核对 `dns` / `route` 本来就丢弃；Dart 也已把 `mixed` / `tun` 剥掉）。选项保留键名、无行为 |
| 19 | 其他弃用 | — | `download_detour`、隐式默认 HTTP 客户端、内联 ACME 等弃用项 1.16 移除 | 我们用不到（不生成远程规则集 / ACME） |

### 3.5 Go / gomobile / 16 KB / 体积（实测）

| 项 | 结论 |
|---|---|
| Go 版本 | `go.mod` 下限 1.25.5；官方 CI 1.26.8；本机 1.26.3 与 1.27.3（`GOTOOLCHAIN=go1.27.3`）都构建通过，主机冒烟（启动 → 经 mixed 入站 GET `generate_204` → 订阅分组 → 选择 → urltest → 停止）两个版本结果一致 |
| linkname | 不带 `-checklinkname=0` 时 Android 目标链接失败：`invalid reference to os.checkPidfdOnce`（libbox 自己的 Android pidfd 处理用了 `go:linkname`）。带上它并启用官方的 `badlinkname` / `tfogo_checklinkname0` tag 即可。这是**上游自己维护**的 hack，不再是我们为旧依赖背的 Go 钉死；代价是每次升 Go 小版本要重新验证 |
| gomobile | `github.com/sagernet/gomobile` **v0.1.13**（官方 `make lib_install` 同款）；旧脚本用的是 v0.1.1 |
| NDK / API | 现有 r28c（28.2.13676358）即可；`-androidapi` 取 App 的 `minSdk = 26`；仅出 `arm64-v8a`（与 `abiFilters` 一致） |
| 16 KB | NDK r28 默认；`llvm-objdump -p` 实测 4 个 LOAD 段全为 `align 2**14`，无需 `-Wl,-z,max-page-size` |
| 体积（arm64 `.so` 未压缩 / aar 内压缩） | 现状 1.8.9（Go 1.22.12）65.2 MB / 29.8 MB；官方 libbox 最小 tag 集、Go 1.26.3：61.4 / 20.2 MB；同上、Go 1.27.3：59.6 / 20.3 MB；自有门面（libbox 仅作 Go 依赖，带 `with_clash_api`）、Go 1.26.3：58.1 / 19.9 MB；**自有门面、推荐 tag 集（去掉 `with_clash_api`）、Go 1.27.3：56.9 / 19.1 MB**；官方完整 tag 集（含 tailscale / openvpn / openconnect / usbip / cloudflared / acme / dhcp）：75.4 / 24.9 MB。结论：**不编不用的东西**，比现在小 |
| 构建耗时 | 单 ABI 约 1 分钟（M 系列，缓存热） |
| tag 集 | `with_gvisor,with_quic,with_wireguard,with_utls,badlinkname,tfogo_checklinkname0`。相对旧集：去掉 `with_ech`（1.12 起走标准库，tag 已不存在）、`with_clash_api`（见 §3.4 第 11 行）、`with_grpc`（官方默认走 lite 实现，不带该 tag；兼容性在真机用 grpc 传输节点验证，列入 §7.3）。**单一来源**：这组 tags 与链接参数（`-checklinkname=0` 等）只写在 `tools/kernel/env.sh`，`go test` / `go vet`、CI 与发布构建都读它，不允许各写一份；缺这组 tags 时 QUIC / WireGuard / gVisor 等是桩实现，`CheckConfig` 会失败（官方 `include/*_stub.go` 的行为），所以裸 `go test ./...` 本来就不是合法的验证命令 |

## 4. 推荐方案与 Go 模块

### 4.1 布局

仓库根新增 `kernel/`（独立 Go module，路径 `github.com/luuuuke88/clashmiao/kernel`），按「核心包 + 平台门面」分层，只有门面与 `engine` 依赖 libbox：

```
kernel/
  go.mod  go.sum  tools.go            # tools.go 空导入 gomobile，锁版本
  core/                               # gomobile 门面（Android；iOS 之后复用）
  engine/                             # 唯一 import experimental/libbox 的包
  internal/options/                   # configOptions 解码、默认值、校验
  internal/build/                     # 运行配置构建（dns.go / route.go / outbounds.go …）
  internal/build/e2e/                 # 测试用本地可控目标（DNS / DoH / HTTP / 假节点，带请求记录），只被 _test.go 使用
  internal/legacy/                    # 旧 schema（1.8 时代产物）→ 新 schema 的清洗
  internal/subscription/              # 格式识别 + sing-box JSON / Clash / URI 列表 → profile
  internal/uri/                       # 单条 URI 转换（vmess / vless / trojan / ss / hy2 / …）
  internal/warp/                      # WARP 账号注册（U13）
  testdata/                           # 夹具与黄金文件
  api/java-api.txt                    # 门面公共 Java API 快照（javap 输出，CI 比对）
tools/kernel/env.sh                   # 唯一的 tags / 链接参数来源（go test、CI、release 共用）
tools/kernel/gotest.sh                # 唯一合法的 Go 验证入口（带共享 tags 与链接参数）
tools/kernel/build-android.sh         # 新构建脚本（沿用 tools/libcore 的固定版本 + 自测写法）
tools/kernel/check-public-names.sh    # 公开内容名称守卫（词表不入库，含自测与提交信息检查）
```

约束：`internal/build`、`internal/subscription`、`internal/uri`、`internal/legacy` **不 import sing-box**（自带最小 schema 类型 + 生成 JSON），因此测试快、与 sing-box 的 `option` API 解耦；升级 sing-box 时靠黄金文件 diff 与 `CheckConfig` / 启动测试发现 schema 变化，而不是靠编译器。

### 4.2 门面 API（Go → Java：`com.clashmiao.libcore.core.*`）

只用 gomobile 能传的类型（基本类型、`string`、`[]byte`、自有 struct / interface）；复杂数据一律 JSON 字符串，字段只增不改。

```go
// 静态函数 → Java 类 Core 的静态方法
func Setup(o *SetupOptions) error             // BasePath, WorkingPath, TempPath string; Debug bool; LogMaxLines int; MemoryLimited bool
func Version() string                         // sing-box 版本
func GoVersion() string
func Parse(outPath, inPath string, debug bool) error          // = Mobile.parse（同参序）
func BuildConfig(profilePath, optionsJSON string) (string, error)  // = Mobile.buildConfig
func CheckConfig(content string) error
func GenerateWarpConfig(licenseKey, accountID, accessToken string) (string, error) // = Mobile.generateWarpConfig
func NewEngine(host Platform, h EngineHandler) (*Engine, error)

type Engine struct{}
func (e *Engine) Start(configJSON string) error        // 阻塞；失败带分类前缀 "create-service:" / "start-service:"（见下）
func (e *Engine) Stop() error                           // 会打断尚未完成的 Start
func (e *Engine) Close() error                          // 与 Stop 一样：清理分步执行，任一步出错继续后面的步骤，返回合并后的错误；重复调用返回 nil
func (e *Engine) Pause()   func (e *Engine) Wake()   func (e *Engine) ResetNetwork()
func (e *Engine) SelectOutbound(group, tag string) error
func (e *Engine) URLTest(tag string) error
func (e *Engine) SubscribeGroups(h GroupsHandler) (*Subscription, error)     // OnGroups(json)：线格式见 §2.3
func (e *Engine) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) // OnStats(json)
func (e *Engine) SubscribeLogs(h LogHandler) (*Subscription, error)         // OnLog(line)
type Subscription struct{}   func (s *Subscription) Close() error

// Kotlin 实现
type Platform interface {
    OpenTun(specJSON string) (int32, error)     // specJSON 见 §4.3
    Protect(fd int32) error                      // = autoDetectInterfaceControl
    UseProcFS() bool
    FindOwner(protocol int32, srcAddr string, srcPort int32, dstAddr string, dstPort int32) (string, error) // JSON {"uid":N,"packages":[...]}
    StartInterfaceMonitor(l InterfaceListener) error
    StopInterfaceMonitor() error
    InterfacesJSON() (string, error)             // [{name,index,mtu,flags,type,addresses[],dns[],gateway[],metered}]
    ClearDNSCache()
    LocalDNS() LocalDNS                          // 可为 nil
    WriteLog(line string)
}
type LocalDNS interface {                        // 与现 SystemDnsBridge 一一对应
    Raw() bool
    Exchange(call *DNSCall, message []byte) error
    Lookup(call *DNSCall, network, domain string) error
}
type DNSCall struct{}   // OnCancel(Func) / Success(string) / RawSuccess([]byte) / ErrorCode(int32) / ErrnoCode(int32)
type InterfaceListener interface { Update(name string, index int32, expensive, constrained bool) }
type EngineHandler interface {                   // = CommandServerHandler 的我们需要的子集
    OnReloadRequested()
    OnStopRequested()
    SystemProxyAvailable() bool
    SystemProxyEnabled() bool
    SetSystemProxyEnabled(enabled bool)
}
```

要点
- **错误分类**：libbox 的 `StartOrReloadService` 把「建服务」与「启动」的失败混在一个错误里。`Engine.Start` 失败时再调一次 `CheckConfig(content)`（只在失败路径，成本可忽略）：它也失败 → 前缀 `create-service:`，否则 `start-service:`。Kotlin 据此保持 `FailureCode.CreateService` / `StartService` 的现有语义。
- **Go Engine 的并发停止能力，与现有协调器的实际行为，是两回事**：新 `Engine.Stop()` 内部调用 libbox 的 `CloseService`，会先 `interruptStart`，所以**在 Go 层**，另一个 goroutine 可以在 `Start` 阻塞期间把它打断（旧 libbox 的 `start()` 做不到）。但**当前 Kotlin 协调器不会这样用**：`KernelExecutor.cancel` 只置位取消标志，teardown 与 start 在同一工作线程上串行执行，所以 `startEngine` 阻塞期间不会有人调用 `Engine.stop()`；取消只在 `KernelStartSequence` 的检查点生效。本期**不改协调器**（它在冻结范围内），也**不承诺**「启动中取消会立即返回」：Go 侧的并发停止由 U2 的单测证明；Kotlin 侧只承诺「取消置位后，`startEngine` 一返回就走 teardown，并回收全部资源」，由 U14 的测试证明。把协调器改成可并发打断，是之后单独立项的优化。
- **线格式在 Go 里产出，类型在 Kotlin 里按通道各自还原**：分组 / 统计 JSON 都由 Go 生成并经 `OnGroups` / `OnStats` 交给 Kotlin（`OutboundSnapshot.kt` 的 Gson 路径与 R8 风险随之消失，字段名由 Go 黄金测试锁定）。Kotlin 对**分组原样透传 `String`**；对**统计解析成数字 Map（`Map<String, Long>`）再发**——Dart 只认 Map（§2.3）。两条流各有**跨语言共享夹具**：Go 产出的 `groups-first.json` / `stats-frame.json`，以及 Kotlin 经真实通道编码出的**信封黄金文件**——统计走 `JSONMethodCodec`，信封是 JSON 文本 `stats-envelope.json`；分组走 Standard codec，信封是二进制，以 base64 存为 `groups-envelope.b64`。测试**必须驱动真实 codec 信封经 `BinaryMessenger`**，不得手工构造 Map：（1）Go 断言产出与 `*-first.json` / `*-frame.json` 一致；（2）Kotlin 把夹具喂给 `StreamBridge` 的真实 `EventChannel`（统计 `JSONMethodCodec.INSTANCE`、分组默认 codec），用记录型 `BinaryMessenger` 抓取 `sink.success` 发出的字节，断言与信封黄金文件逐字节一致；（3）Dart 用 `TestDefaultBinaryMessengerBinding` 为各自通道（统计 `JSONMethodCodec`、分组默认 codec）注册 `listen` 的 mock，再把**同一份信封黄金文件**作为事件消息投递，断言 `watchStats()` 得到非零 `BoxStats`、`watchGroups()` 得到非空分组；另有反例——统计被发成字符串信封时 Dart 回落 `BoxStats.empty`，测试必须能抓住（U2 / U15 / U17）。
- **进程内通道**：Engine 内部用 libbox 的 `CommandClient` 连命令服务器的 unix socket（`BasePath/command.sock`，应用私有目录，不开 TCP，无需 secret）；`SelectOutbound` / `URLTest` 用独立的一次性客户端，与现状一致。
- **Java 命名**：`gomobile bind -javapkg=com.clashmiao.libcore -libname=clashmiao`，生成类位于 `com.clashmiao.libcore.core`。包名特意**不是** `com.clashmiao`：gomobile 生成的 `proguard.txt` 会 `-keep class <javapkg>.** { *; }`，用 `com.clashmiao` 会把整个 App 包挡在 R8 之外。
- **API 快照**：构建脚本把门面的 `javap -public` 输出与 `kernel/api/java-api.txt` 比对，任何公共 API 变化必须同时改快照（沿用 `tools/libcore` 的做法）。

### 4.3 `OpenTun` 的 JSON（`TunSpec`）

```json
{"mtu":9000,"auto_route":true,"strict_route":true,"dns_mode":"hijack",
 "dns_servers":["172.19.0.2"],
 "inet4_address":["172.19.0.1/28"],"inet6_address":[],
 "inet4_route":[],"inet6_route":[],"inet4_route_exclude":[],"inet6_route_exclude":[],
 "inet4_route_range":["0.0.0.0/1","128.0.0.0/1"],"inet6_route_range":[],
 "include_package":[],"exclude_package":[],
 "http_proxy":{"enabled":false,"server":"","port":0,"bypass":[],"match":[]}}
```

Kotlin 的 `TunnelService.buildTunFd` 只换数据来源（从 `TunOptions` getter 换成解析这个 JSON）；`dns_mode == "disabled"` 时不 `addDnsServer`。

### 4.4 保持不动的 Kotlin / Dart 契约

| 契约 | 为什么不用动 |
|---|---|
| `KernelRuntime` / `ExecContext` / `JobResult` 接缝与 `KernelCoordinator`、`CoordinatorCore`、`KernelStore`、`KernelSnapshot` | 它们只依赖 `KernelRuntime` 接口，`LibboxKernelRuntime` 换成 `CoreKernelRuntime` 即可 |
| Pigeon `BoxApi`（含 `getSnapshot` / `request` / `selectOutbound(expectedAttempt)`） | 不碰 |
| EventChannel 载荷（分组 / 统计 / 日志 / 快照） | 类型逐通道保持：分组 `String`（透传 Go 的 JSON）、统计 `Map`（Kotlin 把 Go 的 JSON 解析成数字 Map）；日志 / 快照不变（§2.3、§4.2，共享夹具测试） |
| `RuntimeConfigBuilder.build` 的 `remoteDnsAddress` 参数、`connection_launcher.dart`、`connection_error_classifier.dart` | 签名与文件都不动：参数保留并接受，其值与 `getDefaultConfigOptions` 的 `remote-dns-address` 同源（都来自 `settings.remoteDnsAddress`，真正生效的是后者），构建器内部不再写 dns；`BuildConfig` 失败沿 Kotlin `FailureCode` → `BoxAlert` → 既有分类，不改分类器（§6.4） |
| Dart `KernelPort`、`ConnectionHealthMonitor`、`EgressIpService`、`selection_replay_pipeline.dart`、`latency_test_coordinator` | 只看 `mixed-port` 与分组 / 选择 / urltest 接口，不碰 |
| `getDefaultConfigOptions` 键名 | 全部保留（无行为的键见 §3.4） |

## 5. 配置构建器（`internal/build`）

### 5.1 输入输出

- 输入：`profilePath`（只读 `outbounds`、`endpoints`；其余忽略，见 §3.4 第 18 行）+ `optionsJSON`。
- 输出：完整运行配置 JSON，保证 `libbox.CheckConfig` 通过**且**能真正 `Start`（§7 的两道闸）。
- 未知选项键：记 warn 并忽略；**已知键值非法**（端口越界、枚举不在集合）→ 报错（Dart 侧本来就校验，这是兜底）。

### 5.2 结构（与旧契约同名，新 schema 形态）

```jsonc
{
  "log": {"level": "...", "timestamp": true},                       // 默认不写文件
  "dns": {
    "servers": [
      {"type":"https","tag":"dns-remote","server":"1.1.1.1","path":"/dns-query","detour":"select"},   // detour = 业务出口（§5.2.2）；服务器地址是域名时另带 "domain_resolver":"dns-bootstrap"
      {"type":"udp","tag":"dns-direct","server":"223.5.5.5"},        // 无 detour；地址是域名时同样带 "domain_resolver":"dns-bootstrap"
      {"type":"local","tag":"dns-local"},
      {"type":"udp","tag":"dns-bootstrap","server":"223.5.5.5"}      // 仅当有 DNS 服务器地址是域名时才生成；永远是 IP 字面量，见 §5.2.1
      // enable-fake-dns 时追加 {"type":"fakeip","tag":"dns-fake","inet4_range":"198.18.0.0/15","inet6_range":"fc00::/18"}
    ],
    "rules": [ /* ①直连域名（各节点服务器域名、WARP 对端域名）→ dns-direct（DNS 服务器自己的域名不走规则，走 dns-bootstrap）
                  ②fake DNS（仅 tun-in）→ dns-fake
                  ③enable-dns-routing：bypass 规则逐条 → dns-direct；block → predefined
                  ④cp.cloudflare.com → dns-remote 且 rewrite_ttl 3000 */ ],
    "final": "dns-remote", "strategy": "<ipv6-mode>"
  },
  "inbounds": [
    {"type":"tun","tag":"tun-in","address":[...],"mtu":..,"auto_route":true,"strict_route":..,"stack":"..","endpoint_independent_nat":true},
    {"type":"mixed","tag":"mixed-in","listen":"127.0.0.1|0.0.0.0","listen_port":<mixed-port>},
    {"type":"direct","tag":"dns-in","listen":"...","listen_port":<local-dns-port>}
  ],
  "outbounds": [ select, auto, <节点…>, direct, direct-fragment, bypass ],
  "endpoints": [ <订阅里的 WireGuard 端点（普通节点）>, <内部 warp 端点（仅启用 WARP 时，§5.2.2）> ],
  "route": {
    "rules": [ sniff, hijack-dns…, bypass-lan, 用户规则 ],
    "final": "select",   // warp_over_proxy 时为 "warp"（§5.2.2）
    "auto_detect_interface": true, "override_android_vpn": true,   // 后者仅 Android
    "default_domain_resolver": "dns-direct"
  },
  "experimental": {"cache_file": {"enabled": true, "path": "cache.db"}}
}
```

- `tun-in` 仅 `enable-tun` 时生成。**「仅线路」模式（`enable-tun = false`）没有 `tun-in`**，也就不生成任何引用它的内容（fake DNS 规则 / `dns-fake` 服务器随之省略）；不变量与测试闸按这个条件断言，不再无条件要求 `tun-in` 存在（§7.1）。`override_android_vpn` 仅 Android 生成（其它平台会被内核拒绝，实测）。
- `select`：成员 = `auto` + 全部非隐藏**订阅节点（含订阅端点）**，**不含**内部 `warp` 端点；默认 = 含 `§default§` 的节点真实 tag（端点节点同样可作默认），否则 `auto`；`interrupt_exist_connections` 沿用旧行为（不开）。`auto`：`urltest`，成员 = 同 `select` 去掉 `auto` 自身。
- 订阅里自带的 `selector` / `urltest` / `direct` / `block` / `dns` 类型出站一律丢弃；tag 与预置 tag（`select` `auto` `direct` `bypass` `direct-fragment` `block`）冲突的节点：**重命名**（追加 ` (2)`）而不是静默丢弃，并在解析阶段给出提示（旧实现是 `continue` 丢弃）。
- 节点列表为空 → 报错 `profile has no usable outbound`（上层映射到现有文案）。

#### 5.2.1 DNS 自举与依赖环检查

问题：把 `dns-direct` 配成域名型 DoH（如 `https://doh.example.net/dns-query`）时，「它的服务器域名由谁解析」不能答「它自己」——那会自举成环；远程 DNS 同理。

决定：

- 引入**独立的自举解析器** `dns-bootstrap`：类型 `udp`、无 `detour`（直连），**地址必须是 IP 字面量**（可带端口）。选项键 `bootstrap-dns-address`，默认 `223.5.5.5`；不是 IP 字面量 → `option-invalid`。这是 Go 侧独有的键（Dart 目前不产生、也不新增界面入口；有需要时可经选项 JSON 覆盖），在 `keys.txt` 里标成 go-only，不触发「Dart 键漂移」检查。仅当至少有一个 DNS 服务器的地址是域名时才生成这个服务器。
- **所有域名型 DNS 服务器地址**（`dns-remote` / `dns-direct` 的 `https` / `tls` / `quic` / `h3` 等）一律 `domain_resolver: dns-bootstrap`，**绝不**指向自己或任何依赖它的服务器；DNS 规则不再承担「解析 DNS 服务器自己的域名」这件事。
- 节点服务器的域名仍走 `route.default_domain_resolver = dns-direct`（它的域名又经 bootstrap 解析，无环）。
- **构建器内置依赖环检查**（`internal/build/dnsgraph.go`，每次 `Build` 都跑，失败返回 `build-failed: dns dependency cycle: a -> b -> a`，不产出配置）：建一张依赖图——边 1：服务器 → 它的 `domain_resolver` 服务器（地址是域名时）；边 2：服务器 → 它的 `detour` 出站；边 3：出站（含端点）→ `route.default_domain_resolver` 服务器（保守地假定所有非 IP 字面量节点都需要）。要求图无环，且 `domain_resolver` 的终点必须是 IP 字面量服务器。同一份检查也作为不变量在测试闸里复跑（§7.1），所以改坏任何一条边都会被抓住。

#### 5.2.2 WARP 的出站图（两种模式）

原则：WARP 端点 `warp` 是**内部端点**，**在任何模式下都不是 `select` / `auto` 的成员**（否则 `select` 会含一条回到自己的路径，或让用户 / 自动测速选到一条绕过代理的裸 WARP 路径）；是否「裸 WARP」只由 `route.final` 与规则目标决定。`warp` 是保留 tag（订阅节点重名会被重命名）。变量**业务出口** `egress`：常态 `select`，仅 `warp_over_proxy` 时是 `warp`。`route.final`、用户规则里的 `proxy` 目标、`dns-remote` 的 `detour` 都指向 `egress`。

| | 无 WARP | `warp_over_proxy`（流量先经所选代理，再从 WARP 出） | `proxy_over_warp`（先过 WARP，再经代理） |
|---|---|---|---|
| 业务出口 `egress` / `route.final` | `select` | `warp` | `select` |
| `select`、`auto` 成员 | `auto` + 订阅节点 | 同左（**不含** `warp`） | 同左（**不含** `warp`） |
| `warp` 端点的拨号 | — | `detour: select`（WG 的外层 UDP 经用户所选节点；`select` 里没有 `warp`，所以无环） | 无 `detour`（直连，**拨号域名由 `dns-direct` 解析**） |
| 订阅节点（含订阅端点）的拨号 | 直连 | 直连（它们就是载体） | **每个订阅节点 / 端点的拨号链终点必须是 `warp`**：无 `detour` → `detour: warp`；已有 `detour` 链按其终点改写（见表后「既有 detour 链」）；`direct` / `bypass` / `direct-fragment` 这几个预置出站本身不改（规则命中仍直连） |
| `dns-remote.detour` | `select` | `warp`（DNS 与业务同出口；U13 先用真 `Start` 验证端点可作 DNS `detour`，不可则在附录补证据并把本格改写为 `select`，不得静默改路径） | `select` |
| `urltest auto` 的测速路径 | 节点直连 | 节点直连（测的是载体） | 节点经 `warp`（测的是整条链） |
| 受保护的性质 | — | 没有任何路径使「业务流量从 `select`/`auto` 的成员直接出去而不经 `warp`」；`warp.detour` 链以节点终止 | 没有任何路径使「`select`/`auto` 的成员绕过 `warp`」；`warp` 本身以直连终止 |

**`proxy_over_warp` 下既有 `detour` 链的处理**（保证「每个订阅节点的拨号路径终点是 `warp`」与装配规则一致，不留例外）：对每个订阅节点 / 端点，在**完整实体集合**（所有出站与端点，含分组）里沿 `detour` 走到末端，按末端类型改写：

| 末端 | 改写 |
|---|---|
| 没有 `detour` 的节点本身（链长 0） | 该节点 `detour: warp` |
| 代理类（`vmess` / `vless` / `trojan` / `shadowsocks` / `socks` / … 非直连类） | 把**最后那个代理**的 `detour` 设为 `warp` |
| 直连类（类型为 `direct` 的出站，含预置 `direct` / `direct-fragment` / `bypass` 与订阅里自带的同类） | 把指向该末端的那一跳的 `detour` **替换**为 `warp`（分片在 WARP 隧道里没有意义）；**不修改**被引用的预置出站本身，别的规则 / 节点仍可直连 |
| 成环（`a → b → a`） | 类型化错误 `ErrDetourCycle`，`BuildConfig` 返回 `build-failed: detour cycle: a -> b -> a`，不产出配置 |
| 悬空（`detour` 指向不存在的 tag、或指向订阅里被丢弃的分组） | 类型化错误 `ErrDetourDangling` |
| 末端已是 `warp` | 不变 |

每条**被改写的既有链**记**一条** warning（含节点 tag、旧终点、新终点；直连类被替换时注明「分片被丢弃」）；没有既有 `detour` 的节点不产生 warning。被多个节点共享的代理末端只改一次（幂等）。`warp_over_proxy` 下既有 `detour` 一律不动（节点只是载体）。

验证分两层（都在 U13，不得只留其一）：（1）**图单元测试**：对每种模式，从 `route.final`、每条规则目标、`dns-remote.detour` 出发枚举全部 `detour` 路径，断言 ①无环 ②`warp` 不在 `select` / `auto` 成员里 ③`warp_over_proxy` 下所有业务路径都经过 `warp`、`proxy_over_warp` 下所有订阅节点的拨号链最后一跳都是 `warp`（`warp` 自身直连终止） ④直连类出站（`direct` / `bypass` / `direct-fragment`）只能由规则显式选中；（2）**真流量验证**：用本地假节点与本地 WireGuard 对端（均为测试进程里再起的一个 sing-box 实例，带计数与请求记录）驱动整条链，断言路径：`warp_over_proxy` 时假节点收到 WG 外层 UDP 且目标 HTTP 服务的请求来自 WG 对端；`proxy_over_warp` 时假节点只通过 WG 隧道被访问（来源是隧道内地址），目标请求经假节点；直连规则命中的流量两处记录都为空（§7.1）。

### 5.3 智能分流数据

首期**零 Dart 改动**：继续接 `rules`（`ip` 用逗号分隔 CIDR、`domains` 用 `full:` / `domain:` / `regexp:` 前缀 → 新规则项 `domain` / `domain_suffix` / `domain_regex`，`outbound: bypass` → `action: route, outbound: bypass`）。这与现状等价，但每次启动都带约 7.5k 条 CIDR 与数千条域名的 JSON。**第二期（可选，U6 末尾评估）**：把排除表应用后的清单在构建期编成本地 `.srs`，构建器只写 `rule_set`（本地路径）——新内核终于支持了旧内核做不到的事（`assets/rule-sets/README.md` 里记的三条不可行证据全部不再成立）；实测官方 1.14.3 能加载现有 `geoip-cn.srs` / `geosite-cn.srs`。是否做取决于启动耗时与内存的实测，不预设。

### 5.4 Clash API / 缓存

见 §3.4 第 11 行。`enable-clash-api` 默认值在 Dart 里是 `true` 但没有消费者；构建器**永远不生成 `clash_api`**，也不编 `with_clash_api`：存档里的 `enable-clash-api` / `clash-api-port` / `web-secret` 原样保留（备份导出导入不受影响），仅在值非默认时记一条 warning。不存在「`web-secret` 非空就启用」的条件分支——那条路径没有被编译进去，等于兑现不了的承诺。

### 5.5 内存

旧 `setMemoryLimit(true)`（默认开）= GC 百分比 10 + 软上限 30 MiB + 连接 45 MiB 上限。新 libbox 没有等价开关（OOM killer 服务按平台策略工作，Android 默认不启用）。决定：门面 `SetupOptions.MemoryLimited` 为真时由 wrapper 自己设 `debug.SetGCPercent(10)` 与 `debug.SetMemoryLimit(30 MiB)`，**不**启用 OOM killer；45 MiB 连接杀手无对应物，列入风险 R6，用 K40 稳态 RSS 对比旧内核决定是否调参。

### 5.6 功能对照与界面处理（原则：不给假的可用性）

| 功能（当前界面 / 选项） | 新内核 | 处理 |
|---|---|---|
| TLS 分片开关 `enable-tls-fragment` | 有（`tls.fragment` / `record_fragment`） | 保留开关 |
| 分片 size / sleep（`tlsFragmentSize` / `tlsFragmentSleep`） | 无对应字段 | 界面隐藏这两项，选项键保留 |
| TLS padding（`enableTlsPadding`、`tlsPaddingSize`） / mixed-case SNI | 无 | 界面隐藏；存档值保留不丢；备份导出导入不受影响 |
| WARP 开关与账号 / 模式 / 干净 IP / 端口 | 有（WireGuard 端点 + 我们自己的账号注册，U13） | 保留；U13 未完成前整段 WARP 界面隐藏 |
| WARP 噪声（`warpNoise*` 四项，分叉私有的 fake packets） | 无 | 界面隐藏 |
| 广告拦截 `block-ads` | 需要规则集数据；旧实现拉的是上游 CDN 的远程规则集（不可复用） | 默认**隐藏**该开关；如需保留，另走「随包本地 `.srs`」并核对数据源许可（U6 的可选子项） |
| 分应用代理、系统代理（HTTP 代理）、LAN 共享、fake DNS、DNS 路由、IPv6 模式、MTU、TUN 栈、严格路由、日志级别 | 有 | 保留 |
| `region` | 仅 `other` | 无界面，保持 |

### 5.7 平台差异

Android 与 `kernelEnableTun` 的关系不变：`enable-tun = false`（「仅线路」）不生成 `tun-in`，Android 由 `PlainService` 起；`tproxy-port` 仅 Linux 桌面意义，Android 构建器不生成；`set-system-proxy` 在移动端恒 false。

## 6. 订阅解析（`internal/subscription` + `internal/uri` + `internal/legacy`）

### 6.1 管线

`Parse(outPath, inPath, debug)`：读 `inPath` → 去 BOM / 修剪 → **格式识别**（顺序固定）：
1. JSON（`{` 或 `[` 开头，容忍注释）：
   - 对象含 `outbounds` / `endpoints`：取这两项；
   - 对象但无这两项：当作**单个出站**；
   - 数组：每项必须是对象，当作出站列表（旧实现里这一支有类型断言 bug，会漏掉数组形式——新实现补上并加测试）。
   - 随后过 **legacy 清洗**（§6.3）。
2. Clash YAML（顶层有 `proxies`）：交给 **`github.com/xmdhs/clash2singbox`**（MIT，纯转换库，不依赖 sing-box，已有 1.14 版本档位 `SING114`）；`proxies: []` → 错误 `no outbounds found`。
3. URI 列表：整体 base64 / urlsafe base64（有无 padding 都要认）解码一次；逐行；每行一个 URI，交给 `internal/uri`；`ssconf://` 之类的订阅型 scheme 不支持（明确报错）。
4. 都不是 → `unable to determine config format`。

输出：只含 `outbounds`（+ `endpoints`），**不再补 `inbounds` / `dns` / `route`**。**节点计数 = `outbounds` 里的真实节点 + `endpoints`**（`selector` / `urltest` / `direct` / `block` / `dns` 不算）；`outbounds: []` 而端点非空是合法订阅。单节点失败不拖垮整份订阅（记 warning 计数，至少一个成功即成功；全部失败才报错，并带首个失败原因）。tag 去重（追加 ` (2)`）、空 tag 补 `<type>-<序号>`。

### 6.2 `internal/uri`（净室实现）

范围：`vmess://`（含 base64-JSON 与新式 URL 形式）、`vless://`（含 reality / ws / grpc / httpupgrade / h2 传输）、`trojan://`、`ss://`（SIP002 与旧式 base64、插件 `obfs-local` / `v2ray-plugin` 的 `plugin` 参数）、`hysteria2://` / `hy2://`（`obfs` / `obfs-password` / `pinSHA256` / `insecure` / `sni`，含端口跳跃 `mport`）、`hysteria://`、`tuic://`、`anytls://`、`socks://` / `socks5://`、`http(s)://`（作为代理出站）、`ssh://`、`wg://` / `wireguard://`（→ 端点）。每个 scheme 一个文件、一张表驱动测试。

实现方式的取舍：**默认净室重写**（行为由现有订阅形态与官方文档定义），不拷贝上游 core 的源码。理由：本仓库是公开的，而上游 core 的授权是用户个人购买的商业授权，是否覆盖在公开仓库里再分发其源码并未确认；上游同源的 URI 转换库是 CC0，可以直接参照 / 移植其解析规则与测试向量（需要时允许直接拷贝，且无需署名）。若要移植的是 core 本体的代码，先确认授权覆盖公开分发再动手。

### 6.3 旧 schema 清洗（`internal/legacy`）

用户已落盘的订阅文件是**旧内核 `Parse` 的产物**（1.8 schema），升级后不做数据迁移，改为「读时清洗」：`BuildConfig` 与新 `Parse` 对 `outbounds` / `endpoints` 都先过同一个清洗器（幂等）：

| 旧 | 新 |
|---|---|
| `type: wireguard` 出站 | 转成 `endpoints[]` 的 `wireguard` 端点（`server` / `server_port` → `peers[0].address/port`，`peer_public_key` → `public_key`，`local_address` → `address`，`reserved` 保留，`mtu` 保留） |
| `type: block` / `dns` / `selector` / `urltest` / `direct`（订阅自带的） | 丢弃（`dns` / `block` 实测不能留） |
| 出站上的 `tls_fragment` / `tls.tls_tricks` | 删除字段 |
| `domain_strategy`（dial 字段） | 删除（1.14 仍接受但已弃用；新构建器用 `default_domain_resolver`） |
| 出站上的 `sniff*` 等入站字段 | 删除 |
| `tcp_fast_open`、`udp_fragment` 等仍有效字段 | 保留 |

每条清洗在 `testdata/legacy/` 有「旧夹具 → 新输出」黄金文件，且新输出必须通过 `CheckConfig`。

### 6.4 错误分类

`Parse` / `BuildConfig` 的错误带稳定前缀码（`format-unknown:` / `no-outbounds:` / `uri-invalid:` / `option-invalid:` / `build-failed:`），不再靠 `e.message` 子串猜。映射**只发生在允许改动的边界，不碰 `connection_error_classifier`（冻结，且它按 `BoxAlertType` 归类，从来不看消息文本）**：

- **`Parse`（订阅导入 / 刷新）**：Kotlin 把原生异常消息原样带回；`ProfileRepository` 在 `validateConfig` 失败处把它包成 `ProfileValidationException`，**增加一个可空的 `code` 字段**（取自消息前缀，向后兼容；构造函数其余不变）；`profile_failures.dart` 的 `_profileFailureReason` 按 `code` 映射文案：`no-outbounds` → `t.proxies.emptyProxiesMsg`，`format-unknown` / `uri-invalid` / 其余 → `t.failure.profiles.invalidConfig`。两个文件都在 U16 的允许清单里。
- **`BuildConfig`（启动 / 离线分组）**：启动路径上由 Kotlin `CoreKernelRuntime` 沿用现有对 `Mobile.buildConfig` 异常的 `FailureCode` 映射（不新增失败码），走既有 `BoxAlert` → `classifyBoxAlert` → 既有文案；离线分组（`generateFullConfig`）失败沿用现有降级。消息前缀只用于日志与诊断，不驱动界面分支。

### 6.5 端点贯通 Dart 消费链路

Go 侧让 WireGuard 节点进入 `endpoints` 之后，Dart 侧所有只读 `outbounds` 的位置必须同步认端点，否则「只有端点的订阅」会被判空，默认选择与离线类型识别失效。但「认端点」不等于「全都换成同一个节点列表」：**必须区分两个视图**，用错视图会丢分组或把成员认成 `unknown`。

- **完整实体集合**（`profileEntities`）：所有 `outbounds`（含 `selector` / `urltest` / `direct` / `block` / `dns`）∪ 所有 `endpoints`，每项带 `tag` / `type` / 来源（出站或端点）。用于**分组遍历、tag → 类型的索引、引用重写**（改名后更新 `tag` / `detour` / `default` / 分组成员 / `route` 与 `dns` 里的引用）。
- **叶子节点视图**（`profileLeafNodes`）：完整集合去掉 `selector` / `urltest` / `direct` / `block` / `dns`，即真实可连的节点（含端点）。用于**节点计数与候选筛选**。

| 文件 | 现状（只看 `outbounds`） | 改为 |
|---|---|---|
| `lib/domain/profile/data/subscription_payload.dart`（L87） | 节点计数只数 `outbounds` | **叶子视图**计数；`outbounds: []` 且端点非空不判空 |
| `lib/domain/config/data/runtime_config_builder.dart` | `runtimeSelectorDefaults` 扫 `§default§`；`hideSubscriptionInfoOutbounds` 只遍历出站并改名 | `runtimeSelectorDefaults` 用**叶子视图**（`§default§` 标在端点上也识别，默认值取其真实 tag）；`hideSubscriptionInfoOutbounds` 用**完整集合**：遍历 `outbounds` ∪ `endpoints`，改名时更新 `tag` / `detour` / `default` / 分组成员，**唯一性集合 `allTags` 也包含端点 tag**，`route` / `dns` 引用照旧更新 |
| `lib/domain/config/model/subscription_info_node.dart`（`candidateLeafTags`，L170） | 只列出站 tag | **叶子视图**（含端点 tag） |
| `lib/domain/routing/data/config_parser.dart`（L15–L40） | 遍历 `outbounds` 取分组，并在 `outbounds` 里查成员类型 | **完整集合**：分组遍历与成员类型索引都用它（`select` 里的 `auto` 成员应识别为 `urltest`、WireGuard 端点成员识别为 `wireguard`，而不是 `unknown`）；**不能**用叶子视图——那会丢掉全部分组 |
| `lib/domain/profile/data/profile_repository.dart` | `_normalizeAndWrite` 的 JSON 直通判据要求 `outbounds` 非空；`_ensureMinimalProfileStructure` 假定出站数组存在 | 判据改为「叶子视图非空」，旧形态检测（`wireguard` 出站 / `dns` / `block`）用**完整集合**，含则走 `validateConfig` 清洗；`_ensureMinimalProfileStructure` 不因 `outbounds: []` 而失败 |
| `lib/features/config/data/backup_codec.dart`（L286） | 恢复时只校验「含 `outbounds` 数组」 | 「`outbounds` 或 `endpoints` 任一为非空数组」 |

**端到端测试（U16，下列形态缺一不可）**：用 Go 侧产出并入库的共享夹具 `kernel/testdata/shared/profiles/{endpoint-only,mixed,endpoint-default,groups-with-endpoint}.json`（`outbounds: []` 只有端点 / 出站与端点混合 / `§default§` 标在端点上 / **一个 `selector` 同时含 `auto`、一个 WireGuard 端点成员和一个会被隐藏的订阅信息节点引用**）：Dart 侧断言节点计数（叶子视图，分组不计入）、`runtimeSelectorDefaults`、信息节点筛选、`config_parser` 保留全部分组且成员类型正确（`auto` → `urltest`、端点 → `wireguard`）、`hideSubscriptionInfoOutbounds` 改名后分组成员与 `default` 的引用同步更新、`_normalizeAndWrite` 落盘不被判空；同一批夹具在 Go 侧走 `BuildConfig` → `CheckConfig` → 真 `Start`，断言端点出现在 `select` / `auto` 成员里、默认值正确（U9 / U7）。

## 7. 测试策略

闸门分四层——（1）原始配置的黄金文件与不变量；（2）主机适配副本的 `CheckConfig` 与真 `Start`；（3）本地可控目标上的真流量对等；（4）跨语言契约（选项键、线格式、端点形态）——**任何一层不过都不能发版**。

### 7.1 配置构建器：黄金文件 + 不变量 + 真启动 + 真流量

- **矩阵**：profile 夹具 P1–P7（单节点 / 多节点含订阅信息节点 / 含 `§default§` / WireGuard 端点（含**端点独占**、**端点与出站混合**、**端点带 `§default§`** 三种）/ hy2+tuic / reality / 旧 1.8 形态）× 选项夹具 O1–O9（Android VPN 智能 / Android 仅线路 / fake DNS + DNS 路由 + 绕过局域网 / mux + 分片 / WARP 两种模式 / 远程与直连 DNS 各地址形态：IP、`https://`（域名与 IP）、`h3://`、`tls://`、`quic://`、`tcp://`、`udp://`、`local`，**含「直连 DNS 本身是域名型 DoH」** / IPv6 三种模式 / 允许局域网 / block-ads 开关）→ 约 14 个黄金文件（并非全笛卡尔积，矩阵表写在 `testdata/README`）。
- **统一的构建参数**：所有 Go 测试用与发布构建**同一组 tags 与链接参数**（`tools/kernel/env.sh`，§3.5）；脚本 `tools/kernel/gotest.sh` 封装 `go test -race -tags … -ldflags …`，CI 与本地都只调它。
- **闸门的作用域：原始配置 vs 主机适配副本**。构建器产出的是 **Android 原始配置**（带 `override_android_vpn`、`tun-in` 等主机无法接受 / 无权限创建的东西）；`CheckConfig` 与真 `Start` 在主机上只能跑**适配副本**。两类断言分开、互不替代：
  - **原始配置上断言**（不启动，纯结构）：（1）与签入黄金文件逐字节相同（`-update` 重生成，diff 进评审）；（2）**不变量**——标签图自洽（引用均存在、selector `default` ∈ 成员、`detour` 无环、**无指向空 `direct` 的 `detour`**、DNS 依赖无环且 `domain_resolver` 终点是 IP 字面量、`warp` 不在 `select` / `auto` 成员里）、**禁用键扫描**（`sniff*`、入站 `domain_strategy`、`inet4_address` 等旧 TUN 字段、`geoip` / `geosite`、DNS 服务器 `address`、`outbound: dns-out`、`tls_tricks`、`tls_fragment`、`disable_color`、**`clash_api`**）、**必有 tag 与条件 tag**、规则顺序（`sniff` 在 `hijack-dns` 前）、`dns.final = dns-remote`、`route.final` = 业务出口（常态 `select`，`warp_over_proxy` 为 `warp`）。
  - **必有 / 条件 tag 的区分**：始终要有——`select` `auto` `direct` `bypass` `direct-fragment` `dns-remote` `dns-direct` `dns-local` `mixed-in`；**条件**——`tun-in` ⇔ `enable-tun`（「仅线路」必须没有，且不得有任何引用它的规则 / 服务器）、`dns-in` ⇔ `local-dns-port` 非 0、`dns-fake` ⇔ `enable-fake-dns` 且有 `tun-in`、`dns-bootstrap` ⇔ 有域名型 DNS 服务器、`warp` ⇔ WARP 启用、`override_android_vpn` ⇔ `Env.GOOS == android`。
  - **主机适配副本上断言**：适配函数 `HostAdapt(cfg)` 只允许做白名单里的改动——删 `tun-in` 及引用它的规则 / `dns-fake` 服务器、删 `override_android_vpn`、`mixed-in` / `dns-in` 换成 `127.0.0.1` 随机端口、（DoH 测试里）注入测试 CA；**白名单之外的差异一律使测试失败**（「适配副本与原始配置的差异」自己有一个测试，防止适配悄悄把真 bug 抹掉）。在副本上：`libbox.CheckConfig` 通过，**真 `Start`**（因为 `CheckConfig` 放行了「detour 指向空 direct」「selector 默认值非成员」这类启动期错误），查 `SubscribeGroups` 首帧、`SelectOutbound` / `URLTest` 不报错、`Stop`。
- **真流量对等测试**（占位节点启动成功、命令不报错，**不能**证明 DNS 出口、分流、WARP、IPv6、分片真的生效，所以另设）：测试进程里起一组**本地可控目标**（`internal/build/e2e`）——本地 UDP / TCP DNS 服务器与本地 DoH（域名经 `dns-bootstrap` 解析到回环）、本地 HTTP 目标、假节点（本地 SOCKS 上游），**每个都带请求记录**（来源、目标域名、哪条链路）；构建配置的适配副本经 `engine` 真起，经 `mixed-in` 发请求，**断言实际路径**：
  - **DNS 出口**：`dns-remote` 的查询出现在假节点的记录里（走了代理）、`dns-direct` 的查询只出现在直连 DNS 的记录里；直连 DNS 配成域名型 DoH 时查询**真的完成**（不是只通过 `CheckConfig`）；远程 DNS 配成域名时同样。
  - **分流**：`bypass` 规则命中的目标，HTTP 记录的来源是本机、假节点记录为空；非命中走假节点；`block` 规则被拒；`bypass-lan` 开 / 关两态。
  - **手选**：`SelectOutbound` 换节点后，流量记录换到另一台假节点。
  - **IPv6**（环境不支持回环 v6 时显式 `t.Skip` 并写明原因，不静默通过）：本地 DNS 同时给 A / AAAA，`ipv4_only` / `prefer_ipv6` 下目标记录到的地址族与预期一致。
  - **分片**：`enable-fragment` 开启时，本地 TLS 目标看到 ClientHello 被拆成多条 TLS 记录；关闭时一条。
  - **WARP**（两种模式）：见 §5.2.2 的真流量验证。
- **取消与清理测试**：（1）Go：`Start` 在平台回调里阻塞时，另一个 goroutine 调 `Stop`，`Start` 返回取消错误，资源（tun fd、接口监视、订阅 goroutine、socket 文件）全部释放；（2）清理链路上**每一步依次注入错误**（接口监视关闭失败、命令服务器关闭失败、订阅关闭失败……）：`Stop` / `Close` 仍执行其余全部步骤、返回合并后的错误、且之后能再次 `Start`；（3）Kotlin：取消在每个 `KernelStartSequence` 检查点置位，以及 `startEngine` 返回后才发现取消，两种情形下 tun fd、网络监听、`Seq` 引用都被回收；`teardown` 的每一步抛错时其余步骤仍执行。
- **同步靠事件，不靠延迟**：测试里**不得**用 `time.Sleep` / `Thread.sleep` / `delay` 来等「应该已经发生了」的事；一律用 channel / `CountDownLatch` / 回调通知等待，超时（≥ 30 s）只作为失败兜底。CI 里有一条 `grep` 检查（U1）：`kernel/**/*_test.go` 里除白名单文件外不得出现 `time.Sleep`。
- **Dart 导出夹具 + 漂移检测**：Dart 侧测试把 `getDefaultConfigOptions` 在一组设置下的输出写进 `kernel/testdata/options/*.json`（签入；有差异测试失败）；Go 侧加载全部夹具，**Dart 产生的任何键 Go 不认识就失败**。反向：Go 的已知键集合导出成 `kernel/testdata/options/keys.txt`（go-only 的键单独标注），Dart 测试比对。
- **线格式跨语言夹具**：`kernel/testdata/wire/{groups-first,stats-frame}.json`（Go 产出）与 `{stats-envelope.json, groups-envelope.b64}`（Kotlin 经真实通道编码出的信封黄金文件）同时被 Go（产出）、Kotlin（经真实 `EventChannel` + 记录型 `BinaryMessenger` 逐字节比对）、Dart（把信封黄金文件经 `TestDefaultBinaryMessenger` 投递给真实 `EventChannel`，断言非零 `BoxStats` / 非空分组）三方测试消费（§4.2）；不允许任何一方手工构造 Map 绕过 codec。
- **Dart 侧**：`runtime_config_builder_test.dart` / `default_config_options_test.dart` / `profile_repository_test.dart` 同步新契约（去掉旧格式 dns / inbounds 的断言，加入新夹具与端点三形态，§6.5）。

### 7.2 订阅解析：真实形态、纯合成数据

夹具全部合成：主机用 `example.com` / `*.example.net` / RFC 5737 与 RFC 3849 保留地址，UUID / 密码随机生成并在文件头注明「合成」，**不含任何真实服务器与凭据**。覆盖：

- URI 列表：vmess（base64-JSON，含 `ps` 中文 / emoji、`net=ws/grpc/h2`、`tls`、`alpn`）、vless（reality + `flow` + `fp`；ws + tls；grpc；httpupgrade）、trojan（ws / grpc / tls 参数）、ss（SIP002 带 / 不带插件、旧式整体 base64、IPv6 地址）、hy2（带 `obfs` / `pinSHA256` / `mport`）、tuic（`congestion_control` / `udp_relay_mode`）、anytls、socks、http、混合列表、含空行 / CRLF / BOM / urlsafe 无 padding 的 base64。
- Clash YAML：`proxies` 含 ss / ssr（应报不支持）/ vmess / vless-reality / trojan / hysteria2 / tuic / wireguard；带 `proxy-groups` 与 `rules`（应被忽略）；`proxies: []`；YAML 锚点 / 合并键。
- sing-box JSON：完整配置（含 selector / urltest / 旧 dns / route / inbounds，应只取出站）、纯出站数组、单出站对象、**1.8 时代形态**（wireguard 出站、`tls_tricks`、`tls_fragment`、`domain_strategy`、`dns` / `block` 出站）。
- 订阅信息节点（「剩余流量」之类）原样保留（隐藏标记由 Dart 打，沿用 `subscription_info_node.dart` 的规则）。
- 异常：HTML 拒绝页、空 `proxies`、整份不是已知格式、部分节点损坏（应部分成功并计 warning）、重复 tag、5000 节点规模（耗时与内存上限断言，防回退）。
- 往返性质：`Parse(x)` 的输出再喂给 `Parse` 与 `BuildConfig` 结果不变（幂等）。

### 7.3 真机与模拟器

> 本设计阶段不碰真机与模拟器；以下是任务 U18 的执行清单。**基线先于改动**：先用**现网 1.8.9 包**在同一台设备、同一订阅、同一网络上把**下表每一行**都做一遍并记录结果（连接耗时、稳态 RSS、`dumpsys connectivity` 的 VPN 网络数、关键站点可达性、各行判据的观测值），存 scratchpad；再装新包逐行对比，不边改边测。换包用 `adb install -r`，不先卸载（MIUI 会拒装）。**每个行为组合一行**，没有「同类就不测」的合并。

**Redmi K40（Android 13，arm64，USB，序列号 75fa01d6）**。执行时每行另记两列「1.8.9 基线」「1.14.3 结果」（模板放 scratchpad，不入库）；**基线列全部填完，才允许装新包**。

| # | 行为组合 | 操作与判据 |
|---|---|---|
| 1 | VPN × 智能分流 | 国内站直连、境外站走代理；出口 IP 探测两端不同；断开重连 × 20 |
| 2 | VPN × 全局 | 全部走代理；`select` 手选后出口 IP 变化 |
| 3 | 仅线路（无 tun）× 智能 / 全局 | 经 `127.0.0.1:<mixed-port>` 的探测与出口 IP；**配置里没有 `tun-in`**；VPN 栏无钥匙图标 |
| 4 | VPN ↔ 仅线路切换 | 必须换 Service 类；VPN 网络数始终 ≤ 1 |
| 5 | fake DNS × DNS 路由 × 绕过局域网（各开关组合） | 域名类站点可达；局域网地址直连；DNS 出口观测 |
| 6 | 远程 DNS 各形态（IP / `https` 域名 / `tls` / `quic` / `h3` / `tcp` / `udp`）× 直连 DNS 形态（含域名型 DoH） | 每种都能解析并上网；DNS 出口观测显示远程 DNS 走代理、直连 DNS 不走（无泄漏）；域名型 DNS 不卡在自举 |
| 7 | IPv6 三种模式 × 有 / 无 v6 网络 | 站点可达；地址族与模式相符 |
| 8 | mux 开 / 关 × vmess / vless / trojan / ss | 连通；大文件下载不断流 |
| 9 | TLS 分片开 / 关 | 对分片敏感的站点开关两态结果；其余站点不退化 |
| 10 | WARP × `warp_over_proxy` / `proxy_over_warp`（各用一个干净 IP 与默认入口） | 出口 IP 的归属符合预期；换节点后出口随之变化；关闭 WARP 回到常态 |
| 11 | 逐协议：grpc / reality / hy2 / tuic / ss / anytls 各至少一个真实节点 | 连通、可测速、出口 IP 正确（用户提供的测试订阅，不回显链接） |
| 12 | 订阅形态：端点独占 / 混合 / 端点带默认标记 | 导入不被判空；默认选择正确；离线分组与在线一致 |
| 13 | **覆盖安装后的存量订阅**（1.8 形态文件，不重新导入） | 读时清洗后能正常连接；刷新后落盘为新形态 |
| 14 | 手选 → 断开 → 重连 | 选择被重放；分组测速；延迟显示 |
| 15 | 健康探测 | 「上游黑洞」下进入 degraded，恢复后回到正常 |
| 16 | 生命周期 | App 被杀后冷启动 attach；磁贴启停；开机自启；Doze 暂停 / 唤醒；Wi-Fi ↔ 蜂窝切换后自动重载（连续 20 次，**重载不再固定等待 1 s 后的稳定性**） |
| 17 | 分应用代理 / 系统代理开关 / 允许局域网共享 | 各自生效、互不串扰 |
| 18 | `sniff_override_destination` 去除的影响（§3.4 第 8 行） | 一批域名站点逐个对比，记录差异 |
| 19 | 稳态指标 | 稳态 RSS、连接耗时、`dumpsys connectivity` VPN 网络数；RSS 不高于旧内核 +15% |

- **16 KB 模拟器（AVD `ClashMiao_16k_API36`，system image `google_apis_ps16k`）**：`unzip -l` 抽 APK 里 `lib/arm64-v8a/*.so`，`llvm-objdump -p` 逐段确认 `2**14`；`zipalign -c -P 16 -v 4`；安装、启动、连接 / 断开 20 次无崩溃；logcat 无 `dlopen` / `ELF` 对齐告警；表中第 1、3、16 行在模拟器上各跑一遍。
- 证据留存：logcat 里 `epoch / attempt / desired / source / version` 序列、`dumpsys connectivity`、截图，存 scratchpad，不入库。系统 VPN 授权弹窗不得代点。

## 8. 迁移、回滚与跨平台

### 8.1 存量用户数据

- **订阅文件**：不做数据迁移（§6.3 读时清洗）；刷新时由新 `Parse` 重写为新形态。
- **`configOptions`**：键名不变，旧存档直接可用；无行为的键按 §3.4 / §5.6 处理。
- **手选节点 / 延迟缓存**：键是 `proxy_selection_<id>`，值是 tag；`select` / `auto` tag 与节点 tag 不变，沿用。
- **`cache.db`**：旧 `clash.db`（bbolt）可留可删；新文件名不同，不读旧文件。
- **备份**：备份只含订阅文件与偏好，格式不变；恢复时 Dart 的校验改为「`outbounds` 或 `endpoints` 任一为非空数组」（§6.5，U16），新旧形态都放行。

### 8.2 回滚

保留旧 aar（Release tag `libcore-v1.8.9-16k`）与 `tools/libcore/build-android.sh`。回滚 = 发一个把 aar 与 Kotlin 绑定层换回去的 hotfix 版本。已被新 `Parse` 重写、含 `endpoints` 的订阅文件旧内核读不了（它的出站结构体没有该字段）——这类订阅在回滚后下一次刷新即恢复；该局限写进发版说明。因为改动集中在 `kernel/` 与 `engine/` 绑定层，回滚面也集中。

### 8.3 桌面与 iOS（本期不动）

- 它们继续用旧库与旧 Pigeon / FFI 路径；Dart 的 `configOptions` 契约两边共用，所以同一套选项在两种内核下都有效。
- **已知分叉**：（1）新 `Parse` 产出的订阅（含 WireGuard 端点）在旧桌面内核下读不了——只在跨平台恢复备份时才会碰到；（2）Dart 侧清理旧格式 dns / inbounds 的改动（U16）对旧内核同样安全（旧内核本来就丢弃它们）；（3）§5.6 里隐藏的界面项在桌面 / iOS 上也隐藏（旧内核能用，但保持三端一致，避免功能随平台漂移）。
- 后续立项：给 `kernel/` 增加 `desktop`（cgo 导出，对齐 `FFIBoxService` 的 13 个符号）与 `apple`（`gomobile bind -target ios,macos`，对齐 `KernelProviderProxy` 用到的 libbox 面）两个门面，包内逻辑零重复。

## 9. 实施拆分

18 个任务（U1–U18）见 `docs/superpowers/plans/2026-10-21-kernel-upgrade.md`。依赖顺序：U1 → U2（engine）→ U3（选项模型）→ U4（构建器骨架、测试闸门与本地目标夹具）→ {U5 DNS、U6 路由与规则、U7 出站装配、U8 旧 schema 清洗，彼此可并行} → U9（订阅解析管线，依赖 U8）→ {U10、U11 URI 转换，可并行} → U12（门面 + gomobile 绑定 + API 快照 + CI，依赖 U2 与 U4–U11）→ U13（WARP）；U14 → U15 两个 Kotlin 任务依赖 U12 产出的 aar；U16（Dart 端点贯通与订阅边界）与 U17（Dart 配置收口与跨语言契约）在 U9 之后即可开工，与 U14 / U15 并行（U16 用 U9 产出的共享夹具；U17 里的线格式通道测试读取 U15 产出的信封黄金文件，在 U15 之后收口）；U18（真机验收、文档、发布）最后。Go 部分（U1–U13）全部能在主机上用 `tools/kernel/gotest.sh` 验证，Kotlin 与 Dart 部分才需要 aar。

## 10. 风险与未决

| # | 风险 | 缓解 / 决定 |
|---|---|---|
| R1 | libbox 的 Go API 不是对外稳定契约（1.8.9 → 1.14.3 整体改写；1.14 仍在加入 `PlatformInterface` 方法） | 门面隔离 + `go.mod` 精确 tag + `api/java-api.txt` 快照 + `engine` 单包；升 tag 必过全部闸门 |
| R2 | 自写构建器的行为对等（尤其 DNS：默认出口变化、域名解析器、规则顺序）；`CheckConfig` 放行但 `Start` 拒绝的类别；「启动成功」不等于「路径正确」 | 不变量 + 真启动 + **真流量对等测试（本地 DNS / HTTP 目标与请求记录，§7.1）**；真机基线逐行对比（§7.3）；第 2 行的 `detour` 规则写进代码注释与测试 |
| R3 | 功能缺口：TLS padding / mixed SNI / 分片参数 / WARP 噪声 / block-ads 数据 | 界面隐藏而非保留假开关（§5.6）；存档值不丢；发版说明列明 |
| R4 | `sniff_override_destination` 无等价 | 真机对比；需要时引导开 fake DNS；列入发版说明 |
| R5 | `-checklinkname=0` 依赖 Go 运行时内部符号，Go 1.27 官方 CI 尚未覆盖；Android 运行期未在真机验证 | release Go 版本由我们的矩阵（1.26.x / 1.27.x）决定，U1 / U12 把主机冒烟 + 构建放进 CI（测试与发布共用 `env.sh` 的 tags / 链接参数）；U18 真机验证；退路是 1.26.x |
| R6 | 内存策略与旧内核不同（无 45 MiB 连接杀手） | Redmi K40 稳态 RSS 对比，必要时调 GC 百分比 / 软上限 |
| R7 | Kotlin 绑定层重写位于 VPN 关键路径（`PlatformInterface`、TUN、DNS、流） | 拆成 U14 / U15 两个任务各带 JVM 测试；`KernelRuntime` 接缝保持；真机矩阵 |
| R8 | 桌面 / iOS 暂用旧内核造成双内核期 | §8.3；单独立项 |
| R9 | 授权：公开仓库不得混入上游 core 的受限源码 | 净室实现 + CC0 / MIT / 官方来源；需要移植 core 本体代码时先确认授权范围 |
| R10 | `with_grpc` 不再编入，gRPC 传输走官方 lite 实现 | U18 用真实 grpc 传输节点验证；有问题再加 tag（体积影响很小） |
| R11 | 1.14.x 较新，可能有尚未暴露的缺陷；1.15 预发布在推进 | 跟随 1.14 补丁线；记录升级 runbook；退路 1.13.21（§3.3） |
| R12 | WARP 出站图的两处未验证假设：WireGuard 端点可作 DNS 服务器的 `detour`；`proxy_over_warp` 下给订阅端点加 `detour: warp` 被内核接受 | U13 先用真 `Start` 逐项验证；不成立则改写 §5.2.2 对应格并补附录证据，不静默换路径；图单元测试与真流量测试同时保留 |

未决项（留给实现时按实测拍板，不阻塞开工）：智能分流数据是否转本地 `.srs`（§5.3）；`block-ads` 是否随包提供规则集（§5.6）；内存参数（§5.5）。

## 附录 A：本次研究的实测记录

环境：macOS arm64，Go 1.26.3（本机）与 1.27.3（`GOTOOLCHAIN=go1.27.3`），NDK 28.2.13676358，gomobile v0.1.13，官方 sing-box v1.14.3；脚本与产物都在会话临时目录，未入库。

**A.1 构建（`gomobile bind` → `android/arm64`，`-androidapi 24`，`-trimpath -s -w -buildid=`）**

| 构建 | Go | 耗时 | aar | arm64 `.so`（未压缩 / 压缩） |
|---|---|---|---|---|
| 官方 libbox，最小 tag 集 | 1.26.3 | 61 s | 20.4 MB | 61.4 MB / 20.2 MB |
| 同上 | 1.27.3 | 51 s | 20.5 MB | 59.6 MB / 20.3 MB |
| 官方 libbox，完整 tag 集 | 1.26.3 | — | 25.1 MB | 75.4 MB / 24.9 MB |
| 自有门面（libbox 仅 Go 依赖，带 `with_clash_api`） | 1.26.3 | 17 s（增量） | 19.9 MB | 58.1 MB / 19.9 MB |
| **自有门面，推荐 tag 集与 ldflags（见 §3.5），`-javapkg=com.clashmiao.libcore`，`-androidapi 26`** | 1.27.3 | 17 s（增量） | 19.1 MB | **56.9 MB / 19.1 MB** |
| 现状 1.8.9 | 1.22.12 | — | — | 65.2 MB / 29.8 MB |

最小 tag 集：`with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0`；完整 tag 集再加 `with_dhcp,with_acme,with_tailscale,with_cloudflared,with_usbip,with_openvpn,with_openconnect`。去掉 `badlinkname` / `-checklinkname=0` 后 Android 链接失败（`invalid reference to os.checkPidfdOnce`）；去掉 `with_clash_api` 后分组 / 选择 / urltest 仍正常。两个自有门面的 `.so` 均为 4 个 LOAD 段全部 `align 2**14`；推荐配置生成的 `proguard.txt` 为 `-keep class go.** { *; }` 与 `-keep class com.clashmiao.libcore.** { *; }`（不会覆盖 App 自己的 `com.clashmiao.clashmiao` 包）。门面骨架（约 250 行）生成的 Java 类 11 个，对比直接绑定 libbox 的 152 个。

**A.2 主机冒烟（自有 `Engine`：libbox `CommandServer` + `StartOrReloadService`）**

两个 Go 版本均：启动 25–35 ms；经 `mixed` 入站 GET `https://cp.cloudflare.com/generate_204` → 204；`SubscribeGroups` 首帧即为 §2.3 的 JSON 线格式；`SelectOutbound("select","b")` 成功且下一帧 `selected` 变为 `b`；`URLTest("auto")` 后各节点 `url-test-delay` 更新；`Stop` 正常。DNS 服务器写 `detour: "direct"`（空 direct）时：`CheckConfig` 通过，**`Start` 失败**：`detour to an empty direct outbound makes no sense`。

**A.3 `CheckConfig` 对旧格式夹具的拒绝文案（v1.14.3）**

| 夹具 | 结果 |
|---|---|
| 旧 DNS 服务器（`address` / `address_resolver`） | `legacy DNS server formats are deprecated in sing-box 1.12.0 and removed in sing-box 1.14.0` |
| `dns` 出站 | `dns outbound is deprecated in sing-box 1.11.0 and removed in sing-box 1.13.0, use rule actions instead` |
| 入站 `sniff` / `sniff_override_destination` / `domain_strategy` | `legacy inbound fields are deprecated in sing-box 1.11.0 and removed in sing-box 1.13.0` |
| TUN `inet4_address` | `legacy tun address fields are deprecated in sing-box 1.10.0 and removed in sing-box 1.12.0` |
| 规则 `geoip` / 顶层 `geosite` | `geoip/geosite database is deprecated in sing-box 1.8.0 and removed in sing-box 1.12.0` |
| `clash_api.cache_file` / `store_mode` | `cache_file and related fields in Clash API is deprecated in sing-box 1.8.0, use experimental.cache_file instead` |
| `wireguard` 出站 | `unknown field "server"`（出站类型已改为端点） |
| `tls_tricks` | `unknown field "tls_tricks"` |
| `log.disable_color` | `unknown field "disable_color"` |
| `override_android_vpn`（非 Android） | `only supported on Android` |
| 放行：`block` 出站与 `outbound: block` 规则、出站 `domain_strategy`、`reject` / `predefined` / `hijack-dns` / `sniff` / `resolve` 动作、本地 `.srs` 规则集（现有 `geoip-cn.srs` / `geosite-cn.srs`）、`fakeip` 服务器、`https` / `h3` / `tls` / `quic` / `tcp` 服务器、`tls.fragment` + `record_fragment`、`multiplex`、WireGuard 端点（含 `reserved`）、无 `clash_api` 的 `cache_file` | `<nil>` |

**A.4 上游 core v5.0.3 的要点（2026-10-18）**：`go 1.26.3`；`go.mod` 依赖 `sing-box v1.13.0` 并 `replace` 到本地子模块；两个子模块（其一为 SSH 地址）；`platform/mobile` 导出 `Setup` / `Start` / `Stop` / `GetServerPublicKey` / `AddGrpcClientPublicKey` / `Close` / `Pause` / `Wake`；gRPC 服务含 `Parse`、改设置、`Start` / `StartService` / `Restart` / `HotReload`、`SelectOutbound`、`UrlTest`、`GenerateWarpConfig`；构建 tag 含 `with_embedded_tor`、`with_awg`、`with_conntrack` 等；安卓绑定用 `gomobile bind … libbox ./platform/mobile`。其 sing-box 分叉的 `REBASE_NOTES.md` 自述 205 提交领先、454 提交落后，并列出已知构建缺口。
