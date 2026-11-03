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

# Android 与 iOS 用自有内核模块（kernel/，官方 sing-box 1.14.3）构建的产物；桌面本期不动，
# 仍用旧 tag 的外部构建产物。三个 tag 分开：升级一个平台的内核不影响其它平台的下载。
TAG="${LIBCORE_TAG:-libcore-v1.8.9-16k}"
ANDROID_TAG="${ANDROID_LIBCORE_TAG:-libcore-v1.14.3-r2}"
IOS_TAG="${IOS_LIBCORE_TAG:-libcore-v1.14.3-r3}"
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

# 打印文件的 sha256（64 位十六进制）。没有哈希工具或算不出来时返回 3，不退出——
# 让调用方走统一的清理路径。
file_sha256() {
  local out=""
  if command -v sha256sum >/dev/null; then
    out="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" || out=""
  elif command -v shasum >/dev/null; then
    out="$(shasum -a 256 "$1" 2>/dev/null | awk '{print $1}')" || out=""
  else
    warn "需要 sha256sum 或 shasum 来校验下载"
    return 3
  fi
  case "$out" in
    [0-9a-f]*) [ "${#out}" -eq 64 ] || out="" ;;
    *) out="" ;;
  esac
  if [ -z "$out" ]; then
    warn "无法计算 sha256：$1"
    return 3
  fi
  printf '%s\n' "$out"
}

# verify_asset <tag> <asset> <file>
#   0 = 校验通过；1 = 值不一致；2 = 校验和文件里没有这一条；3 = 算不出文件的 sha256。
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
  actual="$(file_sha256 "$file")" || return 3
  if [ "$actual" != "$expected" ]; then
    warn "sha256 不一致：${tag}/${asset}"
    warn "  期望 ${expected}"
    warn "  实际 ${actual}"
    return 1
  fi
  return 0
}

# verify_or_die <tag> <asset> <file> [keep]
# 校验失败一律以非 0 退出。默认先删掉该文件（刚下载的、或我们自己的缓存，绝不把未经校验的
# 二进制留在原地）；第 4 个参数为 keep 时不删——用于跑之前就已存在于构建读取路径上的文件，
# 它可能是开发者自己编的 libcore，删了无法找回。
verify_or_die() {
  local rc=0
  verify_asset "$1" "$2" "$3" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "${4:-}" = "keep" ]; then
    warn "${3} 校验未通过（退出码 ${rc}），已保留，未做任何修改"
    if [ "$rc" -eq 1 ]; then
      warn "要换成官方版本请执行：FORCE=1 bin/fetch-libcore.sh ${CUR_TARGET:-<目标>}（会重新下载并覆盖它）"
    fi
  else
    rm -f "$3"
    warn "已删除 ${3}（校验未通过，退出码 ${rc}）"
  fi
  exit 1
}

dl() {
  local asset="$1" dest="$2" tag="${3:-$TAG}"
  mkdir -p "$(dirname "$dest")"
  if [ -s "$dest" ] && [ "${FORCE:-}" != "1" ]; then
    # 复用的文件同样要校验：它可能是上次中断的下载、被改过的、或别的 tag 留下的。
    # 但它在构建读取的路径上、可能是本地自编产物，所以不通过也不删（keep）。
    verify_or_die "$tag" "$asset" "$dest" keep
    log "${dest} 已存在且校验通过，跳过（FORCE=1 强制覆盖）"
    return
  fi
  log "下载 $asset → $dest"
  gh release download "$tag" -p "$asset" -O "$dest" --clobber --repo "$LIBCORE_REPO"
  verify_or_die "$tag" "$asset" "$dest"
  log "${asset} sha256 校验通过"
}

fetch_android() {
  CUR_TARGET=android
  dl libcore.aar android/app/libs/libcore.aar "$ANDROID_TAG"
}
fetch_macos() {
  CUR_TARGET=macos
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
  CUR_TARGET=windows
  dl libcore.dll windows/libs/libcore.dll
}
fetch_linux() {
  CUR_TARGET=linux
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
  local framework="$1" item
  [ -d "$framework" ] || return

  # 版本化 bundle（Versions/A + 顶层符号链接，gomobile 的默认产物）：先把真实内容搬到顶层，
  # 否则下面删 Versions 会连二进制一起删掉。
  if [ -d "$framework/Versions/A" ]; then
    for item in Headers Modules Libcore; do
      if [ -e "$framework/Versions/A/$item" ]; then
        rm -rf "$framework/$item"
        mv "$framework/Versions/A/$item" "$framework/$item"
      fi
    done
    if [ ! -f "$framework/Info.plist" ] && [ -f "$framework/Versions/A/Resources/Info.plist" ]; then
      mv "$framework/Versions/A/Resources/Info.plist" "$framework/Info.plist"
    fi
  fi

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
  if [ ! -f "$framework/Libcore" ] || [ -L "$framework/Libcore" ]; then
    warn "$framework 缺少二进制 Libcore"
    exit 1
  fi
  write_ios_framework_info_plist "$framework/Info.plist"
}

normalize_ios_xcframework() {
  local xcframework="ios/Frameworks/Libcore.xcframework"
  local framework

  for framework in "$xcframework"/*/Libcore.framework; do
    [ -d "$framework" ] || continue
    normalize_ios_framework_slice "$framework"
  done

  # 清单里的 BinaryPath 若还指向 Versions/A（版本化 bundle 的写法），跟着改成浅层路径
  local plist="$xcframework/Info.plist" n i bp
  if [ -f "$plist" ] && grep -q "Versions/" "$plist" && command -v plutil >/dev/null; then
    n="$(plutil -extract AvailableLibraries raw "$plist" 2>/dev/null || echo 0)"
    i=0
    while [ "$i" -lt "$n" ]; do
      bp="$(plutil -extract "AvailableLibraries.$i.BinaryPath" raw "$plist" 2>/dev/null || true)"
      case "$bp" in
        *Versions/*) plutil -replace "AvailableLibraries.$i.BinaryPath" -string "Libcore.framework/Libcore" "$plist" ;;
      esac
      i=$((i + 1))
    done
  fi
}

fetch_ios() {
  CUR_TARGET=ios
  local tmp="$REPO_ROOT/.cache/libcore-ios.zip"
  mkdir -p "$(dirname "$tmp")" ios/Frameworks
  if [ ! -s "$tmp" ] || [ "${FORCE:-}" = "1" ]; then
    log "下载 Libcore.xcframework.zip"
    gh release download "$IOS_TAG" -p Libcore.xcframework.zip -O "$tmp" --clobber --repo "$LIBCORE_REPO"
  else
    log "${tmp} 已存在，复用前先校验"
  fi
  # 缓存复用与新下载一视同仁：校验通过才允许解压；不通过则 zip 被删、Frameworks 不动。
  verify_or_die "$IOS_TAG" Libcore.xcframework.zip "$tmp"
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

log "done. tag: ${TAG}（Android: ${ANDROID_TAG}，iOS: ${IOS_TAG}）"
