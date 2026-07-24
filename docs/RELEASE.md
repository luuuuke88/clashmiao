# Release

`Release` workflow is triggered by tags that match `v*`.

```bash
git tag v0.1.0
git push origin v0.1.0
```

It can also be run manually from GitHub Actions with the same tag value.

## Artifacts

The tag workflow builds and publishes these release assets:

- Windows: `ClashMiao-Windows-x64-Setup.exe`
- Windows: `ClashMiao-Windows-x64-<version>.zip`
- Android: `app-release.apk`
- Android: `app-release.aab`
- macOS: `ClashMiao-macOS-universal.dmg`
- macOS: `ClashMiao-macOS-universal.zip` as a fallback/package archive

Before publishing, the workflow runs formatting, analysis, and unit/widget
tests, then verifies that each platform produced the expected package files.
Windows and macOS also verify that `libcore` is bundled into the app output.

## 版本号来自 tag，不是 pubspec

`pubspec.yaml` 里的 `version:` **不参与**发布产物的版本号。CI 从 tag 推导：

- `--build-name` = tag 去掉 `v` 前缀和 prerelease 后缀（`v1.2.3` → `1.2.3`，
  `v2.0.0-beta.1` → `2.0.0`，因为 Flutter 的 `--build-name` 不接受 prerelease 段）
- `--build-number` = `github.run_number`（仓库级严格递增）

tag 推导不出合法的 `x.y.z` 时，`quality` job 直接失败——它是其它 job 的
`needs`，所以在这里 fail 比让三个 build job 并行跑一半再各炸一次好。

**为什么不能省这一步**：产物版本如果用 pubspec 里写死的 `0.1.0+1`，会有两个
硬性后果——① versionCode 恒为 1，Play Store 要求严格递增，第二个包直接被拒；
② App 里报的版本永远比 tag 旧，「检查更新」（比较 `PackageInfo.version` 与
最新 tag）会对所有用户**永久误报**有新版本，因为更新完新包报的还是老版本号。

---

## 构建期参数（`--dart-define`）

所有编译期参数集中声明在 `lib/core/config/build_config.dart`，由
`release.yml` 从仓库的 Secrets / Variables 注入。**没有配置的项不会让构建
失败，但对应功能在正式包里就是不可用的**，并且 UI 会隐藏该入口而不是显示
一个点了没反应的死链。

| 参数 | 来源 | 没配置的后果 |
|---|---|---|
| `SENTRY_DSN` | Secret `SENTRY_DSN` | **线上崩溃完全不可见**（Sentry SDK 永不初始化） |
| `GITHUB_REPO_SLUG` | Variable `REPO_SLUG` | "检查更新"永远回"已是最新" |
| `GITHUB_REPO_URL` | Variable `REPO_URL` | 有兜底默认值，跳项目主页 |
| `TELEGRAM_CHANNEL_URL` | Variable `TELEGRAM_CHANNEL_URL` | 关于页不显示这一项 |
| `PRIVACY_POLICY_URL` | Variable `PRIVACY_POLICY_URL` | 关于页不显示这一项 —— **上架必需** |
| `TERMS_AND_CONDITIONS_URL` | Variable `TERMS_AND_CONDITIONS_URL` | 引导页条款入口失效 —— **上架必需** |
| `GEOIP_CDN_URL` | Variable `GEOIP_CDN_URL` | Geo 资源下载失败 |
| `GEOSITE_CDN_URL` | Variable `GEOSITE_CDN_URL` | 同上 |

> 变量名不能以 `GITHUB_` 开头（GitHub Actions 保留前缀），所以仓库 Variable
> 叫 `REPO_SLUG` / `REPO_URL`，注入到 App 里的 dart-define 名字保持不变。

Secrets 在 `Settings → Secrets and variables → Actions → Secrets`，
Variables 在同一页的 `Variables` 标签下。

---

## Android 签名（必须先做，否则 release 构建会直接失败）

