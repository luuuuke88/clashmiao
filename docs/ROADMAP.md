# ClashMiao 路线图

按里程碑组织，每个里程碑给出**当前状态**、**剩下要做的事**、**前置条件**。

---

## 里程碑 1 — Android VPN ✅ 完成

**结果**：模拟器点连接 → 系统 VPN 权限弹窗 → tun0 接管全部 TCP/UDP → UI「已连接」+ 节点延迟。`bin/test-e2e.sh` 跑 `integration_test/android_smart_mode_test.dart` 断言出口 IP 真实变化。

**关键决策点**（已写入 [docs/ARCHITECTURE.md](ARCHITECTURE.md)）：
- 进程模型：`engine.TunnelService` 与主 App 同进程（Manifest 无 `android:process`），通过 bindService / AIDL 与 Activity 交互
- `startForeground` 必须传 `FOREGROUND_SERVICE_TYPE_SPECIAL_USE`（Android 14+）
- onStartCommand 入口同步挂 placeholder 通知，避免 IO 线程启动 sing-box 超过 5s 超时被杀
- Kotlin 端 2026-05 完成 clean-room 重写（Phase 1-7），17 个 host JVM 单测守 wire-format

---

## 里程碑 2 — macOS 系统代理 ✅ 完成

**结果**：`flutter build macos --debug` + 手动 smoke 验证（154.83.95.148 → 45.202.255.184，36 秒走完）。系统托盘 + 关窗自动停 sing-box + 启动自动更新过期订阅都齐了。

技术要点：
- pbxproj shell script build phase 自动把 `libcore/bin/libcore.dylib` 拷到 `${PRODUCT_NAME}.app/Contents/Frameworks/` 并 `codesign --force --sign -`
- entitlements：sandbox 关、network client/server 开、JIT 允许
- `default_config_options.dart` 在 macOS / Linux / Windows 默认 `set-system-proxy=true / enable-tun=false`

---

## 里程碑 3 — iOS PacketTunnel 🟡 真机已跑通 / 待上架

**已完成**：
- `ios/SingBoxPacketTunnel/` Network Extension target（com.apple.product-type.app-extension）
- `ios/Runner/` 主 App 侧 Swift 全部完工，`Runner.xcodeproj` 自动 embed Libcore.xcframework
- CI `build-ios` job（`flutter build ios --debug --no-codesign`）跑绿
- 组织类型的 Apple Developer 账号、App ID（主 App + `.SingBoxPacketTunnel` 扩展）、App Group `group.com.clashmiao.shared`、签名配置就绪
- 2026-10 真机验证：导入订阅、建立 VPN、出口 IP 切换均正常

**剩下要做的事**：
1. iOS 原生侧补上网络变化事件通道（Dart 侧 `watchNetworkChanged` 在 iOS 上目前收不到事件）
2. App Store 上架材料：隐私说明、截图、审核备注（VPN 类 App 需说明用途，审核指南 5.4）
3. 首发地区：美国、香港

详见 `ios/SCAFFOLDING.md`。

---

## 里程碑 4 — Windows ✅ 完成

**结果**：已在 Windows 真机上验证可用（系统代理模式）。`release.yml` 随 tag 产出 Windows 包。

**技术要点**：
- ✅ `libcore-windows-amd64.dll`（41M，amd64 c-shared，含 setup/start/stop/parse 等 11 个 FFI 符号）在 GitHub Release tag `libcore-v1.11.0`
- ✅ `windows/CMakeLists.txt` install 阶段把 dll 拷到 `.exe` 同级
- ✅ CI `build-windows` 跑 `flutter build windows --release`，bundle 校验 + `clashmiao-windows-release` artifact 上传

---

## 里程碑 5 — Linux 🟡 代码 + lib 就绪 / 卡真机桌面

**当前状态**：
- ✅ `libcore-linux-amd64.so`（45M）在 GitHub Release tag `libcore-v1.11.0`
- ✅ Debian Linux 容器实测 `dlopen()` + `dlsym()` 11 个 FFI 符号全 resolve（`ldd` 只依赖 libc）—— 证 ELF 加载链路真通
- ✅ `linux/CMakeLists.txt` install 拷 so 到 `bundle/lib/`，rpath `$ORIGIN/lib`
- ✅ CI `build-linux` 跑 `flutter build linux --release`，bundle 校验 + `nm -D` 抽查 FFI 符号 + artifact 上传
- ❌ 没有 Linux 桌面 / GUI VM 跑过一次连接 smoke

**剩下要做的事**（拿到 Linux 桌面后）：
```bash
git clone https://github.com/luuuuke88/clashmiao.git
bash bin/fetch-libcore.sh linux
flutter pub get
flutter build linux --release
./build/linux/x64/release/bundle/clashmiao
# GNOME Settings → Network → Network Proxy → Manual 127.0.0.1:2080
# 浏览器看出口 IP
```

可选后续：自己写 `bin/clashmiao-setproxy.sh` 帮 GNOME / KDE / XFCE 自动配。CAP_NET_ADMIN 全局 TUN 模式留单独 milestone。

---

## 横向工作

### libcore 二进制分发 ✅

5 个平台的 libcore 走 GitHub Release tag（当前为 `libcore-v1.11.0`，只是打包标签名，不等于内核版本），`bin/fetch-libcore.sh` 统一拉取。详见 README + ARCHITECTURE。

### CI/CD ✅

`ci.yml` 并行 gate：
- public-links / analyze / test-unit / test-android-unit
- build-android / build-macos / build-ios / build-windows / build-linux（5 平台构建）
- smoke-android / smoke-macos / smoke-windows / smoke-linux（产物启动冒烟）
- Windows / Linux build 后校验 libcore 真被 install 到产物，Linux 还 `nm -D` 抽查 FFI 符号

`release.yml` 由 `v*` tag 触发，产出 Android APK、macOS dmg、Windows、Linux（deb + tar.gz）四个平台的包和 `SHA256SUMS.txt`，发到 GitHub Releases。某个平台失败时其余平台照常发布，release 正文里会显式标出缺了哪个平台。

### 文档

- [x] README.md — 平台支持表 + 入门
- [x] docs/ARCHITECTURE.md — 架构分层 + 各平台 native 文件骨架
- [x] docs/ROADMAP.md — 本文件
- [x] ios/SCAFFOLDING.md / windows/libs/README.md / linux/libs/README.md — 各平台运行前置
- [ ] docs/DEBUGGING.md — Android logcat 关键 tag、macOS Console、iOS Xcode 调试

### 已知风险

- **核心库版本**：当前打包的内核是 sing-box `v1.8.9`（读 `libbox.so` 的构建信息核实）。Release tag 名 `libcore-v1.11.0` 只是打包标签，不是内核版本；上游升级后要重 build，并让 tag 名反映真实内核版本
- **Apple 政策**：iOS NetworkExtension 在 App Store 审核越来越严，VPN 类需证明合理用途
- **协议**：当前 GPL-3.0；若日后闭源 / 商业化，需重新评估各平台 native 实现的协议出处
