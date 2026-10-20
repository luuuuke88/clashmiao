# ClashMiao 架构

## 一句话总览

Flutter 写 UI 与业务，**抽象出 `BoxService` 接口**，每个平台用各自最稳的方式接 sing-box：移动端走原生桥（Pigeon + EventChannel，原生侧是 Android 的 VpnService / iOS 的 PacketTunnel 扩展），桌面端走 FFI 直接调动态库。连接的开 / 关 / 重载不直接调 `BoxService`，而是经 **`KernelPort`** 提交「期望状态」，由内核侧（Android 原生协调器，其它平台的 Dart 模拟层）收敛并回报权威快照，见「连接生命周期」。

`lib/` 按职责分成五层，依赖方向单一，由架构测试在 CI 里强制（见下一节）。

## 分层

### 目录结构

```
lib/
├─ main.dart            启动组装（可依赖全部层）
├─ app/                 应用外壳：App、路由、底部导航 Shell、启动开屏、托盘、快捷键、
│                       窗口退出守卫、启动检查更新、深链编排
├─ features/<功能>/      页面级功能：about assets config home logs profile proxy settings splash
│   ├─ model/           （可选）只给本功能用的模型
│   ├─ data/            （可选）只给本功能用的数据访问
│   ├─ application/     （可选）只给本功能用的状态
│   └─ presentation/    页面与组件
├─ domain/<概念>/        跨功能的业务概念：config profile routing connection
│   ├─ model/           纯 Dart 模型
│   ├─ data/            仓库、解析、IO
│   └─ application/     Provider / Notifier / 服务
├─ core/<模块>/          平台与基础设施，零业务
│                       auto_start battery_optimization box_service env haptic http_client
│                       localization logger proxy storage store_review theme update utils window
└─ shared/<模块>/        不懂业务的通用 UI 与导航状态：components navigation
```

`*.g.dart` 等生成文件跟随所在目录，算作那一层，不单独豁免。

### 依赖规则

| 层 | 允许依赖（项目内） |
|---|---|
| `core` | `core` |
| `shared` | `core`、`shared` |
| `domain/<X>` | `core`、`domain/<X>`、**排序更低**的 `domain/<Y>` |
| `features/<F>` | `domain`、`core`、`shared`、`features/<F>` 自身 |
| `app` | 全部 |
| `main.dart` | 全部 |

`app` 与 `main.dart` 只豁免上表的**依赖方向**；相对 URI 的规范性检查对所有文件一视同仁，`app/` 与 `main.dart` 也不例外。

**domain 概念的固定顺序**（从低到高）：`config` → `profile` → `routing` → `connection`。高的可以依赖低的，反之不行。这是按真实依赖推出来的：订阅仓库要读代理端口（profile → config），节点选择按订阅 id 存（routing → profile），连接状态机要组装订阅、路由和配置（connection → 全部）。用固定顺序而不是「不成环」，是因为它更好懂，也能挡住「两个概念互相引用一次」这种还没成环但已经开始缠绕的情况。新增概念必须先在 `kDomainOrder` 登记位置。

四个 domain 概念的内容：

| 概念 | 内容 |
|---|---|
| `config` | 网络设置（`NetworkSettings`）、默认 sing-box 配置、运行时配置生成、国内直连规则、WARP |
| `profile` | 订阅模型、仓库、解析、拉取、载荷、定时更新、深链解析、到期时间格式化 |
| `routing` | 代理模式、从配置解析节点分组、离线分组、节点选择记录、延迟缓存 |
| `connection` | 纯函数状态机（`ConnectionMachine`）与控制器（`ConnectionController`）、启动产物准备（`ConnectionLauncher`）、错误分类、健康探测、出口 IP |

附加规则：

- **模型纯净（按传递闭包检查）**：从 `domain/*/model/**` 出发，沿项目内 import / export 走到的所有文件（含自身）都不得引用 `package:flutter/*`、Riverpod 系列包、`dart:io`、`dart:ui`，也不得到达任何 `domain/*/data` 或 `domain/*/application`。只查直接 import 会放行「模型 → 工具函数 → 翻译 → Flutter」这种间接依赖。
- **只用 package 导入**：`analysis_options.yaml` 启用了官方 lint `always_use_package_imports`，`flutter analyze --fatal-warnings` 会拦相对导入。
- **功能之间不互相引用**，唯一的口子是白名单（见下）。
- **没有转发用的 barrel 文件**：barrel 会增加一层间接依赖、让依赖归属更难追踪，所以直接导入定义所在的文件。

### 架构测试

位置：`test/architecture/`。

| 文件 | 作用 |
|---|---|
| `layering_test.dart` | 对真实的 `lib/` 跑全部规则 |
| `layering_rules.dart` | 规则判定：层间依赖、domain 顺序（`kDomainOrder`）、模型纯净、非规范 URI（`checkLayering` / `checkModelPurity`），以及白名单的过期条目（`staleEntries`）与合法性、上限（`checkAllowlist`） |
| `import_scanner.dart` | 用官方 `analyzer` 解析器提取 `import` / `export` 指令的 URI（含条件导入的每个分支），不用正则；`part` / `part of` 不产生依赖边，不提取。`projectPath` 把 URI 还原成 `lib/` 内路径，`nonCanonicalUriReason` 判定项目内 URI 是否规范 |
| `allowlist.dart` | 功能之间依赖的白名单与上限 |
| `*_test.dart`（扫描器、规则） | 检查器自测：用合成源码覆盖正反用例，保证检查器真的会报错，不是永远绿 |

