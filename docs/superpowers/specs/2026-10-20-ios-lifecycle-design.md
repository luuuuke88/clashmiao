# iOS 原生层对齐连接生命周期 —— 设计

日期：2026-10-20　状态：v2.1（吸收 Codex v1 审核 C1–C5、I1–I8、M1–M2 与 v2 复审；与 v1 冲突处以本版为准）
前置：`2026-10-19-connection-state-machine-design.md`（下称「B spec」）、`docs/ARCHITECTURE.md` 的「连接生命周期」「持久化」。
目标平台：iOS 15+（主 App `Runner` + Network Extension `SingBoxPacketTunnel`）。

## 1. 目标与非目标

**目标**
1. iOS 原生实现 B spec 的同一份 Pigeon 契约与协调器语义：期望状态（desired）、`execToken` / owner 归属、`epoch / attempt / version`、权威快照（含 `retainedConfigPaths`）、`runtime-<revision>.json`、`acknowledgeReplay`、带 `expectedAttempt` 的 `selectOutbound`。Dart 在 iOS 上改用 `PlatformKernelPort`，`EmulatedKernelPort` 只留给桌面。
2. 手选重放绑定 `(profileId, inc, epoch, attempt)`：Dart 流水线已按 `(epoch, attempt)` 去重并携带 `expectedAttempt`；原生保证 attempt 不符时返回 `stale` 且**不写入**，而且这一保证由**扩展进程内**的串行队列兑现（§4.4）。
3. 健康探测诚实经过隧道：iOS 的 `kernelEnableTun` 恒为 true，Dart 探测走「本进程直连 → 系统路由 → utun → 内核 tun 栈」。是否真的进入隧道取决于 `includedRoutes`（IPv4/IPv6 默认路由）与更具体的系统路由，**不**靠「没设 excludedRoutes」推断：真机验收用命令服务器的连接列表作为证据（探测后列表里出现探测目标 `cp.cloudflare.com`，并排除背景流量；覆盖订阅自带 TUN 配置的情形），并覆盖「内核存活但出口不通」的黑洞场景。
4. 补上网络变化事件：`com.clashmiao.app/network` EventChannel（Runner 内 `NWPathMonitor`，去抖）。
5. 遵守 Packet Tunnel 扩展的内存上限（约 50 MB 的观察值，Apple 不保证固定数字）：减少常驻与瞬时峰值，并留下可诊断的内存与退出痕迹（§5）。

**非目标**
- 分应用代理（iOS 不支持）、iOS 上 `PlainService` 形态（iOS 只能 TUN）。
- 按需连接（On Demand）：本版**不启用**，且保存偏好时显式关闭遗留的 `isOnDemandEnabled`，否则「app 关」无法被系统尊重。
- 把整个协调器搬进扩展进程（§2 取舍）。
- 旧版本 `TunnelProfile` 键的迁移：新流程每次连接都由 Dart 带 `LaunchSpec`，没有 intent 的系统直接启动会以 `emptyConfiguration` 干净失败（§6）。

## 2. 架构取舍：协调器在 Runner，扩展是**自洽的执行体**

Android 的协调器与内核同进程。iOS 的内核在扩展进程里，而**「关」状态下扩展根本不存在**，所以完整协调器必须住在能感知「无隧道」的一方：

| 方案 | 结论 |
|---|---|
| 协调器放扩展 | ❌ 隧道不存在时没有进程可问；快照无法回答「已停止」 |
| **协调器放 Runner，扩展作自洽执行体** | ✅ 采用 |
| 全 Dart（现状 `EmulatedKernelPort`） | ❌ 无原生所有权，覆盖不了系统设置开关与冷启动挂接 |

**后台收敛能力的边界（如实承认）**：Runner 进入后台会被挂起，期间收不到状态通知、定时器冻结。因此扩展必须**对自己的失败负全责**，不依赖 Runner 在场：
- 启动 / 重载 / 自发重载中任何不可恢复的错误，扩展自己清理半初始化资源、写 `failed` 事实、调用 `cancelTunnelWithError`（Apple 对 provider 的要求）；Runner 之后（回到前台或被拉起时）只需**读事实**，不需要先发出一个「停」才能收场；
- Runner 侧的 Connect / Reload / Teardown 只是**提交**，提交之后的完成由系统 / 扩展独立推进；Runner 恢复后 `resync` 追平。

