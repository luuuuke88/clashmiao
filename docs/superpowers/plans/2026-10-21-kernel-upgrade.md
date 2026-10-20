# 内核升级到官方 sing-box 1.14 线 Implementation Plan

**Goal:** 以自有 Go 模块 `kernel/` + 官方 sing-box v1.14.3（libbox 仅作 Go 依赖）替换 Android 上的 1.8.9 分叉内核；订阅解析与运行配置构建重写为 1.14 schema；对 Kotlin / Dart 保持原有契约（`KernelPort`、快照协议、分组 / 统计线格式、选择重放、健康探测、`configOptions` 键名）。
**Spec:** `/Users/luke/code/clashmiao/clashmiao-client/docs/superpowers/specs/2026-10-21-kernel-upgrade-design.md`
**分支与目录:** 主目录 `/Users/luke/code/clashmiao/clashmiao-client`，分支 `k/kernel-114`（建议 `git worktree` 到 `/Users/luke/code/clashmiao/clashmiao-k`）。U1–U13 是纯 Go（`kernel/`、`tools/kernel/`），主机上 `go test` 即可验证，不需要设备；U14–U15 需要 U12 产出的 aar；U16 在 U8 之后可与 U14 / U15 并行；U17 最后。

## Global Constraints
- **不碰**：`lib/domain/connection/**`、`lib/core/box_service/kernel_port*.dart`、`pigeons/**`（协议不变，不重新生成 Pigeon）、Kotlin 的 `engine/CoordinatorCore.kt`、`KernelCoordinator.kt`、`KernelExecutor.kt`、`KernelStore.kt`、`KernelModel.kt`、`KernelRuntime.kt`（接缝）、`InstanceFollower.kt`。允许改的 Kotlin 仅限各任务 Files 列出的绑定层文件。
- **公开内容不出现上游项目名**（README、docs、注释、测试夹具、提交信息、`kernel/**`）。守卫脚本 `tools/kernel/check-public-names.sh` 读取**不入库**的 `tools/kernel/denylist.local`（一行一个名字，加入 `.gitignore`），U1 建立，之后每个任务提交前跑一遍。`io.nekohasekai.libbox` 这类包名只允许出现在 Kotlin 源码的 import 里，文档里只许出现在代码段。
- **净室**：不拷贝上游 core 的源码进仓库；URI 转换参照 CC0 的同源转换库与官方文档自行实现；Clash 转换依赖 MIT 的 `github.com/xmdhs/clash2singbox`。
- **版本钉死**：`kernel/go.mod` 里 `github.com/sagernet/sing-box v1.14.3`；gomobile `v0.1.13`；构建脚本固定 Go 版本（带 sha256）与 NDK `28.2.13676358`。升 sing-box / Go 必须同时过 U4 的三道闸并更新 `kernel/api/java-api.txt`。
- **Go 侧约定**：`internal/build`、`internal/subscription`、`internal/uri`、`internal/legacy`、`internal/options` **不 import sing-box**（只有 `engine`、`core` 与各自的 `_test.go` 里的闸门可以）；`gofmt -l` 无输出、`go vet ./...` 通过；测试默认 `-race`。
- **测试数据全合成**：主机用 `example.com` / `*.example.net` / RFC 5737 / RFC 3849 保留地址，UUID 与密码随机生成并在文件头注明「合成」，不含真实服务器与凭据；不回显用户的测试订阅。
- **Flutter / Dart 工具**：同前（3.44.2 格式化：`/private/tmp/claude-501/-Users-luke-code-clashmiao/cb86ed39-5fc3-4da0-8bce-8c3b8825c23f/scratchpad/flutter-3.44.2/bin/dart format --output=none --set-exit-if-changed lib test integration_test`；`flutter test --no-pub`；`flutter analyze --fatal-warnings`）；Kotlin：`cd android && ./gradlew --offline :app:testDebugUnitTest`。
- 不新增 Flutter 运行时依赖。i18n 新文案 10 种语言补齐。架构测试保持绿、白名单不新增。
- 中文提交，信息末尾 `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`；显式路径暂存（工作树里还有别的未提交改动，**不要** `git add -A`）；不 push。
- **设备**：U17 之前不碰真机与模拟器。U17 换包一律 `adb install -r`，不先卸载。

## Review Focus
1. DNS 语义：`dns-remote` 必须 `detour: select`；`dns-direct` / `dns-local` 绝不写指向空 direct 的 `detour`（`CheckConfig` 放行、`Start` 拒绝）；`route.default_domain_resolver` 与域名型服务器的 `domain_resolver` 齐全。
2. 三道闸是否真的在拦：黄金文件 + `CheckConfig` + 不变量 + 真启动；故意改坏一条规则能被至少一道闸抓住（每个构建器任务都要演示一次反例）。
3. 线格式逐字节：分组 / 统计 JSON 与 `OutboundSnapshotTest` 现有断言一致；`FailureCode` 映射不变（`create-service:` / `start-service:` 前缀）。
4. Kotlin：取消检查点与回收完整（`KernelStartSequenceTest`、`CoordinatorCoreTest` 不改断言通过）；`teardown(soft/hard)` 不遗漏 Seq 引用 / tun fd / 网络监听。
5. 回滚面：旧 aar、旧脚本、旧 Release tag 仍可用；新旧订阅文件互相的可读性（§8.2）。
6. 功能缺口一律隐藏而不是保留假开关；存档值不丢。

---