`release.yml` **不会**在缺少签名配置时回退到 debug 签名。这是有意的：
debug 签名的 AAB 无法上架 Google Play，而且签名 key 一旦确定就不能更换——
产出一个"构建成功"的废包，比构建直接失败糟糕得多。

需要配置这四个 Secret：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

### 生成 keystore

在你自己的机器上执行（**密钥和密码不要发给任何人，也不要提交进仓库**）：

```bash
keytool -genkey -v -keystore ~/clashmiao-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

会依次询问密码和证书信息。记住你输入的：

- **keystore 密码** → 之后填进 `ANDROID_STORE_PASSWORD`
- **key 密码**（可以直接回车沿用 keystore 密码）→ 填进 `ANDROID_KEY_PASSWORD`
- **alias** → 上面命令里是 `upload`，填进 `ANDROID_KEY_ALIAS`

### 转成 base64 并录入

```bash
base64 -i ~/clashmiao-upload-keystore.jks | pbcopy
```

粘贴到 Secret `ANDROID_KEYSTORE_BASE64`。

> ⚠️ **把 `~/clashmiao-upload-keystore.jks` 和密码离线备份好。** 丢了就再也
> 无法给已上架的应用发布更新——Google Play 不接受换签名 key 的新版本。

---

## macOS 签名与公证

现状：`release.yml` 里的签名/公证步骤**已经写好，但需要 Apple 开发者账号
才能生效**。在配置下面这些 Secret 之前，构建照常产出 dmg/zip，只是没有签名。

未签名 dmg 的用户体验：首次打开会被 Gatekeeper 拦住（提示"无法验证开发者"），
需要**右键点击 App → 选择"打开" → 再次确认**。下载页务必写清这一步，否则
用户会以为软件坏了。

账号到位后配置：

- `MACOS_CERTIFICATE_P12_BASE64` — Developer ID Application 证书（.p12）的 base64
- `MACOS_CERTIFICATE_PASSWORD` — 该 .p12 的密码
- `MACOS_SIGNING_IDENTITY` — 形如 `Developer ID Application: Your Name (TEAMID)`
- `MACOS_NOTARY_APPLE_ID` — Apple ID
- `MACOS_NOTARY_PASSWORD` — App-specific password
- `MACOS_NOTARY_TEAM_ID` — Team ID

### 架构

macOS 产物是 **universal**（`x86_64` + `arm64`），Intel Mac 和 Apple Silicon
都能原生运行。CI 会显式校验最终 `.app` 的可执行文件和 `libcore.dylib` 两者
都包含这两个架构——只出 arm64 的话 Intel 用户装了也跑不起来
（Rosetta 只能 x86→arm，反向不行）。

重建 libcore 时注意用 `core/build.sh macos`，它会分别编 amd64/arm64 再
`lipo -create` 合成；只编单架构会静默丢掉 Intel 支持。

---

## Windows 代码签名

**当前不签名。** SmartScreen 会对未签名的安装包弹"Windows 已保护你的电脑"，
用户需要点 **"更多信息" → "仍要运行"** 才能安装。下载页必须写清这一步。

`release.yml` 已预留签名位，购买 OV/EV 代码签名证书后配置：

- `WINDOWS_CERTIFICATE_PFX_BASE64`
- `WINDOWS_CERTIFICATE_PASSWORD`

---

## 发布前检查清单

- [ ] 四个 Android 签名 Secret 已配置（否则构建直接失败）
- [ ] `SENTRY_DSN` 已配置（否则线上崩溃看不到）
- [ ] `PRIVACY_POLICY_URL` / `TERMS_AND_CONDITIONS_URL` 已配置（上架必需）
- [ ] `REPO_SLUG` 已配置（否则"检查更新"永远说已是最新）
- [ ] 下载页写清 macOS 首次打开需右键、Windows 需过 SmartScreen
- [ ] keystore 文件与密码已离线备份
