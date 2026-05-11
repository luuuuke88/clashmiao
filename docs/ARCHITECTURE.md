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

基于 sing-box 的 Android 接入实现：

```
clashmiao/
├── Application.kt             — Seq.setContext()，全局 Application
├── MainActivity.kt            — FlutterFragmentActivity，注册 7 个 Plugin
├── MethodHandler.kt           — 处理 start/stop/parse_config 等
├── EventHandler.kt            — status + alerts 双 EventChannel
├── StatsChannel.kt / GroupsChannel.kt / ActiveGroupsChannel.kt
├── LogHandler.kt              — 日志流
├── Settings.kt                — SharedPreferences 持久化
├── PlatformSettingsHandler.kt — Flutter 设置同步到原生
├── bg/
│   ├── BoxService.kt          — 核心 Service，管理 libbox 生命周期
│   ├── VPNService.kt          — VpnService 子类，建 TUN
│   ├── ProxyService.kt        — 非 VPN 模式 Service
│   ├── ServiceBinder.kt       — AIDL 服务端（IService.Stub）
│   ├── ServiceConnection.kt   — AIDL 客户端代理
│   ├── PlatformInterfaceWrapper.kt — libbox.PlatformInterface 实现
│   ├── ServiceNotification.kt — 前台通知 + startForeground
│   ├── DefaultNetworkMonitor.kt / DefaultNetworkListener.kt
│   ├── LocalResolver.kt
│   ├── AppChangeReceiver.kt / BootReceiver.kt
├── aidl/
│   ├── IService.aidl / IServiceCallback.aidl
└── constant/ / ktx/ / utils/
```

native 层依赖 `android/app/libs/libcore.aar`（gomobile bind 产物，包 `io.nekohasekai.libbox` + `io.nekohasekai.mobile`）。

### 桌面侧（FFI）

`FFIBoxService` 直接 dlopen `libcore.dylib`（macOS）/ `libcore.so`（Linux）/ `libcore.dll`（Windows），dart:ffi 调 Go 导出函数。配置文件结构跟 Android 端一致。

**桌面端不走 TUN**（需 admin 权限），默认 `set-system-proxy=true` + `enable-tun=false`：sing-box 在 `127.0.0.1:2080` 起 mixed inbound，macOS 把系统代理设到这里。

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
- `core/sing-box/` 目录在 `core/build.sh` 远程 clone，没纳入版本控制。重建 native 库前要手动跑一次 build.sh。
- 桌面 dylib 还没自动构建脚本（`core/build.sh macos` 输出在 `libcore/bin/`），CI 接入时要补。
- 没有 unit test 覆盖 box_service 适配层；EventChannel 解析逻辑全靠手动模拟器跑通。
