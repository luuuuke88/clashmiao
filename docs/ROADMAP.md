# ClashMiao 路线图

按里程碑组织，每个里程碑给出**当前状态**、**剩下要做的事**、**前置条件**。

---

## 里程碑 1 — Android VPN ✅ 完成

**结果**：用户在模拟器上点连接 → 系统 VPN 权限弹窗 → tun0 接管全部 TCP/UDP → UI 显示「已连接」+ 节点延迟。

**关键决策点**（已写入 [docs/ARCHITECTURE.md](ARCHITECTURE.md)）：
- 进程模型：VpnService 跑独立进程，AIDL 跟主进程通讯
- `startForeground` 必须传 `FOREGROUND_SERVICE_TYPE_SPECIAL_USE`（Android 14+）
- onStartCommand 入口同步挂 placeholder 通知，避免 IO 线程启动 sing-box 超过 5s 超时被杀

---

## 里程碑 2 — macOS 系统代理 🟡 进行中

**当前状态**：
- ✅ `flutter build macos` 通过，`.app` 自动打包 `libcore.dylib` 到 `Contents/Frameworks/`
- ✅ entitlements 已配（sandbox 关、network client/server 开、JIT 允许）
- ✅ `FFIBoxService` 完整实现，`default_config_options.dart` 在 macOS 上默认 `set-system-proxy=true / enable-tun=false`
- 🟡 没有手动验证：sing-box 是否真在 127.0.0.1:2080 监听、macOS 系统代理是否真被切到这里

**剩下要做的事**：
1. **运行验证**
   ```bash
   flutter run -d macos
   # 添加订阅，点连接，观察:
   # 1. 终端日志：sing-box 是否启动成功（Status: Started）
   # 2. 系统设置 → 网络 → Wi-Fi → 详细信息 → 代理：是否被改为 127.0.0.1:2080
   # 3. lsof -nP -iTCP:2080 -sTCP:LISTEN：是否有 clashmiao 在监听
   # 4. 在浏览器访问 https://www.google.com 看是否能通
   ```

2. **可能的 bug**：
   - macOS dylib 加载路径：`FFIBoxService` 怎么找 `libcore.dylib`？看 `lib/core/box_service/ffi_box_service.dart` 的 `DynamicLibrary.open(...)` 调用，确认走的是 `@executable_path/../Frameworks/libcore.dylib`
   - macOS 14+ 设置系统代理可能需要管理员权限（输 admin 密码）
   - `tun-implementation: mixed` 在 macOS 用不上但 sing-box 应该忽略它

3. **未实现**：
   - macOS 退出时自动还原系统代理设置（避免离开 app 后所有流量都死）
   - macOS 菜单栏图标 + 快捷切换（tray_manager 已在依赖里）

---

## 里程碑 3 — iOS PacketTunnel ❌ 未开始

**前置条件**（必须先满足）：
1. 注册 Apple Developer 账号（$99/年），位置：<https://developer.apple.com/programs/enroll/>
2. 在 Developer 后台申请 **NetworkExtension Capability** entitlement（人工审批，1–2 个工作日）
3. 注册主 App ID `com.clashmiao.clashmiao` 和 Extension App ID `com.clashmiao.clashmiao.SingBoxPacketTunnel`
4. 注册 App Group `group.com.clashmiao.clashmiao`
5. 下载 Provisioning Profile 到本机 Xcode
6. iOS 真机一台（iOS Simulator **不能**跑 NetworkExtension）

**Port 计划**：

| 阶段 | 工作 | 工时 |
|------|------|------|
| 1 | 新建 `ios/SingBoxPacketTunnel/` Extension target 目录 + Swift 源文件 | 1–2 h |
| 2 | 新建 `ios/Runner/VPN/` + `ios/Runner/Handlers/` 主 app 侧代码 | 1 h |
| 3 | 在 Xcode 新建 SingBoxPacketTunnel target（Application Extension → Network Extension） | 30 min |
| 4 | 把 swift 源加进 target，链接 `Libbox.xcframework` | 30 min |
| 5 | entitlements 写 App Group + NetworkExtension capability；Info.plist 配 NSExtensionPrincipalClass | 30 min |
| 6 | Podfile 加 Extension target 段 | 15 min |
| 7 | 配 Signing & Capabilities（依赖前置条件 1–5 完成）| 30 min |
| 8 | 真机部署、调试 startTunnel/stopTunnel、修 routes/DNS 配置 bug | 4–8 h |

