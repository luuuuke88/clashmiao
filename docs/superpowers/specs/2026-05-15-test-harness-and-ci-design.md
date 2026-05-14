# 自动化测试地基 + Android E2E + CI/CD

**Date:** 2026-05-15
**Status:** Approved (skip user-review per user instruction)
**Scope:** A+B+C — 测试金字塔脚手架、Android emulator 端到端自动化、GitHub Actions CI/CD。
**Out of scope:** iOS / Windows / Linux 移植；macOS E2E（短期内手动验证）；测试自愈机器人。

---

## 1. 动机

当前仓库只有 4 个 widget test，没有 CI。每次改动核心逻辑（RuntimeConfigBuilder / changeConfigOptions / 路由注入），都要手动起 emulator → 添加订阅 → 点连接 → curl → 看 logcat，整个回归循环 ≥ 5 分钟，且每次必跑全套，否则不放心。

目标：把"改一行代码 → 知道有没有打破整体功能"这件事，**本地 ~30 秒、CI ~6 分钟**自动给出红绿反馈。

---

## 2. 总体架构

测试金字塔：

```
        ╱ E2E ╲             1 条用例：Android smart mode 真上网
       ╱───────╲
      ╱ Widget  ╲           ~6 条：ConnectionButton + ModeSelector + Settings 关键交互
     ╱───────────╲
    ╱   Unit      ╲         ~25 条：纯逻辑层（RuntimeConfigBuilder / Parser / Repo 等）
   ╱_______________╲
```

底层多、顶层少。E2E 只用来兜底 "改了一堆 unit 全绿但整体跑不通" 这个最贵的 bug，不替代覆盖率。

---

## 3. 文件结构

```
.github/workflows/
├── ci.yml                # PR + push → analyze / unit / e2e / build APK 4 个 job 并行
└── release.yml           # git tag v* → Android APK/AAB + macOS dmg + gh release create

bin/
├── test-all.sh           # 本地一键：analyze + unit + widget + E2E
├── test-e2e.sh           # 只跑 E2E（针对已连的 AVD 或 boot 一个）
└── test-unit.sh          # 不需要模拟器的部分

integration_test/
├── _fixtures/
│   └── subscription_source.dart   # 双路 URL：env → file fallback
└── android_smart_mode_test.dart   # 第一条 E2E 用例

test/
├── core/
│   ├── config/runtime_config_builder_test.dart   # 新
│   ├── model/box_alert_test.dart                  # 新
│   └── utils/config_parser_test.dart              # 新
└── features/
    ├── profile/data/
    │   ├── profile_repository_test.dart           # 新（用临时 dir + 假 SharedPreferences）
    │   └── profile_parser_test.dart               # 新
    └── home/widget/
        ├── connection_button_test.dart            # 已有
        └── mode_selector_test.dart                # 新
```

---

## 4. 子系统设计

### 4.1 SubscriptionSource（订阅 URL 注入）

```dart
class SubscriptionSource {
  /// 优先级：env > file。两个都没有 → throw（不 fallback 到假 URL，避免假绿）。
  static Future<String> resolve() async {
    const fromEnv = String.fromEnvironment('CLASHMIAO_TEST_SUB_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    final home = Platform.environment['HOME'];
    if (home != null) {
      final f = File('$home/.clashmiao_dev_subscription_url');
      if (await f.exists()) return (await f.readAsString()).trim();
    }
    throw StateError('No test subscription URL available; set CLASHMIAO_TEST_SUB_URL or ~/.clashmiao_dev_subscription_url');
  }
}
```

- **本地**：复用已有的 `~/.clashmiao_dev_subscription_url`（DevBoot 已经在读这个文件）
- **CI**：GitHub Secret `CLASHMIAO_TEST_SUB_URL` → 通过 `flutter test --dart-define=CLASHMIAO_TEST_SUB_URL=...` 注入
- 失败模式 = 显式 throw，不沉默：避免 "URL 没读到 → 跑了个假测试 → 永远绿" 的灾难

### 4.2 Android E2E test (`android_smart_mode_test.dart`)

测试流程：