**读事实优先于裁决**：Runner 每次回到前台（`UIApplication.didBecomeActiveNotification`，不用 AppDelegate 的 `applicationDidBecomeActive`——项目使用 Scene，该回调不会被调用）、每次状态通知、**每个定时器触发之前**，都先同步读取 `connection.status` 与 `extension-state.json`，再让核心推导。恢复后已过期的启动超时因此不会误杀后台已成功的启动。超时按**墙钟**计算且**包含挂起时间**（`DispatchWallTime`）。

**首份快照的发布顺序**：协调器构造完成 → 异步加载 NE 偏好 → 读取事实并喂给核心 → 才标记 `ready`。在 `ready` 之前 `getSnapshot` 有界等待（≤1.5 s，超时返回 `unavailable` 错误，Dart 的退避重试接管），`/kernel.snapshot` 的订阅在 `ready` 之后才推第一份。绝不先发默认 `stopped` 让 Dart 当作权威值开始清理文件。

## 3. 进程间契约（App Group 容器 `…/Library/Application Support/ClashMiao/kernel/`）

不放 `Library/Caches`（系统可能清理）；也不放 Dart 的 `Runtime/`（Dart 启动器会清理 `runtime-*.json`）。

| 文件 | 写入方 | 内容 |
|---|---|---|
| `final-<revision>.json` | Runner | 已拼好的最终 sing-box 配置（§5）。`revision` 是（options + 运行时配置内容）的稳定哈希，**同名即同内容，不可变**；原子写、一次成型 |
| `intent.json` | Runner（唯一写者） | `{version:1, desired, launchId, spec:{runtimeConfigPath, optionsJson, profileName, configRevision}, finalConfigPath, finalRevision}` |
| `extension-state.json` | 扩展（唯一写者） | `{sessionId, launchId, phase, generation, revision, code, message, stopReason, availableMemoryMin, updatedAt}` |

**标识（C3）**——三个不同的东西，不再混用：
- `launchId`：**Runner 的操作 ID**。每次派发 Connect / Reload 时生成，写入 `intent.json`；
- `sessionId`：**扩展实例 ID**。扩展每次 `startTunnel` 生成新 UUID（系统启动、扩展被杀后重启都会换新）；
- `generation`：**内核 service 代次**。扩展内每创建一次 service +1（首次启动 =1；Runner 触发的重载、内核自发重载各 +1；`clearDNSCache` 引起的 `reasserting` **不**改变它）。

Runner 据此判断：「这是我这次启动的结果」= `state.launchId == 我派发的 launchId` 且 `sessionId` 是新见到的；「内核被重载过」= 同一 `sessionId` 下 `generation` 变大；「扩展换了一个实例」= `sessionId` 变了。`attempt` 严格按真实 service 代次变化分配，不靠 `reasserting` 猜。

**发布顺序（C5）**：先把 `final-<rev>.json` 完整写好（原子改名），再原子发布指向它的 `intent.json`；`intent.json` 的所有写入都经 `KernelStore` 的同一把锁、写整份内存内容，后一次必然包含前一次；执行层在拼配置之后、写 intent 之前复查取消标，被取消的任务不发布。扩展读取时「读 intent → 读 final」，final 缺失则**重读一次 intent 再试**（有界一次）。`final-*` 只在发布新 intent **之后**清理，保留「新 + 上一份 + 扩展 state 报告的运行中 revision」，**以及修改时间在 120 s 以内的所有 `final-*`**。这是有界风险而非证明：扩展读完 intent 到打开 final 之间只隔毫秒，要让它读不到 final，需要在这段时间内连续完成两次完整发布（每次含拼配置与 IPC），且全部落在 120 s 保护期之外不可能；极端情况下读不到则按「重读 intent 一次」→「`emptyConfiguration` 干净失败」收场，不会产生损坏状态。执行层在「复查取消标」与「发布 intent」之间被取消，会多发布一份无害的意图（扩展只在启动时读它）。

