# iOS 真机冒烟：状态与操作手册（2026-10-20）

## 现状：模拟器 / 单元层已绿，真机端到端**尚未跑通**

已验证（自动化）：
- `swift test`（临时 SwiftPM 壳，86 个用例：核心状态机、配置拼装、外壳、扩展状态写入）全绿。
- `xcodebuild test`（iPhone 17 模拟器，含仅 Xcode 可跑的 Pigeon 对齐用例）：TEST SUCCEEDED。
- `flutter build ios --no-codesign --debug`、`flutter build ios --profile`（签名）通过；`flutter analyze --fatal-warnings`、`flutter test`（2585 通过）通过。

未完成（需要人在场）：
1. 真机 iPhone 16 Pro Max（UDID 00008140-000409580E98801C）当前**无线连接且屏幕锁定**：
   - `flutter run --publish-port` 经无线调试时 Dart VM Service 发现失败（mDNS，75 s 后超时），集成测试无法附着；
   - `devicectl process launch` 报 `Locked`（设备未解锁）。
2. 首次运行会弹系统「添加 VPN 配置」授权，必须在手机上点「允许」，否则 `boxService.setup` 会一直等授权（上一次冒烟即卡在这里 30 s 超时；现已把该步骤超时放宽到 3 分钟）。

## 需要的人工操作
- 用数据线连接手机（避免无线 VM Service 发现问题）、解锁并保持亮屏；
- 首次弹出 VPN 配置授权时点「允许」。

## 运行
```bash
# 订阅地址只放在本地 define 文件里，不要打印、不要提交
flutter run -d <UDID> --publish-port \
  --target integration_test/ios_lifecycle_smoke_test.dart \
  --dart-define-from-file=<本地 define 文件>
```
冒烟脚本覆盖：导入订阅 → 连接 → 出口 IP 变化 → 延迟列表 → 切换节点（含过期 attempt 被拒） → 断开/重连。

## 仍需人工/真机核对的项目（App Store 前必须）
| 项 | 做法 | 通过标准 |
|---|---|---|
| 杀进程后重新打开 | `CLASHMIAO_SMOKE_LEAVE_CONNECTED=true` 跑完后终止 App，再用 profile/release 包启动 | 快照为 started / source=system / attempt=1，无需重连 |
| 前后台切换 | 连接中切后台 ≥1 分钟再回前台 | 状态不变，健康探测通过 |
| 系统设置里开关 VPN | 在「设置 → VPN」关/开 | 应用状态跟随（source=system） |
| Wi-Fi ↔ 蜂窝 | 连接中切换网络 | 收到网络事件，连接恢复，状态一致 |
| 内存余量 | 从 App Group 读 `extension-state.json` 的 `availableMemoryMin` / `footprintMax` | 余量显著大于 0，无 jetsam |

读扩展状态：
```bash
xcrun devicectl device copy from --device <UDID> \
  --domain-type appGroupDataContainer --domain-identifier group.com.clashmiao.shared \
  --source "Library/Application Support/ClashMiao/kernel/extension-state.json" --destination /tmp/ext-state.json
```
