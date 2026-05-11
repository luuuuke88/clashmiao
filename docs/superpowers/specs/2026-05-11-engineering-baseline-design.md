# 工程基线（Engineering Baseline）设计

**日期**：2026-05-11
**状态**：approved
**适用范围**：clashmiao-client 仓库（[https://github.com/luuuuke88/clashmiao](https://github.com/luuuuke88/clashmiao)）

---

## 目标

把仓库升级到"production-ready open source"基线，让：

- 外部贡献者**知道怎么贡献**（CONTRIBUTING / COC / SECURITY / templates 齐全）
- 每个 PR / push 到 main **自动跑 CI**，失败阻塞 merge
- 发版从"手动 tag 改 CHANGELOG"变成"merge release PR 自动出多平台 signed artifact"
- 依赖升级有 bot 盯，patch/minor 自动 merge、major 留人审

## 非目标

- 不做 Apple 开发者账号申请 / Apple cert 生成 / iOS Provisioning（用户自己注册之后再补 secrets）
- 不做 Android keystore 生成（CI workflow 留 secret 占位，用户自己产 keystore 上传）
- 不做中文/英文翻译质量优化（templates 双语硬写一次即可）
- 不做商店上架自动化（fastlane / Google Play Console API / App Store Connect API 等）
- 不在本 spec 接入 iOS Network Extension 端代码（独立 spec / M5）

## 实施路径

**渐进式 4 个 milestone**，每个独立 commit/PR，独立可验证、可 revert。

| M | 内容 | 文件数 | 验证手段 |
|---|---|---|---|
| **M1** docs/templates | CONTRIBUTING / COC / SECURITY / Issue templates / PR template / CHANGELOG seed + README 微调 | 8 | GitHub 渲染检查、新建测试 issue |
| **M2** CI 基线 | ci.yml + commitlint.yml + .commitlintrc + CONTRIBUTING 增量 | 4 | 故意挂的 PR 必须 red |
| **M3** 多平台扩展 | ci-multi-platform.yml（macOS 实跑、Win/Linux build green-but-stub） | 1 | main push 触发矩阵 |
| **M4** release + bot | release.yml / release-please-config / dependabot.yml / dependabot-auto-merge / Git LFS 接入 | 5+1 | merge 一个 feat commit、看是否自动出 Release |

---

## 关键决策（已与项目主决策）

| 项 | 决策 | 理由 |
|---|---|---|
| CI scope | 完整：多平台 + release | 项目目标是 production-ready |
| Release 方式 | release-please + signed artifact | 自动生成 CHANGELOG、按 Conventional Commits 决定版本号 |
| Commit lint 强度 | 硬性拦截（PR title + 所有 commit） | release-please 依赖 conventional commits，弱拦会漏 |
| Rollout 节奏 | 渐进式 4 个 milestone | 每步独立 verify，避免一个大 PR 跨 review fatigue |
| Templates 语言 | 双语（中英） | 项目 README 已双语；面向中文用户但开源面向国际 |
| Issue 格式 | GitHub Forms (.yml) | 结构化、好维护 |
| `SECURITY_CONTACT` | 占位 `TBD` | 真实联系方式留给用户 M4 阶段填 |
| APK build 时机 | M4，配合 Git LFS | .aar 110MB 不适合直接进 git，LFS 一并接入 |
| Husky commit-msg hook | CONTRIBUTING 推荐、不强制 | Flutter 项目不背 Node 工具链；CI server-side 拦截就够 |
| 多平台 PR 触发 | 不触发，只 main push 触发 | private repo macOS runner 10x 计费、省配额 |
| iOS CI | 推到 M5（独立 spec） | 需 Apple 账号 + 真机，本 spec 范围外 |
| Linux/Windows build 真实度 | green-but-stub | 保 build pipeline 活性，sing-box 接入时再优化 |
| LFS 接入时机 | M4 | M2/M3 不 build APK 就不需要 .aar |
| dependabot auto-merge | patch/minor 自动、major 人审 | 行业惯例 |

---

## M1：docs/templates

### 新增文件

| 路径 | 内容方向 |
|---|---|
| `CONTRIBUTING.md` | 准备开发环境（Flutter/Go/Xcode/NDK 版本）/ 启动 app / Dev auto-boot 用法 / 代码规范 / Conventional Commits / PR 流程 / 链 ARCHITECTURE & ROADMAP |
| `CODE_OF_CONDUCT.md` | Contributor Covenant v2.1 中文翻译版，contact = `TBD` |
| `SECURITY.md` | 支持版本表 / 上报漏洞（不公开 issue、邮件 `TBD`） / 隐私承诺：不收集 telemetry、订阅数据仅本地 |
| `CHANGELOG.md` | Keep a Changelog 格式 seed，第一节 [0.1.0] - 2026-05-11 内容跟 README 平台支持表对齐 |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | GitHub Forms 结构化模板（双语）：平台 dropdown / 版本 / 复现步骤 / 预期 vs 实际 / 日志（带 redaction 提示） |
| `.github/ISSUE_TEMPLATE/feature_request.yml` | 使用场景 / 期望方案 / 已考虑替代 / 是否愿意自己 PR |
| `.github/ISSUE_TEMPLATE/config.yml` | `blank_issues_enabled: false` + contact_links 指向 Discussions |
| `.github/PULL_REQUEST_TEMPLATE.md` | 概要 / 关联 Issue / Test plan（必填，含平台验证 checkbox）/ Checklist（commits 符合 Conventional Commits / docs 更新） |

### 修改文件

- `README.md` 加 CI badge 占位（M2 接入后实际亮）、License badge、Contributing 链接、Discussions 链接

### 验证

- 推到 GitHub 后浏览器看渲染
- 新建测试 issue 验证 templates 生效
- Security 页面识别 SECURITY.md
- 通过 Discussions 入口看 contact_links 配置生效

---

## M2：CI 基线

### `.github/workflows/ci.yml`

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.41.4'
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - name: dart format check
        run: dart format --set-exit-if-changed lib test
      - run: flutter test --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
```

### `.github/workflows/commitlint.yml`

```yaml
name: Commitlint
on:
  pull_request:
    types: [opened, edited, synchronize]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm install -g @commitlint/cli @commitlint/config-conventional
      - name: Lint PR title
        run: echo "${{ github.event.pull_request.title }}" | npx commitlint
      - name: Lint commits in PR
        run: npx commitlint --from=${{ github.event.pull_request.base.sha }} --to=${{ github.event.pull_request.head.sha }}
```

### `.commitlintrc.yml`

```yaml
extends:
  - '@commitlint/config-conventional'
rules:
  type-enum:
    - 2
    - always
    - [feat, fix, docs, style, refactor, perf, test, chore, build, ci, revert]
  subject-case: [0]
  subject-max-length: [2, always, 100]
  body-max-line-length: [0]
```

### CONTRIBUTING.md 增量

新增一节"本地配置 commit hook（可选）"：husky + commitlint 配置命令，强调**不强制**。

### 决定不做 / 推到 M4 的事

- **APK build**：因 `android/app/libs/libcore.aar`（115MB）目前 .gitignore 排除，CI checkout 无此文件，APK build 必挂。推到 M4 用 Git LFS 一起处理。

### 验证

1. 推一个 commit message 不符合规范的 PR → workflow red
2. 改对 commit message → workflow green → merge 可以
3. 故意改坏 dart format → CI red
4. 故意改坏 analyzer → CI red

### M2 完成后用户在 GitHub repo 后台手动做的事

M2 PR merge 后，user 需要在 `Settings → Branches → Branch protection rules` 给 `main` 加规则：

- Require a pull request before merging（必经 PR）
- Require status checks to pass before merging：勾上 `analyze-and-test`、`Commitlint` / `lint`
- Require branches to be up to date before merging
- (可选) Require approvals: 1

不做这步的话 CI red 也能合（auto-merge 也会被绕过），M4 的 dependabot auto-merge 安全前提就崩。

### 风险 + 缓解

| 风险 | 缓解 |
|---|---|
| flutter-action 锁版本 3.41.4 → flutter 升级要手动 bump | M4 加 dependabot 自动 PR |
| commitlint 配 Node 工具链让 CI 多 30s/PR | 可接受 |
| 老代码 dart format 不过 | M2 PR 提交前本地跑 `dart format lib test` 一次 |
| 第一次 CI 配置后 CI 本身可能 red | M2 PR 推送前本地 dry-run analyze + test |

---

## M3：多平台扩展

### `.github/workflows/ci-multi-platform.yml`

```yaml
name: CI Multi-Platform
on:
  push: { branches: [main] }
  workflow_dispatch:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { os: macos-latest,   target: macos,   runner_label: macOS }
          - { os: windows-latest, target: windows, runner_label: Windows }
          - { os: ubuntu-latest,  target: linux,   runner_label: Linux }
    runs-on: ${{ matrix.os }}
    name: build ${{ matrix.runner_label }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.4' }
      - if: matrix.target == 'linux'
        run: sudo apt-get update && sudo apt-get install -y ninja-build pkg-config libgtk-3-dev libsecret-1-dev
      - run: flutter config --enable-${{ matrix.target }}-desktop
      - run: flutter pub get
      - run: flutter build ${{ matrix.target }} --debug
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.runner_label }}-debug
          path: build/${{ matrix.target }}/...
          retention-days: 7
