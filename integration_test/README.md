# integration_test 运行说明

这里的测试都要在模拟器或真机上跑，不属于 `flutter test test/` 的单测范围，也不计入单测覆盖率。下面逐个说明，每一项都以对应测试文件里的代码为准。

| 测试 | 跑在哪 | 是否建立真实隧道 | 是否需要测试订阅地址 | 目前是否在 CI 里跑 |
| --- | --- | --- | --- | --- |
| `android_smart_mode_test.dart` | Android 模拟器或真机 | 是 | 是 | 仅 `smoke-android` 任务，默认关闭 |
| `ios_lifecycle_smoke_test.dart` | iOS 真机 | 是 | 是 | 否 |
| `quick_settings_ios_test.dart` | iOS 模拟器或真机 | 否 | 否 | 否 |
| `home_connection_info_ios_test.dart` | Android 或 iOS 的模拟器、真机 | 否 | 否 | 否 |

`_fixtures/` 是共用的辅助代码，不是测试：`subscription_source.dart` 负责取测试订阅地址，`test_helpers.dart` 提供等待连接状态、查询出口 IP 等工具。

## 测试订阅地址怎么传

只有需要真实隧道的两个测试（`android_smart_mode_test`、`ios_lifecycle_smoke_test`）会用到。`SubscriptionSource.resolve()` 按下面的优先级取值，两处都没有就抛 `StateError`，不会假绿：

1. 编译参数 `CLASHMIAO_TEST_SUB_URL`，通过 `--dart-define` 或 `--dart-define-from-file` 传入；
2. 兜底：读取 `$HOME/.clashmiao_dev_subscription_url` 文件。

注意第 2 条读的是**测试进程自己的 `HOME`**。测试在设备或模拟器里运行，它的 `HOME` 是设备（或模拟器应用）的沙盒目录，不是开发机的主目录，所以放在开发机 `~/` 下的那个文件在设备上读不到。在设备上跑，一律用第 1 条，不要指望兜底。

推荐做法：把订阅地址写进开发机上的一个 JSON 文件，放在仓库目录之外，用 `--dart-define-from-file` 传入。这个参数由 `flutter` 命令在开发机上读取，再编译进测试包，这样地址不会出现在 shell 历史里，也不会进仓库：

```json
{ "CLASHMIAO_TEST_SUB_URL": "<测试订阅地址>" }
```

```bash
flutter test integration_test/<测试文件>.dart \
  -d <设备 id> \
  --dart-define-from-file=<本机 JSON 文件的路径>
```

Android 另有现成脚本：`bin/test-e2e.sh` 会在**开发机**上依次读取环境变量 `CLASHMIAO_TEST_SUB_URL` 和 `~/.clashmiao_dev_subscription_url`（文件内容就是测试订阅地址），再用 `--dart-define` 传给测试。iOS 没有这样的脚本，请用上面的 JSON 文件。

订阅地址属于敏感信息：不要写进仓库、日志或 PR。CI 里它存放在仓库 secret `CLASHMIAO_TEST_SUB_URL`。

## android_smart_mode_test：Android 智能模式端到端

- 平台：Android，模拟器或真机均可。其他平台会跳过。
- 依赖：真实内核（不是桩），会真的建立 VPN 隧道；需要测试订阅地址；`adb` 能看到设备。
- 流程：导入测试订阅，选智能模式，连接，确认出口 IP 与连接前不同，断开。
- 首次运行会弹出系统的 VPN 授权框，需要人工点允许。模拟器上可以用 `bin/grant-vpn-android.sh` 在后台自动点击。

本地运行：

```bash
# 推荐：脚本自动取订阅地址并选设备
bin/test-e2e.sh

# 或手动指定
flutter test integration_test/android_smart_mode_test.dart \
  -d <设备 id> \
  --dart-define=CLASHMIAO_TEST_SUB_URL=<测试订阅地址>
```

CI：对应 `ci.yml` 里的 `smoke-android` 任务（API 34 模拟器），默认不运行，需要同时满足仓库变量 `ENABLE_SMOKE` 为 `true` 和仓库 secret `CLASHMIAO_TEST_SUB_URL` 已配置。它不是合并门槛：GitHub 的模拟器上系统路由和出口 IP 不稳定，不能代替真机验证，Android 的发版验收以真机为准。

## ios_lifecycle_smoke_test：iOS 生命周期冒烟

- 平台：iOS 真机（文件头注明「iOS 真机冒烟」）。非 iOS 平台会跳过。
- 依赖：真实内核和 NetworkExtension，会真的建立 VPN 隧道；需要测试订阅地址。
- 流程：导入订阅，连接，出口 IP 变化，健康探测，延迟列表，切换节点，断开，再连接。每一步打印 `[e2e]` 日志，并输出内核快照序列。
- 首次运行会弹出系统的「添加 VPN 配置」授权框，需要人在真机上点允许。
- 可选参数 `--dart-define=CLASHMIAO_SMOKE_LEAVE_CONNECTED=true`：测试结束后保持连接，用于手动验证「杀进程重开后重新挂接」。

```bash
flutter test integration_test/ios_lifecycle_smoke_test.dart \
  -d <iOS 真机 id> \
  --dart-define-from-file=<本机 JSON 文件的路径>
```

CI：不跑。GitHub 的 macOS runner 上无法建立 NetworkExtension 隧道，这个测试只能在本地用真机跑。

## quick_settings_ios_test：快捷设置弹窗

- 平台：iOS，模拟器或真机均可。非 iOS 平台会跳过。
- 依赖：用 `StubBoxService` 桩内核启动整个 App，不建立隧道，不需要订阅地址。
- 流程：点击首页的快捷设置按钮，断言 `QuickSettingsModal` 出现。测试结尾停留 20 秒，方便用 `xcrun simctl io <模拟器 id> screenshot` 从外部截图。
- 可选参数 `--dart-define=CLASHMIAO_EMIT_QUICK_SETTINGS_SCREENSHOT=true`：测试自己截图，并以 base64 打印在日志的 `[quick-settings-ios-base64-begin]` 与 `[quick-settings-ios-base64-end]` 之间（把日志重定向到文件后再解码）。

```bash
flutter test integration_test/quick_settings_ios_test.dart -d <iOS 模拟器 id>
```

CI：不跑。原因不是技术上做不到，而是目前没有任何 CI 任务启动 iOS 模拟器（`build-ios` 只编译，不运行测试），所以这个测试只在本地模拟器上手动跑。

## home_connection_info_ios_test：首页连接信息

- 平台：Android 或 iOS，模拟器或真机均可（代码里的判断是「非 Android 且非 iOS 则跳过」），文件名里的 `ios` 只是历史命名。
- 依赖：用固定的节点数据渲染首页的连接信息，不建立隧道，不需要订阅地址。
- 流程：断言节点名与延迟按一行布局显示，不出现「已连接 」前缀。
- 可选参数 `--dart-define=CLASHMIAO_EMIT_HOME_INFO_SCREENSHOT=true`：截图并以 base64 打印在日志的 `[home-info-ios-base64-begin]` 与 `[home-info-ios-base64-end]` 之间。

```bash
flutter test integration_test/home_connection_info_ios_test.dart -d <设备 id>
```

CI：不跑。原因同上：目前没有任何 CI 任务启动 iOS 模拟器，`smoke-android` 也只运行 `android_smart_mode_test`。

## 提交前

这个目录下的代码也要通过 CI 的格式化检查：

```bash
dart format --set-exit-if-changed lib/ test/ integration_test/
```
