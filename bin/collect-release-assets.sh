#!/usr/bin/env bash
# collect-release-assets.sh — 把各平台 job 上传的 artifact 收集到一个暂存目录，
# 供 SHA256SUMS 生成和 `gh release upload` 使用。
#
#   bin/collect-release-assets.sh <artifacts-dir> <staging-dir>
#
# 只收 `release-*` 前缀的 artifact。`store-android-aab` 故意排除：AAB 是
# Play Store 的上传格式，终端用户下载了装不上，放进公开下载列表只会造成困惑。
#
# ## 为什么这段逻辑要单独成脚本
#
# 它原来是内联在 release.yml 里的一段 shell。内联的代码没法在本地跑，于是它带
# 着两个 bug 上线了，直到第一次真实排练发版才炸：
#
#   1. 暂存目录写死叫 `assets`——**仓库自己就有一个 `assets/` 目录**（Flutter
#      的字体/图片/规则集）。checkout 之后 `mkdir -p assets` 直接复用了它，
#      于是 `gh release upload assets/*` 撞上 `assets/fonts` 这个目录，报
#      "read assets/fonts: is a directory" 而失败。
#   2. 更糟的是产物计数：`find assets -type f` 数到 22 个文件，其中只有 5 个是
#      真产物，其余 17 个是仓库资源。那条"一个平台的产物都没有就不发布空
#      release"的守卫因此**完全失效**——四个平台全挂它也会照发一个装满字体
#      文件的 release。
#
# 所以这里有两道防线，而不是只挑一个"更干净的目录名"：调用方传 $RUNNER_TEMP
# 下的路径（结构上不可能和仓库内容重名），脚本自己再拒绝任何非空的暂存目录。
# 第二道防线不依赖调用方选对路径。
set -euo pipefail

ARTIFACTS="${1:?用法: bin/collect-release-assets.sh <artifacts-dir> <staging-dir>}"
STAGING="${2:?用法: bin/collect-release-assets.sh <artifacts-dir> <staging-dir>}"

log() { printf '\033[0;32m[collect]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[0;31m[collect]\033[0m %s\n' "$*" >&2; exit 1; }

[ -d "$ARTIFACTS" ] || die "找不到 artifact 目录：$ARTIFACTS"

# 暂存目录必须是空的或不存在。非空说明它撞上了别的东西（仓库目录、上次运行
# 的残留），继续下去会把无关文件当成发布产物。
if [ -e "$STAGING" ]; then
  [ -d "$STAGING" ] || die "$STAGING 已存在且不是目录"
  if [ -n "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    die "暂存目录 $STAGING 非空——它可能撞上了仓库里的同名目录。换一个路径（建议 \$RUNNER_TEMP 下）"
  fi
fi
mkdir -p "$STAGING"

# 递归找文件，**不要**只扫 release-*/ 的第一层。upload-artifact 会保留所传
# 路径的「最近公共祖先」目录结构：一个 job 如果传了 build/installer/x.exe 和
# build/release/y.zip，公共祖先是 build/，artifact 里就带着 installer/ 和
# release/ 两层子目录；而所有文件都在同一个目录下的 job，落下来就是平的。
# 只扫一层的话，前者的文件会被**静默跳过**——排练时 windows job 明明成功，
# release 里却一个 Windows 包都没有，就是这么来的。
shopt -s nullglob
for dir in "$ARTIFACTS"/release-*/; do
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    # 重名会让后一个悄悄盖掉前一个，发出去的包少一个而没有任何提示。
    [ -e "$STAGING/$base" ] && die "两个 artifact 里都有 $base，重名会互相覆盖"
    cp "$f" "$STAGING/$base"
  done < <(find "$dir" -type f -print0)
done

# -maxdepth 1：只数暂存目录顶层。产物都是单个文件，出现子目录就是收错了东西。
COUNT="$(find "$STAGING" -maxdepth 1 -type f | wc -l | tr -d ' ')"
[ "$COUNT" -gt 0 ] || die "一个平台的产物都没有，不发布空 release"

log "收到 $COUNT 个文件："
find "$STAGING" -maxdepth 1 -type f -printf '  %f (%s bytes)\n' | sort >&2

# 只有这一行走 stdout，方便调用方 `COUNT=$(...)`。
echo "$COUNT"