### Task U1：脚手架、构建脚本、守卫、CI
**Files:** 新建 `kernel/go.mod`、`kernel/go.sum`、`kernel/tools.go`（`//go:build tools`，空导入 `github.com/sagernet/gomobile/cmd/gomobile` 与 `.../cmd/gobind` 以锁版本）、`kernel/doc.go`、`tools/kernel/build-android.sh`、`tools/kernel/check-public-names.sh`；修改 `.gitignore`（加 `tools/kernel/denylist.local`）、`.github/workflows/ci.yml`（新增 `kernel` job）。
- `go.mod`：`module github.com/luuuuke88/clashmiao/kernel`；`go 1.25.5`；`require github.com/sagernet/sing-box v1.14.3`、`github.com/xmdhs/clash2singbox`（固定到 2026-09-07 的提交伪版本）、`github.com/sagernet/gomobile v0.1.13`。不写任何 `replace`。
- `build-android.sh`：沿用 `tools/libcore/build-android.sh` 的写法（**复制函数，不 source**，旧脚本保持冻结作回滚工具）：固定 `GO_VERSION`（初值 1.27.3）逐平台 sha256 下载校验；gomobile 装进构建目录私有 `GOBIN`；`check_ndk_revision`（28.2.13676358）；`BUILD_ROOT` 规范化 + 同级锁；产物 `build/kernel/libcore.aar` + `.sha256`。bind 参数固定为：`-target android/arm64 -androidapi 26 -javapkg=com.clashmiao.libcore -libname=clashmiao -trimpath -buildvcs=false -tags with_gvisor,with_quic,with_wireguard,with_utls,badlinkname,tfogo_checklinkname0 -ldflags "-checklinkname=0 -X github.com/sagernet/sing-box/constant.Version=<sing-box 版本> -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -s -w -buildid="`，包 `./core`（U12 之前 `./core` 只有占位类型，用来验证流水线）。放行门：16 KB 对齐（`check_alignment`，所有 LOAD 段 ≥ 2**14）、`go version -m` 核对 Go 版本 / tags / `-checklinkname=0` / sing-box 版本、`proguard.txt` 必须含 `-keep class com.clashmiao.libcore.** { *; }` 且不含 `com.clashmiao.**`。`--self-test` 故障注入（沿用旧脚本的 `expect_ok` / `expect_fail` 套路）。
- `check-public-names.sh`：读取 `tools/kernel/denylist.local`，对 `kernel/ tools/kernel/ docs/ README.md CHANGELOG.md` 做大小写不敏感的 `grep -rIn`，命中即失败；denylist 缺失时给出「请先创建」的提示并失败（不静默通过）。
- CI：`kernel` job 在 `ubuntu-latest` 上矩阵 `go: [1.26.x, 1.27.x]`，跑 `cd kernel && go vet ./... && go test -race ./...`；单独一步 `tools/kernel/build-android.sh --self-test`。
- 测试：`bash tools/kernel/build-android.sh --self-test` 全绿；`cd kernel && go build ./... && go vet ./...`；手动跑一次真实构建，产物通过放行门（记录耗时与 `.so` 体积到提交信息）。
- Commit: `build(kernel): 新增自有 Go 内核模块脚手架与可复现的 Android 构建脚本`

### Task U2：`engine` —— libbox 适配、平台适配、订阅流、主机冒烟
**Files:** 新建 `kernel/engine/engine.go`、`platform.go`、`dns.go`、`stream.go`、`classify.go`、`memory.go`，测试 `engine_test.go`、`platform_test.go`、`stream_test.go`、`classify_test.go`，夹具 `kernel/engine/testdata/wire/*.json`。**这是全仓唯一 `import "github.com/sagernet/sing-box/experimental/libbox"` 的包**（除 U12 的门面外）。
- 公开 Go 面（`core` 门面在 U12 原样转发，签名与 spec §4.2 一致）：
  ```go
  type Platform interface { OpenTun(specJSON string) (int32, error); Protect(fd int32) error; UseProcFS() bool
      FindOwner(protocol int32, srcAddr string, srcPort int32, dstAddr string, dstPort int32) (string, error)
      StartInterfaceMonitor(l InterfaceListener) error; StopInterfaceMonitor() error; InterfacesJSON() (string, error)
      ClearDNSCache(); LocalDNS() LocalDNS; WriteLog(line string) }
  type Handler interface { OnReloadRequested(); OnStopRequested(); SystemProxyAvailable() bool; SystemProxyEnabled() bool; SetSystemProxyEnabled(bool) }
  func Setup(o SetupOptions) error
  func New(host Platform, h Handler) (*Engine, error)
  func (e *Engine) Start(configJSON string) error   // 阻塞；失败带 "create-service:" / "start-service:" 前缀
  func (e *Engine) Stop() error; Close(); Pause(); Wake(); ResetNetwork()
  func (e *Engine) SelectOutbound(group, tag string) error; URLTest(tag string) error
  func (e *Engine) SubscribeGroups(h GroupsHandler) (*Subscription, error)       // OnGroups(json)
  func (e *Engine) SubscribeStats(h StatsHandler, intervalMillis int64) (*Subscription, error) // OnStats(json)
  func (e *Engine) SubscribeLogs(h LogHandler) (*Subscription, error)            // OnLog(line)
  ```
- `platform.go`：实现全部 28 个 `libbox.PlatformInterface` 方法（编译期断言 `var _ libbox.PlatformInterface = (*platformAdapter)(nil)`）；`OpenTun` 把 `libbox.TunOptions` 序列化成 spec §4.3 的 `TunSpec` JSON；`FindConnectionOwner` 把 Kotlin 返回的 `{"uid","packages"}` 还原成 `libbox.ConnectionOwner`；`GetInterfaces` 解析 `InterfacesJSON`；通知 / 邻居 / Shell / 桥 / Tailscale 一律「不使用」。`dns.go`：`LocalDNS` ↔ `libbox.LocalDNSTransport`（含 `DNSCall` 包装 `ExchangeContext`）。`memory.go`：`Setup` 的 `MemoryLimited` 为真时 `debug.SetGCPercent(10)` + `debug.SetMemoryLimit(30<<20)`。`classify.go`：`Start` 出错后再 `libbox.CheckConfig(content)`，失败 → `create-service:`，否则 `start-service:`。`Stop` 调 `CloseService`（会打断未完成的启动）。
- `stream.go`：用 `libbox.NewCommandClient` 经 `BasePath/command.sock` 连接；**线格式在这里产出**：分组 `[{"tag","type","selected","items":[{"tag","type","url-test-delay"}]}]`，统计 `{"connections-in","connections-out","uplink","downlink","uplink-total","downlink-total"}`；`SelectOutbound` / `URLTest` 用一次性 standalone client；订阅断线后上抛 `Disconnected` 由调用方重连（重连策略留在 Kotlin 的 `CoreStream`，U15）。
- 测试（主机、不联网；用 `net/http/httptest` 起 `127.0.0.1` 的本地目标）：
  - `engine_test.go`：`Start`（mixed 入站随机端口 + 两个 direct 出站 + selector/urltest）→ 经代理 GET 本地 httptest → 200；再 `Start` 一次（重载）仍可用；`Stop` / `Close` 幂等；`Stop` 并发打断一次慢启动（fake Platform 的 `StartInterfaceMonitor` 延迟）不死锁。
  - `stream_test.go`：首帧分组与 `testdata/wire/groups-first.json` 逐字节一致（延迟字段规范化后）；`SelectOutbound("select","b")` 后下一帧 `selected == "b"`；`URLTest("auto")` 指向本地 `/generate_204` 后 `url-test-delay > 0`；统计帧含全部 6 个键且为数字。
  - `classify_test.go`：非法 JSON 配置 → `create-service:`；合法配置但监听端口被占用 → `start-service:`；**DNS 服务器 `detour` 指向空 direct → `start-service:`**（把附录 A.2 的坑固化成回归测试）。
  - `platform_test.go`：`TunSpec` 序列化（用 fake `libbox.TunOptions`）与 spec §4.3 的示例 JSON 一致；`InterfacesJSON` 往返；28 方法断言。