**持久性与文件保护**：kernel 目录里的文件显式设为 `completeUntilFirstUserAuthentication`（锁屏后系统直接启动扩展也读得到）。配置引用的 `.srs` 规则集在 `Library/Caches/Runtime`，系统可能清理；缺失时内核创建失败，扩展以 `createService` 干净失败，Dart 重新连接会重新 provision 规则集。

**`phase` 语义与终态粘性**：`starting` → `running`（带 `generation` / `revision`）→ 正常停止时 `stopped`（带 `stopReason`）；任何启动 / 重载失败写 `failed`（带 `code` / `message`）。`failed` 与 `stopped` 对同一 `sessionId` 是**终态**：写入器丢弃随后的任何写（含内存采样），因此失败记录不会被后续的 `stopped` 覆盖。被系统强杀（内存超限）不会写任何终态：状态停在 `running` / `starting` 而隧道已 `disconnected`，Runner 判定 `kernelExited`，文案注明可能是内存不足。

**扩展忽略 `desired`**：隧道被起来就说明系统层面的意图是开（设置里手动打开 VPN）。因为本版不启用按需连接，没有「系统反复拉起、反向覆盖 off」的路径；Runner 保存偏好时把 `isOnDemandEnabled` 置 false。

## 4. Runner 侧协调器

```
ios/Runner/Kernel/
├─ CoordinatorModel.swift   Desired / Source / FailureCode / KernelSnapshot / Receipt / Effect（wire 字符串与 Dart 逐字一致）
├─ CoordinatorCore.swift    纯 Swift 状态机：事件 → Effect 列表 + 新快照；不碰线程 / NE / 文件 / 时钟
├─ KernelCoordinator.swift  命令层外壳：串行队列上执行 Effect，把执行结果当事件喂回核心；定时器触发前先读事实
├─ KernelExecutor.swift     执行层：串行后台队列，跑「授权 → 拼配置 → 发布意图 → 提交 / 发重载消息 / 停」，分步报告、可取消
├─ TunnelAdapter.swift      协议：对 NETunnelProviderManager 的最小抽象（真实现 + 测试替身）
├─ KernelStore.swift        intent.json 的读写
├─ ConfigBuilder.swift      内核拼装（注入）+ tun inbound 去重 + 原子写 final-<rev>.json
└─ TunnelController.swift   NE 适配器真实现 + 前台恢复 + ready 门
```

### 4.1 核心状态机（`CoordinatorCore`）

骨架与 Android `CoordinatorCore` 一致：单一入口 `reconcile()`、每种动作靠标志位保证只发一次、Owner / Exec / Job 带不可变归属、只有仍属于当前请求的 Exec 才能写 `lastFailure` 并把 desired 置 off、配置引用由原生在快照里声明。差异只有「承载内核的东西」：Android 是多个 Service 实例，iOS 是**一条隧道会话**，所以换成隧道事实（`TunnelStatus` + 扩展 state）与三类任务。**所有隧道输入都是电平触发**：外壳每次都读**当前**的 `connection.status` 与 state 文件，不依赖通知载荷，因此陈旧的 `disconnected` 通知不会被误读成「刚刚断了」。

事件入口：`onRequest` / `onExternal` / `onTunnelStatus(status, report)` / `onJobStep / onJobFinished` / `onTimer` / `onAckReplay` / `onReloadRequested` / `onNetworkResolved` / `onPersistResult`，语义同 Android，iOS 专属部分如下。

**Job 种类**
- `Connect(spec, launchId)`：确保 NE 偏好存在并启用（首次会弹系统「添加 VPN 配置」，被拒 → `permissionDenied`；步骤名 `authorize`，不计 20 s 看门狗，由 30 s 启动超时统一兜底）→ 拼配置 → 发布意图 → `startVPNTunnel()` → **等隧道状态离开 disconnected（≤5 s）**。等不到 = **`abandoned`**：执行层立即补一次 `stopVPNTunnel()`（撤销可能迟到的启动）并返回失败；核心据此置 `stopSubmitted` 与一个 10 s 的 **adoptGuard**——期间任何迟到的 `connecting/connected` 都**不当作外部启动**，而是当作我们那次被放弃的启动，desired=off 时直接 Teardown。这样「已提交但未终结」的启动始终有归属：`.launched` 之后到 `connected`/`down` 之前是 `launching`；`abandoned` 之后到 adoptGuard 结束或 `down` 之前是 `adoptGuard`。两个窗口里的观察都不会被误认成外部启动；
- `Reload(spec, launchId)`：拼配置 → 发布意图 → `sendProviderMessage({"op":"reload","launchId":…})` → 等回执 `{ok, code, message, sessionId, generation}`；
- `Teardown`：`stopVPNTunnel()`。