跑法：`flutter test test/architecture/`（全量 `flutter test` 也会跑到）。失败时每条违规打印成「源文件 → 目标文件 · 违反的规则 · 修复建议」，一次列全。**报错时的处理顺序**：

1. **层间依赖违规**：改代码，不要去动测试。共享的状态 / 模型下沉到 `domain`，共享的 UI 下沉到 `shared`，与业务无关的基础能力下沉到 `core`。
2. **domain 顺序违规**：说明依赖方向反了。把被依赖的那部分挪到更低的概念里，或改由更高的概念来组装。
3. **模型纯净违规**：报错里带有最短的传递链，沿链找到把 Flutter / Riverpod / `dart:io` 带进模型的那个文件，把那部分挪出 `model/`。
4. **「白名单条目对应的依赖已经消除」**：依赖已经没了，把那几条从 `allowlist.dart` 删掉即可（见下面的棘轮）。
5. **提示不在任何一层里**：文件放错了位置，按下面「新文件归属」归位。
6. **「非规范 URI」**：`import` / `export`（含条件导入分支）里写了含反斜杠、百分号转义、query/fragment、空段的项目内 URI，或含 `.` / `..` 段的 `package:clashmiao/` 路径（如 `package:clashmiao/core/../domain/x.dart`），或越出 `lib/` 的相对路径，检查器无法可靠还原依赖边，一律按违规处理（失败即关闭）。改成 `package:clashmiao/...` 导入。

### 白名单：只减不增

`features/<F> → features/<G>` 的文件级依赖默认是违规的，目前只登记了 5 条页面之间的直接跳转（首页 → 订阅表单、首页 → 订阅列表、首页快捷设置 → 配置页、配置页 → 资源页、配置页 → 日志页）：路由集中到统一入口之前，页面需要持有目标页面的类型，暂时无法解耦。

- 白名单**只能**豁免功能之间的边；两端不都在 `features/` 下的条目本身就算违规，跨层依赖没有后门。
- **棘轮**：条目对应的依赖在代码里已经不存在时，测试失败，要求删除该条目。
- **上限**：`allowlist.dart` 里的 `kAllowlistCeiling`（当前为 5）限制条数。上限只能调小：每清掉一条依赖，同时删条目、调低上限；想加一条，必须同时改条目和上限两处，在 diff 里一眼可见，评审时要有充分理由。

### 新文件归属

清单之外的新文件按下面的顺序判定：

1. 被两个及以上功能、或被 `app` / `domain` 使用的业务逻辑 → `domain`。
2. 不知道任何代理 / 订阅概念、换个 App 也能用 → `core`（逻辑）或 `shared`（UI）。
3. 只服务一个页面 → 该功能内部。
4. 判定不了时放更靠近使用方的一侧，等出现第二个使用方再上提。

## 关键模块

### `BoxService` 抽象（`lib/core/box_service/box_service.dart`）

工厂方法按平台分发：

| 平台 | 实现 |
|------|------|
| Android / iOS | `PlatformBoxService` — Pigeon 强类型调用 + EventChannel 推送流 |
| macOS / Linux / Windows | `FFIBoxService` — 直接 `DynamicLibrary.open` 加载 `libcore`，dart:ffi 调 Go 导出符号 |
| 其他平台（或工厂里 `FFIBoxService()` 构造抛异常） | `StubBoxService` — 占位实现，操作返回空数据，避免 UI 崩；构造抛异常时带 `StubReason.coreLoadFailed` |

桌面端加载 libcore 并不发生在构造时，而发生在稍后的 `FFIBoxService.init()`（`_loadLibrary()`）。`main.dart` 在 `init()` 失败时只打一行日志（`sing-box 初始化失败`），`boxService` 仍是 `FFIBoxService` 实例，并不会被换成 `StubBoxService`；因此首页读 `coreLibraryMissingProvider` 的「核心库缺失」告警目前不会因为动态库加载失败而触发（见「已知技术债」）。

接口方法：`init` / `setup` / `validateConfig` / `changeConfigOptions` / `start` / `stop` / `restart` / `selectOutbound` / `urlTest` / `generateFullConfig` / `generateWarpConfig` / `clearLogs` / `resetTunnel`，以及监听流 `watchStatus` / `watchAlerts` / `watchStats` / `watchGroups` / `watchLogs` / `watchNetworkChanged`。持有需要显式释放资源的实现（目前是 `FFIBoxService`）额外实现 `DisposableBoxService`。

在 Android 上，连接生命周期（开 / 关 / 重载 / 手选重放确认）不再走这里的 `start` / `stop` / `restart`，而走 `KernelPort`；iOS 与桌面由 `EmulatedKernelPort` 包装本接口实现同一份契约（见「连接生命周期」）。

### 移动端通信协议

`PlatformBoxService` 与原生层之间有三类通道：

