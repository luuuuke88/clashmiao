# iOS 连接生命周期 —— 实施计划

设计：`docs/superpowers/specs/2026-10-20-ios-lifecycle-design.md`（下称「spec」）。
分支：直接在 `main` 本地提交（用户要求：本地提交，推送前先问）。

## Global Constraints

- 公开文档、注释、commit message 不出现上游项目名；不回显测试订阅 URL。
- Swift 新文件必须加入 `Runner.xcodeproj` 对应 target（`objectVersion=54`，无同步分组；用 CocoaPods 自带的 `xcodeproj` gem 写脚本改，脚本放 `ios/scripts/`，幂等）。
- 纯逻辑（Model / Core / ConfigBuilder 的去重 / Store 编解码）不得 import UIKit / NetworkExtension / Flutter，便于单测。
- 线上 wire 字符串与 Dart `KernelSnapshot.fromJson`（`lib/core/box_service/kernel_port.dart`）逐字一致。
- 每个任务：先写测试看它红，再实现；任务末尾 `xcodebuild test` 对应用例绿、提交一次。
- 子代理一律 Sonnet 5.5。

## v2 修订（吸收 Codex v1 审核）

- I0 的验收改为真实的 `@testable import Runner` 逻辑测试（不是占位测试绿），命令用 `Runner.xcworkspace` + 可用模拟器；接线脚本同时覆盖添加 / 移除 / 各 target membership。
- I1 增加 `sessionId` / `generation`；I2 核心按 spec §3–§4 的标识与外部变化矩阵实现，并把 C1–C5 的竞态写成确定性测试；I4 定时器触发前先读事实、`ready` 门；I5 同步改造 `BoxAlertsStream`、Scene 前台通知；I6 扩展串行 `opQueue`、自洽失败、`select` 消息；I5–I7 视为同一个端到端集成门，三者都完成后才跑 `flutter build ios` 与全量测试。
- I8 增加：双栈 / 流量计数差证据、大订阅与连续重载内存余量。

## Review Focus

1. 核心状态机的归属 / 竞态（过时 Job 不得改 desired；Runner 自己的启动不得被误判成外部启动）；
2. 扩展失败必须 `throw`，不再「写 marker 后正常返回」；
3. 扩展内存（无整份配置解析、无多余网络轮询、重载先释放旧 service）；
4. Runner 被挂起 / 杀掉后的 `resync` 与冷启动挂接；
5. Dart 契约不变，iOS 只是换了 Port 实现。

## Task I0 工程接线

- 写 `ios/scripts/add_sources.rb`：给指定 target 加文件引用与 Sources build phase（幂等）；新建组 `Runner/Kernel`、`Shared/Kernel`（Runner + Extension 双 target）。
- 给 `RunnerTests` target 配好 `TEST_HOST`，确认 `xcodebuild test -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17'` 能跑起现有占位测试。
- 验收：真实的 `@testable import Runner` 逻辑测试在模拟器上绿（不是占位测试）；`flutter build ios --no-codesign` 绿。

## Task I1 共享契约（Shared）

文件：`ios/Shared/Kernel/KernelIntent.swift`、`ExtensionState.swift`；扩展 `ProfilePathResolver`（`kernelDirectory` / `intentFile` / `extensionStateFile` / `finalConfig(revision:)`）。
- `KernelIntent`（Codable，`version:1`）、`ExtensionState`（`phase` / `code` / `reloadCount` / `availableMemoryMin`…）、失败码字符串常量；原子读写帮助函数（坏文件返回 nil 并不抛）。
- 测试：编解码往返、缺字段 / 坏 JSON / 未知 phase、原子写覆盖。

## Task I2 协调器模型与核心

文件：`ios/Runner/Kernel/CoordinatorModel.swift`、`CoordinatorCore.swift`。
- 把 Android `KernelModel.kt` / `CoordinatorCore.kt` 移植为 Swift，按 spec §4.1 去掉 Service 实例 / startId / 授权对话框，换成隧道事实与 `Connect / Reload / Teardown` Job；含 Owner / Exec / Job / Timer / Persist / 网络去抖 / 外部变化推导表（§4.3）。
- 测试（`CoordinatorCoreTests`）覆盖 spec §8 列出的全部场景，另加：外部启动不被误判（launching / adoptGuard）、扩展被杀推断 `kernelExited`、`phase==stopped` 按 `stopReason` 分类、`generation` 变化（而非 `reasserting`）触发外部重载。
- 验收：核心用例全绿。