- Commit: `feat(kernel): 封装官方 libbox 命令服务器与客户端，提供可测试的 Engine`

### Task U3：选项模型 `internal/options`
**Files:** 新建 `kernel/internal/options/options.go`、`rules.go`、`warp.go`、`options_test.go`、`rules_test.go`、`testdata/options/default.json`（手写一份与 Dart 当前输出等价的夹具；U16 换成导出夹具）。
- `type Options struct`：覆盖 spec §2.4 列出的全部键（kebab-case 的 `json` 标签；`mux`、`tls-tricks`、`warp`、`warp2`、`rules` 为嵌套结构）；`func Decode(raw []byte) (*Options, Warnings, error)`：未知键进 `Warnings`（不是错误），**已知键类型不符是错误**；`func Default() *Options`（与 Dart `NetworkSettings` 默认值一致：`mixed-port 2080`、`ipv6-mode ipv4_only`、`log-level warn`、`mtu 9000`、`strict-route true`、`tun-implementation mixed`、`url-test-interval 600`、`connection-test-url`…）；`func (o *Options) Validate() error`：端口 1–65535、`mtu` 范围、枚举（`ipv6-mode ∈ {ipv4_only, prefer_ipv4, prefer_ipv6, ipv6_only}`，`*-dns-domain-strategy ∈ {"", …}`，`tun-implementation ∈ {mixed, system, gvisor}`，`log-level ∈ {trace, debug, info, warn, error}`，`warp.mode ∈ {proxy_over_warp, warp_over_proxy}`）。`region != "other"` → 警告并按 `other` 处理。
- `rules.go`：`type Rule struct{ IP, Domains, Port, Network, Protocol, Outbound string }` → `func (r Rule) Matchers() (Matchers, error)`：`Matchers{Domain, DomainSuffix, DomainRegex, DomainKeyword, IPCIDR []string; Port []uint16; PortRange []string; Network, Protocol []string}`；`full:` → `Domain`、`domain:` → `DomainSuffix`、`regexp:` → `DomainRegex`、`keyword:` → `DomainKeyword`；`geoip:` / `geosite:` 前缀 → 错误（`option-invalid: geosite/geoip rules are not supported`）；`outbound ∈ {bypass, block, proxy, ""}`，其它值错误。
- 测试：默认值与 Dart 默认逐键对照（硬编码期望表）；每个枚举 / 端口边界的通过与失败各一例；未知键进入 `Warnings`；`rules` 解析表（≥ 20 行：各前缀、混合列表、端口范围 `1000:2000`、空串、非法 CIDR、重复项去重保序）。
- Commit: `feat(kernel): configOptions 解码、默认值、校验与规则解析`

### Task U4：构建器骨架与测试闸门 `internal/build`
**Files:** 新建 `kernel/internal/build/cfg/types.go`（最小 schema 类型：`Config`、`Log`、`DNS`、`DNSServer`、`DNSRule`、`Inbound`、`Outbound`（`map[string]any` 承载节点）、`Route`、`RouteRule`、`RuleSet`、`Experimental`），`build.go`（`func Build(profile Profile, o *options.Options, env Env) ([]byte, error)`；`Env{GOOS string; IPv6Supported bool}` 使构建可测试地区分 Android / 桌面）、`log.go`、`inbounds.go`、`experimental.go`；测试闸门 `kernel/internal/build/gate/gate_test.go`（此包的 `_test.go` 允许 import sing-box 与 `engine`）、`gate/invariants.go`、`gate/golden.go`（`-update` 标志）、`testdata/README`（矩阵表）、`testdata/profiles/*.json`（P1–P7 骨架）。
- 这一任务只落 `log` / `inbounds`（`tun-in`、`mixed-in`、`dns-in`；`allow-connection-from-lan`；IPv6 开关控制 TUN `address` 与监听）/ `experimental.cache_file` 三块，以及**闸门本身**：
  1. `golden.go`：与签入文件逐字节比较，`-update` 重写；
  2. `CheckConfig`：`libbox.CheckConfig(content)`；
  3. `invariants.go`：标签图自洽（引用均存在、selector `default` ∈ 成员、`detour` 无环、**无指向空 direct 的 detour**）、禁用键扫描（`sniff*`、入站 `domain_strategy`、`inet4_address` / `inet6_address` / `inet4_route_*`、`geoip` / `geosite`、DNS 服务器 `address`、`outbound` 为 `dns-out`、`tls_tricks`、`tls_fragment`、`disable_color`）、旧契约 tag 齐全（`select` `auto` `direct` `bypass` `direct-fragment` `dns-remote` `dns-direct` `dns-local` `tun-in` `mixed-in` `dns-in`）、规则顺序（`sniff` 在 `hijack-dns` 前）、`dns.final == dns-remote`、`route.final == select`；
  4. `Start`：去掉 `tun-in`、`mixed-in` 换随机端口，经 `engine` 真启动，查首帧分组，`Stop`。
- 测试：对 P1 × O1（最小：单节点、默认选项）走通四道检查；**反例**：在测试里故意构造「DNS 服务器 detour 指向空 direct」「selector default 不在成员」「含 `sniff` 入站字段」三个坏配置，断言分别被 `Start` / `Start` / 禁用键扫描抓住（证明闸门不是摆设）；`Env{GOOS:"android"}` 才含 `override_android_vpn`。
- Commit: `feat(kernel): 构建器骨架与四道测试闸门（黄金文件 / CheckConfig / 不变量 / 真启动）`

