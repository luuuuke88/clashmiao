# ClashMiao 路线图

按里程碑组织，每个里程碑给出**当前状态**、**剩下要做的事**、**前置条件**。

---

## 里程碑 1 — Android VPN ✅ 完成

**结果**：模拟器点连接 → 系统 VPN 权限弹窗 → tun0 接管全部 TCP/UDP → UI「已连接」+ 节点延迟。`bin/test-e2e.sh` 跑 `integration_test/android_smart_mode_test.dart` 断言出口 IP 真实变化。

**关键决策点**（已写入 [docs/ARCHITECTURE.md](ARCHITECTURE.md)）：
- 进程模型：`engine.TunnelService` 跑独立进程，AIDL 跟主进程通讯
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

## 里程碑 3 — iOS PacketTunnel 🟡 代码就绪 / 卡签名

**代码完成**：
- `ios/SingBoxPacketTunnel/` Network Extension target（com.apple.product-type.app-extension）
- `ios/Runner/{VPN,Handlers,Shared}/` 主 app 侧 Swift 全部完工（~20 个 .swift）
- `Runner.xcodeproj` 注册 SingBoxPacketTunnel 为 app-extension，自动 embed Libcore.xcframework
- Podfile 已加 extension target 段
- CI `build-ios` job (`flutter build ios --debug --no-codesign`) 跑绿

**阻塞**（用户层硬约束，无法绕开）：
1. Apple Developer 账号（$99/年）—— https://developer.apple.com/programs/enroll/
2. NetworkExtension capability 申请审批（1–2 个工作日人工审）
3. App ID `com.clashmiao.clashmiao` + `com.clashmiao.clashmiao.SingBoxPacketTunnel` 注册
4. App Group `group.com.clashmiao.shared` 注册
5. Provisioning Profile 下载到本机 Xcode
6. iOS 真机一台（Simulator 不支持 NetworkExtension）

详见 `ios/SCAFFOLDING.md`。拿到资源后预期 ~半天调试可上真机。

---

## 里程碑 4 — Windows 🟡 代码 + lib 就绪 / 卡真机

**当前状态**：
- ✅ `libcore-windows-amd64.dll`（41M，amd64 c-shared，含 setup/start/stop/parse 等 11 个 FFI 符号）在 GitHub Release tag `libcore-v1.11.0`
- ✅ `windows/CMakeLists.txt` install 阶段把 dll 拷到 `.exe` 同级
- ✅ CI `build-windows` 跑 `flutter build windows --release`，bundle 校验 + `clashmiao-windows-release` artifact 上传
- ❌ 没有 Windows 物理机 / VM 跑过一次连接 smoke（设系统代理 + 浏览器 → 出口 IP 变化）

**剩下要做的事**（拿到 Windows 机器后）：
```powershell
git clone luke501/clashmiao
bash bin/fetch-libcore.sh windows
flutter pub get
flutter build windows --release
build\windows\x64\runner\Release\clashmiao.exe
# 添加订阅、点连接、看 Edge / Chrome 出口 IP
```

可能踩坑：`set-system-proxy: true` 写 IE 注册表需要管理员权限；macOS / Linux 编 dll 的 CGo 链接方式跟 native MSVC 不完全一致，可能要重编一次。

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
git clone luke501/clashmiao
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

5 个平台的 libcore 走 GitHub Release tag `libcore-v<sing-box-version>`，`bin/fetch-libcore.sh` 统一拉取。详见 README + ARCHITECTURE。

### CI/CD ✅

GitHub Actions 8 个 job 并行 gate：
- analyze / test-unit / test-android-unit（PR gate）
- build-android / build-macos / build-ios / build-windows / build-linux（5 平台 release/debug build）
- Windows / Linux build 后校验 libcore 真被 install 到产物，Linux 还 `nm -D` 抽查 FFI 符号

`release.yml` 跟 `v*` tag 触发 Android APK/AAB + macOS dmg 自动发布。

### 文档

- [x] README.md — 平台支持表 + 入门
- [x] docs/ARCHITECTURE.md — 架构分层 + 各平台 native 文件骨架
- [x] docs/ROADMAP.md — 本文件
- [x] ios/SCAFFOLDING.md / windows/libs/README.md / linux/libs/README.md — 各平台运行前置
- [ ] docs/DEBUGGING.md — Android logcat 关键 tag、macOS Console、iOS Xcode 调试

### 已知风险

- **核心库版本**：libcore 是 sing-box `v1.11.0` snapshot；上游升级后要重 build。tag 命名 `libcore-v<version>` 留出升级路径
- **Apple 政策**：iOS NetworkExtension 在 App Store 审核越来越严，VPN 类需证明合理用途
- **协议**：当前 GPL-3.0；若日后闭源 / 商业化，需重新评估各平台 native 实现的协议出处
