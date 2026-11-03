#!/usr/bin/env bash
# build-apple.sh — 从源码构建 iOS 内核 Libcore.xcframework（与 Android 同一份 kernel/ 模块、同一组 tags 与链接参数）。
#
# 用法（只能在装了 Xcode 的 macOS 上跑）：
#   tools/kernel/build-apple.sh                 # 产物写到 build/kernel/
#   OUT_DIR=/some/dir tools/kernel/build-apple.sh
#   KEEP_WORK=1 ...                             # 保留构建目录便于排查
#   tools/kernel/build-apple.sh --check <Libcore.xcframework>   # 只跑放行门（不构建）
#
# 产物：<OUT_DIR>/Libcore.xcframework.zip 与 .sha256。xcframework 含 ios-arm64 与 ios-arm64_x86_64-simulator 两个切片，
# 模块名 Libcore（Xcode 工程与 Swift 的 import 不用改），ObjC 符号前缀 Core（core 门面包名）。
#
# 依赖：Xcode 命令行工具（xcrun）、curl、zip、unzip、shasum；Go 按 build-android.sh 里的固定版本下载并校验 sha256。
# 共享构建参数只来自 env.sh；固定的 Go 版本与 sha256 从 build-android.sh 读取，不在这里再写一份。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tools/kernel/env.sh
source "$SCRIPT_DIR/env.sh"