**预期中的下线（C1）**：派发 Teardown 的那一刻核心置 `stopSubmitted`，直到观察到 `disconnected` 才清除。期间：任何 `connecting / connected` 都不当作外部启动；随后到达的 `disconnected`（无论 state 里是 `stopped` 还是别的）都只算「停止完成」，**不会**按「系统关闭」覆盖期间到达的新 on 请求；新的 on 请求在 `disconnecting` 期间等待 `disconnected` 再派发 Connect（`startVPNTunnel` 在 disconnecting 期间会失败）。

**收敛判断**：隧道 connected 且 state 为 `running` 且 `revision == spec.configRevision` 且无待重载、无 `stopSubmitted` → 已收敛。revision 不同 → `Reload`（不断开 VPN）；隧道 down → `Connect`；其余等待。

**外部变化推导（`onTunnelStatus`，含 I2 的完整矩阵）。处理优先级自上而下：①预期下线（`stopSubmitted`）→ ②操作归属（`launching` / `adoptGuard` / `launchId`）→ ③state 阶段有效性（只有 `phase=running` 才能证明内核在跑；`connected` + 非 running 一律「未确认」，保持 starting 等 resync / 超时）→ ④实例变化（`sessionId` / `generation`）。「down」指 `disconnected` 与 `invalid`，二者对 `stopSubmitted` 的处理相同。**

| 观察 | 处理 |
|---|---|
| `connecting`/`connected`，不是我们的启动，也不在预期下线，desired=off | **外部启动**：作为 `source=system` 的 on 受理（沿用持久化的 spec，可为空）；`connected` + `running` 时接管：`attempt` +1、`selectionsReplayNeeded=true`、记下 `sessionId/generation` |
| `connected` 且 state `phase=running`，已认为内核在跑，但 `sessionId` 变了 | 扩展换了实例而我们没看到下线：按「接管」重新记账，attempt +1 |
| `connected`，同 `sessionId`，`generation` 变大且不是我们的 Reload | **内核被重载**（含后台完整发生、没看到 `reasserting` 的情况）：attempt +1，`selectionsReplayNeeded=true`；`reasserting` 只用来显示 starting，**不**据它分配 attempt（`clearDNSCache` 也会触发 `reasserting`） |
| `disconnected/invalid`，state `failed` 且 `launchId` 匹配当前操作 | `fail(state.code)`，属于当前请求 |
| `disconnected/invalid`，state `stopped`，`stopReason` ∈ {providerFailed, configurationFailed, connectionFailed} | 失败：`kernelExited`，信息带 `stopReason` |
| `disconnected/invalid`，state `stopped`，其它 `stopReason`（userInitiated、providerDisabled、configurationDisabled/Removed、superceded、userLogout/Switch、appUpdate、sleep、idleTimeout、noNetworkAvailable、authenticationCanceled 等） | 系统 / 用户关闭：`desired:=off, source=system`，不写 failure；未知 reason 同此 |
| `disconnected/invalid`，state 为 `running`/`starting`（无终态记录），且我们的 Connect 已确认提交（`launchSubmitted`） | 扩展被强杀：`kernelExited`（可能是内存不足）；启动中则 `startService` |
| `disconnected`，Connect 尚未确认提交（执行层还在拼配置 / 等授权 / 等可见） | 噪声：忽略（不改 `stopSubmitted`、不算失败） |
| `disconnected/invalid`，state 缺失 / 损坏 / `launchId` 不属于当前操作 | 启动中 → `startService`（"tunnel stopped during start"）；运行中 → `kernelExited`（"ended unexpectedly"） |
| `invalid`（偏好不存在 / 被禁用） | 等同 `disconnected`；`stopping` 因此不会永远悬着 |
| `disconnecting` + state 已 `stopped`（非本请求触发） | 提前按「系统关闭」处理，不必等 `disconnected` |