**1. Pigeon（强类型 host API）**。接口定义在 `pigeons/box_api.dart` 的 `BoxHostApi`，生成 `lib/core/box_service/pigeon/box_api.g.dart`、`android/.../pigeon/BoxApi.g.kt`、`ios/Runner/Pigeon/BoxApi.g.swift` 三端代码；改完接口跑 `bin/regen-pigeon.sh`。连接生命周期（`getSnapshot` / `request` / `acknowledgeReplay`，以及带 `expectedAttempt` 的 `selectOutbound`）、内核配置与工具（`setup` / `validateConfig` / `changeConfigOptions` / `urlTest` / `generateFullConfig` / `clearLogs` / `resetTunnel`；`start` / `stop` / `restart` 是 iOS `BoxService` 的路径，Android 原生侧只把它们留作翻译成协调器请求的兼容入口，Dart 不再调用）、已安装应用列表与图标（`getInstalledApps` / `getAppIconBase64`，分应用代理页用）、iOS App Group 工作目录（`getAppGroupWorkingDirectory`）都走这里。channel 名由 Pigeon 生成，形如 `dev.flutter.pigeon.clashmiao.BoxHostApi.<method>`。

**2. EventChannel（原生 → Flutter 的推送流）**，统一前缀 `com.clashmiao.app`：

| Channel | 内容 |
|---------|------|
| `/kernel.snapshot` | 权威内核快照（JSON map，订阅时先推当前值；仅 Android），格式见「连接生命周期」 |
| `/service.status` | 内核状态（`Started` / `Starting` / `Stopping` / `Stopped`）；Android 上只是从快照派生的兼容流，供统计 / 分组订阅门控 |
| `/service.alerts` | 只剩**与连接生命周期无关**的提示（如通知权限被拒）。启动失败、授权被拒、超时等一律在快照的 `lastFailure` 里 |
| `/stats` | 上下行速率、累计流量与连接数 |
| `/groups` | 代理组列表（JSON 字符串） |
| `/service.logs` | 核心日志 |
| `/network` | 默认网络切换事件（仅 Android 原生侧有实现） |

原生侧推送的状态名是 PascalCase（`Started`），`_parseStatus` 做 `toLowerCase()` 后再匹配。`watchStatus`（共享的 `ValueStream`）、`watchAlerts`、`watchStats`、`watchGroups`、`watchNetworkChanged` 在 Dart 侧各缓存一份流、不重复 `receiveBroadcastStream()`：同一时刻 EventChannel 只服务一个活跃的平台订阅，重复新建会把先前的订阅静默顶掉。**`watchLogs()` 例外**：它每次调用都新建一个 `receiveBroadcastStream()`，没有缓存，所以同时存在多个日志订阅者时，后订阅的会把先前的顶掉；目前只有日志页一处订阅（`boxLogStreamProvider`）。

**3. 裸 MethodChannel（少数没走 Pigeon 的原生能力）**：

| Channel | 用途 |
|---------|------|
| `com.clashmiao.app/method` | Dart 当前只用它调 `generate_warp_config`（WARP 账号注册）；Android 原生侧同样只保留这一个方法，iOS 原生侧（`ChannelMethodHandler.swift`）仍注册着 setup / start / stop 等旧方法，Dart 不再调用 |
| `com.clashmiao.app/platform` | 电池优化豁免查询与申请（仅 Android，`BatteryOptimizationService`） |
| `com.clashmiao/auto_start` | macOS 开机启动（`auto_start_notifier.dart`） |

### Android 原生侧（`android/app/src/main/kotlin/com/clashmiao/clashmiao/`）

**进程模型：所有组件同进程。** `AndroidManifest.xml` 里没有任何 `android:process` 属性，`TunnelService`（VpnService）、`PlainService`、`QuickSettingsTileService` 与 `MainActivity` 都跑在主 App 进程里。状态由进程级 `KernelCoordinator` 直接提供：Activity、磁贴、快捷方式、开机广播都只向它提交请求或读快照，不绑定 Service、没有 AIDL；Service 只作为 started service 存在。