```

### CONTRIBUTING.md 增量

新增"测试多平台改动"：解释 PR 阶段不跑多平台、merge 到 main 后自动跑；想 PR 阶段验证可以请 maintainer `workflow_dispatch` 手动触发。

### 关键决策详述

- **PR 不跑多平台**：private repo 下 macos-latest 10x 计费、windows 2x。每 PR 跑全矩阵 50 分钟+ 配额。一天 10 个 PR 耗光月配额。
- **iOS 不在矩阵**：需 Apple 账号 + 真机；iOS Simulator 不能跑 NetworkExtension；推 M5 独立 spec。
- **Windows/Linux 是 vanilla Flutter**（无 sing-box FFI 集成）：CI green 仅代表 Flutter 工程链未腐，桌面 app 当前是空壳。这是有意的。

### 验证

1. 推一个改 `macos/` 的 commit 到 main → macOS job green
2. 故意改坏 `macos/Runner.swift` → macOS red、Windows/Linux green（验证 fail-fast: false）
3. workflow_dispatch 手动触发能跑

### 风险 + 缓解

| 风险 | 缓解 |
|---|---|
| Linux apt 包名变动 | ubuntu-latest = 24.04 LTS，5 年内稳定 |
| macOS Xcode 升级 break | GitHub runner Xcode changelog；M4 dependabot 提 PR |
| Flutter desktop stable/preview 反复 | 锁 3.41.4，升 flutter 前查 changelog |

---

## M4：release + bot

### Release flow

```
maintainer push feat: ... 到 main
      ↓