**冷启动挂接**：首次读到 `connected` + `running` 且无 Exec → 视同外部启动：`attempt=1`、`selectionsReplayNeeded=true`、`source=system`。若 intent 里的 spec revision 与 state 的运行 revision 对不上，`retainedConfigPaths` 报**未知（null）**（我们不知道正在跑的是哪份 `runtime-*.json`），直到下一次自有启动 / 重载。

**快照 `status`**：on：已收敛且无在途 Exec / Job → `started`，否则 `starting`；off：隧道 down 且无 Exec / Job / `stopSubmitted` → `stopped`，否则 `stopping`。字段、版本号、`retainedConfigPaths` 与 Android 相同（当前意图 spec、已确认与未确认的持久化 spec、运行中 spec、在途 Connect/Reload 的 spec；坏文件 / 未知运行引用 → null，**不是**空集合）。

**时间预算**：同 B spec（30 s 启动超时含授权弹窗；20 s 看门狗按步骤；Teardown 超 20 s 未 disconnected → `kernelUnresponsive`，状态保持 stopping）。

### 4.2 外壳与线程

`KernelCoordinator` 持有一条**串行命令队列**；Pigeon 回调（主线程）只投递或 `sync` 取回执（核心是纯内存、微秒级）。`KernelExecutor` 是另一条串行队列，阻塞操作只在这里。每个定时器触发时**先 `resync` 再进核心**。每个任务完成后也立即 `resync`。

### 4.3 `selectOutbound` 与 `expectedAttempt`（C4）

Runner 内的栅栏（Android 式 `liveAttempt`）只能挡住「Runner 已知的重载」；扩展自发重载或被系统重启时，Runner 的队列管不到扩展。所以**真正的校验与写入在扩展里**：

1. Runner 命令队列：`expectedAttempt` 必须等于当前已就绪实例的 attempt，否则立即 `stale`；通过则取该 attempt 对应的 `(sessionId, generation)`；
2. Runner 执行层向扩展发 `{"op":"select","group","outbound","sessionId","generation"}`；
3. 扩展在**与 service 替换同一条串行队列**上先比对当前 `(sessionId, generation)`，不符返回 `{ok:false, code:"stale"}` 且**不写入**，相符才在本进程内用独立命令客户端写入；
4. Runner 把 `stale` 映射为 `FlutterError("stale")`。`expectedAttempt` 为空（旧调用）则不校验。回调恰好一次、有界（消息超时 10 s）。

### 4.4 Pigeon 实现与遗留入口

- `getSnapshot` / `request` / `acknowledgeReplay` / `selectOutbound` 如上；错误统一用生成的 `PigeonError(code:…)`。`/kernel.snapshot` 用 `FlutterJSONMethodCodec` 推 JSON map（`Int64` 不经 `Double`）；旧 `/service.status` 仍发 `{"status": "Starting|Started|Stopping|Stopped"}` map，改为从快照派生；`/service.alerts` 通道保留，`BoxAlertsStream` 不再依赖旧 manager。
- `initialize` / `setup`：`KernelBridge.bootOnce()` + 加载 NE 偏好（保持现状：提前触发系统授权弹窗，避免落在首次连接的 30 s 里）。
- 旧 `start` / `stop` / `restart`：Dart 已不调用，iOS 直接返回 `FlutterError("unsupported")`（不留绕过协调器的旁路）。`ChannelMethodHandler` 删到只剩 `generate_warp_config`。
- `resetTunnel`：`desired==on` 时 `onReloadRequested(app)`，否则无操作。
- `TunnelManager` 删除，职责并入 `TunnelAdapter` / `KernelStore`；`TunnelProfile` 只留 `configOptions`（`generateFullConfig` 开发用）。

## 5. 配置拼装与扩展内存（I4）

**拼配置在 Runner，不在扩展**：`ConfigBuilder` 调用内核的 `MobileBuildConfig(spec.runtimeConfigPath, spec.optionsJson)`，再做与 Android `TunInbounds.keepLast` 相同的 tun inbound 去重，原子写入 `final-<revision>.json`。