```dart
testWidgets('smart mode: connect → traffic proxied → disconnect', (tester) async {
  // 1. 注入测试订阅（绕开 UI 添加流程）
  await _injectTestProfile();

  // 2. 启动 app
  await tester.pumpWidget(const ProviderScope(child: ClashMiaoApp()));
  await _waitFor(tester, () => ref.read(activeProfileProvider).valueOrNull != null);

  // 3. baseline IP（VPN 未开）
  final baselineIp = await _fetchEgressIp();

  // 4. tap ConnectionButton
  await tester.tap(find.byType(ConnectionButton));
  await tester.pump();

  // 5. 轮询状态（pumpAndSettle 在 starting 动画期会卡死）
  await _waitForStatus<BoxStarted>(tester, timeout: Duration(seconds: 30));

  // 6. 验证流量走了代理（出口 IP 变化）
  final proxiedIp = await _fetchEgressIp();
  expect(proxiedIp, isNot(equals(baselineIp)),
      reason: 'Egress IP should change after VPN connects');
  expect(proxiedIp, matches(_ipv4Regex));

  // 7. 断开
  await tester.tap(find.byType(ConnectionButton));
  await _waitForStatus<BoxStopped>(tester, timeout: Duration(seconds: 30));
});
```

**关键决策**：

- **HTTP 调用从 app 进程内发起**：Android TUN 接管整个 UID 的 socket，从 integration_test 内 `http.get()` 的请求自然走 tun0。无需 ADB shell。
- **比较 IP 而非 hardcode**：节点 / 出口 IP 会变；"开 VPN 前后 IP 不同"是稳定不变量。
- **`_waitForStatus` 用 300ms 间隔轮询**，最多 30s。`pumpAndSettle` 在背景动画无限循环时会死锁。
- **`_injectTestProfile` 直接调 `ProfileRepository.addByUrl`**，绕开 UI 添加流程（避免依赖 `+` 按钮、表单 widget tree、modal 时序）。

**Failure mode 区分**：

| 现象 | 分类 | CI 行为 |
|------|------|---------|
| status 永远 BoxStarting → 超时 | 真 bug | fail |
| BoxStarted 但 egress IP 没变 | 真 bug | fail |
| baseline IP 取不到（emulator 网络挂） | 基础设施 | skip + warn |
| 订阅返回 4xx/5xx | 订阅过期/被黑 | skip + warn |

通过 `markTestSkipped(reason)` 区分前两种和后两种。

### 4.3 GitHub Actions CI (`ci.yml`)

4 个 job 并行，均跑 Ubuntu：

```yaml
on:
  pull_request:
  push:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - setup-flutter (cached)
      - run: flutter pub get
      - run: dart format --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-warnings

  test-unit:
    runs-on: ubuntu-latest
    steps:
      - 同上 setup
      - run: bash bin/test-unit.sh

  test-e2e:
    runs-on: ubuntu-latest
    steps:
      - checkout
      - setup-flutter (cached)
      - setup-java (17)
      - enable KVM (sudo apt-get install -y kvm + KVM group permission)
      - reactivecircus/android-emulator-runner@v2:
          api-level: 33
          target: google_apis
          arch: x86_64
          script: bash bin/test-e2e.sh
        env:
          CLASHMIAO_TEST_SUB_URL: ${{ secrets.CLASHMIAO_TEST_SUB_URL }}
      - upload-artifact (on failure): screenshots + logcat tail

  build-android:
    runs-on: ubuntu-latest
    steps:
      - 同上 setup
      - run: flutter build apk --release
      - upload-artifact: app-release.apk
```

**缓存策略**：
- Flutter SDK：`subosito/flutter-action` 自带缓存
- Pub deps：`actions/cache` 路径 `~/.pub-cache`
- Gradle：`actions/cache` 路径 `~/.gradle/caches` + `~/.gradle/wrapper`
- AVD snapshot：`reactivecircus/android-emulator-runner` 自带 `cache-key` 选项

预计冷启 8 min，缓存命中后 4–5 min。

### 4.4 GitHub Actions Release (`release.yml`)

```yaml
on:
  push:
    tags: ['v*']

jobs:
  android:
    runs-on: ubuntu-latest
    outputs: { apk-path, aab-path }
    steps:
      - flutter build apk --release
      - flutter build appbundle --release
      - upload-artifact

  macos:
    runs-on: macos-latest
    outputs: { dmg-path }
    steps:
      - flutter build macos --release
      - create-dmg
      - upload-artifact

  publish:
    needs: [android, macos]
    runs-on: ubuntu-latest
    steps:
      - download-artifact (all)
      - gh release create $TAG --generate-notes *.apk *.aab *.dmg
```

### 4.5 本地脚本