release-please action 跑（main push 触发）
      ↓
release-please 累积 conventional commits、生成 release PR：
  - 自动 bump pubspec.yaml 的 version
  - 自动追加 CHANGELOG.md
  - 更新 .release-please-manifest.json
      ↓
maintainer review + merge release PR
      ↓
release-please 自动 tag + 创建 GitHub Release
      ↓
release.yml 下游 jobs 检测 release_created==true 触发：
  build-android / build-macos / build-windows / build-linux
  各自 sign / notarize / 打包 → upload artifact 到 Release
```

### `release-please-config.json`

```json
{
  "release-type": "dart",
  "include-component-in-tag": false,
  "include-v-in-tag": true,
  "bump-minor-pre-major": true,
  "bump-patch-for-minor-pre-major": false,
  "draft": false,
  "prerelease": false,
  "packages": {
    ".": {
      "package-name": "clashmiao",
      "changelog-path": "CHANGELOG.md",
      "release-type": "dart"
    }
  }
}
```

### `.release-please-manifest.json`

```json
{ ".": "0.1.0" }
```

### `.github/workflows/release.yml`

```yaml
name: Release
on:
  push: { branches: [main] }

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      release_created: ${{ steps.rp.outputs.release_created }}
      tag_name:        ${{ steps.rp.outputs.tag_name }}
    steps:
      - uses: googleapis/release-please-action@v4
        id: rp
        with:
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json

  build-android:
    needs: release-please
    if: needs.release-please.outputs.release_created
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: '17' }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.4' }
      - name: decode keystore (if secret present)
        if: env.ANDROID_KEYSTORE_BASE64 != ''
        run: |
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/keystore.jks
          cat > android/key.properties <<EOF
          storeFile=keystore.jks
          storePassword=$ANDROID_KEYSTORE_PASSWORD
          keyAlias=$ANDROID_KEY_ALIAS
          keyPassword=$ANDROID_KEY_PASSWORD
          EOF
        env:
          ANDROID_KEYSTORE_BASE64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS:         ${{ secrets.ANDROID_KEY_ALIAS }}
          ANDROID_KEY_PASSWORD:      ${{ secrets.ANDROID_KEY_PASSWORD }}
      - run: flutter build apk --release --split-per-abi
      - name: upload to release
        run: gh release upload "${{ needs.release-please.outputs.tag_name }}" build/app/outputs/flutter-apk/app-*-release.apk

  build-macos:
    needs: release-please
    if: needs.release-please.outputs.release_created
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.4' }
      - name: import Developer ID cert (if secret present)
        if: env.APPLE_CERT_P12_BASE64 != ''
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/build.keychain
          KEYCHAIN_PASSWORD=$(openssl rand -hex 16)
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
          echo "$APPLE_CERT_P12_BASE64" | base64 -d > /tmp/cert.p12
          security import /tmp/cert.p12 -k "$KEYCHAIN_PATH" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          # 导出 cert identity 给后续 codesign 命令用
          DEVELOPER_ID=$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
          echo "DEVELOPER_ID=$DEVELOPER_ID" >> $GITHUB_ENV
        env:
          APPLE_CERT_P12_BASE64: ${{ secrets.APPLE_CERT_P12_BASE64 }}
          APPLE_CERT_PASSWORD:   ${{ secrets.APPLE_CERT_PASSWORD }}
      - run: flutter build macos --release
      - name: codesign + notarize (if Apple secrets present)
        if: env.APPLE_ID != ''
        run: |
          codesign --deep --force --options=runtime --sign "$DEVELOPER_ID" build/macos/Build/Products/Release/clashmiao.app
          xcrun notarytool submit ... --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
          xcrun stapler staple build/macos/.../clashmiao.app
        env:
          APPLE_ID:           ${{ secrets.APPLE_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          APPLE_TEAM_ID:      ${{ secrets.APPLE_TEAM_ID }}
      - name: create dmg + upload
        run: |
          hdiutil create -volname ClashMiao -srcfolder build/macos/.../clashmiao.app -ov -format UDZO clashmiao.dmg
          gh release upload "${{ needs.release-please.outputs.tag_name }}" clashmiao.dmg

  build-windows:
    needs: release-please
    if: needs.release-please.outputs.release_created
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.4' }
      - run: flutter build windows --release
      - run: Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath clashmiao-windows.zip
      - run: gh release upload "${{ needs.release-please.outputs.tag_name }}" clashmiao-windows.zip

  build-linux:
    needs: release-please
    if: needs.release-please.outputs.release_created
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - run: sudo apt-get update && sudo apt-get install -y ninja-build pkg-config libgtk-3-dev libsecret-1-dev
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.41.4' }
      - run: flutter build linux --release
      - run: tar -czf clashmiao-linux.tar.gz -C build/linux/x64/release/bundle .
      - run: gh release upload "${{ needs.release-please.outputs.tag_name }}" clashmiao-linux.tar.gz
```

**Signing 缺 secrets 时的 graceful degrade**：每个 build job 内部 `if: env.SECRET != ''` 判断；不存在就 fallback 到 debug 签名或跳过 codesign，仍上传 artifact 但 release notes 自动加 `⚠️ unsigned build` 标记。fork 用户没有 secrets 时也能正常出 release，不会卡死。

### `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly, day: monday }
    labels: [dependencies, github-actions]

  - package-ecosystem: pub
    directory: /
    schedule: { interval: weekly, day: monday }
    open-pull-requests-limit: 5
    labels: [dependencies, dart]
    ignore:
      - dependency-name: "*"
        update-types: ["version-update:semver-major"]

  - package-ecosystem: gradle
    directory: /android
    schedule: { interval: weekly }
    labels: [dependencies, android]
```

### `.github/workflows/dependabot-auto-merge.yml`

```yaml
name: Auto-merge Dependabot
on: pull_request_target

permissions:
  contents: write
  pull-requests: write

jobs:
  auto-merge:
    if: github.actor == 'dependabot[bot]'
    runs-on: ubuntu-latest
    steps:
      - uses: dependabot/fetch-metadata@v2
        id: meta
      - if: |
          steps.meta.outputs.update-type == 'version-update:semver-patch' ||
          steps.meta.outputs.update-type == 'version-update:semver-minor'
        run: gh pr merge --auto --squash "$PR_URL"
        env:
          PR_URL:   ${{ github.event.pull_request.html_url }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

GitHub 看 PR 上 CI 全 green 之后才真的 merge。CI 不严就漏，所以 M2 把 CI 加严是 M4 auto-merge 安全的前提。

### Git LFS 接入（同 M4）

```bash
# 在 M4 PR 内执行
git lfs install
git lfs track "android/app/libs/libcore.aar"
git lfs track "core/output/Libbox.xcframework/**"
git lfs track "libcore/bin/libcore.dylib"

# 调整 .gitignore：把 *.aar / *.xcframework 等行移除
# 然后 git add 这些原本被 ignore 的二进制
git add .gitattributes
git add android/app/libs/libcore.aar core/output libcore/bin
```

LFS 私仓 GitHub 默认 1GB 带宽/月。当前 LFS 候选 ~250MB，能撑 4 次完整 clone/月。超了升 GitHub Team plan ($4/user/月) 或者把 .aar 改成 release artifact 不进 LFS。

### CONTRIBUTING.md 增量

新加"发版流程"段：解释 release-please 自动 PR 机制、maintainer review、自动 build 上传 artifact。

### Secrets 清单（用户后续配）

| Secret | 何处获得 | 缺失时影响 |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i /path/to/keystore.jks` | APK 用 debug 签名 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 创建时设的 | 同上 |
| `ANDROID_KEY_PASSWORD` | 同上 | 同上 |
| `ANDROID_KEY_ALIAS` | keystore alias 名 | 同上 |
| `APPLE_CERT_P12_BASE64` | Apple Developer → Cert → Export P12 → base64 | macOS dmg unsigned |
| `APPLE_CERT_PASSWORD` | 导 P12 时设的密码 | 同上 |
| `APPLE_ID` | 你的 Apple ID | 不 notarize |
| `APPLE_APP_PASSWORD` | appleid.apple.com 生成的 app-specific password | 同上 |
| `APPLE_TEAM_ID` | Apple Developer Membership 页面 | 同上 |
| `SECURITY_CONTACT_EMAIL` | 用户填 | SECURITY.md 保留 TBD |

### 验证

1. push 一个 `feat: dummy` commit 到 main → 等 release-please 开 release PR
2. merge release PR → 自动 tag + 出 Release
3. 看 release.yml 是否触发多平台 build → artifact 是否附在 Release
4. 取消订阅 dependabot 第一次后等下周一，看是否自己开 PR

### 风险 + 缓解

| 风险 | 缓解 |
|---|---|
| 第一次 release-please 不识别已有 commits | 推一个 `chore: bootstrap release-please` 手动触发；或者 `gh workflow run release.yml` |
| Git LFS 私仓 1GB 带宽/月超 | 监控 GitHub Settings → Billing → LFS usage；超了升 Team plan 或迁出 LFS |
| Signing secrets 缺失 → fork CI fallback unsigned | 这是有意的；fork 用户自己加 secrets |
| dependabot auto-merge 把不兼容的 minor 合入 | CI 是 gate（analyzer + test + commitlint 全 green 才 merge）；M2 CI 严就是 M4 自动 merge 的前提 |

---

## 全局风险

| 风险 | 缓解 |
|---|---|
| 4 个 PR merge 顺序错误 | 在 PR description 明确依赖：M2 需要 M1、M3 不依赖任何、M4 需要 M2 + M3 |
| 第一个 PR 推完 CI 配置后 CI 自己 fail | M2 PR 推送前本地把 analyzer + test + dart format + commitlint 全跑一遍 |
| `*.g.dart` 当前已 commit，dart format check 可能挂 | analysis_options.yaml 已经把 generated 文件 exclude，但 dart format 没看 exclude；M2 在 ci.yml 的 format 命令只跑 `lib test`，跳过 lib/**/*.g.dart 的话需要明确写 |
| user 没有 Discussions、issue config.yml 引用会 404 | M1 写明：需在 GitHub 后台开启 Discussions feature；不开启时该链接显示但点击 404 |

---

## 终态对比

**before 本 spec**：
- 0 CI、0 templates、0 release flow
- 8 个 commit 散落、没有 changelog
- 1 个 widget test

**after 本 spec（4 个 PR merge 后）**：
- PR 必经 analyze + test + commitlint，failed 阻 merge
- main push 触发多平台 build
- 一致的 Conventional Commits 历史
- release-please 自动出 GitHub Release + signed artifact
- dependabot 周更新、patch/minor 自动 merge
- 完整 CONTRIBUTING / COC / SECURITY / templates，外部贡献者能立刻上手

---

## 后续工作（**不在本 spec 范围**，留给后续独立 spec）

- **M5 iOS Network Extension**：需 Apple 开发者账号、iOS 端代码 port + Xcode 项目配置 + 真机调试 + ci-multi-platform 启用 iOS job
- **测试覆盖扩展**：box_alert.parse / default_config_options / profile_parser 单元测试 + golden test for ConnectionButton
- **macOS 实际可用**：解 sing-box rule-set 鸡蛋问题（profile rule-set 切 local file 或预下载方案）
- **3 个超大 widget 文件拆分**：home_page (830) / proxies_page (786) / settings_page (694)
- **结构化 logger 替代 debugPrint**
