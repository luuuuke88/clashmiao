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
# 完整性：每个资产在下载之后、以及复用本地已存在的文件之前，都要对照
# tools/kernel/libcore-checksums.txt（路径可用 LIBCORE_CHECKSUMS 覆盖）校验 sha256。
# 不一致或没有条目一律删掉该文件并以非 0 退出——这些二进制会被直接打进安装包。
#
# 依赖：gh CLI（已登录），unzip，shasum 或 sha256sum

set -euo pipefail

# Android 用自有内核模块（kernel/，官方 sing-box 1.14.3）构建的 aar；桌面与 iOS 本期不动，
# 仍用旧 tag 的外部构建产物。两个 tag 分开：升级 Android 内核不影响其它平台的下载。
TAG="${LIBCORE_TAG:-libcore-v1.8.9-16k}"
ANDROID_TAG="${ANDROID_LIBCORE_TAG:-libcore-v1.14.3-r2}"
LIBCORE_REPO="${LIBCORE_REPO:-luuuuke88/clashmiao}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
CHECKSUMS="${LIBCORE_CHECKSUMS:-$REPO_ROOT/tools/kernel/libcore-checksums.txt}"

log()  { printf '\033[0;32m[fetch-libcore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fetch-libcore]\033[0m %s\n' "$*" >&2; }

require_gh() {
  if ! command -v gh >/dev/null; then
    warn "需要 gh CLI（brew install gh && gh auth login）"
    exit 1
  fi
}

file_sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    warn "需要 sha256sum 或 shasum 来校验下载"
    return 3
  fi
}

# verify_asset <tag> <asset> <file>
#   0 = 校验通过；1 = 值不一致；2 = 校验和文件里没有这一条。
#   只返回结果并打印原因，不删文件、不退出——由调用方决定怎么处置。
verify_asset() {
  local tag="$1" asset="$2" file="$3" expected actual
  if [ ! -f "$CHECKSUMS" ]; then
    warn "缺少校验和文件：${CHECKSUMS}"
    return 2
  fi
  expected="$(awk -v k="$tag/$asset" '$1 !~ /^#/ && $2 == k { print $1; exit }' "$CHECKSUMS")"
  if [ -z "$expected" ]; then
    warn "缺少校验和：${tag}/${asset} 不在 ${CHECKSUMS} 里"
    return 2
  fi
  actual="$(file_sha256 "$file")" || exit 1
  if [ "$actual" != "$expected" ]; then
    warn "sha256 不一致：${tag}/${asset}"
    warn "  期望 ${expected}"
    warn "  实际 ${actual}"
    return 1
  fi
  return 0
}

# 校验 <file>；任何失败都删掉它并退出，绝不把未经校验的二进制留在构建会读取的路径上。
verify_or_die() {
  local rc=0
  verify_asset "$1" "$2" "$3" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$3"
    warn "已删除 ${3}（校验未通过，退出码 ${rc}）"
    exit 1
  fi
}

dl() {
  local asset="$1" dest="$2" tag="${3:-$TAG}"
  mkdir -p "$(dirname "$dest")"
  if [ -s "$dest" ] && [ "${FORCE:-}" != "1" ]; then
    # 复用的文件同样要校验：它可能是上次中断的下载、被改过的、或别的 tag 留下的。
    verify_or_die "$tag" "$asset" "$dest"
    log "${dest} 已存在且校验通过，跳过（FORCE=1 强制覆盖）"
    return
  fi
  log "下载 $asset → $dest"
  gh release download "$tag" -p "$asset" -O "$dest" --clobber --repo "$LIBCORE_REPO"
  verify_or_die "$tag" "$asset" "$dest"
  log "${asset} sha256 校验通过"
}

