#!/usr/bin/env bash
# setup-android-signing.sh — 生成 Android 上传签名密钥并录入 GitHub Secrets。
#
#   bash bin/setup-android-signing.sh
#
# ## 为什么这一步必须你自己跑
#
# 这把密钥决定"谁能发布用户设备和 Google Play 认可为正版的更新"。它必须：
#   - 只有你知道密码（密码在本脚本里只经过 `read -s`，不回显、不进命令历史）
#   - 由你离线备份（丢了就**永远**无法给已上架的应用发更新，Play 不接受换 key）
#
# 所以这个脚本只做机械工作：生成、编码、上传、校验。密码从头到尾只在你的
# 终端里，不落任何日志。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

KEYSTORE="$HOME/clashmiao-upload-keystore.jks"
ALIAS="upload"

log()  { printf '\033[0;32m[signing]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[signing]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[signing]\033[0m %s\n' "$*" >&2; exit 1; }

command -v keytool >/dev/null || die "找不到 keytool，需要安装 JDK"
command -v gh >/dev/null      || die "找不到 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录，先跑 gh auth login"

# ------------------------------------------------------- 1. 生成 keystore
if [ -f "$KEYSTORE" ]; then
  warn "已存在 $KEYSTORE"
  warn "如果这是你之前给**同一个应用**用过的密钥，继续（会复用它）。"
  warn "如果是别的项目的，先挪走再重跑——覆盖掉的密钥无法恢复。"
  read -r -p "复用现有 keystore？[y/N] " reuse
  [ "$reuse" = "y" ] || die "已中止，什么都没改"
else
  log "生成新的上传密钥：$KEYSTORE"
  echo
  echo "接下来 keytool 会问你："
  echo "  1. keystore 密码（记住它，下面还要用）"
  echo "  2. 姓名/组织等证书信息 —— 随便填，不影响功能，回车可跳过"
  echo "  3. key 密码 —— 直接回车沿用 keystore 密码（推荐，少记一个）"
  echo
  keytool -genkey -v \
    -keystore "$KEYSTORE" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$ALIAS"
fi

# ------------------------------------------------- 2. 读密码（不回显）
echo
read -r -s -p "再输一次 keystore 密码（用于校验和上传，不回显）: " STORE_PW
echo
read -r -s -p "key 密码（刚才直接回车沿用的话，这里输同一个）: " KEY_PW
echo

# 校验密码对不对——错了的话 CI 会在构建时才失败，不如现在就发现
keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass "$STORE_PW" >/dev/null 2>&1 ||
  die "keystore 密码不对（或 alias 不是 '$ALIAS'），什么都没上传"
log "密码校验通过"

# ------------------------------------------------------ 3. 录入 Secrets
log "上传到 GitHub Secrets…"
base64 -i "$KEYSTORE" | gh secret set ANDROID_KEYSTORE_BASE64
printf '%s' "$ALIAS"    | gh secret set ANDROID_KEY_ALIAS
printf '%s' "$KEY_PW"   | gh secret set ANDROID_KEY_PASSWORD
printf '%s' "$STORE_PW" | gh secret set ANDROID_STORE_PASSWORD

unset STORE_PW KEY_PW

# ------------------------------------------------------------ 4. 校验
echo
log "已配置的 Secrets（只显示名字，GitHub 不回显值）："
gh secret list | grep -E 'ANDROID_' || die "没查到 ANDROID_* secret，上传可能失败了"

MISSING=()
for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEY_ALIAS \
            ANDROID_KEY_PASSWORD ANDROID_STORE_PASSWORD; do
  gh secret list | grep -q "^$name" || MISSING+=("$name")
done
[ ${#MISSING[@]} -eq 0 ] || die "缺少：${MISSING[*]}"

echo
log "完成。现在打 tag 就会产出签名的 Android 包了。"
echo
warn "⚠️  最后一件事，比上面所有步骤都重要："
warn "    把 $KEYSTORE 和两个密码离线备份好（密码管理器 / 加密盘 / 纸质）。"
warn "    丢了就永远无法给已上架的应用发布更新——Play Store 不接受换签名 key，"
warn "    只能以新应用重新上架，老用户全部失联。"
