#!/usr/bin/env bash
# make-release-notes.sh — 生成 GitHub Release 正文。
#
# 用法：bin/make-release-notes.sh <version> <assets-dir> > notes.md
#
# 为什么不用 `gh release create --generate-notes` 就完事：那个只会列 commit /
# PR 标题，用户点进 release 页面看到十几个文件名，不知道自己该下哪个。而这个
# 项目还有两个绕不开的坑必须写在下载页上——macOS 包未公证会被 Gatekeeper 拦、
# Windows 包未签名会触发 SmartScreen——用户不知道怎么绕会直接以为软件是坏的。
#
# 缺平台时会在最上面给出显式警告，而不是让用户以为"这个平台不支持"。
set -euo pipefail

VERSION="${1:?用法: bin/make-release-notes.sh <version> <assets-dir>}"
ASSETS="${2:?用法: bin/make-release-notes.sh <version> <assets-dir>}"

# 不要写成 `find ... | grep -q .`：`grep -q` 一命中就退出，find 可能收到
# SIGPIPE，而本脚本开了 pipefail → 函数返回 141 → 被 `|| MISSING+=` 解读成
# "这个平台缺包"，于是在 release 正文里挂一条**假的**缺平台警告。同一个坑在
# package-linux.sh 和 setup-android-signing.sh 里各踩过一次。
# 用命令替换取输出再判空，管道就不存在了。
have() { [ -n "$(find "$ASSETS" -maxdepth 1 -type f -name "$1" -print -quit 2>/dev/null)" ]; }

MISSING=()
have 'ClashMiao-Android-*.apk'      || MISSING+=("Android")
have 'ClashMiao-macOS-*'            || MISSING+=("macOS")
have 'ClashMiao-Windows-*'          || MISSING+=("Windows")
have 'ClashMiao-Linux-*'            || MISSING+=("Linux")

echo "## ClashMiao $VERSION"
echo

if [ ${#MISSING[@]} -gt 0 ]; then
  # 不用 `IFS=、` 拼接：IFS 只取第一个**字节**，而「、」是多字节字符，
  # 结果会拼出乱码（实跑验证过：Android?Linux）。手动拼。
  joined="${MISSING[0]}"
  for m in "${MISSING[@]:1}"; do joined="$joined、$m"; done

  echo "> [!WARNING]"
  echo "> **本次发布缺少以下平台的安装包：$joined**"
  echo '> 这不是「该平台不支持」，是这次构建没能产出。多数情况是仓库缺少对应的'
  # shellcheck disable=SC2016  # 反引号是要输出的 Markdown 代码标记，不是命令替换
  echo '> 签名密钥（Android 必须配置 keystore 才会出包，见 `docs/RELEASE.md`）。'
  echo
fi

echo "### 下载哪个文件"
echo

if have 'ClashMiao-Android-*.apk'; then
  cat <<'EOF'
**Android**

| 文件 | 适用 |
|---|---|
| `ClashMiao-Android-arm64-v8a-*.apk` | **绝大多数手机选这个**（2017 年后的机型基本都是 arm64） |
| `ClashMiao-Android-armeabi-v7a-*.apk` | 老旧 32 位设备 |
| `ClashMiao-Android-x86_64-*.apk` | 模拟器 / x86 平板 |
| `ClashMiao-Android-universal-*.apk` | 不确定自己是哪种架构时用这个（体积约为上面的 3 倍） |

安装需在系统设置里允许「安装未知来源应用」。首次连接会请求 VPN 权限，
这是建立隧道的必要授权。

EOF
fi

if have 'ClashMiao-macOS-*'; then
  cat <<'EOF'
**macOS**（universal，Intel 与 Apple Silicon 都能原生运行）

下载 `ClashMiao-macOS-universal-*.dmg`。

> ⚠️ 安装包**未经 Apple 公证**，首次打开会被 Gatekeeper 拦下，提示"无法验证
> 开发者"。通过方式：在「访达」里**右键点击** ClashMiao.app → 选择「打开」→
> 弹窗里再点一次「打开」。之后就能正常双击启动。

EOF
fi

if have 'ClashMiao-Windows-*'; then
  cat <<'EOF'
**Windows**（x64）

- `ClashMiao-Windows-x64-Setup.exe` —— 安装版
- `ClashMiao-Windows-x64-*.zip` —— 免安装版，解开就能跑

> ⚠️ 安装包**未经代码签名**，SmartScreen 会弹「Windows 已保护你的电脑」。
> 通过方式：点「更多信息」→「仍要运行」。

EOF
fi

if have 'ClashMiao-Linux-*'; then
  cat <<'EOF'
**Linux**（x86_64）

- `clashmiao_*_amd64.deb` —— Debian / Ubuntu，`sudo apt install ./clashmiao_*.deb`
- `ClashMiao-Linux-x86_64-*.tar.gz` —— 其它发行版，解开直接运行 `./clashmiao`

EOF
fi

cat <<'EOF'
### 桌面端的流量接管范围

桌面端（macOS / Windows / Linux）**只做到系统代理级接管，不是全局 TUN**：

- ✅ 遵循系统代理设置的程序（浏览器、多数应用）会走隧道
- ❌ **不遵循的程序会直连并暴露真实 IP** —— 部分游戏、命令行工具、自带代理
  设置的客户端都属于这一类

需要全局接管请用 Android 端。

### 校验下载完整性

`SHA256SUMS.txt` 里是所有文件的 SHA-256。校验方式：

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing   # Linux
shasum -a 256 -c SHA256SUMS.txt --ignore-missing   # macOS
```

---
EOF