### Task U5：DNS 子系统 `internal/build/dns.go`
**Files:** 新建 `kernel/internal/build/dns.go`、`dns_address.go`、`dns_test.go`、`dns_address_test.go`；黄金文件 `testdata/golden/dns-*.json`。
- `ParseDNSAddress(addr string) (Server, error)`：表驱动（spec §3.4 第 1 行）：`1.1.1.1` / `1.1.1.1:53` / `udp://` → `udp`；`tcp://` → `tcp`；`tls://` → `tls`（默认 853）；`https://host[:port]/path` → `https`（默认 443、`/dns-query`）；`h3://` → `h3`；`quic://` → `quic`（默认 853）；`local` → `local`；`fakeip` → fakeip；`rcode://…` / `dhcp://…` / 未知 scheme → `option-invalid`。主机是域名 → 设 `domain_resolver: dns-direct`；IPv6 字面量（含 `[::1]:53`）正确切分。
- `BuildDNS(o, nodes) cfg.DNS`：服务器 `dns-remote`（`detour: select`）、`dns-direct`（无 detour）、`dns-local`、可选 `dns-fake`；`final: dns-remote`；`strategy` ← `ipv6-mode`；规则顺序：①直连域名（`remote-dns-address` 主机名（若是域名）+ 各节点 `server` 域名，去重、排序保证确定性）→ `dns-direct`；②fake DNS（`inbound: [tun-in]`、`disable_cache`）；③`enable-dns-routing` 为真时 `bypass` 规则逐条 → `dns-direct`、`block` 规则 → `predefined` NOERROR；④`cp.cloudflare.com` → `dns-remote`、`rewrite_ttl: 3000`；`remote/direct-dns-domain-strategy` 非空时才在对应规则写 `strategy`（弃用字段集中在一个函数，注释标明 1.16 前迁走）；`independent-dns-cache` 忽略并产生 warning。
- 测试：`dns_address_test.go` ≥ 25 行（含 IPv6、带端口、带路径、域名 / IP、大小写 scheme、非法端口、空串）；`dns_test.go` 对 O3 / O6 / O7 三组选项产出黄金文件并过 U4 的四道闸；**反例**：把 `dns-direct` 的 `detour` 改成 `direct` 的构建被 `Start` 闸拒绝；断言 `dns-remote.detour == "select"`；节点域名去重与排序稳定（打乱节点顺序输出不变）。
- Commit: `feat(kernel): 新 schema 的 DNS 构建（类型化服务器、默认出口、域名解析器）`

### Task U6：路由与规则 `internal/build/route.go`
**Files:** 新建 `kernel/internal/build/route.go`、`rules.go`、`route_test.go`；黄金文件 `testdata/golden/route-*.json`。
- 规则顺序固定（spec §3.4 第 7 行）：`sniff` → `protocol: dns` → `hijack-dns` → `inbound: [dns-in]` → `hijack-dns` → `port: [53]` → `hijack-dns` → `bypass-lan`（`ip_is_private: true` → `bypass`）→ 用户规则（`options.Rule.Matchers()` → `domain` / `domain_suffix` / `domain_regex` / `domain_keyword` / `ip_cidr` / `port` / `port_range` / `network` / `protocol`；`outbound: bypass` → `route` 到 `bypass`；`block` → `reject`；`proxy` → `route` 到 `select`）；`resolve-destination` 为真时在 `sniff` 之后插入 `{action: resolve, strategy: <ipv6-mode>}`；`final: select`；`auto_detect_interface: true`；`override_android_vpn` 仅 Android；`default_domain_resolver: dns-direct`。
- 智能分流数据沿用 `rules`（首期零 Dart 改动）。**末尾评估项（可选，不阻塞）**：用 `assets/rule-sets/*.srs` + 排除表在构建期编出本地 `.srs`、构建器只写 `rule_set`；以 U4 的真启动测试测「`rules` 内联 7.5k CIDR + 域名」与「本地规则集」两种形态的启动耗时与内存，写一段数据在提交信息里，结论决定是否另开任务。`block-ads` 为真时：本任务**不生成**任何远程规则集（返回 warning），界面隐藏在 U16 处理。
- 测试：O1 / O3 黄金；用户规则表驱动（每种前缀 / 目标一行）；规则顺序断言；`bypass-lan` 开关两态；`resolve-destination` 两态；`geoip:` 前缀在选项层已被拒（U3），这里再断言构建器遇到会报错；**反例**：把 `sniff` 放到 `hijack-dns` 之后的构建被不变量闸抓住；用 `cn_direct_rules.dart` 导出的全量清单（夹具文件 `testdata/rules/cn-direct.json`，由 Dart 测试生成，U16）跑一遍：生成配置通过 `CheckConfig` 与真启动，耗时 / 配置大小记录在测试日志。
- Commit: `feat(kernel): 新 schema 的路由与规则构建（规则动作、DNS 劫持、域名解析器）`

### Task U7：出站装配 `internal/build/outbounds.go`
**Files:** 新建 `kernel/internal/build/outbounds.go`、`tls.go`、`mux.go`、`graph.go`、`outbounds_test.go`；黄金文件 `testdata/golden/outbounds-*.json`。
- 装配（spec §5.2）：丢弃订阅自带的 `selector` / `urltest` / `direct` / `block` / `dns` 类型；预置 tag（`select` `auto` `direct` `bypass` `direct-fragment` `block`）冲突的节点重命名（追加 ` (2)` 并给 warning）；`§hide§` 节点不进 `select` / `auto` 成员；`select` = `[auto, …节点, …端点]`，默认值 = 含 `§default§` 的节点真实 tag 否则 `auto`；`auto` = `urltest`（`url` ← `connection-test-url`、`interval` ← `url-test-interval`、`idle_timeout` = interval×10）；预置出站：`direct`、`direct-fragment`（带 `tcp_fast_open: false`，保证它有选项因而可被 `detour`）、`bypass`；无可用节点 → `build-failed: profile has no usable outbound`。
- `tls.go`：`enable-fragment` 为真时对 `tls.enabled` 的出站设 `tls.fragment: true`、`record_fragment: true`；reality 出站跳过；其余 `tls-tricks` 键产生 warning 不生效（spec §5.6）。`mux.go`：`mux.enable` 为真时对 vmess / vless / trojan / shadowsocks 且无自带 `multiplex` 的节点注入（reality 节点跳过）。`graph.go`：`ValidateGraph(cfg)`（U4 不变量复用）。
- WARP 钩子：`PatchWarp(endpoints, o)` 先留空实现（U13 填），保证 `warp.enable=false` 时无影响。
- 测试：P1–P3 × O1 / O4 黄金；表驱动：tag 冲突重命名、隐藏节点、默认标记、仅一个节点、端点进成员、重复 tag；mux 与分片的有 / 无 / 已自带；**反例**：`§default§` 指向不存在节点的构造被不变量闸抓住。
- Commit: `feat(kernel): 出站装配（选择组、自动选择、预置出站、分片与多路复用）`