```
clashmiao/
├── Application.kt             — Seq.setContext()，全局 Application
├── MainActivity.kt            — FlutterFragmentActivity：注册三个桥；通知权限；作为 ActivityHost 弹 VPN 授权
├── ShortcutActivity.kt        — 桌面快捷方式入口（经协调器提交外部请求）
├── core/
│   ├── Constants.kt           — wire-format 常量（KernelStatus / AlertCode / EngineMode / AppFilterMode / PrefsKey）
│   ├── LibboxAdapters.kt      — libbox 类型 → Kotlin 适配辅助
│   └── Prefs.kt               — SharedPreferences 分组与 StringList 解码
├── bridge/
│   ├── MethodBridge.kt        — 两条 MethodChannel：`/method`（仅 generate_warp_config）与 `/platform`
│   ├── StreamBridge.kt        — EventChannel：kernel.snapshot / status / alerts / stats / groups / active-groups / logs / network
│   └── PigeonBridge.kt        — Pigeon BoxHostApi 的实现（生命周期调用转给协调器）
├── engine/
│   ├── KernelCoordinator.kt   — 进程级协调器的命令层外壳：主线程上把核心的动作落成副作用
│   ├── CoordinatorCore.kt     — 命令层纯状态机（事件 → 动作 + 快照），JVM 单测的主体
│   ├── KernelModel.kt         — 快照 / LaunchSpec / Service 形态等模型与显式键名的线上编码
│   ├── KernelStore.kt         — 持久化最近被受理的 LaunchSpec 与 desired（外部入口冷启动用）
│   ├── KernelExecutor.kt      — 执行层：唯一后台线程，串行执行阻塞的 libbox 调用
│   ├── KernelRuntime.kt / KernelStartSequence.kt / LibboxKernelRuntime.kt — 启动链与回收（可注入、可测）
│   ├── AndroidCoordinatorPlatform.kt — 定时器、VPN 授权、拉起 Service 的 Android 实现
│   ├── VpnConsentBroker.kt    — 每个授权对话框一个唯一 requestCode，结果只归弹出它的请求
│   ├── KernelHost.kt          — Service 实例与协调器之间的薄适配层（生命周期上报、按实例 stopSelfResult）
│   ├── TunnelService.kt       — VPN 模式前台 Service（VpnService 子类，建 TUN）
│   ├── PlainService.kt        — 纯代理模式前台 Service，不申请 VPN 权限
│   ├── LibboxHost.kt          — libbox PlatformInterface 的抽象基类
│   ├── LibboxCommandStream.kt — libbox CommandClient 流式推送的连接管理
│   ├── ForegroundNotice.kt / NoticeUpdates.kt — 前台通知与动态通知的代际归属
│   ├── NetworkWatcher.kt      — 默认网络监听
│   ├── SystemDnsBridge.kt     — 系统 DNS 透传
│   ├── LogBuffer.kt           — 线程安全的定长日志缓冲
│   ├── PermissionGate.kt      — 通知权限申请（VPN 授权不经这里）
│   ├── OutboundSnapshot.kt    — 出站组只读快照（显式键名编码给 Dart）
│   ├── BootReceiver.kt        — 开机 / 升级后按持久化的 desired 与 spec 提交外部请求
│   └── QuickSettingsTileService.kt — 快捷设置磁贴
└── pigeon/BoxApi.g.kt         — Pigeon 生成代码
```

native 层依赖 `android/app/libs/libcore.aar`（gomobile 生成的 libbox 包）。aar **不在 git tracking**，CI / fresh clone 用 `bin/fetch-libcore.sh android` 从 GitHub Release 拉取（见下文「内核版本」）。

### 内核版本

当前打包的内核是 **sing-box v1.8.9**，由 Go 1.22 系列编译。读法：解压 `android/app/libs/libcore.aar`，对 `jni/arm64-v8a/libbox.so` 执行 `go version -m`，依赖列表里 `sing-box` 的版本为 `v1.8.9`，Go 版本为 `go1.22.0`；macOS 的 `libcore/bin/libcore.dylib` 用同样方法读到同样的 sing-box 版本（Go 为 `go1.22.3`）。

`bin/fetch-libcore.sh` 与 CI 里默认拉取的 Release tag 叫 `libcore-v1.11.0`（可用环境变量 `LIBCORE_TAG` 覆盖）。**这只是打包用的 tag 名，不是 sing-box 的版本号。** `core/build.sh` 里的 `SINGBOX_VERSION="1.11.0"` 同理不代表实际内核：该脚本克隆上游 sing-box 源码，而它构建移动端用的 `./mobile` 包在那份源码里并不存在，所以当前发布的 libcore 并不是它产出的。

### 桌面侧（FFI）

`FFIBoxService` 直接 `DynamicLibrary.open` `libcore.dylib`（macOS）/ `libcore.so`（Linux）/ `libcore.dll`（Windows），用 `lookupFunction` 绑定 13 个 Go 导出符号：`setupOnce` / `setup` / `start` / `stop` / `restart` / `parse` / `generateConfig` / `generateWarpConfig` / `selectOutbound` / `urlTest` / `startCommandClient` / `stopCommandClient` / `changeConfigOptions`。状态通过 `ReceivePort` 由 Go 侧推回；配置文件结构跟 Android 端一致。

**桌面端默认不走 TUN**（需 admin 权限）：`NetworkSettings` 的默认值是 `setSystemProxy = true`、`enableTun = false`，sing-box 在默认端口 `127.0.0.1:2080`（`mixedPort`）起 mixed inbound，系统代理指向这里。设置页的服务模式只提供「仅线路 / 系统线路」两档，不主动提供 TUN；但已持久化的 `enableTun = true`（旧版本、备份恢复、导入配置选项）不会被改写，照旧进启动配置（以足够权限运行时可用），界面把它显示为选中的 VPN 档并展示 TUN 相关设置，用户切到别的档后它就不再出现。

平台 lib 的落点：
- macOS：`libcore/bin/libcore.dylib` 由 Xcode 的 shell script build phase 拷到 `Runner.app/Contents/Frameworks/`
- Linux：`linux/libs/libcore.so` 由 CMake install 拷到 `bundle/lib/`（rpath `$ORIGIN/lib`）
- Windows：`windows/libs/libcore.dll` 由 CMake install 拷到与 `.exe` 同级的目录

### iOS 原生侧（`ios/Runner/` + `ios/SingBoxPacketTunnel/`）

