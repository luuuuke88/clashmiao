# ClashMiao 架构

## 一句话总览

Flutter 写 UI 与业务，**抽象出 `BoxService` 接口**，每个平台用各自最稳的方式接 sing-box：移动端走原生桥（Pigeon + EventChannel，原生侧是 Android 的 VpnService / iOS 的 PacketTunnel 扩展），桌面端走 FFI 直接调动态库。

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

`*.g.dart`、`*.freezed.dart` 等生成文件跟随所在目录，算作那一层，不单独豁免。

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
| `connection` | 连接状态机（`ConnectionController`）、错误分类、健康探测、出口 IP |

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
| `layering_rules.dart` | 规则判定：层间依赖、domain 顺序（`kDomainOrder`）、模型纯净、非规范相对 URI（`checkLayering` / `checkModelPurity`），以及白名单的过期条目（`staleEntries`）与合法性、上限（`checkAllowlist`） |
| `import_scanner.dart` | 用官方 `analyzer` 解析器提取 `import` / `export` 指令的 URI（含条件导入的每个分支），不用正则；`part` / `part of` 不产生依赖边，不提取。`projectPath` 把 URI 还原成 `lib/` 内路径，`nonCanonicalRelativeUriReason` 判定相对 URI 是否规范 |
| `allowlist.dart` | 功能之间依赖的白名单与上限 |
| `*_test.dart`（扫描器、规则） | 检查器自测：用合成源码覆盖正反用例，保证检查器真的会报错，不是永远绿 |

跑法：`flutter test test/architecture/`（全量 `flutter test` 也会跑到）。失败时每条违规打印成「源文件 → 目标文件 · 违反的规则 · 修复建议」，一次列全。**报错时的处理顺序**：

1. **层间依赖违规**：改代码，不要去动测试。共享的状态 / 模型下沉到 `domain`，共享的 UI 下沉到 `shared`，与业务无关的基础能力下沉到 `core`。
2. **domain 顺序违规**：说明依赖方向反了。把被依赖的那部分挪到更低的概念里，或改由更高的概念来组装。
3. **模型纯净违规**：报错里带有最短的传递链，沿链找到把 Flutter / Riverpod / `dart:io` 带进模型的那个文件，把那部分挪出 `model/`。
4. **「白名单条目对应的依赖已经消除」**：依赖已经没了，把那几条从 `allowlist.dart` 删掉即可（见下面的棘轮）。
5. **提示不在任何一层里**：文件放错了位置，按下面「新文件归属」归位。
6. **「非规范相对 URI」**：`import` / `export`（含条件导入分支）里写了含反斜杠、百分号转义、空段或越出 `lib/` 的相对路径，检查器无法可靠还原依赖边，一律按违规处理（失败即关闭）。改成 `package:clashmiao/...` 导入。

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

### 移动端通信协议

`PlatformBoxService` 与原生层之间有三类通道：

**1. Pigeon（强类型 host API）**。接口定义在 `pigeons/box_api.dart` 的 `BoxHostApi`，生成 `lib/core/box_service/pigeon/box_api.g.dart`、`android/.../pigeon/BoxApi.g.kt`、`ios/Runner/Pigeon/BoxApi.g.swift` 三端代码；改完接口跑 `bin/regen-pigeon.sh`。内核生命周期与配置（`setup` / `validateConfig` / `changeConfigOptions` / `start` / `stop` / `restart` / `selectOutbound` / `urlTest` / `generateFullConfig` / `clearLogs` / `resetTunnel`）、已安装应用列表与图标（`getInstalledApps` / `getAppIconBase64`，分应用代理页用）、iOS App Group 工作目录（`getAppGroupWorkingDirectory`）都走这里。channel 名由 Pigeon 生成，形如 `dev.flutter.pigeon.clashmiao.BoxHostApi.<method>`。

**2. EventChannel（原生 → Flutter 的推送流）**，统一前缀 `com.clashmiao.app`：

| Channel | 内容 |
|---------|------|
| `/service.status` | 内核状态（`Started` / `Starting` / `Stopping` / `Stopped`） |
| `/service.alerts` | 内核 / VPN 层的告警（VPN 权限缺失、配置为空、启动失败等）。`isFatal` 的告警由 `ShellPage` 弹阻断式对话框，其余告警弹 toast |
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

**进程模型：所有组件同进程。** `AndroidManifest.xml` 里没有任何 `android:process` 属性，`TunnelService`（VpnService）、`PlainService`、`QuickSettingsTileService` 与 `MainActivity` 都跑在主 App 进程里。Activity 与 Service 之间仍然通过 `bindService` + AIDL（`IService`）交互，只是 binder 调用发生在进程内。