log()  { printf '\033[0;32m[kernel-apple]\033[0m %s\n' "$*"; }
die()  { printf '\033[0;31m[kernel-apple]\033[0m %s\n' "$*" >&2; exit 1; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

# 固定参数：Go 版本与压缩包 sha256 只在 build-android.sh 里维护一份
pin() { sed -n "s/^$1=\"\\([^\"]*\\)\".*/\\1/p" "$SCRIPT_DIR/build-android.sh" | head -n 1; }
GO_VERSION="$(pin GO_VERSION)"
SINGBOX_MODULE="$(pin SINGBOX_MODULE)"
GODEBUG_DEFAULT="$(pin GODEBUG_DEFAULT)"
[ -n "$GO_VERSION" ] && [ -n "$SINGBOX_MODULE" ] && [ -n "$GODEBUG_DEFAULT" ] || die "读不到 build-android.sh 里的固定参数"
IOS_MIN="15.0"
FRAMEWORK="Libcore"
BIND_PKG="./core"
# 头文件里必须出现的门面符号（缺一个说明 bind 的不是当前 core，或 !android 文件没编进去）
REQUIRED_SYMBOLS="CoreNewEngine CoreNewClient CoreTunnelFileDescriptor CoreBuildConfig CoreParse CoreSetup CorePlatform"

# ---------------------------------------------------------------- 放行门
# check_xcframework <xcframework>：逐切片核对 Go 版本、sing-box 依赖、tags、版本覆盖、GODEBUG 默认值与门面符号。
# check_archive <单架构静态库> <标签> <gomobile 追加的 tags>
# c-archive 里的字符串常量首尾相连（没有 NUL 分隔），strings 切不开；直接在原始字节上按模式取。
check_archive() {
  local bin="$1" label="$2" extra="$3" got_tags v
  raw() { LC_ALL=C grep -aoE "$1" "$bin" | head -n 1; }
  [ -n "$(raw "go${GO_VERSION//./\.}([^0-9]|\$)")" ] || die "${label}：Go 版本串不是 go${GO_VERSION}"
  [ -n "$(raw "dep	${SINGBOX_MODULE}	${SINGBOX_VERSION//./\.}([^0-9.]|\$)")" ] \
    || die "${label}：buildinfo 里没有 ${SINGBOX_MODULE} ${SINGBOX_VERSION}"
  got_tags="$(raw "build	-tags=[A-Za-z0-9_,]+" | sed 's/^build	-tags=//')"
  [ "$(tr ',' '\n' <<<"$got_tags" | sort | tr '\n' ',')" = "$(tr ',' '\n' <<<"${KERNEL_TAGS},${extra}" | sort | tr '\n' ',')" ] \
    || die "${label}：build tags 与 env.sh 不一致（得到 ${got_tags}）"
  v="${SINGBOX_VERSION#v}"
  # 版本串两侧是 NUL（Go 的字符串常量池），不能是版本字符，免得把 go1.14.3 / v1.14.3 / 1.14.30 当成命中
  LC_ALL=C grep -aqE "(^|[^0-9A-Za-z.])${v//./\.}(\$|[^0-9A-Za-z.])" "$bin" \
    || die "${label}：找不到独立的版本串 ${v}，-X 版本覆盖没有生效"
  [ -n "$(raw "$(sed 's/[.]/\\./g' <<<"$GODEBUG_DEFAULT")")" ] || die "${label}：找不到 GODEBUG 默认值 ${GODEBUG_DEFAULT}"
  log "${label}：Go ${GO_VERSION}、tags、sing-box ${SINGBOX_VERSION}、版本覆盖 ✓"
}

# 清单（AvailableLibraries）必须恰好是这两个切片：<平台>|<变体>|<排序后的架构>
EXPECTED_LIBRARIES="ios||arm64
ios|simulator|arm64,x86_64"

check_xcframework() {
  local XC="$1" slices=0 fw slice bin headers sym archs arch extra_tags tmpd plist n i id platform variant got want bp lp want_platform plats
  [ -f "$XC/Info.plist" ] || die "产物缺少 xcframework 的 Info.plist"
  plist="$XC/Info.plist"
  n="$(plutil -extract AvailableLibraries raw "$plist" 2>/dev/null)" || die "清单里没有 AvailableLibraries"
  got=""
  i=0
  while [ "$i" -lt "$n" ]; do
    id="$(plutil -extract "AvailableLibraries.$i.LibraryIdentifier" raw "$plist")" || die "清单第 ${i} 项缺 LibraryIdentifier"
    platform="$(plutil -extract "AvailableLibraries.$i.SupportedPlatform" raw "$plist")" || die "${id}：清单缺 SupportedPlatform"
    # plutil 取不到键时把错误写到 stdout（不同版本不一），所以按退出码判断、失败时丢弃输出
    if ! variant="$(plutil -extract "AvailableLibraries.$i.SupportedPlatformVariant" raw "$plist" 2>/dev/null)"; then variant=""; fi
    archs="$(plutil -extract "AvailableLibraries.$i.SupportedArchitectures" json -o - "$plist" | tr -d '[]" ' | tr ',' '\n' | sort | paste -sd, -)"
    bp="$(plutil -extract "AvailableLibraries.$i.BinaryPath" raw "$plist" 2>/dev/null)" || die "${id}：清单缺 BinaryPath"
    [ "$bp" = "${FRAMEWORK}.framework/${FRAMEWORK}" ] || die "${id}：清单的 BinaryPath 不是浅层路径（${bp}）"
    lp="$(plutil -extract "AvailableLibraries.$i.LibraryPath" raw "$plist" 2>/dev/null)" || die "${id}：清单缺 LibraryPath"
    [ "$lp" = "${FRAMEWORK}.framework" ] && [ -d "$XC/$id/$lp" ] || die "${id}：清单的 LibraryPath 与实际目录不符（${lp}）"
    bin="$XC/$id/$bp"
    [ -f "$bin" ] && [ ! -L "$bin" ] || die "${id}：清单指向的二进制不存在"
    # 二进制里的架构必须与清单声明的完全一致
    [ "$(lipo -archs "$bin" | tr ' ' '\n' | sort | paste -sd, -)" = "$archs" ] || die "${id}：二进制架构与清单不一致"
    got="${got}${platform}|${variant}|${archs}
"
    i=$((i + 1))
  done
  [ "$(printf '%s' "$got" | sort)" = "$(printf '%s\n' "$EXPECTED_LIBRARIES" | sort)" ] \
    || die "清单里的切片不是预期的「设备 arm64 + 模拟器 arm64/x86_64」：$(printf '%s' "$got" | tr '\n' ' ')"
  tmpd="$(mktemp -d "${TMPDIR:-/tmp}/clashmiao-apple-check.XXXXXX")"
  slices=0
  for fw in "$XC"/*/"${FRAMEWORK}.framework"; do
    [ -d "$fw" ] || continue
    slices=$((slices + 1))
    slice="$(basename "$(dirname "$fw")")"
    bin="$fw/${FRAMEWORK}"
    # iOS 只认浅层 bundle：二进制与 Info.plist 必须在根上，不能有 Versions / 符号链接
    [ -f "$bin" ] && [ ! -L "$bin" ] || die "${slice}：根上没有二进制（或是符号链接）"
    [ -f "$fw/Info.plist" ] && [ ! -e "$fw/Versions" ] || die "${slice}：不是浅层 bundle"
    # gomobile 会自动追加平台标签：设备切片 ios，模拟器切片 ios,iossimulator。
    # 平台以清单为准（上面已核对清单恰好是设备 + 模拟器），再用 Mach-O 的 LC_BUILD_VERSION 核对每个目标文件
    if ! variant="$(plutil -extract "AvailableLibraries" json -o - "$plist" | tr '}' '\n' | grep -F "\"LibraryIdentifier\":\"${slice}\"" | grep -o '"SupportedPlatformVariant":"[a-z]*"')"; then variant=""; fi
    case "$variant" in
      *simulator*) extra_tags="ios,iossimulator"; want_platform="7|IOSSIMULATOR" ;;
      "") extra_tags="ios"; want_platform="2|IOS" ;;
      *) die "${slice}：未知的平台变体 ${variant}" ;;
    esac
    archs="$(lipo -archs "$bin")" || die "${slice}：lipo 读不出架构"
    for arch in $archs; do
      if [ "$(printf '%s' "$archs" | wc -w | tr -d ' ')" = 1 ]; then
        cp -f "$bin" "$tmpd/thin"   # 单架构（可能不是胖二进制，lipo -thin 会拒绝）
      else
        lipo -thin "$arch" "$bin" -output "$tmpd/thin" || die "${slice}：取不出 ${arch} 架构"
      fi
      check_archive "$tmpd/thin" "${slice}/${arch}" "$extra_tags"
      plats="$(otool -l "$tmpd/thin" | awk '/LC_BUILD_VERSION/{f=1} f && / platform /{print $2; f=0}' | sort -u | paste -sd, -)"
      printf '%s' "$plats" | grep -qxE "$want_platform" || die "${slice}/${arch}：目标文件的平台是 ${plats:-<无>}，应为 ${want_platform%%|*}"
    done
    headers="$(cat "$fw"/Headers/*.h 2>/dev/null || true)"
    for sym in $REQUIRED_SYMBOLS; do
      grep -q "$sym" <<<"$headers" || die "${slice}：头文件里没有 ${sym}"
    done
    log "${slice}：门面符号 ✓"
  done
  rm -rf "$tmpd"
  [ "$slices" -eq 2 ] || die "xcframework 应有 2 个切片（设备 + 模拟器），实际 ${slices}"
}

if [ "${1:-}" = "--check" ]; then
  [ -n "${2:-}" ] && [ -d "$2" ] || die "用法：$0 --check <Libcore.xcframework>"
  SINGBOX_VERSION="$(awk -v m="$SINGBOX_MODULE" '$1 == m { print $2; exit }' "$REPO_ROOT/kernel/go.mod")"
  [ -n "$SINGBOX_VERSION" ] || die "kernel/go.mod 里没有 ${SINGBOX_MODULE}"
  check_xcframework "$2"
  exit 0
fi

[ "$(uname -s)" = Darwin ] || die "只能在 macOS 上构建 Apple 内核"
case "$(uname -m)" in
  arm64)  GO_PLATFORM="darwin-arm64"; GO_SHA256="$(pin GO_SHA256_DARWIN_ARM64)" ;;
  x86_64) GO_PLATFORM="darwin-amd64"; GO_SHA256="$(pin GO_SHA256_DARWIN_AMD64)" ;;
  *) die "不支持的构建主机：$(uname -m)" ;;
esac
[ -n "$GO_SHA256" ] || die "读不到 Go 压缩包的 sha256"
for tool in curl zip unzip xcrun lipo; do command -v "$tool" >/dev/null || die "缺少 ${tool}"; done
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 || die "Xcode 的 iphoneos SDK 不可用"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/build/kernel}"
CACHE_DIR="${KERNEL_BUILD_CACHE:-$REPO_ROOT/build/kernel-cache}"
mkdir -p "$CACHE_DIR"
go_tgz="go${GO_VERSION}.${GO_PLATFORM}.tar.gz"
if [ ! -f "$CACHE_DIR/$go_tgz" ] || [ "$(sha256 "$CACHE_DIR/$go_tgz")" != "$GO_SHA256" ]; then
  log "下载 Go ${GO_VERSION} (${GO_PLATFORM})"
  curl -fsSL -o "$CACHE_DIR/$go_tgz.part" "https://go.dev/dl/$go_tgz"
  mv "$CACHE_DIR/$go_tgz.part" "$CACHE_DIR/$go_tgz"
fi
[ "$(sha256 "$CACHE_DIR/$go_tgz")" = "$GO_SHA256" ] || die "Go 压缩包 sha256 不匹配"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/clashmiao-kernel-apple.XXXXXX")"
log "构建目录：${WORK}"
cleanup() {
  if [ "${KEEP_WORK:-}" = 1 ]; then log "保留构建目录：${WORK}"; return; fi
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
started_at="$(date +%s)"

tar -xzf "$CACHE_DIR/$go_tgz" -C "$WORK"
export GOROOT="$WORK/go"
export GOPATH="$WORK/gopath"
export GOMODCACHE="${GOMODCACHE_OVERRIDE:-$GOPATH/pkg/mod}"
export GOBIN="$WORK/gobin"
export GOTOOLCHAIN=local
export GOFLAGS="-mod=readonly"
export CGO_ENABLED=1
export PATH="$GOBIN:$GOROOT/bin:$PATH"
[ "$(go env GOVERSION)" = "go$GO_VERSION" ] || die "Go 版本不对：$(go env GOVERSION)"

cd "$REPO_ROOT/kernel"
SINGBOX_VERSION="$(go list -m -f '{{.Version}}' "$SINGBOX_MODULE")"
case "$SINGBOX_VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) die "go.mod 里的 sing-box 版本不是正式 tag：${SINGBOX_VERSION}" ;;
esac
log "sing-box ${SINGBOX_VERSION}，Go ${GO_VERSION}，tags=${KERNEL_TAGS}"

log "安装 gomobile / gobind（版本取自 go.mod）"
go install github.com/sagernet/gomobile/cmd/gomobile github.com/sagernet/gomobile/cmd/gobind
codesign -f -s - "$GOBIN/gomobile" "$GOBIN/gobind" >/dev/null 2>&1 || true
gomobile init >"$WORK/gomobile-init.log" 2>&1 || { tail -20 "$WORK/gomobile-init.log" >&2; die "gomobile init 失败"; }

LDFLAGS_ALL="${KERNEL_LDFLAGS_LINK} -X ${SINGBOX_MODULE}/constant.Version=${SINGBOX_VERSION#v} -X runtime.godebugDefault=${GODEBUG_DEFAULT} -s -w -buildid="
log "gomobile bind（ios + iossimulator，最低 iOS ${IOS_MIN}）"
mkdir -p "$WORK/out"
gomobile bind -v \
  -target ios,iossimulator \
  -iosversion "$IOS_MIN" \
  -trimpath \
  -buildvcs=false \
  -tags "$KERNEL_TAGS" \
  -ldflags "$LDFLAGS_ALL" \
  -o "$WORK/out/${FRAMEWORK}.xcframework" \
  "$BIND_PKG" >"$WORK/bind.log" 2>&1 || { tail -40 "$WORK/bind.log" >&2; die "gomobile bind 失败"; }

# ---------------------------------------------------------------- 拍平
# gomobile 产出的是 macOS 式的版本化 bundle（Versions/A + 符号链接），iOS 只认浅层 bundle：
# 把 Versions/Current 下的内容搬到顶层、Info.plist 放到根上，删掉 Versions 与符号链接。
flatten_framework() {
  local fw="$1" cur
  [ -d "$fw/Versions" ] || return 0
  cur="$fw/Versions/A"
  [ -d "$cur" ] || die "$(basename "$(dirname "$fw")")：找不到 Versions/A"
  local item
  for item in Headers Modules "${FRAMEWORK}"; do
    rm -f "$fw/$item"
    mv "$cur/$item" "$fw/$item" || die "拍平失败：${item}"
  done
  [ -f "$cur/Resources/Info.plist" ] || die "$(basename "$(dirname "$fw")")：缺少 Resources/Info.plist"
  mv "$cur/Resources/Info.plist" "$fw/Info.plist"
  rm -rf "$fw/Versions" "$fw/Resources"
  [ ! -L "$fw/${FRAMEWORK}" ] && [ -f "$fw/${FRAMEWORK}" ] && [ -f "$fw/Info.plist" ] || die "拍平后的结构不对：${fw}"
}
for fw in "$WORK/out/${FRAMEWORK}.xcframework"/*/"${FRAMEWORK}.framework"; do
  flatten_framework "$fw"
done
# xcframework 的清单里 BinaryPath 仍指向 Versions/A，跟着改成浅层路径
plist="$WORK/out/${FRAMEWORK}.xcframework/Info.plist"
n="$(plutil -extract AvailableLibraries raw "$plist")" || die "读不了 xcframework 的 AvailableLibraries"
i=0
while [ "$i" -lt "$n" ]; do
  if plutil -extract "AvailableLibraries.$i.BinaryPath" raw "$plist" >/dev/null 2>&1; then
    plutil -replace "AvailableLibraries.$i.BinaryPath" -string "${FRAMEWORK}.framework/${FRAMEWORK}" "$plist" || die "改写 BinaryPath 失败"
  fi
  i=$((i + 1))
done

# ---------------------------------------------------------------- 放行门
check_xcframework "$WORK/out/${FRAMEWORK}.xcframework"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/${FRAMEWORK}.xcframework.zip"
(cd "$WORK/out" && zip -q -r -y "$OUT_DIR/${FRAMEWORK}.xcframework.zip" "${FRAMEWORK}.xcframework")
(cd "$OUT_DIR" && sha256 "${FRAMEWORK}.xcframework.zip" | sed "s/\$/  ${FRAMEWORK}.xcframework.zip/" >"${FRAMEWORK}.xcframework.zip.sha256")
elapsed=$(( $(date +%s) - started_at ))
log "完成：${OUT_DIR}/${FRAMEWORK}.xcframework.zip（$(wc -c <"$OUT_DIR/${FRAMEWORK}.xcframework.zip" | tr -d ' ') 字节），耗时 ${elapsed}s"
log "sha256：$(cut -d' ' -f1 "$OUT_DIR/${FRAMEWORK}.xcframework.zip.sha256")"
log "本地使用：rm -rf ios/Frameworks/${FRAMEWORK}.xcframework && unzip -q \"${OUT_DIR}/${FRAMEWORK}.xcframework.zip\" -d ios/Frameworks/"