iOS 没有 Android 那样的原生 VPN Service，走 **NetworkExtension PacketTunnelProvider**：内核跑在 Network Extension 进程里，主 App 通过 `NETunnelProviderManager` 控制隧道，两个进程通过 App Group 共享容器交换配置与运行时文件。

```
ios/
├── Runner/                    — 主 App
│   ├── AppDelegate.swift / SceneDelegate.swift
│   ├── Extensions/Bundle+Properties.swift — 从 Info.plist 读 SERVICE_IDENTIFIER（channel 前缀）
│   ├── VPN/
│   │   ├── TunnelManager.swift   — NETunnelProviderManager 生命周期与告警
│   │   └── TunnelProfile.swift   — 当前选中的隧道配置（UserDefaults 持久化）
│   ├── Handlers/                 — Flutter 侧桥接
│   │   ├── PigeonBridge.swift       — Pigeon BoxHostApi 的实现
│   │   ├── ChannelMethodHandler.swift — `/method` MethodChannel
│   │   └── TunnelStatusStream / BoxAlertsStream / TrafficStatsStream / ProxyGroupsStream / LogLinesStream
│   └── Pigeon/BoxApi.g.swift     — Pigeon 生成代码
├── SingBoxPacketTunnel/       — Network Extension（com.apple.product-type.app-extension）
│   ├── ClashMiaoTunnelProvider.swift  — NEPacketTunnelProvider 入口（继承 KernelProviderProxy）
│   ├── TrafficStats / TunnelLogger
│   └── Kernel/
│       ├── KernelProviderProxy.swift  — 持有内核生命周期（LibboxBoxService / CommandServer）
│       ├── KernelEngine.swift         — 配置串校验
│       ├── KernelPlatformBridge.swift — 实现 libcore 的平台回调（TUN 配置、日志、DNS 等）
│       └── BlockingRunner.swift       — 把 async Swift 桥成 libcore 要求的同步回调
└── Shared/                    — Runner 和 Extension 都用
    ├── KernelBridge.swift / KernelCommandClient.swift
    └── ProfilePathResolver.swift — App Group 容器内的路径约定
```

`ios/Frameworks/Libcore.xcframework/` 同 Android：不在 git tracking，`bin/fetch-libcore.sh ios` 拉 zip 解压并整理成 iOS 能用的 shallow framework。

签名与 Xcode 工程配置（NetworkExtension capability、App Group `group.com.clashmiao.shared`、扩展 target）见 `ios/SCAFFOLDING.md`。

### Flutter 端关键 provider

- `connectionControllerProvider`（`lib/domain/connection/application/connection_controller.dart`）— 连接的**唯一真值**（`ConnectionSnapshot`：phase、failure、startedAt……）：连接 / 断开 / 切换 / `applyConfig`，网络设置与激活订阅变化后防抖重新应用；`isConnectedProvider` 等只读 provider 都从它派生
- `boxStatusProvider`（`lib/core/box_service/box_providers.dart`）— 只给统计 / 分组订阅做门控；架构测试禁止 `features` / `app` / `main.dart` 引用它
- `boxAlertsProvider` — 非生命周期提示流（如通知权限），`ShellPage` 弹 toast；连接失败的提示改由控制器快照的 `failure` 驱动
- `boxStatsProvider`、`outboundGroupsProvider` — 只在已连接时才订阅，避免无谓 IPC
- `proxyModeProvider` — 智能 / 全局模式持久化（`lib/domain/routing/application/proxy_mode_notifier.dart`，默认 1 = 智能）
- `profileListProvider` / `activeProfileProvider` — 订阅列表与当前激活订阅（`lib/domain/profile/application/profile_providers.dart`）
- `networkSettingsProvider` — 端口、TUN、系统代理、DNS 等设置（`lib/domain/config/application/network_settings.dart`）
- `optimisticProxySelectionsProvider` — 乐观切换代理节点（`lib/features/proxy/application/`）

### 默认 sing-box 配置（`lib/domain/config/data/default_config_options.dart`）

`getDefaultConfigOptions` 把用户设置与当前模式拼成推给内核的 `configOptions`。按平台分流的两项：

- `enable-tun` 取自 `service_mode.dart` 的 `kernelEnableTun`：Android 由服务模式决定（VPN → true，「仅线路」→ false，原生协调器据此选 `TunnelService` / `PlainService`，形态进 revision）；iOS 恒为 true（Packet Tunnel 只能以 TUN 运行）；桌面尊重显式设置 `enableTun`（界面不主动提供，但不替用户改写）。订阅配置里自带的 tun inbound 由 `runtimeKeepsTunInbound` 决定去留：桌面一律剥掉（桌面的 TUN 只经 `enable-tun` 由内核创建），Android「仅线路」剥掉，其余保留。
- `set-system-proxy`：移动端恒为 false（改系统代理需要 root）；桌面按用户开关（CI smoke 强制 false）。

服务模式的可选档位同样只列能生效的：Android「仅线路 / VPN」，iOS 只有 VPN（界面说明「iOS 仅支持 VPN 模式」，不给选择器），桌面「仅线路 / 系统线路」（已持久化 `enableTun = true` 时额外显示选中的 VPN 档，可切走）；界面能力与启动参数分开算：界面只藏不能生效的档位，不改写持久化的显式设置。只对 TUN 起作用的设置（严格路由、TUN 实现）在内核不以 TUN 运行时不展示。

