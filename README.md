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

| 文件 | 适用 |
|---|---|
| `ClashMiao-Android-arm64-v8a-*.apk` | **绝大多数手机选这个**（2017 年后机型基本都是 arm64） |
| `ClashMiao-Android-armeabi-v7a-*.apk` | 老旧 32 位设备 |
| `ClashMiao-Android-x86_64-*.apk` | 模拟器 / x86 平板 |
| `ClashMiao-Android-universal-*.apk` | 不确定架构时用，体积约为上面的 3 倍 |

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

### Android

直接安装 APK 即可（需在系统里允许"安装未知来源应用"）。首次连接会请求
VPN 权限，这是 Android 建立 TUN 隧道的必要授权。

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
- **代理核心**: sing-box（通过 [libcore](https://github.com/SagerNet/sing-box) gomobile/CGo 绑定）

架构细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 编译

### 前置要求

- Flutter 3.41+
- Go 1.21+（重新编译 sing-box 核心时需要）
- Xcode 15+（iOS / macOS）
- Android NDK + SDK

### sing-box 核心

预编译动态库通过 GitHub Release（tag `libcore-v<sing-box-version>`）分发。fresh clone 后跑：

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

CI 同样走这个脚本。升级 sing-box 版本时另起一个 `libcore-v*` tag 上传新二进制。

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

测试覆盖：684 个 unit/widget + Android 模拟器 E2E。翻译完整性、连接前置校验、
黑洞检测等关键路径都有回归测试锁定。

## 许可证

GPL-3.0。
