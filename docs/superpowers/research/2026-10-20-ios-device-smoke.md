# iOS 真机冒烟：状态与操作手册（2026-10-20）

## 现状：真机主链路已验证（iPhone 镜像手动操作，profile 包），部分项待补

测试设备：iPhone 16 Pro Max，profile 签名包，通过 macOS「iPhone 镜像」操作（Flutter 集成测试因无线调试的 VM Service 发现失败无法附着，改为手动走一遍）。订阅为 e2e-test（测试订阅，未回显链接）。

| 项 | 结果 |
|---|---|
| 启动（含新原生层）无崩溃，读到已有订阅 | ✅ |
| 连接（点击 → 正在连接 → 已连接，状态栏 VPN 标识） | ✅ 约 6 秒内完成，自动选择香港节点，延迟 71ms |
| 出口 IP 变化 | ✅ 出现香港出口 IP |
| 线路页延迟列表 | ✅ 全部节点带延迟，按延迟排序 |
| 切换节点（日本01）并回首页 | ✅ 出口 IP 变为日本 IP，连接未中断（计时连续） |
| 切后台 75 秒再回前台 | ✅ 仍为已连接，流量计数继续增长 |
| 杀进程后冷启动 | ✅ 重新打开即为「已连接」，节点（日本01）与出口 IP 保持，无需重连（接管成功） |
| 主动断开 | ✅ 「正在断开连接」→「点击连接」；扩展状态 `phase=stopped, stopReason=1`（用户停止），intent `desired=off` |
| 扩展内存（来自 `extension-state.json`） | ✅ `footprintMax≈15.0 MB`，`availableMemoryMin≈35.0 MB`（可用余量最低值），无被系统杀死 |

未完成 / 未验证：
- **断开后再次连接**：断开后 iPhone 镜像会话中断（连接中断 → 已超时），之后的画面是过期帧，重连点击没有落到手机上，所以**不是失败而是未验证**。需要在手机上手点一次确认。
- Wi-Fi ↔ 蜂窝切换、系统「设置 → VPN」开关：未做（需要人在手机上操作）。
- 自动化集成测试（`integration_test/ios_lifecycle_smoke_test.dart`）：需数据线连接才能附着 VM Service。

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

## 2026-10-22 补充：模拟器全流程（release 候选 0.3.0）

设备：iPhone 17 Pro Max 模拟器、iPad Pro 13" 模拟器，debug 包。

| 项 | 结果 |
|---|---|
| 首次启动、空状态 | ✅ |
| 新的配置文件 → 从剪贴板添加（系统粘贴授权 → 允许） | ✅ 导入成功，订阅流量 / 到期信息正确；面板按 UA 白名单发内容的回退生效 |
| 失效订阅（HTTP 403） | ✅ 报错提示，不崩溃 |
| 添加订阅弹窗没有「添加 WARP」、快速设置没有 WARP 行 | ✅ |
| 线路页列出全部节点；未连接时点测速提示「请连接后测速」 | ✅ |
| 设置页无「隐私 / 启用分析」（本构建没有上报 DSN） | ✅ |
| 关于页无「检查更新」，有「隐私政策」 | ✅ |
| 点连接 | ⚠️ 模拟器限制：模拟器里没有 `nehelper`，`NETunnelProviderManager` 读写配置报 `NEConfigurationErrorDomain Code=11 IPC failed`，App 提示「与后台服务失去联系」。**VPN 隧道只能在真机验证** |
| iPad 布局（首页 / 线路） | ✅ 无溢出 |

iOS 原生层（`ios/`）自 10-20 真机冒烟以来没有改动（只补了隐私清单），隧道链路沿用当日真机结论。仍未在真机上验证的项见上文「未完成 / 未验证」。