### Task U8：旧 schema 清洗 `internal/legacy`
**Files:** 新建 `kernel/internal/legacy/clean.go`、`clean_test.go`、`testdata/legacy/*.in.json` / `*.out.json`。
- `Clean(outbounds []map[string]any, endpoints []map[string]any) (outs, eps []map[string]any, warns []string)`，幂等：`type: wireguard` 出站 → `endpoints[]` 的 `wireguard` 端点（`server`/`server_port` → `peers[0].address`/`port`，`peer_public_key` → `peers[0].public_key`，`pre_shared_key`，`local_address` → `address`，`reserved` → `peers[0].reserved`，`mtu`，`allowed_ips` 缺省 `["0.0.0.0/0","::/0"]`）；丢弃 `type ∈ {block, dns, selector, urltest, direct}`；删除 `tls_fragment`、`tls.tls_tricks`、`domain_strategy`、`sniff*`、`sniff_override_destination`；保留 `tcp_fast_open`、`udp_fragment` 等仍有效字段；未知字段原样保留（不替上游猜）。
- 测试：每条规则一对 in / out 黄金文件；输出再喂 `Clean` 结果不变（幂等）；输出通过 `libbox.CheckConfig`（把清洗后的节点塞进最小配置）；wireguard 夹具的端点字段逐项断言。
- Commit: `feat(kernel): 旧 1.8 schema 订阅产物的读时清洗`

### Task U9：订阅解析管线 `internal/subscription`
**Files:** 新建 `kernel/internal/subscription/parse.go`、`sniff.go`、`clash.go`、`singbox.go`、`list.go`、`errors.go`、`parse_test.go`、`errors_test.go`、`testdata/subscriptions/**`（合成夹具，文件头注明）；`kernel/go.mod` 增加对 `clash2singbox` 的依赖已在 U1 完成。
- `func Parse(in []byte) (Profile, Warnings, error)` 与文件版 `ParseFile(outPath, inPath string, debug bool) error`（门面 `Core.Parse` 的实现，写出 `{"outbounds":[…],"endpoints":[…]}`）；识别顺序与规则见 spec §6.1：JSON（容忍注释；对象含 `outbounds` / `endpoints` / 单出站对象 / **出站数组**）→ `legacy.Clean`；Clash（顶层 `proxies`；`proxies: []` → `no-outbounds:`；转换用 `convert.Clash2sing(clash, model.SINGLATEST)`，不引入其 `Patch` 模板）；URI 列表（base64 / urlsafe、有无 padding、CRLF、BOM；逐行交给 `internal/uri`，单行失败记 warning）；全部失败带首个原因。tag 去重、空 tag 补 `<type>-<序号>`。错误码前缀 `format-unknown:` / `no-outbounds:` / `uri-invalid:` / `build-failed:`（`errors.go` 定义常量 + `Is` 辅助）。
- 本任务里 URI 转换只接一个注册表接口 `uri.Convert(line string) (Outbound, error)`（U10 / U11 填充；本任务用一个只认 `ss://` 的最小实现跑通管线测试）。
- 测试（合成夹具，spec §7.2）：Clash（ss / vmess / vless-reality / trojan / hysteria2 / tuic / wireguard、带 `proxy-groups` 与 `rules`、`proxies: []`、YAML 锚点 / 合并键）；sing-box JSON（完整配置、纯数组、单出站、1.8 时代形态）；HTML 页面与空输入的错误码；部分节点损坏 → 部分成功 + warning 计数；5000 节点性能断言（耗时与分配上限，防回退）；**幂等**：`Parse(Parse(x))` 不变；输出不含 `inbounds` / `dns` / `route`。
- Commit: `feat(kernel): 订阅解析管线（sing-box JSON / Clash YAML / URI 列表）与稳定错误码`

### Task U10：URI 转换 A —— vmess / vless / trojan / shadowsocks
**Files:** 新建 `kernel/internal/uri/uri.go`（注册表与公共工具：base64 宽松解码、查询参数、名称解码）、`vmess.go`、`vless.go`、`trojan.go`、`shadowsocks.go`、`transport.go`（ws / grpc / httpupgrade / h2 / tcp-http 的传输参数）、`tls.go`（`security=tls|reality`、`sni`、`alpn`、`fp`、`pbk`、`sid`、`allowInsecure`）、各自的 `_test.go`、`testdata/uri/*.txt`。
- 行为：vmess 同时认 base64-JSON（`v`、`ps`、`add`、`port`、`id`、`aid`、`scy`、`net`、`type`、`host`、`path`、`tls`、`sni`、`alpn`、`fp`）与 URL 形式；vless 含 `flow` / reality / `encryption=none`；trojan 含 ws / grpc；ss 同时认 SIP002（含 `plugin=obfs-local;obfs=…` / `v2ray-plugin`）与旧式整体 base64、IPv6 地址；名称（`#fragment`、`ps`）做 percent / base64 解码；不支持的 `net` / `security` 组合 → `uri-invalid:`（不静默降级）。输出为 sing-box 出站 `map[string]any`。
- 测试：每个 scheme 一张表驱动（≥ 10 行 / scheme，覆盖 spec §7.2 的形态）+ 往返性质（`Convert` 的输出再过 `legacy.Clean` 不变）+ 把输出塞进最小配置跑 `libbox.CheckConfig`（`kernel/internal/uri/gate_test.go`）。
- Commit: `feat(kernel): URI 转换（vmess / vless / trojan / shadowsocks）`

### Task U11：URI 转换 B —— hysteria2 / hysteria / tuic / anytls / socks / http / ssh / wireguard
**Files:** 新建 `kernel/internal/uri/hysteria2.go`、`hysteria.go`、`tuic.go`、`anytls.go`、`socks.go`、`http.go`、`ssh.go`、`wireguard.go`、各自 `_test.go`、`testdata/uri/*.txt`、`gate_test.go` 增补。
- 行为：`hysteria2://` / `hy2://`（`obfs` / `obfs-password` / `pinSHA256` / `insecure` / `sni` / `mport` 端口跳跃 → `server_ports`）；`hysteria://`（`auth` / `upmbps` / `downmbps` / `obfs` / `protocol`）；`tuic://`（`uuid:password@`、`congestion_control`、`udp_relay_mode`、`alpn`、`sni`、`allow_insecure`）；`anytls://`；`socks://` / `socks5://`（含 base64 用户信息）；`http://` / `https://` 作为代理出站（**仅限列表行里的显式代理 URI**，不把订阅 URL 本身当节点）；`ssh://`；`wg://` / `wireguard://` → `endpoints`。
- 测试：同 U10 的三项（表驱动、往返、`CheckConfig`）；端口跳跃与 IPv6 的边界行。
- Commit: `feat(kernel): URI 转换（hysteria2 / hysteria / tuic / anytls / socks / http / ssh / wireguard）`

