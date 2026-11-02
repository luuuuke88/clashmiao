# integration_test 运行说明

这里的测试都要在真机或模拟器上跑，不属于 `flutter test test/` 的单测范围，也不计入单测覆盖率。

| 测试 | 平台 | 要不要真实隧道 | 要不要测试订阅地址 | CI |
| --- | --- | --- | --- | --- |
| `android_smart_mode_test.dart` | Android 模拟器或真机 | 要 | 要 | `smoke-android` 任务（默认关闭，见下） |
| `ios_lifecycle_smoke_test.dart` | iOS 真机 | 要 | 要 | 不跑 |
| `quick_settings_ios_test.dart` | iOS 模拟器或真机 | 不要 | 不要 | 不跑 |
| `home_connection_info_ios_test.dart` | Android / iOS 模拟器或真机 | 不要 | 不要 | 不跑 |

`_fixtures/` 是共用的辅助代码，不是测试：

- `subscription_source.dart`：解析测试订阅地址。
- `test_helpers.dart`：等待连接状态、查询出口 IP 等。

## 测试订阅地址

需要订阅的测试按下面的优先级取地址，两处都没有就直接报错，不会假绿：

1. 编译参数 `--dart-define=CLASHMIAO_TEST_SUB_URL=<测试订阅地址>`；
2. 本机文件 `~/.clashmiao_dev_subscription_url`（文件内容就是测试订阅地址）。

订阅地址属于敏感信息：不要写进仓库、日志或 PR。CI 里它存放在仓库 secret `CLASHMIAO_TEST_SUB_URL`。

## android_smart_mode_test：Android 智能模式端到端

流程：导入测试订阅，连接，确认出口 IP 与连接前不同，断开。

本地运行，需要 `adb` 能看到一台模拟器或真机：

```bash
# 推荐：脚本会自己读取订阅地址并选设备
bin/test-e2e.sh

# 或手动指定
flutter test integration_test/android_smart_mode_test.dart \
  -d <设备 id> \
  --dart-define=CLASHMIAO_TEST_SUB_URL=<测试订阅地址>
```

首次运行会弹出系统的 VPN 授权框，需要人工点允许。模拟器上可以用 `bin/grant-vpn-android.sh` 在后台自动点击。

CI 对应的是 `ci.yml` 里的 `smoke-android` 任务，它默认不运行，需要同时满足：

- 仓库变量 `ENABLE_SMOKE` 设为 `true`；
- 仓库 secret `CLASHMIAO_TEST_SUB_URL` 已配置。

即便打开，GitHub 的模拟器上系统路由和出口 IP 也不稳定，不能代替真机验证，所以它不是合并门槛。

## iOS 的 3 个测试

iOS 上的隧道依赖 NetworkExtension。GitHub 的 macOS runner 上无法建立隧道，所以这 3 个测试不进 CI，只能在本机的 iOS 模拟器（或真机）上跑。先用 `flutter devices` 查设备 id。

### ios_lifecycle_smoke_test：iOS 生命周期冒烟

流程：导入订阅，连接，出口 IP 变化，健康探测，延迟列表，切换节点，断开，再连接。每一步打印 `[e2e]` 日志，并输出内核快照序列。

必须在真机上跑：要真的建立隧道。首次运行会弹出系统的「添加 VPN 配置」授权框，需要人工点允许。

```bash
flutter test integration_test/ios_lifecycle_smoke_test.dart \
  -d <iOS 设备 id> \
  --dart-define=CLASHMIAO_TEST_SUB_URL=<测试订阅地址>
```

可选参数：加上 `--dart-define=CLASHMIAO_SMOKE_LEAVE_CONNECTED=true`，测试结束后保持连接，用于手动验证「杀进程重开后重新挂接」。

订阅地址也可以放进一个 JSON 文件，用 `--dart-define-from-file=<文件>` 传入，这样不会出现在 shell 历史里。

### quick_settings_ios_test：快捷设置弹窗

用桩内核启动整个 App，点击首页的快捷设置按钮，断言弹窗出现。不需要订阅，也不建立隧道。测试在非 iOS 平台会直接跳过。

```bash
flutter test integration_test/quick_settings_ios_test.dart -d <iOS 模拟器 id>
```

测试结尾会停留 20 秒，方便用 `xcrun simctl io <模拟器 id> screenshot` 从外部截图。也可以加 `--dart-define=CLASHMIAO_EMIT_QUICK_SETTINGS_SCREENSHOT=true`，让测试自己截图，并以 base64 打印在日志的 `[quick-settings-ios-base64-begin]` 和 `[quick-settings-ios-base64-end]` 之间（需要把日志重定向到文件再解码）。

### home_connection_info_ios_test：首页连接信息

用固定的节点数据渲染首页的连接信息，断言「节点名 + 延迟」按一行布局显示。不需要订阅，也不建立隧道。虽然文件名带 iOS，代码里实际允许 Android 和 iOS 运行，桌面平台会跳过。

```bash
flutter test integration_test/home_connection_info_ios_test.dart -d <设备 id>
```

可选参数：`--dart-define=CLASHMIAO_EMIT_HOME_INFO_SCREENSHOT=true`，截图并以 base64 打印在日志的 `[home-info-ios-base64-begin]` 和 `[home-info-ios-base64-end]` 之间。

## 提交前

这个目录下的代码也要通过 CI 的格式化检查：

```bash
dart format --set-exit-if-changed lib/ test/ integration_test/
```