fetch_android() {
  dl libcore.aar android/app/libs/libcore.aar "$ANDROID_TAG"
}
fetch_macos() {
  dl libcore.dylib libcore/bin/libcore.dylib
  if command -v lipo >/dev/null; then
    local archs
    archs="$(lipo -archs libcore/bin/libcore.dylib 2>/dev/null || true)"
    # 必须双架构，不能只查宿主架构。这条通道只分发**一个** dylib 给所有人，
    # 所以唯一正确的产物就是 universal。
    #
    # 之前这里只校验 `uname -m` 在不在里面，结果放过了一个纯 arm64 的资产：
    # Apple Silicon 开发机和 arm64 CI runner 都"通过"，直到 release 流水线跑
    # 完整个 macOS 构建、在最后一步的 universal 断言才炸。校验点离错误源头
    # 太远了——在下载完的当场就能判死的事，不该拖到 5 分钟后。
    case " $archs " in
      *" x86_64 "*) ;;
      *) warn "libcore.dylib 缺 x86_64，Intel Mac 跑不起来（实际: ${archs:-unknown}）"
         warn "重新编：桌面 libcore 需分别编 amd64/arm64 再 lipo 合成 universal"
         exit 1 ;;
    esac
    case " $archs " in
      *" arm64 "*) ;;
      *) warn "libcore.dylib 缺 arm64，Apple Silicon 跑不起来（实际: ${archs:-unknown}）"
         warn "重新编：桌面 libcore 需分别编 amd64/arm64 再 lipo 合成 universal"
         exit 1 ;;
    esac
  fi
}
fetch_windows() {
  dl libcore.dll windows/libs/libcore.dll
}
fetch_linux() {
  dl libcore.so linux/libs/libcore.so
}

write_ios_framework_info_plist() {
  local plist="$1"

  cat >"$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Libcore</string>
	<key>CFBundleIdentifier</key>
	<string>ios.libcore.clashmiao</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Libcore</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0.4</string>
	<key>CFBundleVersion</key>
	<string>2.0.4</string>
	<key>MinimumOSVersion</key>
	<string>15.0</string>
</dict>
</plist>
PLIST
}

normalize_ios_framework_slice() {
  local framework="$1"
  [ -d "$framework" ] || return

  if [ ! -f "$framework/Info.plist" ]; then
    if [ -f "$framework/Resources/Info.plist" ]; then
      cp -f "$framework/Resources/Info.plist" "$framework/Info.plist"
    elif [ -f "$framework/Versions/A/Resources/Info.plist" ]; then
      cp -f "$framework/Versions/A/Resources/Info.plist" "$framework/Info.plist"
    else
      warn "$framework 缺少 Info.plist"
      exit 1
    fi
  fi

  # iOS frameworks must be shallow bundles. Some libcore archives are built with
  # macOS-style Versions/Resources directories, which Xcode rejects for iOS apps.
  rm -rf "$framework/Versions" "$framework/Resources"
  write_ios_framework_info_plist "$framework/Info.plist"
}

normalize_ios_xcframework() {
  local xcframework="ios/Frameworks/Libcore.xcframework"
  local framework

  for framework in "$xcframework"/*/Libcore.framework; do
    [ -d "$framework" ] || continue
    normalize_ios_framework_slice "$framework"
  done
}

fetch_ios() {
  local tmp="$REPO_ROOT/.cache/libcore-ios.zip"
  mkdir -p "$(dirname "$tmp")" ios/Frameworks
  if [ ! -s "$tmp" ] || [ "${FORCE:-}" = "1" ]; then
    log "下载 Libcore.xcframework.zip"
    gh release download "$TAG" -p Libcore.xcframework.zip -O "$tmp" --clobber --repo "$LIBCORE_REPO"
  else
    log "${tmp} 已存在，复用前先校验"
  fi
  # 缓存复用与新下载一视同仁：校验通过才允许解压；不通过则 zip 被删、Frameworks 不动。
  verify_or_die "$TAG" Libcore.xcframework.zip "$tmp"
  log "Libcore.xcframework.zip sha256 校验通过"
  rm -rf ios/Frameworks/Libcore.xcframework
  unzip -q -o "$tmp" -d ios/Frameworks/
  normalize_ios_xcframework
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

log "done. tag: ${TAG}（Android: ${ANDROID_TAG}）"