**实际工作量**：纯代码 ~3 h + Xcode 配置 ~1 h + 真机调试 ~ 半天。

**Extension 端关键 Swift 文件**（自己实现，参考 sing-box-for-ios 的 PacketTunnelProvider 模式）：

```
ios/SingBoxPacketTunnel/PacketTunnelProvider.swift  — Extension 入口，继承 NEPacketTunnelProvider
ios/SingBoxPacketTunnel/ExtensionProvider.swift     — sing-box 核心生命周期
ios/SingBoxPacketTunnel/PlatformInterface.swift     — NEPacketTunnelNetworkSettings 配置
ios/Runner/VPN/VPNManager.swift                     — NEVPNManager 生命周期
ios/Runner/VPN/VPNConfig.swift                      — UserDefaults 持久化
ios/Runner/Handlers/MethodHandler.swift             — Flutter MethodChannel 接入
ios/Runner/Handlers/AlertsEventHandler.swift        — alerts 流
ios/Runner/Handlers/GroupsEventHandler.swift / StatsEventHandler.swift
ios/Shared/FilePath.swift / CommandClient.swift     — 主 app 与 Extension 共享
```

---

## 里程碑 4 — Windows ❌ 未开始

**思路**：FFI 直接调 `libcore.dll`，桌面端走系统代理（与 macOS 同款思路）。

**前置**：
1. 用 `core/build.sh windows` 编译 Windows dll（脚本待扩展 `windows` target）
2. 在 Windows 机器或 Parallels VM 上跑 `flutter build windows`
3. `tray_manager` + `window_manager` 已在依赖里，可以做最小化到系统托盘

**未知数**：
- Windows 系统代理设置 API（应该 sing-box 内部已实现，看 `set-system-proxy` 在 Windows 上的行为）
- WinTun TUN 模式（如果以后要支持全局 TUN，需要 admin + 安装 WinTun 驱动）

---

## 里程碑 5 — Linux ❌ 未开始

类似 macOS：FFI + `libcore.so` + 系统代理（gnome / KDE 环境变量 `http_proxy` 或 `gsettings`）。

完整 TUN 模式需要 `CAP_NET_ADMIN`（pkexec / setcap），开发体验差，建议先只支持 mixed inbound + 用户手动设代理。

---

## 横向工作

### 测试覆盖

当前：只有 `ConnectionButton` 4 个 widget test。

下一步该补的：
- `BoxAlertType.parse` unit test（PascalCase → enum）
- `_parseStatus` unit test（toLowerCase 兼容）
- `default_config_options` 平台分支 test（mock `Platform.isAndroid`）
- 集成 test：模拟 EventChannel 推送 → 验证 provider 状态变化

### CI

还没接。目标：
1. GitHub Actions：每 push 跑 `flutter analyze` + `flutter test`
2. Android APK debug 构建产物（artifact）
3. macOS dmg release 构建（需要 macOS runner，免费额度有限）
4. iOS / Windows / Linux 暂搁置

### 文档

- [x] README.md — 平台支持表 + 入门
- [x] docs/ARCHITECTURE.md — 架构分层 + channel 协议
- [x] docs/ROADMAP.md — 本文件
- [ ] docs/CONTRIBUTING.md — 提交规范、commit 风格
- [ ] docs/DEBUGGING.md — Android logcat 关键 tag、macOS Console、iOS Xcode 调试 step

### 已知风险

- **协议**：当前 GPL-3.0；若未来要闭源 / 商业化，需要重新评估原生层代码出处与协议（咨询律师）
- **核心库版本**：`libcore.aar` / `libcore.dylib` 是某个 sing-box 版本 snapshot，sing-box 升级后要重 build。`core/build.sh` 里写死了 `SINGBOX_VERSION="1.11.0"`，定期评估升级
- **Apple 政策**：iOS NetworkExtension 在 App Store 审核越来越严，2024 后 VPN 类应用必须证明合理用途，自用 / 企业可绕开
