#!/usr/bin/env bash
# fetch-libcore.sh — 把预编译 sing-box 核心库从 GitHub Release 拉到本地，
# 放在各平台 build 期望的路径上。
#
# 用法：
#   bin/fetch-libcore.sh          # 拉当前平台 + Android（最常见）
#   bin/fetch-libcore.sh all      # 拉所有 5 个平台的 lib
#   bin/fetch-libcore.sh ios      # 只拉 iOS xcframework
#   bin/fetch-libcore.sh android  # 只拉 Android aar
#   bin/fetch-libcore.sh macos    # 只拉 macOS dylib
#   bin/fetch-libcore.sh windows  # 只拉 Windows dll
#   bin/fetch-libcore.sh linux    # 只拉 Linux so
#
# 依赖：gh CLI（已登录），unzip

set -euo pipefail

TAG="${LIBCORE_TAG:-libcore-v1.11.0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log()  { printf '\033[0;32m[fetch-libcore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fetch-libcore]\033[0m %s\n' "$*" >&2; }

require_gh() {
  if ! command -v gh >/dev/null; then
    warn "需要 gh CLI（brew install gh && gh auth login）"
    exit 1
  fi
}

dl() {
  local asset="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -s "$dest" ] && [ "${FORCE:-}" != "1" ]; then
    log "$dest 已存在，跳过（FORCE=1 强制覆盖）"
    return
  fi
  log "下载 $asset → $dest"
  gh release download "$TAG" -p "$asset" -O "$dest" --clobber
}

fetch_android() {
  dl libcore-android.aar android/app/libs/libcore.aar
}
fetch_macos() {
  dl libcore-macos-arm64.dylib libcore/bin/libcore.dylib
}
fetch_windows() {
  dl libcore-windows-amd64.dll windows/libs/libcore.dll
}
fetch_linux() {
  dl libcore-linux-amd64.so linux/libs/libcore.so
}
fetch_ios() {
  local tmp="$REPO_ROOT/.cache/libcore-ios.zip"
  mkdir -p "$(dirname "$tmp")" ios/Frameworks
  if [ ! -s "$tmp" ] || [ "${FORCE:-}" = "1" ]; then
    log "下载 Libcore.xcframework.zip"
    gh release download "$TAG" -p Libcore.xcframework.zip -O "$tmp" --clobber
  fi
  rm -rf ios/Frameworks/Libcore.xcframework
  unzip -q -o "$tmp" -d ios/Frameworks/
  log "解压完成：ios/Frameworks/Libcore.xcframework/"
}

require_gh

case "${1:-default}" in
  android) fetch_android ;;
  macos)   fetch_macos ;;
  windows) fetch_windows ;;
  linux)   fetch_linux ;;
  ios)     fetch_ios ;;
  all)
    fetch_android
    fetch_macos
    fetch_windows
    fetch_linux
    fetch_ios
    ;;
  default)
    fetch_android
    case "$(uname -s)" in
      Darwin)  fetch_macos; fetch_ios ;;
      Linux)   fetch_linux ;;
      MINGW*|MSYS*|CYGWIN*) fetch_windows ;;
    esac
    ;;
  *)
    echo "Usage: $0 {android|macos|windows|linux|ios|all|default}"
    exit 1
    ;;
esac

log "done. tag: $TAG"
