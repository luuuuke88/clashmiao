# Changelog

ClashMiao（喵速）版本变更记录。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

### 后续轮次（基础设施 + 修 P0 bug）

#### Added
- **Pigeon 强类型 native bridge** 脚手架：`pigeons/box_api.dart` 定义 BoxHostApi，
  `dart run pigeon` 生成三端代码（Dart/Kotlin/Swift），完整迁移留待单独 PR
- **Git LFS** 入库 `android/app/libs/libcore.aar`（120MB），CI 现在能编 Android release APK；
  ci.yml `build-android` job 重新启用、去掉 continue-on-error

#### Fixed
- **Android 单 SS URI DNS 不通**根因：sing-box fork 在 `enable-full-config=true` 时
  强制把 `dns-remote` 改成 `udp://1.1.1.1` 经代理转发，但 SS 协议很多服务器不支持 UDP
  → DNS 包丢 → Chrome DNS_PROBE_FINISHED。改默认 `remoteDnsAddress` 为 DoH
  (`https://1.1.1.1/dns-query`)，走 TCP 通道，所有 SS / Trojan 服务都支持 TCP
- `curly_braces_in_flow_control_structures` lint 修一处（CI analyze 拦了）
- `dart format` 全仓重排（10 个文件）

### Added
- iOS NetworkExtension 脚手架（PacketTunnelProvider + Runner VPNManager + Handlers）
- Windows / Linux libcore 集成的 CMake 配置 + SCAFFOLDING 文档
- macOS 系统托盘图标 + 连接/断开/退出快捷菜单
- 关窗口前自动停 sing-box（避免系统代理残留）
- 主页 options 按钮跳设置 tab
- 删除订阅二次确认 AlertDialog
- 日志页接 box.log tail 流（1.5s poll）按 error/warn/debug 着色
- NetworkSettings 持久化层 + SettingsPage 4 个开关 + port / DNS editor 全部接真
- 连接时长显示（"已连接 5m 32s"）
- 启动自动按 updateInterval 更新过期订阅
- ss:// / vless:// 等 7 种代理 URI 直接导入（`addByContent`）
- 自动 dns.servers + tun inbound 补齐（让 single-URI profile 在 Android 上 TUN 可用）

### Fixed
- `reconnect()` 用 RuntimeConfigBuilder 拼好的 runtime-config（之前用原始 profile 导致分流失效）
- 切换"全局/智能"模式时如果连着会自动 reconnect
- connect 失败时把错误写到 `connectionErrorProvider` → HomePage listen 弹 toast

### Tests
- 92 个 unit + widget 测试全绿（覆盖 NotifierState、ProfileRepository CRUD、ConnectionController、formatters、SubscriptionInfo、ConfigParser、ProfileParser、BoxAlertType、ModeSelector、SettingsPage、ProfilesPage）
- Android emulator integration_test 验证 ss:// 单节点路由

### Engineering
- GitHub Actions CI：analyze + unit test 在 PR / push 上跑，~2 分钟
- 仓库 luke501/clashmiao (private)，CI Secret CLASHMIAO_TEST_SUB_URL 已配
- `bin/test-all.sh` 本地一键全套（并行 Android E2E + macOS 烟雾）
- 公开文档完全脱敏，不出现具体上游项目名

## [0.1.0] - 2026-03-01

### Added
- Flutter 3.41 + Riverpod + go_router 基础架构
- sing-box 内核接入（Android VpnService + macOS FFI）
- 订阅管理（Clash YAML / base64 / sing-box JSON 三种格式）
- 智能 / 全局两种代理模式
- 节点列表 + 延迟测试 + 排序
- 主题（明/暗/跟随系统）+ 10 种语言翻译