```
clashmiao/
├── Application.kt             — Seq.setContext()，全局 Application
├── MainActivity.kt            — FlutterFragmentActivity，注册 Method/Stream/Pigeon 三个桥
├── ShortcutActivity.kt        — 桌面快捷方式入口
├── core/
│   ├── Constants.kt           — wire-format 常量（BroadcastIntents / KernelStatus / AlertCode / EngineMode / AppFilterMode / PrefsKey）
│   ├── LibboxAdapters.kt      — libbox 类型 → Kotlin 适配辅助
│   └── Prefs.kt               — SharedPreferences 分组（Profile / Engine / Notice / AppFilter）
├── bridge/
│   ├── MethodBridge.kt        — 两条 MethodChannel：`/method`（仅 generate_warp_config）与 `/platform`
│   ├── StreamBridge.kt        — 7 条 EventChannel：status / alerts / stats / groups / active-groups / logs / network
│   └── PigeonBridge.kt        — Pigeon BoxHostApi 的实现（内核方法已全部迁到这里）
├── engine/
│   ├── KernelHost.kt          — 内核生命周期控制器，TunnelService / PlainService 都委托给它
│   ├── TunnelService.kt       — VPN 模式前台 Service（VpnService 子类，建 TUN）
│   ├── PlainService.kt        — 纯代理模式前台 Service，不申请 VPN 权限
│   ├── KernelBinder.kt        — AIDL 服务端（IService.Stub），状态 / 告警 / 日志向订阅者扇出
│   ├── KernelConnection.kt    — Activity / Tile 侧的 bind-service 代理
│   ├── LibboxHost.kt          — libbox PlatformInterface 的抽象基类
│   ├── LibboxCommandStream.kt — libbox CommandClient 流式推送的连接管理
│   ├── ForegroundNotice.kt    — 前台通知（specialUse 前台服务类型，manifest 已声明）
│   ├── NetworkWatcher.kt      — 默认网络监听
│   ├── SystemDnsBridge.kt     — 系统 DNS 透传
│   ├── LogBuffer.kt           — 线程安全的定长日志缓冲
│   ├── PermissionGate.kt      — VPN / 通知权限申请
│   ├── OutboundSnapshot.kt    — 出站组只读快照（序列化给 Dart）
│   ├── BootReceiver.kt        — 开机 / 升级后按用户上次的启动意图拉起内核
│   └── QuickSettingsTileService.kt — 快捷设置磁贴
├── pigeon/BoxApi.g.kt         — Pigeon 生成代码
└── (src/main/aidl) IService.aidl / IServiceCallback.aidl
```

native 层依赖 `android/app/libs/libcore.aar`（gomobile 生成的 libbox 包）。aar **不在 git tracking**，CI / fresh clone 用 `bin/fetch-libcore.sh android` 从 GitHub Release 拉取（见下文「内核版本」）。

### 内核版本

当前打包的内核是 **sing-box v1.8.9**，由 Go 1.22 系列编译。读法：解压 `android/app/libs/libcore.aar`，对 `jni/arm64-v8a/libbox.so` 执行 `go version -m`，依赖列表里 `sing-box` 的版本为 `v1.8.9`，Go 版本为 `go1.22.0`；macOS 的 `libcore/bin/libcore.dylib` 用同样方法读到同样的 sing-box 版本（Go 为 `go1.22.3`）。

`bin/fetch-libcore.sh` 与 CI 里默认拉取的 Release tag 叫 `libcore-v1.11.0`（可用环境变量 `LIBCORE_TAG` 覆盖）。**这只是打包用的 tag 名，不是 sing-box 的版本号。** `core/build.sh` 里的 `SINGBOX_VERSION="1.11.0"` 同理不代表实际内核：该脚本克隆上游 sing-box 源码，而它构建移动端用的 `./mobile` 包在那份源码里并不存在，所以当前发布的 libcore 并不是它产出的。

### 桌面侧（FFI）

`FFIBoxService` 直接 `DynamicLibrary.open` `libcore.dylib`（macOS）/ `libcore.so`（Linux）/ `libcore.dll`（Windows），用 `lookupFunction` 绑定 13 个 Go 导出符号：`setupOnce` / `setup` / `start` / `stop` / `restart` / `parse` / `generateConfig` / `generateWarpConfig` / `selectOutbound` / `urlTest` / `startCommandClient` / `stopCommandClient` / `changeConfigOptions`。状态通过 `ReceivePort` 由 Go 侧推回；配置文件结构跟 Android 端一致。

**桌面端默认不走 TUN**（需 admin 权限）：`NetworkSettings` 的默认值是 `setSystemProxy = true`、`enableTun = false`，sing-box 在默认端口 `127.0.0.1:2080`（`mixedPort`）起 mixed inbound，系统代理指向这里；两个开关用户都可以在设置页改。

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