### Task U12：`core` 门面、gomobile 绑定、API 快照、构建收口
**Files:** 新建 `kernel/core/core.go`（静态函数：`Setup`、`Version`、`GoVersion`、`Parse`、`BuildConfig`、`CheckConfig`、`GenerateWarpConfig`（U13 前返回 `unsupported`）、`NewEngine`）、`kernel/core/engine.go`（把 `engine.Engine` 包成 gomobile 友好的类型：`Engine`、`Platform`、`LocalDNS`、`DNSCall`、`InterfaceListener`、`EngineHandler`、`GroupsHandler`、`StatsHandler`、`LogHandler`、`Subscription`、`SetupOptions`、`Func`）、`kernel/core/core_test.go`、`kernel/api/java-api.txt`；修改 `tools/kernel/build-android.sh`（放行门增加「`javap -public` 与 `kernel/api/java-api.txt` 零差异」，`UPDATE_API=1` 重生成）、`.github/workflows/ci.yml`（kernel job 增加构建脚本 `--self-test`）。
- `BuildConfig(profilePath, optionsJSON)`：读 profile → `legacy.Clean` → `options.Decode` + `Validate` → `build.Build` → 返回 JSON 文本；`Parse(outPath, inPath, debug)` → `subscription.ParseFile`。签名与旧 `Mobile.parse` / `Mobile.buildConfig` 同形，Kotlin 迁移只改 import 与类名。
- 门面不暴露 slice / map；复杂载荷全是 JSON 字符串（spec §4.2）。
- 测试：`core_test.go` 端到端（Go 内）：`Parse` 一份合成订阅 → `BuildConfig` → `CheckConfig` → `NewEngine` + fake Platform `Start`（去掉 tun）→ 分组首帧；`Parse` 与 `BuildConfig` 对旧形态订阅（U8 夹具）同样走通。构建脚本放行门：真实 `bind` 一次，`javap` 快照零差异、`.so` 16 KB 对齐、`proguard.txt` 规则正确。API 快照纳入评审。
- Commit: `feat(kernel): core 门面与 gomobile 绑定，API 快照与构建放行门`

### Task U13：WARP（账号注册 + 端点生成）
**Files:** 新建 `kernel/internal/warp/register.go`、`endpoint.go`、`warp_test.go`；修改 `kernel/internal/build/outbounds.go`（填 `PatchWarp`）、`kernel/core/core.go`（`GenerateWarpConfig`）。
- `Register(ctx, client *http.Client, licenseKey string) (Account, error)` 与 `Delete(ctx, client, accountID, token)`：对 Cloudflare 的设备注册接口（POST 注册、PUT 绑定 license、DELETE 旧设备）**自己实现**；`client` 可注入，测试用 `httptest`。`GenerateWarpConfig(licenseKey, accountID, token)` 返回与旧 Dart 解析兼容的 JSON：`{"account-id","access-token","log","config":{"private-key","local-address-ipv4","local-address-ipv6","peer-public-key","client-id"}}`。
- `endpoint.go`：`Endpoint(cfg WireguardConfig, o options.Warp) cfg.Endpoint`：`type: wireguard` 端点，`address`（v4/24 + v6/128）、`private_key`、`mtu: 1280`（有 detour 时 -50 以内保持旧行为的 1330-50）、`peers[0]`（`address` / `port` 取 `clean-ip` / `clean-port` 或默认 Cloudflare 入口、`public_key`、`allowed_ips`、`reserved` ← `client-id` 的前 3 字节）；`mode == warp_over_proxy` → `detour: select`；`proxy_over_warp` → 其它出站 `detour` 指向该端点（仅对没有自带 `detour` 的节点）。**噪声（`noise*`）不生效**，产生 warning。
- 若本任务因 Cloudflare 接口变化 / 条款原因暂缓：保持 `GenerateWarpConfig` 返回 `unsupported:`，并在 U16 隐藏整段 WARP 界面（spec §5.6），不留半截。
- 测试：`httptest` 模拟三种响应（成功、license 无效、网络失败）；返回 JSON 的键集合与旧契约一致（断言键名）；端点黄金文件 O5（两种模式）过四道闸；`proxy_over_warp` 不覆盖节点自带 `detour`。
- Commit: `feat(kernel): WARP 账号注册与 WireGuard 端点生成`

### Task U14：Kotlin 绑定层 A —— 运行时、平台、DNS、网络监听、TUN
**Files（Kotlin，路径相对 `android/app/src/main/kotlin/com/clashmiao/clashmiao/`）:** 新建 `engine/CoreKernelRuntime.kt`（取代 `LibboxKernelRuntime.kt`，删除旧文件）、`engine/CorePlatform.kt`（取代 `LibboxHost.kt`）、`engine/TunSpec.kt`（`TunSpec.parse(json)`：用 `org.json`，字段见 spec §4.3）；修改 `engine/SystemDnsBridge.kt`（实现 `LocalDNS`，`DNSCall` 替 `ExchangeContext`）、`engine/NetworkWatcher.kt`（`InterfaceListener.update(name, index, expensive, constrained)`）、`engine/TunnelService.kt`、`engine/PlainService.kt`、`engine/KernelHost.kt`（只改类型名与构造）、`engine/KernelStartSequence.kt`、`core/LibboxAdapters.kt`（删除；`asAndroidPrefix` 改为 `String` CIDR 版放进 `core/NetAdapters.kt`）、`Application.kt`（仍 `Seq.setContext`）；`android/app/build.gradle.kts`（aar 文件名、依赖不变）；`android/app/libs/`（换入 U12 产物，**本地**，不入库，沿用 `bin/fetch-libcore.sh` 流程）；测试 `engine/KernelStartSequenceTest.kt`（更新）、`engine/TunSpecTest.kt`（新）、`engine/NetworkWatcherTest`（如已有则更新）。
- `CoreKernelRuntime : KernelRuntime`：`bootstrapOnce()` → `Core.setup(SetupOptions(base, working, temp, debug, logMaxLines = 300, memoryLimited = !Prefs.Engine.disableMemoryLimit))`；`start()` 的步骤改为 `bootstrap → createEngine → buildConfig → prepareRuntime(网络监听 arm) → startEngine`，**`KernelStartOps` 收敛为 5 个方法**（删除 `newService` / `startService` / `bindCommandServer` 拆分，合并为 `startEngine(content)`），每个阻塞调用后检查 `ctx.cancelled`；`Engine.start` 的错误前缀映射 `FailureCode.CreateService` / `StartService`，`createEngine` 失败映射 `StartCommandServer`（保持 `FailureCode` 枚举不变）。重载（`reload == true`）不再等待固定 1 s：直接再次 `engine.start`（libbox 内部先关旧实例）；`settleAfterReload` 删除，并把行为变化写进测试注释，U17 真机验证重载稳定性。`teardown(soft=true)`：`engine.stop()` + 关闭 tun fd；`soft=false`：再 `engine.close()` + `NetworkWatcher.disarm()` + 释放 `Seq` 引用。`SystemProxyStatus` 由 `EngineHandler` 的三个方法提供。`onIdleModeChanged` → `engine.pause()` / `wake()`。
- `TunnelService.buildTunFd` 改读 `TunSpec`：`dns_mode == "disabled"` 不 `addDnsServer`，否则逐个添加 `dns_servers`；路由 / 地址 / 应用过滤逻辑不变；`wireSystemProxy` 读 `http_proxy`。
- `TunInbounds.keepLast` 保留（构建器已保证唯一，留作防御）。
- 测试：`KernelStartSequenceTest` 改用新的 5 步 `KernelStartOps` 假实现，**取消检查点与失败码映射的既有断言原样通过**；`TunSpecTest`：spec §4.3 示例 JSON 解析、缺字段容错、`dns_mode` 三态；`CoordinatorCoreTest`、`KernelCoordinatorTest`、`KernelExecutorTest`、`KernelSnapshotTest` **不改断言**通过；`cd android && ./gradlew --offline :app:testDebugUnitTest` 全绿；`flutter build apk --debug --target-platform android-arm64` 通过（需要本地 aar）。
- Commit: `refactor(android): 内核绑定层改用自有门面——运行时、平台回调、DNS、网络监听、TUN`

