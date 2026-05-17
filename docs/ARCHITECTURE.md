# ClashMiao 架构

## 一句话总览

Flutter 写 UI 与业务，**抽象出 `BoxService` 接口**，每个平台用各自最稳的方式接 sing-box：移动端走原生 IPC（VpnService / PacketTunnel），桌面端走 FFI 直接调 dylib。

## 分层

```
┌─────────────────────────────────────────────────────────────────┐
│ Flutter UI (lib/features/*)                                     │
│  home / proxies / profile / settings widget                     │
├─────────────────────────────────────────────────────────────────┤
│ State (lib/features/*/state) + Providers (lib/core/box_service) │
│  ProxyModeNotifier、boxStatusProvider、boxAlertsProvider …      │
├─────────────────────────────────────────────────────────────────┤
│ BoxService 抽象（lib/core/box_service/box_service.dart）         │
│  init / setup / start / stop / watchStatus / watchAlerts / …    │
├──────────────┬────────────────┬─────────────────────────────────┤
│ Android      │ macOS / Linux  │ iOS (TODO) / Windows (TODO)     │
│ Platform     │ / Windows       │                                 │
│ Channel      │                 │                                 │
│ Service      │ FFI 直调 dylib  │ NetworkExtension PacketTunnel    │
│              │                 │ Provider                        │
├──────────────┼────────────────┼─────────────────────────────────┤
│ VpnService   │ libcore.dylib   │ ExtensionPlatformInterface       │
│ (Kotlin)     │ + 系统代理      │ + NEPacketTunnelNetworkSettings │
│ libcore.aar  │                 │                                 │
└──────────────┴────────────────┴─────────────────────────────────┘
```

## 关键模块

### `BoxService` 抽象（`lib/core/box_service/box_service.dart`）

工厂方法按平台分发：

| 平台 | 实现 |
|------|------|
| Android / iOS | `PlatformBoxService` — 用 Flutter MethodChannel + EventChannel 跟原生通讯 |
| macOS / Linux / Windows | `FFIBoxService` — 直接 dlopen `libcore.dylib`，dart:ffi 调 Go 导出符号 |
| 加载失败 | `StubBoxService` — 占位实现，每个方法返回空数据，避免 UI 崩 |

接口包含 14 个方法：`init` / `setup` / `validateConfig` / `changeConfigOptions` / `start` / `stop` / `restart` / `selectOutbound` / `urlTest` / `watchStatus` / `watchAlerts` / `watchStats` / `watchGroups` / `watchLogs`。

### Channel 协议（移动端）

Flutter 端 (`platform_box_service.dart`) 与原生层共用以下 channel 名（统一前缀 `com.clashmiao.app`）：

| Channel | 类型 | 方向 |
|---------|------|------|
| `/method` | MethodChannel | Flutter → Native（start/stop/parse_config/…） |
| `/service.status` | EventChannel | Native → Flutter（"Stopped" / "Starting" / "Started"） |
| `/service.alerts` | EventChannel | Native → Flutter（VPN 权限错误等） |
| `/stats` | EventChannel | Native → Flutter（uplink/downlink/total） |
| `/groups` | EventChannel | Native → Flutter（代理组列表） |
| `/service.logs` | EventChannel | Native → Flutter（核心日志） |

**注意**：原生侧推送的 enum 名是 PascalCase（`Started`），Flutter 端 `_parseStatus` 做 `toLowerCase()` 后再 match，保证三端一致解析。

### Android 原生侧（`android/app/src/main/kotlin/com/clashmiao/clashmiao/`）

基于 sing-box 的 Android 接入实现，2026-05 完成 Kotlin clean-room 重写（见 CHANGELOG Phase 1-7）：

```
clashmiao/
├── Application.kt             — Seq.setContext()，全局 Application
├── MainActivity.kt            — FlutterFragmentActivity，注册 Method/Stream Bridge
├── core/
│   ├── Constants.kt           — 三类 wire-format 枚举（BroadcastIntents / KernelStatus / AlertCode / EngineMode / AppFilterMode）
│   ├── LibboxAdapters.kt      — libbox 类型 → Kotlin 适配辅助
│   └── Prefs.kt               — SharedPreferences 分组（Profile / Engine / Notice / AppFilter）
├── bridge/
│   ├── MethodBridge.kt        — Flutter → Native 方法分发（name→suspend handler map）
│   ├── StreamBridge.kt        — 5 个 EventChannel：status / alerts / stats / groups / logs
│   └── PigeonBridge.kt        — Pigeon 强类型路径（validateConfig 试水，其余 10 个 method stub）
├── engine/
│   ├── KernelHost.kt          — 核心 host，管理 libbox 生命周期
│   ├── TunnelService.kt       — VpnService 子类，建 TUN（AndroidManifest 已配 specialUse fgs）
│   ├── PlainService.kt        — 非 VPN 模式 Service
│   ├── KernelBinder.kt        — AIDL 服务端 (IService.Stub)
│   ├── KernelConnection.kt    — AIDL 客户端代理（Sink 接口替代 Callback）
│   ├── LibboxHost.kt          — libbox.PlatformInterface 抽象 host
│   ├── LibboxCommandStream.kt — libbox CommandClient 推送解码
│   ├── ForegroundNotice.kt    — 前台通知 + startForeground(specialUse)
│   ├── NetworkWatcher.kt      — 默认网络监听
│   ├── SystemDnsBridge.kt     — 系统 DNS 透传
│   ├── LogBuffer.kt           — thread-safe capacity bound 日志缓冲
│   ├── PermissionGate.kt      — VpnService.prepare 弹窗 gate
│   └── OutboundSnapshot.kt    — 出站组只读快照
├── pigeon/BoxApi.g.kt         — Pigeon 生成代码
└── aidl/
    ├── IService.aidl / IServiceCallback.aidl
```