智能模式（`isSmart`，即模式索引不为 0）下，中国大陆 IP 段与域名（`cn_direct_rules.dart`，由 `assets/rule-sets/` 里的 `.srs` 反编译生成）作为 `rules` 字段注入、走 `bypass` 直连；全局模式不注入。原因是当前打包的内核在 `region: "other"` 下不支持任何 rule-set，分流数据只能以明文列表经 `rules` 注入——详见 `default_config_options.dart` 与 `cn_direct_rules.dart` 文件头的注释。

## 连接生命周期

设计要点：**期望状态归原生协调器所有**。Dart 不推断原生在做什么，只提交「我想要 on / off」，然后读权威快照；失败一律由内核侧写进快照，Dart 从不合成终态。

### `KernelPort` 契约（`lib/core/box_service/kernel_port.dart`）

| 方法 | 语义 |
|------|------|
| `current()` | 权威快照，2 s 内返回或抛 `KernelPortException`；带查询 token，过期结果丢弃 |
| `watch()` / `watchLink()` | 快照流（订阅先推当前值，只推通过版本过滤的）；通道健康度 `connected` / `lost` |
| `request(DesiredRequest)` | 只表示「已入队 / 被拒绝」，2 s 内返回；完成与否看快照 |
| `acknowledgeReplay(attempt)` | 确认该 attempt 的手选重放已完成（幂等） |
| `selectOutbound(..., expectedAttempt)` | attempt 不符时不写入，返回 `SelectStale` |

实现：Android 为 `PlatformKernelPort`（Pigeon + `/kernel.snapshot`，流断开后 0.5 / 1 / 2 / 4 s 退避重订阅并重同步）；其它平台为 `EmulatedKernelPort`。接线在 `kernel_port_provider.dart`。

**请求序号**：`DesiredRequest{epoch, seq, desired, reason, launch}`。seq 在「启动产物准备完成、即将发送」时才分配（准备期间被新意图取代的不占号），基线是首个快照的 `appliedSeq + 1`，每次纪元变化重设。协调器按 seq 顺序处理、后到覆盖先到；`seq ≤ appliedSeq` 回 `stale`，纪元不符回 `wrongEpoch`，两者都不改变状态。

**快照字段**（`KernelSnapshot`）：

| 字段 | 含义 |
|------|------|
| `epoch` / `version` | 进程纪元（随机 id，变化 = 原生重启，Dart 重置全部基线）；纪元内单调的版本号，用来丢弃乱序快照 |
| `status` / `desired` / `source` | 内核状态；协调器追求的目标；谁设定的（app / tile / shortcut / boot / notification / system） |
| `attempt` | 纪元内每次真正开始一次启动或重载 +1；副作用按 `(epoch, attempt)` 去重 |
| `appliedSeq` | 已处理到的最后一个 Dart 请求序号 |
| `activeConfigRevision` | 运行实例所用 `LaunchSpec.configRevision`；与请求不同即重载 |
| `lastFailure` | `{code, message, attempt, seq?}`，协调器把 desired 置 off 时附带 |
| `selectionsReplayNeeded` | 当前 attempt 是新实例、手选尚未重放确认（确认后才探测出口 IP） |
| `retainedConfigPaths` | 内核之后可能还会读取的运行时配置文件（持久化 spec、当前意图、运行中、在途启动）；`null` = 未知 |

**请求的四种结局**（`RequestOutcome`，`connect()` / `disconnect()` / `applyConfig()` 的 Future）：`succeeded`（connected / stopped 达成）、`failed(ConnectionFailure)`（准备失败、RPC 失败、反复被拒、失联、或 `lastFailure` 属于该 seq）、`superseded`（更新的请求已被受理，或发送前就被新意图取代）、`interrupted`（纪元变化）。每个请求恰好得到一个。

**时间预算**（`ConnectionTiming`）：未确认请求 5 s 后重同步、再 3 s 宽限仍追不上判 `nativeUnresponsive`；失联超过 10 s 判 `nativeUnresponsive`；wrongEpoch 之后单次等待重同步不超过 10 s，同一意图最多重发 3 次。「约 40 s」（`retryPhaseBudget` = 4 × 2 s + 3 × 10 s = 38 s）**只约束重试阶段**；最后一次请求被受理后，终结由协调器给出：启动 / 重载 30 s 启动超时，停止时单个阻塞调用超过 20 s 报 `kernelUnresponsive`。

### Android 原生协调器

`KernelCoordinator`（进程级单例）分两层：**命令层**在主线程，核心是纯 Kotlin 状态机 `CoordinatorCore`（事件 → 动作 + 新快照，从不阻塞）；**执行层** `KernelExecutor` 是唯一后台线程，串行执行 bootstrap、command server、建配置、`newService`、`start`、`close` 等阻塞调用。启动中收到 off 立即发布 stopping，当前阻塞调用返回后不再继续，转为完整回收。每次执行带不可变的归属：只有仍属于当前请求的执行才能把 desired 置 off、写 `lastFailure`。Service 形态（VPN / 纯代理）随请求的 `enable-tun` 走：换形态时先退休旧实例（等它真实的 `onDestroy`），再起新的。VPN 授权每个对话框一个唯一 requestCode（`VpnConsentBroker`）。最近被受理的 spec 与 desired 由 `KernelStore` 持久化，磁贴、快捷方式、开机在没有 Dart 的冷进程里据此启动。