### Task U15：Kotlin 绑定层 B —— 流、命令、桥接
**Files（Kotlin）:** 新建 `engine/CoreStream.kt`（取代 `LibboxCommandStream.kt`，删除旧文件）；删除 `engine/OutboundSnapshot.kt`（线格式已由 Go 产出）；修改 `bridge/StreamBridge.kt`（分组 / 统计订阅者直接透传 Go 给的 JSON 字符串；`GROUP_INFO_ONLY` 流先确认 Dart 是否仍订阅 `com.clashmiao.app/active-groups`：有则与全量流同源、无则删除通道并同步 `BoxApi` / Dart 常量——这一步先 `grep` 取证再决定，结论写进提交信息）、`bridge/PigeonBridge.kt`（`validateConfig` → `Core.parse`；`urlTest` → `engine.urlTest`；`generateFullConfig` → `Core.buildConfig`；`setup` 删除 `Mobile.setup()` 调用）、`bridge/MethodBridge.kt`（`Core.generateWarpConfig`）、`engine/AndroidCoordinatorPlatform.kt`（`OutboundSelector` → `engine.selectOutbound`）、`engine/ForegroundNotice.kt`（自带 `formatBytes`）、`engine/LogBuffer.kt` 接线（`SubscribeLogs` 或 `Platform.writeLog` 二选一，以 U2 的实现为准）；测试 `engine/CoreStreamTest.kt`（由 `LibboxCommandStreamTest` 迁移）、`engine/ForegroundNoticeFormatTest.kt`（新，`formatBytes`）、`OutboundSnapshotTest` 的线格式断言迁移到 Go（U2 的 `groups-first.json`），Kotlin 侧改为对 `StreamBridge` 透传做一次「JSON 原样到达 sink」的测试。
- `CoreStream`：沿用旧 `LibboxCommandStream` 的代际 / 重试语义（`MAX_ATTEMPTS = 10`、线性退避、候选连接被 `disconnect` 抛弃、不留 ghost client），把 `Client` 接口的生产实现换成 `Engine.subscribeGroups/Stats`；`InstanceFollower` 不改。
- 测试：`CoreStreamTest` 把旧测试的全部行为用例（重试、代际、断开时丢弃候选、`close` 释放）迁过来，断言不放宽；`cd android && ./gradlew --offline :app:testDebugUnitTest` 全绿；`flutter build apk --release --target-platform android-arm64` 通过；`unzip -l` 抽查 APK 里 `lib/arm64-v8a/libclashmiao.so` 存在且旧 `libbox.so` 已不在。
- Commit: `refactor(android): 分组 / 统计 / 日志流与选择、测速、订阅解析入口接到自有门面`

### Task U16：Dart 侧收口与跨语言契约
**Files:** 修改 `lib/domain/config/data/runtime_config_builder.dart`、`lib/domain/config/data/default_config_options.dart`、`lib/domain/profile/data/profile_repository.dart`、`lib/domain/config/model/dns_defaults.dart`、`lib/features/config/presentation/config_options_page.dart`、`lib/features/home/presentation/quick_settings_modal.dart`、`lib/features/home/presentation/experimental_feature_notice_dialog.dart`、10 种语言的 slang 文案（`lib/core/localization/**` 源 JSON，再 `bin/regen-i18n.sh`）；新增 `test/domain/config/data/options_fixture_export_test.dart`、`test/domain/config/data/cn_direct_fixture_export_test.dart`；更新 `test/domain/config/data/runtime_config_builder_test.dart`、`default_config_options_test.dart`、`test/domain/profile/data/profile_repository_test.dart`；`kernel/testdata/options/*.json`、`kernel/testdata/options/keys.txt`、`kernel/testdata/rules/cn-direct.json`（导出产物，入库）、`kernel/internal/options/dart_fixture_test.go`。
- `RuntimeConfigBuilder`：删除旧格式的 `_ensureDnsSelfSufficient` / `_overrideRemoteDnsAddress` 与 `remoteDnsAddress` 参数（内核重建 dns，它们对运行无效且是旧格式）；保留剥 `mixed` / `tun`、`hideSubscriptionInfoOutbounds`、`_injectMux`；`remoteDnsOverride` 改由 `getDefaultConfigOptions(advancedConfig:)` 写入 `remote-dns-address`（顺带让它真的生效；它目前没有界面入口，不新增入口）。`runtimeSelectorDefaults`：默认值改为「含 `§default§` 的节点真实 tag，否则 `auto`」，与 spec §3.4 第 17 行一致（同步更新测试）。
- `ProfileRepository._ensureMinimalProfileStructure`：不再写旧格式 `dns.servers` 与带 `inet4_address` / `sniff` 的标准 inbounds；保留「`outbounds` 存在 + `direct`」所需的最小修复；`_normalizeAndWrite` 的「JSON 直通」分支保留，但直通前要求 `outbounds` 非空且**不含** `type: wireguard` 出站 / `dns` / `block` 出站（含则走 `validateConfig` 清洗），避免旧形态直通落盘。
- 界面能力闸（spec §5.6）：隐藏 TLS 分片的 size / sleep、TLS padding、mixed-case SNI、WARP 噪声四项、`block-ads`（以及 U13 未完成时的整段 WARP）；**只隐藏入口，不改持久化值**（备份导出导入、`network_settings` 的校验不动）；`experimental_feature_notice_dialog.dart` 里对应的判定同步去掉。新文案（若有）10 种语言补齐。
- 跨语言契约：
  - `options_fixture_export_test.dart`：对一组设置矩阵（默认 / VPN 智能 / 仅线路全局 / fake DNS + DNS 路由 + 绕过局域网 / mux + 分片 / WARP 两模式 / 各远程 DNS 地址形态 / IPv6 三种 / 允许局域网）调用 `getDefaultConfigOptions`，与 `kernel/testdata/options/*.json` 比对（`UPDATE_GOLDEN=1` 重写）；同时把键集合写成 `keys.txt`。
  - `dart_fixture_test.go`：加载全部 Dart 导出夹具并 `Decode`——**Dart 产生任何 Go 不认识的键即失败**；反向：Go 已知键集合与 `keys.txt` 一致，缺任何一个 Dart 不再产生的键也要在评审里被看见。
  - `cn_direct_fixture_export_test.dart` 产出 U6 要用的 `cn-direct.json`。
  - Dart 构建出的 `runtime-config.json`（P1–P7）全部喂给 Go `BuildConfig`，禁用键扫描为零。
