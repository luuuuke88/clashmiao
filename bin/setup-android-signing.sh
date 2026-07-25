#!/usr/bin/env bash
# setup-android-signing.sh — 生成 Android 上传签名密钥并录入 GitHub Secrets。
#
#   bash bin/setup-android-signing.sh
#
# **零交互**：不问密码、不问证书信息，跑完就好。
#
# ## 密码怎么来的
#
# 由脚本用 `openssl rand` 在**你自己的机器上**随机生成（32 字符），写进
# `~/clashmiao-signing-password.txt`（权限 600）。全程不打印到屏幕、不进命令
# 历史——所以就算你把本脚本的输出贴给别人看也不会泄漏。
#
# 随机密码比人想的密码强得多，而且你本来就不需要记住它：CI 从 Secrets 读，
# 你本地签包时从那个文件读。
#
# ## 为什么证书信息全部写死
#
# keytool 会问姓名/组织/城市/省份/国家 6 个问题，**这些字段对签名功能毫无
# 影响**——Android 只校验密钥本身，不校验证书里的身份信息（不像 HTTPS 证书
# 有 CA 验证）。而且最后那句"是否正确?"默认是"否"，回车会让它重问一轮，
# 很容易卡住。所以直接用 -dname 一次性给全，跳过整段问答。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

KEYSTORE="$HOME/clashmiao-upload-keystore.jks"
PW_FILE="$HOME/clashmiao-signing-password.txt"
ALIAS="upload"
DNAME="CN=ClashMiao, OU=ClashMiao, O=ClashMiao, L=Unknown, ST=Unknown, C=CN"

log()  { printf '\033[0;32m[signing]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[signing]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[signing]\033[0m %s\n' "$*" >&2; exit 1; }

command -v keytool >/dev/null || die "找不到 keytool，需要安装 JDK"
command -v openssl >/dev/null || die "找不到 openssl"
command -v gh >/dev/null      || die "找不到 gh CLI"
gh auth status >/dev/null 2>&1 || die "gh 未登录，先跑 gh auth login"

# 上一次跑到一半留下的残缺 keystore 要清掉，否则 keytool 会因为 alias 已存在
# 而失败，报一个跟真实原因无关的错。
if [ -f "$KEYSTORE" ]; then
  if [ -f "$PW_FILE" ] && keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" \
       -storepass "$(cat "$PW_FILE")" >/dev/null 2>&1; then
    log "已存在可用的 keystore + 密码文件，复用它们（不重新生成）"
    REUSED=1
  else
    warn "发现残缺/密码不匹配的 $KEYSTORE（上次可能中断了），移到备份并重新生成"
    mv "$KEYSTORE" "$KEYSTORE.broken.$(date +%s)"
    REUSED=0
  fi
else
  REUSED=0
fi

if [ "$REUSED" -eq 0 ]; then
  # 32 字符随机密码。tr 去掉 base64 里的 /+= ——某些工具链对这几个字符处理
  # 不一致，避免踩坑。
  PW="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  [ ${#PW} -eq 32 ] || die "密码生成异常（长度 ${#PW}）"

  # 先建空文件并收紧权限，再写内容——反过来的话内容会有一瞬间是 644。
  : > "$PW_FILE"
  chmod 600 "$PW_FILE"
  printf '%s\n' "$PW" > "$PW_FILE"

  log "生成密钥：$KEYSTORE"
  keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$ALIAS" \
    -dname "$DNAME" \
    -storepass "$PW" -keypass "$PW" >/dev/null 2>&1 ||
    die "keytool 生成失败"
  chmod 600 "$KEYSTORE"
else
  PW="$(cat "$PW_FILE")"
fi

# 校验：密码真的能打开这个 keystore。不验的话错误会推迟到 CI 构建时才暴露。
keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" -storepass "$PW" \
  >/dev/null 2>&1 || die "密钥校验失败（keystore 与密码不匹配）"
log "密钥校验通过"

log "上传到 GitHub Secrets…"
# base64 走管道直传，密钥字节不落任何中间文件、不进任何日志。
base64 -i "$KEYSTORE" | gh secret set ANDROID_KEYSTORE_BASE64
printf '%s' "$ALIAS" | gh secret set ANDROID_KEY_ALIAS
printf '%s' "$PW"    | gh secret set ANDROID_KEY_PASSWORD
printf '%s' "$PW"    | gh secret set ANDROID_STORE_PASSWORD
unset PW

MISSING=()
for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEY_ALIAS \
            ANDROID_KEY_PASSWORD ANDROID_STORE_PASSWORD; do
  gh secret list | grep -q "^$name" || MISSING+=("$name")
done
[ ${#MISSING[@]} -eq 0 ] || die "这些 Secret 没上传成功：${MISSING[*]}"

echo
log "完成。四个 Secret 已就位，现在打 tag 就会产出签名的 Android 包。"
echo
log "本地留存（都是 600 权限，只有你能读）："
log "  密钥： $KEYSTORE"
log "  密码： $PW_FILE"
echo
warn "⚠️  把这两个文件备份到密码管理器或加密盘。"
warn "    丢了就永远无法给已上架的应用发布更新——Google Play 不接受更换签名"
warn "    密钥，只能当新应用重新上架，老用户全部失联。"