**扩展内存纪律**（Apple 不保证固定上限，约 50 MB 是观察值；`os_proc_available_memory` 只是即时参考）：
1. 删除 `KernelEngine.normaliseConfig` 对整份配置的 `JSONSerialization` 解析；扩展只读文件 → `String` → 建 service 后立即释放，**不保留 `activeConfig` 常驻副本**；
2. 删除 `TrafficStatsReader` 与 `"stats"` 应用消息：它轮询固定端口 `127.0.0.1:10864`，而默认 options 的 clash API 端口是 6756，二者从未对上，失败后每 5 ms 重试，白占 `URLSession` / WebSocket 与 CPU；且 Runner 已有命令服务器统计通道，这是重复通道；
3. 断开 `provider ↔ KernelPlatformBridge` 的强引用环（bridge 持 provider 改 `weak`）；停止时断开所有原生句柄；
4. 重载先完整释放旧 service（并 `FreeOSMemory`）再建新的，不同时持有两份；
5. `LibboxSetMemoryLimit(true)` 恒开；
6. 在生命周期关键点（读配置前后、`newService` 后、`start` 后、每次重载后）和每 10 s 采样 `phys_footprint` 与 `os_proc_available_memory()`，把历史最低余量写入 state 并打日志；
7. 验收不止「能连上」：大订阅（上千节点）、大规则量、测速并发、连续 20 次重载，观察余量不随重载持续下降；保留 jetsam 诊断（下次启动读 state，`running` 而隧道已死 = 被杀）。

## 6. 扩展改造（I1）

**串行执行与无互等**：扩展内有一条 `opQueue`，`startTunnel` 的主体、`stopTunnel`、`handleAppMessage`（`reload` / `select`）、内核自发重载（`serviceReload`、系统代理开关）、内存采样与 state 写入全部在其上排队；`stopTunnel` **不经过** `opQueue` 排队：它先在锁内置 `stopping` 标志（在途的 start / reload 在每个检查点看到后放弃并回收），再把回收投递到 `opQueue`。同步路径 `service.start()` → `openTun` → `awaitBlocking` → `setTunnelNetworkSettings` 只依赖 NE 自己的回调队列，不依赖 `opQueue`（实现时逐一核对这条依赖链）。`select` 在 `opQueue` 内执行，仅当 `running && !stopping`；命令服务器的本地 socket 调用没有期限，是已知风险——缓解：Runner 侧 10 s 超时释放 Dart；扩展整体被卡死时由系统在 `stopTunnel` 超时后回收进程，Runner 看到 `running` 而隧道已 down，按 `kernelExited` 处理。`serviceReload()` 回调**不阻塞**等待重载完成（只入队），避免 libbox 回调线程与 `opQueue` 互等。state 写入器持锁、遵守终态粘性。

**资源归属**：`LibboxNewService` 一返回就登记到 provider 名下（在 `start()` 之前），任何失败路径统一调用同一个回收函数，不存在「局部 service 没人管」的窗口。

**失败自洽（C2）**：`startTunnel` 任何一步失败 → 回收、写 `failed`、**`throw`**（系统据此判定启动失败；现状是写 marker 后正常返回，系统以为隧道已 connected——黑洞）。`reload` / 自发重载失败 → 回收、写 `failed`、（有回执则先回 `{ok:false,…}`）、`cancelTunnelWithError`。无 intent / final 读不到（含重读一次之后）→ `emptyConfiguration`，同样干净失败。

**其它**：`handleAppMessage` 解析 JSON `{"op":…}`，未知 op 回 `{ok:false}`；`reload` 请求绑定 `(launchId, sessionId)`：`launchId` 必须等于扩展此刻读到的 `intent.launchId`，`sessionId` 必须等于扩展自己的 `sessionId`（系统换了实例后，原消息被拒绝）；扩展保存「最近一次已完成的 reload 的 launchId 与回执」，同一 `launchId` 的重复消息直接返回缓存回执，不再重建。

## 7. Dart 侧改动（最小）