**`bin/test-all.sh`**：
```bash
#!/usr/bin/env bash
set -euo pipefail
flutter pub get
dart format --set-exit-if-changed lib/ test/
flutter analyze --fatal-warnings
flutter test
if adb devices | grep -q emulator; then
  flutter test integration_test/
else
  echo "[skip e2e] no Android device connected"
fi
```

**`bin/test-e2e.sh`**：
```bash
#!/usr/bin/env bash
set -euo pipefail
URL="${CLASHMIAO_TEST_SUB_URL:-}"
if [[ -z "$URL" && -f "$HOME/.clashmiao_dev_subscription_url" ]]; then
  URL=$(cat "$HOME/.clashmiao_dev_subscription_url" | tr -d '[:space:]')
fi
[[ -z "$URL" ]] && { echo "no subscription URL"; exit 2; }
flutter test integration_test/ --dart-define=CLASHMIAO_TEST_SUB_URL="$URL"
```

---

## 5. 单元测试覆盖目标

| 模块 | 测试文件 | 用例数 | 关键 case |
|------|----------|--------|-----------|
| `RuntimeConfigBuilder` | `runtime_config_builder_test.dart` | 6 | smart 注入 rule-set / global 剥离 / desktop strip tun+mixed / dns rule 注入 / 空 inbounds 兜底 / 非法 JSON 抛错 |
| `BoxAlertType` | `box_alert_test.dart` | 4 | PascalCase / snake_case / unknown fallback / null 输入 |
| `ConfigParser` | `config_parser_test.dart` | 3 | 标准 profile / 缺 outbounds / 嵌套 group |
| `ProfileRepository._normalizeAndWrite` | `profile_repository_test.dart` | 5 | sing-box JSON 直通 / Clash YAML 走 native parse / native 失败回退 / 缺 outbounds 走 parse / 异常处理 |
| `ProfileParser` | `profile_parser_test.dart` | 4 | subscription-userinfo 解析 / 自定义名称 / URL 仅 host fallback / 缺 header |

widget test 新增 2 个：

- `mode_selector_test.dart`：tap → `proxyModeProvider` 更新 + `changeConfigOptions` 被调用一次
- `connection_button_test.dart`：已有 4 case，不动

**目标覆盖率**：`lib/core/` 行覆盖 ≥ 60%，整体不设硬指标（避免为了刷数字写无意义 test）。

---

## 6. 不在本 spec 范围内

明确写出来防止 scope creep：

- iOS / Windows / Linux 平台移植 → 独立 spec
- macOS E2E → 当下手动验证，等 Android E2E 稳定后再扩展
- 测试覆盖率 gate（codecov 等）→ 第一版不接
- pre-commit hook → 用户没要求，不引入
- 测试报告美化 / 趋势图 → YAGNI
- "测试自愈" / agent-driven 修复 → 不在工程范围

---

## 7. 风险登记

| 风险 | 概率 | 缓解 |
|------|------|------|
| **Android emulator 在 GitHub Ubuntu runner 上 TUN 跑不起来** | 中 | Plan B：E2E 降级为只验证状态机（BoxStarted/Stopped），不验证流量。CI 仍然能跑，但价值打折。 |
| **订阅过期 / 节点全挂 → CI 持续红** | 中 | E2E 内部区分基础设施失败 vs 真实 bug，前者 markTestSkipped 不 fail |
| **Public 仓库公开订阅 URL** | 高（如果不注意） | URL 永远走 `secrets.*`，永不进代码。测试代码 grep 一遍提交前没有硬编码。 |
| **缓存 miss 导致 CI 时间退化到 10min+** | 低 | 接受。CI 不在 critical path 上，多 5 分钟可承受。 |
| **flutter_test 在 emulator 里发 HTTP 时被 Dart 自身的 proxy detection 拦截** | 低 | 如果遇到，强制 `HttpClient` 不走系统代理（findProxy=DIRECT），让 TUN 接管 |

---

## 8. 完成定义 (DoD)

- [ ] 仓库已转 public，README 通过 hiddify/baseproxy/nekobox grep 检查
- [ ] `bin/test-all.sh` 本地一条命令跑完 analyze + unit + widget + E2E，全绿
- [ ] CI 在 PR + push 上自动跑 4 job 并行，全绿
- [ ] tag v0.1.1 推上去，release.yml 自动出 APK + dmg，挂上 GitHub Release
- [ ] 新增 ≥ 22 个测试用例（5 单测文件 + 1 widget 文件 + 1 E2E）
- [ ] `docs/ROADMAP.md` 更新：测试 / CI 段移到"已完成"