### Dart 侧

- `ConnectionMachine`（纯函数，不读时钟）：输入快照、链路、用户意图、准备 / 发送结果与 Tick，输出界面快照（phase：resolving / connecting / connected / reconnecting / disconnecting / disconnected）、动作（准备、发送、重同步、副作用、终结请求）与下次唤醒时间。
- `ConnectionController`：执行这些动作、按 `nextWake` 安排 Tick；副作用（触觉、评分、手选重放、系统代理脏标记、上报）按 `(epoch, attempt)` 至多一次。冷启动挂上运行中的隧道（首个快照即 started）不触觉、不评分、时长未知。
- `ConnectionLauncher`：生成内联 options 与运行时配置文件。**命名**：`runtime-<revision>.json`，`configRevision` 是（options JSON + 运行时配置内容）的稳定哈希；先写 `runtime-prep-<token>.json`，目标不存在或内容不同时才原子改名覆盖。**清理**：只有同时满足以下条件的文件才删（含旧版 `runtime-config-<seq>.json` 与临时文件）——已收到首个权威快照；不在最新快照的 `retainedConfigPaths` 里（快照报未知则一个都不删）；不被未终结请求引用；不是本进程最近准备的 3 个 revision 之一。从不按修改时间或文件年龄删。

### iOS / 桌面：降级契约

`EmulatedKernelPort` 包装 `BoxService`，在 Dart 里实现同样的接口与语义（串行受理、stale / wrongEpoch、30 s 启动超时、20 s 停止无响应、失败归属当前请求），但承诺降低：epoch / attempt 是 Dart 本地值；来自平台自身的变化（iOS 系统设置、意外退出）一律记 `source=system`；iOS 的初始状态读取与连接中断开、桌面 FFI 调用阻塞 UI isolate 维持现状。核心库不可用（桩实现）时 on 请求立即以 `coreUnavailable` 失败。iOS 平台会持久化最近一次启动的配置路径，第一次调用确认之前 `retainedConfigPaths` 报未知。

### 原生 → Dart 的 JSON 模型：键名必须显式写出

release 包经 R8 混淆：字段被改名，Gson 不带 keep 规则，`@SerializedName` 注解随字段一起被剥掉，反射编码会输出 `{"a":...,"b":...}`，Dart 读到的全是空值。所以原生推给 Dart（或持久化）的 JSON 一律**先转成键名显式写出的 Map 再编码**（`OutboundSnapshot.toWire`、`AppRow.toWire`、`KernelSnapshot.toWireMap`、`KernelStore.encode`），不靠反射。JVM 守卫测试禁止 main 源码再用 `@SerializedName` 决定载荷键名。

## 持久化

### 订阅存储 `ProfileStore`（`lib/domain/profile/data/profile_store.dart`）

进程级单例，所有读改写走同一把锁且基于锁内最新数据。写入一律 `commit(plan)`：`plan` 是**同步**函数，拿锁内视图算出 `Plan`（列表、激活 id、待装 / 待删配置文件、待删附属键），Store 自己在锁内落盘：暂存文件改名为正式文件（被替换的旧文件先改名 `.undo`）→ 写列表键与激活键并检查返回值 → 成功清理 `.undo` 与附属键并广播 `changes`；任一步失败还原。网络等慢操作在锁外，落地前用 `(id, inc, rev, url, ua)` 校验输入仍成立，否则丢弃为 stale。启动时清理残留（`.staging` 删除、正式文件缺失时还原 `.undo`）。

- 每条订阅有 `rev`（每次修改 +1）与本机代际 `inc`（创建 / 导入时随机生成，不进备份）；附属数据（手选、延迟缓存）经 `writeAux(id, inc, …)` 在锁内校验后写入，旧写入者不能复活已删订阅的键。
- 激活订阅只存 `clashmiao_active_profile` 一个真源。
- 读取永不抛出：外层 JSON 坏了原文存到 `clashmiao_profiles_corrupt` 后按空列表处理；单条坏数据（解析失败、id 不合法、重复 id）原样移到 `clashmiao_profiles_quarantine`（最多 50 条），不拖垮整张列表。
- 存储版本高于本应用时进入只读模式：`commit` 抛 `StoreReadOnlyException`，界面提示升级 App。

### 版本与迁移

`clashmiao_storage_schema`（缺失 = 0，当前为 1）。启动屏障（`app/bootstrap/storage_bootstrap.dart` 的 `prepareStorage`）在任何业务 provider 之前依次：检查恢复标记 → `StorageMigrator.run`。迁移步骤必须幂等、每个写入检查返回值、只用原始偏好；失败即停、不推进 schema，读取代码同时兼容新旧格式，所以迁移失败不影响使用，下次启动重跑。v0 → v1（`migrations/v1_profiles.dart`）：先把原值备份到 `clashmiao_migration_backup_v0`，再先写激活键、去掉订阅 JSON 的 `active` 并补 `rev` / `inc`、删除孤儿附属键。降级（schema 更高）不迁移。