- `kernel_port_provider.dart`：`Platform.isAndroid || Platform.isIOS` 用 `PlatformKernelPort`；桌面保留 `EmulatedKernelPort`，删除其 `platformPersistsConfigPath` 参数与相关分支和测试（只为 iOS 存在）。
- 契约逐项核对（I8），每项在 Swift 测试或既有 Dart 测试里有断言：`epoch/version`（同纪元只认更大 version，查询与事件同一状态源）；revision 为非负 63 位哈希，Swift 全程 `Int64`；`status/desired` 非法值会丢整份快照，故只发合法字符串；`appliedSeq/Receipt` 受理即推进、拒绝码精确为 `stale` / `wrongEpoch` 且不改状态；`attempt` 首次实际工作时才分配、同配置无操作不递增；`lastFailure` 携带正确 `attempt/seq`、只用九个现有码；`retainedConfigPaths` `null`=未知 `[]`=确知无引用；`selectOutbound` 只有精确的 `stale` 映射为 `SelectStale`，原生保证有界且恰好一次回调。
- `ARCHITECTURE.md`：更新「iOS / 桌面：降级契约」「iOS 原生侧」，删除已知技术债里 iOS 的三条，写入本设计。

## 8. 测试与验收

**Swift 单测**（`RunnerTests`，模拟器 `xcodebuild test`，I0 就用真实的 `@testable import Runner` 验证接线）：
- `CoordinatorCore`：请求覆盖 / stale / wrongEpoch；off→on 等待旧停止且旧 `stopped` 不覆盖新 on（C1）；start 提交后状态尚未变化即 off；取消后迟到 connected；启动中收 off；过时 Job 失败不改 desired；启动超时；revision 变化 → Reload；同 revision 无操作；`generation` 变化 = 外部重载（含没看到 `reasserting`）；`reasserting` 但 `generation` 不变不产生 attempt；`sessionId` 变化 = 实例更换；`stopReason` 分类全表；`invalid`；state 缺失 / 损坏；冷启动挂接（含 spec 对不上时 retained=null）；`retainedConfigPaths`（含未确认持久化）；epoch/attempt/version 单调；Teardown 超时 `kernelUnresponsive`；
- `ConfigBuilder`：tun 去重（同 Android 用例）、`final-*` 清理只保留新 / 上一份 / 运行中；
- `KernelStore` 与 state 编解码：坏文件、版本不认识、原子写；
- `KernelCoordinator` 外壳（假 adapter / 手动 scheduler）：连接成功、授权被拒、Connect 后隧道不可见 → 失败、定时器触发前先读事实、选择栅栏与扩展侧 `stale` 映射、`ready` 前 `getSnapshot` 有界等待；
- 扩展侧可单测的纯逻辑放 `Shared`：state 写入器的终态粘性、消息解析、`stopReason` 分类。

**构建门**：`flutter analyze --fatal-warnings`、`flutter test`、`flutter build ios --no-codesign`、`xcodebuild test`。

**真机验收**（需 iPhone 在线）：导入订阅 → 连接 → 出口 IP 变化 → 延迟列表 → 切节点 → 后台 / 前台 → 杀 App 重开（挂接、无触觉、时长不显示）→ 系统设置里关 / 开 VPN（`source=system`）→ Wi-Fi↔蜂窝（`/network` 事件；连接是否自恢复）→ 黑洞场景（健康探测 degraded）→ 探测后命令服务器连接列表里出现探测目标（证明进了 utun；双栈）→ 大订阅与连续重载的内存余量。每项记录快照的 `epoch/attempt/desired/source` 序列。

## 9. 风险

- 协调器在 Runner，后台被挂起期间无法计时 / 响应；以「扩展自洽失败 + 读事实优先 + 墙钟」兜底，属已知降级，写入文档。
- 扩展被杀无回调，只能事后推断；可能把系统内存回收与内核崩溃混为 `kernelExited`，文案诚实标注。
- `startVPNTunnel` / `stopVPNTunnel` 的系统层竞态靠 `stopSubmitted` 与「Connect 等隧道可见」规避，仍以真机为准。
- `NEProviderStopReason` 的取值随系统版本增加，未知值按「系统关闭」处理。
- `fetchLastDisconnectError` 需要 iOS 16，故失败原因走 state 文件，不依赖它。
