# 喵速 (ClashMiao)

[![CI](https://github.com/luuuuke88/clashmiao/actions/workflows/ci.yml/badge.svg)](https://github.com/luuuuke88/clashmiao/actions/workflows/ci.yml)

跨平台代理客户端，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心。

## 平台支持

| 平台 | 状态 | 流量接管方式 |
|------|------|---------|
| Android | ✅ 可用 | VpnService（TUN，**全局接管**） |
| macOS | ✅ 可用 | 系统代理（见下方"桌面端的接管范围"） |
| Windows | ✅ 可用（已真机验证） | 系统代理（同上） |
| Linux | 🟡 可出包 / 待真机验证 | 系统代理（同上） |
| iOS | 🟡 代码就绪，未上真机 | NetworkExtension；阻塞于付费 Apple 开发者账号 |

### ⚠️ 桌面端的接管范围

桌面端（macOS / Windows / Linux）**只做到系统代理级接管，不是全局 TUN**。
这意味着：

- ✅ 遵循系统代理设置的程序（浏览器、多数应用）会走隧道
- ❌ **不遵循的程序会直连并暴露你的真实 IP** —— 部分游戏、命令行工具、
  自带代理设置的客户端都属于这一类

这是当前架构的边界，不是 bug。桌面端因此**不提供 VPN(TUN) 服务模式**——
仓库里没有 wintun 驱动、macOS 也没有网络扩展权限，给出这个选项只会让连接必定
失败。需要全局接管请用 Android 端。

详见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 安装

从 [Releases](https://github.com/luuuuke88/clashmiao/releases) 下载对应平台的包。
每个 release 都附 `SHA256SUMS.txt` 可校验完整性：

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing      # Linux
shasum -a 256 -c SHA256SUMS.txt --ignore-missing  # macOS
```

### Android

`ClashMiao-Android-arm64-v8a-*.apk` —— 只有这一个包。

**需要 Android 8.0（API 26）及以上、64 位 ARM 设备**，也就是 2017 年之后的
绝大多数手机。32 位（armeabi-v7a）与 x86_64 不再提供：前者在新的 ARMv9 芯片上
已经无法执行，后者只用于模拟器。Android 7.x 与 32 位设备安装会失败并提示
「应用未安装」。

需在系统设置里允许「安装未知来源应用」。首次连接会请求 VPN 权限，这是建立
TUN 隧道的必要授权。

### Linux

- `clashmiao_*_amd64.deb` —— Debian / Ubuntu：`sudo apt install ./clashmiao_*.deb`
- `ClashMiao-Linux-x86_64-*.tar.gz` —— 其它发行版：解开直接跑 `./clashmiao`

### macOS

安装包**未经 Apple 公证**（需要付费开发者账号），首次打开会被 Gatekeeper 拦下，
提示"无法验证开发者"。通过方式：

1. 在「访达」里**右键点击** ClashMiao.app → 选择「打开」
2. 弹窗里再点一次「打开」

之后就能正常双击启动了。dmg 是 universal 包，Intel 和 Apple Silicon 都能原生跑。

### Windows

安装包**未经代码签名**，SmartScreen 会弹「Windows 已保护你的电脑」。通过方式：

1. 点击「更多信息」
2. 点击「仍要运行」

## 特性

- 🐱 简洁现代的 UI 设计（Material 3 + 动态颜色）
- 🔗 订阅管理：支持 base64 / clash / singbox 格式
- ⚡ 延迟测试与自动选择
- 📊 实时流量统计
- 🌐 智能 / 全局模式切换（智能模式内置完整的中国大陆 IP 段与域名直连规则）
- 🩺 连接健康探测：检测到"已连上但实际不通"时会明确告知，而不是一直显示已连接

## 技术栈

- **UI**: Flutter 3.41+
- **状态**: Riverpod (hooks_riverpod)
- **路由**: go_router
- **代理核心**: [sing-box](https://github.com/SagerNet/sing-box)。Android 用仓库内的 Go 模块 `kernel/`（官方 sing-box 1.14.3 + 自有门面，gomobile 绑定）；桌面与 iOS 暂用预编译库

架构细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 编译

### 前置要求

- Flutter 3.41+
- Go 1.25+（改 `kernel/` 或重新编译 sing-box 核心时需要；Android 发布构建由脚本自带固定版本的 Go）
- Xcode 15+（iOS / macOS）
- Android NDK + SDK

### sing-box 核心

预编译库通过 GitHub Release 分发：Android 的 aar 用 tag `libcore-v1.14.3-r1`（自有内核模块构建），桌面与 iOS 暂用 `libcore-v1.8.9-16k`。fresh clone 后跑：

```bash
bin/fetch-libcore.sh          # 默认拉 Android + 当前 host 平台的 lib
bin/fetch-libcore.sh all      # 拉全部 5 个平台
bin/fetch-libcore.sh ios      # 单独拉 iOS xcframework
```

放到正确路径：
- `android/app/libs/libcore.aar`
- `libcore/bin/libcore.dylib`（macOS）
- `ios/Frameworks/Libcore.xcframework/`（iOS，zip 解开）
- `windows/libs/libcore.dll`
- `linux/libs/libcore.so`

CI 同样走这个脚本（`ANDROID_LIBCORE_TAG` 与 `LIBCORE_TAG` 分别指定 Android 与其它平台的 tag）。升级 sing-box 版本时另起一个 tag 上传新二进制。

#### 构建与验证 Android 内核（`kernel/`）

```bash
tools/kernel/gotest.sh              # Go 侧唯一合法的验证入口（别用裸 go test）
tools/kernel/build-android.sh       # 真实 gomobile 构建：产物 build/kernel/libcore.aar（+ .sha256）
```

构建参数（build tags、链接参数）只在 `tools/kernel/env.sh` 一处定义。构建脚本固定 Go / NDK / gomobile 版本，校验 16 KB 页对齐、proguard 规则与 Java API 快照（`kernel/api/java-api.txt`）。分层、门面接口与升级流程见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 的「内核模块 `kernel/`」。

#### 重编旧 Android 内核（仅用于回滚）

以下是旧内核（sing-box 1.8.9）的可复现重编流程，保留作回滚工具；日常开发用上面的 `tools/kernel/`。

Android 15 起出现 16 KB 内存页设备，Google Play 也要求所有原生库支持 16 KB 页。
内核库 `libbox.so` 必须让所有 LOAD 段按 16 KB（`2**14`）对齐，否则在这类设备上加载失败。
`tools/libcore/build-android.sh` 会从固定的内核上游提交重编 `libcore.aar`：

内核上游仓库地址不放在公开仓库里：构建前设置环境变量 `LIBCORE_UPSTREAM_REPO`，或把地址写进不入 git 的 `tools/libcore/upstream.local`（一行）。脚本克隆后会校验源码提交与固定的提交一致。

```bash
tools/libcore/build-android.sh                       # 产物：build/libcore/libcore.aar + .sha256
REFERENCE_AAR=android/app/libs/libcore.aar \
  tools/libcore/build-android.sh                     # 顺便与现有 aar 对比 Java 公共 API
tools/libcore/build-android.sh --self-test           # 校验逻辑的故障注入自测（不联网、不构建）
```

固定内容（都写在脚本顶部）：

| 项 | 值 |
| --- | --- |
| 内核源码 | 内核上游仓库提交 `5098951`（sing-box 1.8.9 分支，go.mod / go.sum 锁定全部依赖） |
| Go | 1.22.12（1.22 系列最后一个补丁版：与原发布版 1.22.0 语言、运行时语义相同，另含标准库的安全修复；脚本自行下载并校验 sha256，`GOTOOLCHAIN=local`） |
| gomobile / gobind | v0.1.1（绑定运行时 v0.1.3 由 go.mod 决定） |
| NDK | r28c `28.2.13676358`，另加 `-extldflags=-Wl,-z,max-page-size=16384` |
| JDK | 17（保证 `classes.jar` 与发布版逐字节一致） |
| build tags | `with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc` |
| 目标 | `-androidapi=21`，四个 ABI：arm64-v8a / armeabi-v7a / x86 / x86_64 |

脚本在固定路径 `/tmp/clashmiao-libcore-build` 里克隆和构建，每次开始前清空、结束后删除。
`BUILD_ROOT` 可以改位置，但因为要递归清空，限制很严：必须是绝对路径、最后一级必须叫 `clashmiao-libcore-build`、不能是符号链接，
根目录和 `$HOME` 的各种写法都会被拒绝；互斥锁是同级的 `<路径>.lock`，尾斜杠等等价写法共用同一把锁。
构建完成后自动校验，任何一项不符都会非零退出，且在全部通过之前不会写输出目录：

- NDK 的 `source.properties` 里 `Pkg.Revision` 必须正好是 `28.2.13676358`；
- 每个 ABI 的所有 LOAD 段对齐 ≥ `2**14`；
- `go version -m` 里的 Go 版本、build tags 和锁定依赖版本；
- `classes.jar` 的 sha256 必须与发布版一致。用别的 JDK 编出来字节码会不同，默认直接失败；
  确需放行，须同时给 `REFERENCE_AAR` 并设 `ALLOW_JDK_MISMATCH=1`，且 `javap -public` 对比零差异才通过
  （两侧的 `javap` 输出都要成功且非空）。

依赖：Android SDK 中装好对应 NDK（`sdkmanager "ndk;28.2.13676358"`）、JDK 17、git、curl。
macOS 自带的 Bash 3.2 可以直接运行（含 UTF-8 环境）。

**可复现性**：构建路径会写进 Go 的 buildinfo，所以路径是固定的。同一台机器、同一套固定工具链下，
两次全新构建得到的四个 `libbox.so`、`classes.jar` 以及整个 `libcore.aar` 都逐字节相同（Go 1.22.12 / NDK r28c / JDK 17 实测）。
这个保证只在构建路径、主机平台和工具链都不变时成立；改 `BUILD_ROOT`、换 Go 补丁版或 NDK，哈希都会不同。
不同主机平台（如 Linux 与 macOS）编出的 C 胶水部分是否逐字节一致，尚未验证。

产物替换到 `android/app/libs/libcore.aar` 即可本地使用。正式分发时，把它和其余平台未变的二进制一起上传到新的
`libcore-v*` Release，再同步修改 `bin/fetch-libcore.sh`、`.github/workflows/ci.yml`、
`.github/workflows/release.yml` 里的 `LIBCORE_TAG`。

iOS / macOS 不受 Android 页大小影响；同一份源码也能编 xcframework（`gomobile bind -target ios`），本脚本不涉及。

### 跑起来

```bash
flutter pub get
flutter run                 # 自动检测设备
flutter run -d emulator-5554  # 指定 Android 模拟器
flutter run -d macos          # macOS 桌面
```

## 测试

```bash
bash bin/test-unit.sh    # unit + widget（无设备需求）
bash bin/test-all.sh     # 加 format + analyze + 可选 E2E
bash bin/test-e2e.sh     # Android emulator E2E（需 adb 可见设备）
```

测试覆盖：unit / widget + Android 模拟器 E2E。翻译完整性、连接前置校验、
黑洞检测等关键路径都有回归测试锁定。

## 许可证

GPL-3.0。
