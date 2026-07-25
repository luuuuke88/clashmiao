# Release

## 正式发版

打一个 `v*` 的 tag 即可：

```bash
git tag v0.1.0
git push origin v0.1.0
```

## 先排练一次（强烈建议首次发版前做）

这条流水线的每一步都单独验证过，但**首次真实发版是它的第一次端到端运行**。
Actions 页面手动触发 `Release`，填 tag、**保持 `draft` 勾选**：

- 产物照常构建、release 照常创建，但是 **draft 状态——只有协作者能看到**
- 确认四个平台的包、`SHA256SUMS.txt`、release 正文都对了之后，在 Releases
  页面点 Publish 转正式；不满意直接删掉，外界全程无感

tag push 触发时不受这个开关影响，永远是正式发布。

## 发布产物

打 tag 后会构建并发布这些文件（四个平台）：

| 平台 | 文件 |
|---|---|
| Android | `ClashMiao-Android-arm64-v8a-<ver>.apk`（**多数用户**） |
| | `ClashMiao-Android-armeabi-v7a-<ver>.apk`（老旧 32 位设备） |
| | `ClashMiao-Android-x86_64-<ver>.apk`（模拟器 / x86 平板） |
| | `ClashMiao-Android-universal-<ver>.apk`（不确定架构时用，体积约 3 倍） |
| macOS | `ClashMiao-macOS-universal-<ver>.dmg` / `-<ver>.zip`（Intel + Apple Silicon） |
| Windows | `ClashMiao-Windows-x64-Setup.exe` / `ClashMiao-Windows-x64-<ver>.zip` |
| Linux | `clashmiao_<ver>_amd64.deb` / `ClashMiao-Linux-x86_64-<ver>.tar.gz` |
| 全部 | `SHA256SUMS.txt` |

**AAB 不在公开下载里**。`ClashMiao-Android-<ver>.aab` 作为单独的 workflow
artifact（`store-android-aab`）上传，只用于上传 Play Store——终端用户下载 AAB
是装不上的，放在 release 资产里只会造成困惑。要上传商店时从 Actions 页面的
artifact 里下载。

发布前会跑格式化、静态分析和单元/widget 测试，然后逐平台校验产物存在且
`libcore` 真被打进去了（Linux 还会用 `nm` 验 FFI 符号、macOS 验双架构）。

### 缺一个平台不会阻断其余平台

`publish` 是 `if: always()`：某个平台缺签名密钥或构建失败时，其余平台的包照样
发出去，缺哪个会在 release 正文里显式警告。整个 run 仍然标记为失败，不会掩盖
问题。

之前是硬 `needs`，结果 Android 缺 keystore 就一个包都不发、连桌面端都没有——
用户打开 release 页面看到的是空的。

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

### 一条命令搞定

```bash
bash bin/setup-android-signing.sh
```

它会：生成密钥 → 校验密码 → base64 编码 → 录入四个 Secret → 复查。

密码只经过 `read -s`（不回显、不进命令历史），不落任何日志。中途密码输错会
**当场**报错并中止，而不是等到 CI 构建时才失败。

### 为什么这一步必须你自己跑

这把密钥决定"谁能发布用户设备和 Google Play 认可为正版 ClashMiao 的更新"。
它必须只有你知道密码、由你离线备份。别人（包括 AI 助手）代跑的话，密码会
经过对方的上下文和 shell 历史，而你手上反而没有独立备份。

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

重建 libcore 时必须用 `core/build.sh macos`，它会分别编 amd64/arm64 再
`lipo -create` 合成。上传到 `libcore-v*` tag 的 dylib **必须是 universal**——
那个 tag 给所有人分发同一个文件，单架构等于直接砍掉一半用户。

`bin/fetch-libcore.sh macos` 下载完当场校验双架构，缺哪个报哪个。曾经它只
校验"宿主架构在不在"，于是一个纯 arm64 的资产在 Apple Silicon 开发机和 arm64
CI runner 上一路绿灯，直到 release 流水线跑完整个 macOS 构建才在最后一步炸。

---

## Windows 代码签名

**当前不签名。** SmartScreen 会对未签名的安装包弹"Windows 已保护你的电脑"，
用户需要点 **"更多信息" → "仍要运行"** 才能安装。下载页必须写清这一步。

`release.yml` 已预留签名位，购买 OV/EV 代码签名证书后配置：

- `WINDOWS_CERTIFICATE_PFX_BASE64`
- `WINDOWS_CERTIFICATE_PASSWORD`

---

## 发布前检查清单

- [ ] 四个 Android 签名 Secret 已配置（跑 `bin/setup-android-signing.sh`；否则 Android 包不产出）
- [ ] `SENTRY_DSN` 已配置（否则线上崩溃看不到）
- [ ] `PRIVACY_POLICY_URL` / `TERMS_AND_CONDITIONS_URL` 已配置（上架必需）
- [ ] `REPO_SLUG` 已配置（否则"检查更新"永远说已是最新）
- [ ] 下载页写清 macOS 首次打开需右键、Windows 需过 SmartScreen
- [ ] keystore 文件与密码已离线备份（**最重要的一条**）
- [ ] 先用手动触发 + `draft` 排练过一次，确认产物和正文都对