## Task I3 配置拼装

文件：`ios/Runner/Kernel/ConfigBuilder.swift`（拼装器协议 + `MobileBuildConfig` 实现 + `TunInbounds.keepLast` Swift 版 + 原子写 + 旧 `final-*` 清理）。
- 测试：tun 去重（0 / 1 / 多个、解析失败原样返回、非 tun 保序）、清理只删未被引用的 `final-*`。

## Task I4 外壳、执行层、适配器协议

文件：`KernelStore.swift`、`KernelExecutor.swift`、`TunnelAdapter.swift`（协议 + 假实现放测试里）、`KernelCoordinator.swift`。
- 命令队列串行；Effect→副作用；`request()` 同步取回执；`selectOutbound` 栅栏；`resync()`；持久化 serial 确认。
- 测试（假 adapter / 假 builder / 手动时钟）：连接成功、启动失败带 code、启动中 off、30 s 启动超时、选择 stale、`resync` 追平挂起期间错过的状态。

## Task I5 NE 适配器与 Flutter 桥

文件：`TunnelController.swift`（`NETunnelProviderManager` 实现 `TunnelAdapter`，替代 `TunnelManager`）、`Handlers/PigeonBridge.swift`、`Handlers/KernelSnapshotStream.swift`、`NetworkStream.swift`、`TunnelStatusStream.swift`（改为快照派生）、`ChannelMethodHandler.swift`（删旧方法）、`AppDelegate.swift`（注册、`didBecomeActive → resync`）。删除 `TunnelManager.swift`、`TunnelProfile.swift` 中不再用的部分。
- `/kernel.snapshot` 用 `FlutterJSONMethodCodec`，订阅时先推当前值；`/network` 由 `NWPathMonitor` 去抖后推 `{}`。
- 验收：`flutter build ios --no-codesign` 绿；模拟器上 App 能启动、`getSnapshot` 返回 `stopped`（隧道在模拟器上不可用，只验证桥与快照）。

## Task I6 扩展改造

文件：`ClashMiaoTunnelProvider.swift`、`Kernel/KernelProviderProxy.swift`、`KernelEngine.swift`（删）、`TrafficStats.swift`（删）、新增 `ExtensionStateWriter.swift`。
- 按 spec §6：读 intent、失败 `throw`、state 文件、`reload` 应用消息、`reloadCount`、内存采样、移除整份配置解析与流量轮询。
- 验收：扩展 target 编译通过；逻辑可单测的部分（失败码映射、state 写入）放 Shared 并测。

## Task I7 Dart 与文档

- `kernel_port_provider.dart` iOS 走 `PlatformKernelPort`；删 `EmulatedKernelPort.platformPersistsConfigPath` 及测试；`flutter analyze --fatal-warnings`、`flutter test`、`dart format`。
- 更新 `docs/ARCHITECTURE.md`、`ios/SCAFFOLDING.md`（新的 target 成员、冒烟步骤）、`docs/ROADMAP.md` 里程碑 3、`CHANGELOG.md`。

## Task I8 真机验收（设备在线时）

按 spec §8 清单逐项执行并把 epoch/attempt/desired/source 序列、内存余量写入 `docs/superpowers/research/2026-10-20-ios-device-smoke.md`。设备不在线则本任务保持未完成，并在交接说明里写明。

## Task I9 上架材料

`docs/release/app-store-checklist.md`：隐私（数据收集声明、`PrivacyInfo.xcprivacy` 核对、隐私政策 / 支持 URL）、审核备注（指南 5.4 VPN 类要求、测试账号 / 订阅说明、演示步骤）、截图规格与清单、出口合规、美国 / 香港店面设置（不勾选中国大陆）、构建上传与 TestFlight 步骤。