- `boxStatusProvider`（StreamProvider<BoxStatus>）— 全局连接状态，UI 都 watch 它（`lib/core/box_service/box_providers.dart`）
- `boxAlertsProvider`（StreamProvider<BoxAlert>）— 告警流，`ShellPage` 用 `ref.listen`：fatal 告警弹阻断式对话框，其余告警弹 toast（`lib/app/shell_page.dart`）
- `boxStatsProvider`、`outboundGroupsProvider` — 只在已连接时才订阅，避免无谓 IPC
- `connectionControllerProvider`（`lib/domain/connection/application/connection_controller.dart`）— 连接状态机：连接 / 断开 / 重连，网络设置变更后防抖自动重连
- `proxyModeProvider` — 智能 / 全局模式持久化（`lib/domain/routing/application/proxy_mode_notifier.dart`，默认 1 = 智能）
- `profileListProvider` / `activeProfileProvider` — 订阅列表与当前激活订阅（`lib/domain/profile/application/profile_providers.dart`）
- `networkSettingsProvider` — 端口、TUN、系统代理、DNS 等设置（`lib/domain/config/application/network_settings.dart`）
- `optimisticProxySelectionsProvider` — 乐观切换代理节点（`lib/features/proxy/application/`）

### 默认 sing-box 配置（`lib/domain/config/data/default_config_options.dart`）

`getDefaultConfigOptions` 把用户设置与当前模式拼成推给内核的 `configOptions`。按平台分流的两项：

```dart
final isMobile = Platform.isAndroid || Platform.isIOS;
final enableTunFinal = isMobile ? true : s.enableTun;        // 移动端必须开 TUN 才能接管流量
final setSystemProxyFinal = (isMobile || isSmoke) ? false : s.setSystemProxy;  // 移动端系统代理不可用
```

智能模式（`isSmart`，即模式索引不为 0）下，中国大陆 IP 段与域名（`cn_direct_rules.dart`，由 `assets/rule-sets/` 里的 `.srs` 反编译生成）作为 `rules` 字段注入、走 `bypass` 直连；全局模式不注入。原因是当前打包的内核在 `region: "other"` 下不支持任何 rule-set，分流数据只能以明文列表经 `rules` 注入——详见 `default_config_options.dart` 与 `cn_direct_rules.dart` 文件头的注释。

## 测试

`test/` 与 `lib/` 的新路径一一对应（`test/core`、`test/domain`、`test/features`、`test/shared`、`test/app`），另有：

- `test/architecture/` — 架构测试，见「分层」一节；
- `test/support/` — 共享的测试替身（`fake_box_service.dart`、`counting_box_service.dart`、`temp_dirs.dart`）；
- `test/main_test.dart`、`test/branding/` — 入口与品牌资源回归；
- `integration_test/` — 真机 / 模拟器上的集成测试（Android 智能模式、iOS 首页连接信息与快捷设置）；
- `android/app/src/test/` — Android 原生层的 JVM 单测（`cd android && ./gradlew :app:testDebugUnitTest`，CI 里是 `test-android-unit`）。

跑法：`flutter test`（全量）；提交前还要过 `flutter analyze --fatal-warnings` 和 `dart format --set-exit-if-changed lib test integration_test`（格式化器版本与 CI 的 Flutter 3.44.2 保持一致，版本不同会改动无关行）。

写测试的两个惯例：

- 需要 `sharedPreferencesProvider` 的组件测试，用 `UncontrolledProviderScope` 预先读好它，避开 FutureProvider 第一帧的 `AsyncLoading`（见 `test/features/home/presentation/connection_button_test.dart`）。
- 带 flutter_animate 的组件要用 `runAsync` 让它的 timer 真实触发。

## 已知技术债

- `*.g.dart` / `*.freezed.dart` 提交进了 git（避免 fresh clone 跑 build_runner）。CI 接入后应该改回 ignore + CI 生成。
- `core/build.sh` 不是发布用 libcore 的来源（见「内核版本」）。libcore 二进制目前由外部构建后挂到 GitHub Release tag，CI / release flow 已通过 `bin/fetch-libcore.sh` 解耦。后续可考虑加一个 release workflow 自动重建 libcore tag，并让 tag 名反映真实内核版本。
- 桌面内核加载失败目前只记日志，`coreLoadFailed` 告警路径未接通（见「`BoxService` 抽象」一节：失败发生在 `init()`，不在工厂构造里）。
- Windows / Linux 缺真机 connection smoke：CI 默认只 gate 编译 + libcore 打包 + 符号检查，真流量 smoke job 需要 `ENABLE_SMOKE` 开关和测试订阅 secret 才会跑。
- iOS 原生侧没有实现 `/network` EventChannel（`ios/Runner/Handlers/` 里只有 status / alerts / stats / groups / logs 五条），Dart 侧 `watchNetworkChanged` 在 iOS 上收不到事件。
- 原生层测试很薄：Android 只有 5 个纯逻辑的 JVM 单测（`android/app/src/test/`，CI 的 `test-android-unit` 跑：常量、日志缓冲、权限 gate、AIDL 解码），iOS 只有 Xcode 模板自带的占位测试；各条 EventChannel 的推送与解析主要靠真机连接验证。
- 功能之间还有 5 条页面跳转依赖留在架构测试白名单里，等路由统一后清零（见「白名单：只减不增」）。