偏好注册表 `core/storage/pref_registry.dart` 登记参与备份或与原生共享的键：类型、备份策略（`include` / `exclude` / `secret`）与校验函数；原生共享键由契约测试与 Kotlin 侧定义对齐。

### 备份 v2

导出 `{version: 2, schema, createdAt, profiles, activeProfileId, profileConfigs, preferences}`：在 Store 锁内取一致快照；偏好只含注册表 `include` 的键，机密（WARP 凭证）与运行时键一律不导出，`inc` 不导出。导入接受 `1.0` 与 `2`：先完整校验、不写任何东西（id 合法且不重复、配置是含 `outbounds` 的 JSON 对象、偏好类型与值域、`enableWarp` 导入为 false 并提示），语义是**整表替换**（导入前确认会移除的本机订阅），远程订阅缺配置的导入后后台补拉。

### 恢复：快照与标记

`BackupEngine.restore`：①把**当前**状态用导出函数写到 `<应用文档目录>/backups/pre-restore-<时间戳>.json`，并写标记键 `clashmiao_restore_in_progress=<该路径>`；②应用（整表替换订阅与激活、配置文件、删除不在备份中的订阅及其附属键、写偏好）；③成功删除标记，快照保留最近 3 份；失败用同一快照、同一应用流程回滚，回滚也失败则保留标记。恢复互斥，不排队。进程中途被杀：下次启动屏障发现标记，先用快照回滚再继续启动；快照丢失 / 损坏则清标记并提示无法撤销，回滚失败则保留标记并提供重试。

恢复期间 `RestoreRefresher` 暂停订阅定时刷新与连接控制器的「配置变更 → 重新应用」（已排队的防抖取消、期间的变化只记下），失效并重读各 provider 后按最终状态至多处理一次：激活订阅没了 → 断开，否则重新应用一次。

## 测试

`test/` 与 `lib/` 的新路径一一对应（`test/core`、`test/domain`、`test/features`、`test/shared`、`test/app`），另有：

- `test/architecture/` — 架构测试，见「分层」一节；另有用户可见文案守卫（`user_visible_strings_test.dart`）：异常原文插值进文案、或出现未登记的写死中文即失败；
- `test/support/` — 共享的测试替身（`fake_box_service.dart`、`counting_box_service.dart`、`temp_dirs.dart`）；
- `test/main_test.dart`、`test/branding/` — 入口与品牌资源回归；
- `integration_test/` — 真机 / 模拟器上的集成测试（Android 智能模式、iOS 首页连接信息与快捷设置）；
- `android/app/src/test/` — Android 原生层的 JVM 单测（`cd android && ./gradlew :app:testDebugUnitTest`，CI 里是 `test-android-unit`）。

跑法：`flutter test`（全量）；提交前还要过 `flutter analyze --fatal-warnings` 和 `dart format --set-exit-if-changed lib test integration_test`（格式化器版本与 CI 的 Flutter 3.47.7 保持一致，版本不同会改动无关行）。

写测试的两个惯例：

- 需要 `sharedPreferencesProvider` 的组件测试，用 `UncontrolledProviderScope` 预先读好它，避开 FutureProvider 第一帧的 `AsyncLoading`（见 `test/features/home/presentation/connection_button_test.dart`）。
- 带 flutter_animate 的组件要用 `runAsync` 让它的 timer 真实触发。

## 已知技术债

- 生成物（slang 的 `lib/core/localization/gen/`、Pigeon 的三端 `*.g.*`）提交进了 git，fresh clone 不用先跑生成器（本仓库不用 build_runner，见 `bin/regen-i18n.sh`、`bin/regen-pigeon.sh`）。CI 目前不校验生成物与源文件是否一致，后续可加一步「重新生成后 diff 为空」。
- `core/build.sh` 不是发布用 libcore 的来源（见「内核版本」）。libcore 二进制目前由外部构建后挂到 GitHub Release tag，CI / release flow 已通过 `bin/fetch-libcore.sh` 解耦。后续可考虑加一个 release workflow 自动重建 libcore tag，并让 tag 名反映真实内核版本。
- 桌面内核加载失败目前只记日志，`coreLoadFailed` 告警路径未接通（见「`BoxService` 抽象」一节：失败发生在 `init()`，不在工厂构造里）。
- Windows / Linux 缺真机 connection smoke：CI 默认只 gate 编译 + libcore 打包 + 符号检查，真流量 smoke job 需要 `ENABLE_SMOKE` 开关和测试订阅 secret 才会跑。
- iOS 原生侧没有实现 `/network` EventChannel（`ios/Runner/Handlers/` 里只有 status / alerts / stats / groups / logs 五条），Dart 侧 `watchNetworkChanged` 在 iOS 上收不到事件。
- iOS 原生侧只有 Xcode 模板自带的占位测试；Android 的协调器、执行层、持久化与线上编码有约 190 个 JVM 单测（`android/app/src/test/`，CI 的 `test-android-unit`），但 libbox 真实调用与各条 EventChannel 的推送仍主要靠真机验证。
- iOS / 桌面的连接生命周期是降级契约（见「连接生命周期」）：iOS 初始状态读取与连接中断开、桌面 FFI 移出 UI isolate 尚未完成。
- 功能之间还有 5 条页面跳转依赖留在架构测试白名单里，等路由统一后清零（见「白名单：只减不增」）。