- 测试：`flutter test --no-pub`、`flutter analyze --fatal-warnings`、`dart format` 检查全绿；`cd kernel && go test ./...` 绿（含 Dart 夹具）；架构测试绿。
- Commit: `refactor(config): Dart 侧移除旧格式 dns / inbounds 写入，按新内核能力收口界面，新增跨语言选项契约`

### Task U17：真机验收、文档与发布
**Files:** 修改 `docs/ARCHITECTURE.md`（「内核版本」「构建配置」章节改成新内核与新绑定层；**不出现上游名**）、`docs/ROADMAP.md`（内核版本一栏）、`CHANGELOG.md`、`bin/fetch-libcore.sh`（默认 `TAG` → `libcore-v1.14.3-r1`；Android 资产名保持 `libcore.aar`）、`.github/workflows/ci.yml` 与 `release.yml`（`LIBCORE_TAG`）、`README.md`（如有内核版本表述）；不改 `tools/libcore/**`（回滚工具）。
- 发版前置：`tools/kernel/build-android.sh` 真实构建；**经用户确认后**再 `gh release create libcore-v1.14.3-r1`，上传 `libcore.aar` 与 `.sha256`（只上传 Android 资产；桌面 / iOS 仍用旧 tag 的资产，`fetch-libcore.sh` 为它们保留旧 `TAG` 常量）。
- 真机与模拟器清单（spec §7.3，**先录基线**：现网 1.8.9 包在同一台设备同一订阅上的连接耗时、稳态 RSS、`dumpsys connectivity` VPN 网络数、关键站点可达性，存 scratchpad；再装新包对比）：
  1. Redmi K40（serial `75fa01d6`，USB）：`flutter build apk --release --target-platform android-arm64` → `adb -s 75fa01d6 install -r`（**绝不先卸载**）；订阅 / 激活 / 手选 / 模式保留；连接断开 × 20；VPN ↔ 仅线路切换（必须换 Service 类）；Wi-Fi ↔ 蜂窝切换后重载；分应用代理；系统代理开关；手选 → 断开 → 重连的选择重放；分组测速；健康探测在黑洞下进入 degraded；App 被杀后冷启动 attach；磁贴启停；开机自启；Doze 暂停 / 唤醒；`grpc` / `reality` / `hy2` / `tuic` / `ss` 各一个真实节点逐协议连通（用户提供的测试订阅，不回显链接）；稳态 RSS 对比；去掉 `sniff_override_destination` 的影响（若干域名站点对比）；重载不再等待 1 s 后的稳定性（连续 20 次网络切换）。
  2. 16 KB 模拟器 `ClashMiao_16k_API36`（`google_apis_ps16k`）：APK 里 `lib/arm64-v8a/*.so` 逐段 `2**14`；`zipalign -c -P 16 -v 4`；安装、启动、连接 / 断开 20 次无崩溃；logcat 无对齐 / `dlopen` 告警。
  3. 证据：logcat 里 `epoch / attempt / desired / source / version` 序列、`dumpsys connectivity`、截图，存 scratchpad；系统 VPN 授权弹窗不得代点。
- 验收门槛：清单全绿；稳态 RSS 不高于旧内核 +15%（否则回到 spec §5.5 调参）；发现缺陷先在 Go 侧补测试再修。
- 文档：`docs/ARCHITECTURE.md` 增加「内核模块 `kernel/`」小节（分层、门面 API、构建、闸门、升级流程 runbook：改 `go.mod` → 跑三道闸 → 更新 `api/java-api.txt` → 真机清单）。
- 测试 / 检查：`tools/kernel/check-public-names.sh` 通过；`bin/check-public-links.sh` 通过；全量 `flutter test --no-pub` + Kotlin 单测 + `go test ./...`。
- Commit: `docs(arch): 内核改为官方 sing-box 1.14 + 自有 Go 模块，更新发版与升级流程`

---
## 备注
- **任务粒度**：U4–U8 可并行（U4 完成后）；U10 / U11 可并行；U14 与 U16 可并行（U16 不依赖 aar）。每个任务提交前都要跑 `go test -race ./...`（Go 任务）或对应 Kotlin / Dart 检查，以及守卫脚本。
- **桌面 / iOS**：不在本计划内；`kernel/` 的 `engine` 与 `internal/*` 已按「核心 + 门面」分层，后续只加 `desktop`（cgo 导出）与 `apple`（gomobile ios/macos）门面，另立设计。
- **回滚**：保留 `tools/libcore/build-android.sh`、Release tag `libcore-v1.8.9-16k` 与旧 Kotlin 绑定层的 git 历史；回滚 = 还原 U14 / U15 提交并换回旧 aar。