native 层依赖 `android/app/libs/libcore.aar`（gomobile bind 产物，包 `io.nekohasekai.libbox` + `io.nekohasekai.mobile`）。aar **不在 git tracking**，CI / fresh clone 用 `bin/fetch-libcore.sh android` 从 GitHub Release `libcore-v1.11.0` tag 拉取。

### 桌面侧（FFI）

`FFIBoxService` 直接 `DynamicLibrary.open` `libcore.dylib`（macOS）/ `libcore.so`（Linux）/ `libcore.dll`（Windows），dart:ffi 调 Go 导出函数。dlopen + dlsym 验证 11 个 FFI 符号：`setup` / `setupOnce` / `start` / `stop` / `parse` / `generateConfig` / `selectOutbound` / `urlTest` / `changeConfigOptions` / `startCommandClient` / `stopCommandClient`。配置文件结构跟 Android 端一致。

**桌面端不走 TUN**（需 admin 权限），默认 `set-system-proxy=true` + `enable-tun=false`：sing-box 在 `127.0.0.1:2080` 起 mixed inbound，桌面系统代理设到这里。

平台 lib 由 CMake install 阶段拷到运行时目录：
- macOS：`Runner.app/Contents/Frameworks/libcore.dylib`（pbxproj shell script build phase）
- Linux：`bundle/lib/libcore.so`（rpath `$ORIGIN/lib`）
- Windows：`Release/libcore.dll`（与 `.exe` 同目录）

### iOS 原生侧（`ios/Runner/` + `ios/SingBoxPacketTunnel/`）

跟 Android 不一样：iOS 不支持原生 VPN service，走 **NetworkExtension PacketTunnelProvider**：

```
ios/
├── Runner/                    — 主 app
│   ├── AppDelegate.swift / SceneDelegate.swift
│   ├── VPN/
│   │   ├── TunnelManager.swift   — NEVPNManager / NETunnelProviderManager 生命周期
│   │   └── TunnelProfile.swift   — UserDefaults 持久化
│   └── Handlers/                 — Flutter MethodChannel / EventChannel
│       ├── ChannelMethodHandler.swift
│       ├── TunnelStatusStream / BoxAlertsStream / TrafficStatsStream
│       ├── ProxyGroupsStream / LogLinesStream
├── SingBoxPacketTunnel/       — Network Extension (com.apple.product-type.app-extension)
│   ├── ClashMiaoTunnelProvider.swift  — NEPacketTunnelProvider 入口
│   ├── TrafficStats / TunnelLogger
│   └── Kernel/
│       ├── KernelEngine.swift         — Libcore sing-box 生命周期
│       ├── KernelProviderProxy.swift  — Extension ↔ Runner 桥
│       ├── KernelPlatformBridge.swift — NEPacketTunnelNetworkSettings 配置
│       └── BlockingRunner.swift       — 阻塞主线程跑 Go runtime
└── Shared/                    — Runner 和 Extension 都用
    ├── KernelBridge.swift / KernelCommandClient.swift
    └── ProfilePathResolver.swift
```

`ios/Frameworks/Libcore.xcframework/` 同 Android：不在 git tracking，`bin/fetch-libcore.sh ios` 拉 zip 解压。

**真机部署阻塞**：Apple Developer 账号 + NetworkExtension capability + App Group `group.com.clashmiao.shared`。详见 `ios/SCAFFOLDING.md`。

### Flutter 端关键 provider

- `boxStatusProvider`（StreamProvider<BoxStatus>）— 全局连接状态，UI 都 watch 它
- `boxAlertsProvider`（StreamProvider<BoxAlert>）— 错误流，`ShellPage` 用 `ref.listen` 弹 toast
- `boxStatsProvider`、`outboundGroupsProvider` — 只在已连接时才订阅，避免无谓 IPC
- `proxyModeProvider` — 智能/全局模式持久化（feature/home/state/）
- `optimisticProxySelectionsProvider` — 乐观切换代理节点（feature/proxy/state/）

### 默认 sing-box 配置（`lib/core/config/default_config_options.dart`）

按平台分流：

```dart
final isMobile = Platform.isAndroid || Platform.isIOS;
// ...
'enable-tun': isMobile,         // 移动端必须开 TUN 才能接管流量
'set-system-proxy': !isMobile,  // 桌面端走系统代理（移动端 set-system-proxy 需 root）
```

中国分流规则 `geoip:cn + geosite:cn → bypass` 自动注入到智能模式（`executeConfigAsIs=false`）。

## 测试

`test/features/home/widget/connection_button_test.dart` — ConnectionButton 四态渲染回归。

测试用 `UncontrolledProviderScope` 预读 `sharedPreferencesProvider`，避开 FutureProvider 第一帧 AsyncLoading。Started 用 `runAsync` 让 flutter_animate 的 timer 真实 fire。

## 已知技术债

- `*.g.dart` / `*.freezed.dart` 提交进了 git（避免 fresh clone 跑 build_runner）。CI 接入后应该改回 ignore + CI 生成。
- `core/build.sh` 是空壳脚本（指向不存在 main 函数的 package），未实际工作。libcore 二进制目前由外部 build 后挂到 GitHub Release tag。CI / release flow 已通过 `bin/fetch-libcore.sh` 解耦。后续可考虑加一个 release workflow 自动 rebuild libcore tag。
- iOS 真机部署阻塞 Apple Developer 账号；Windows / Linux 缺真机 connection smoke（CI 只 gate 编译 + libcore bundle + 符号 dlsym，不点连接）。
- 没有 unit test 覆盖 box_service 适配层；EventChannel 解析逻辑全靠 e2e 真连接覆盖。
