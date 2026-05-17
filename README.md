# 喵速 (ClashMiao)

[![CI](https://github.com/luuuuke88/clashmiao/actions/workflows/ci.yml/badge.svg)](https://github.com/luuuuke88/clashmiao/actions/workflows/ci.yml)

跨平台代理客户端，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心。

## 平台支持

| 平台 | 状态 | 实现方式 | 验证情况 |
|------|------|---------|---------|
| Android | ✅ 可用 | VpnService + `libcore.aar` | tun0 接管流量、模拟器 ping 通、订阅 / ss-uri 都能加载 |
| macOS | ✅ 可用 | FFI + `libcore.dylib` + 系统代理 | 154.83.95.148 → 45.202.255.184 验证通过，烟雾 36s 跑完 |
| iOS | 🟡 代码脚手架完成 | NetworkExtension PacketTunnelProvider | 阻塞：Apple Developer 账号 + 真机签名，见 `ios/SCAFFOLDING.md` |
| Windows | 🟡 lib 就绪 / 待真机验证 | FFI + `libcore.dll` (LFS) + 系统代理 (Wininet) | `flutter build windows` 可出 release，需 Windows 机器走一次连接 smoke |
| Linux | 🟡 lib 就绪 / 待真机验证 | FFI + `libcore.so` (LFS) + 系统代理 (GNOME 手动设) | `flutter build linux` 可出 release，需 Linux 机器走一次连接 smoke |

详见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 特性

- 🐱 简洁现代的 UI 设计（Material 3 + 动态颜色）
- 🔗 订阅管理：支持 base64 / clash / singbox 格式
- ⚡ 延迟测试与自动选择
- 📊 实时流量统计
- 🌐 智能 / 全局模式切换（智能模式自带中国大陆 IP / 域名分流规则）

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

预编译产物已经放在 `core/output/`（iOS xcframework）、`android/app/libs/libcore.aar`、`libcore/bin/libcore.dylib`（macOS）。重新生成：

```bash
cd core
./build.sh android   # Android arm64-v8a / armeabi-v7a / x86_64
./build.sh ios       # iOS arm64 + simulator
./build.sh macos     # macOS arm64 + x86_64 universal
./build.sh all
```

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

测试覆盖：~30 个 unit/widget + 1 个 Android E2E（真实出流量验证）。

## 许可证

GPL-3.0。
