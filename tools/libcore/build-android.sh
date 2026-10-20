#!/usr/bin/env bash
# build-android.sh — 从源码重编 Android 内核库 libcore.aar（16 KB 页对齐）。
#
# 产物与 GitHub Release 里分发的 libcore.aar 同源同 API：
#   - 同一个内核上游提交、同一组 build tags、同一版 Go / gomobile / JDK；
#   - 唯一的刻意差异：链接时加 -z max-page-size=16384，并换用 NDK r28
#     （默认就是 16 KB），使 libbox.so 的所有 LOAD 段都按 16 KB 对齐，
#     满足 Android 15+ 16 KB 页设备与 Google Play 的要求。
#
# 用法：
#   tools/libcore/build-android.sh                 # 产物写到 build/libcore/
#   OUT_DIR=/some/dir tools/libcore/build-android.sh
#   REFERENCE_AAR=old/libcore.aar tools/libcore/build-android.sh
#       # 额外与参考 aar 做 Java 公共 API 对比（javap -public，期望零差异）
#   KEEP_WORK=1 ...                                # 保留临时目录便于排查
#
# 依赖：
#   - git、curl、unzip、shasum/sha256sum
#   - Android SDK（ANDROID_HOME，默认 ~/Library/Android/sdk 或 ~/Android/Sdk），
#     其中装好 NDK ${NDK_VERSION}：
#       sdkmanager "ndk;28.2.13676358"
#   - JDK 17（JAVA17_HOME，或 macOS 上 /usr/libexec/java_home -v 17 能找到）。
#     用 17 是为了让 classes.jar 与现有发布版逐字节一致；别的 JDK 也能编，
#     但字节码常量池顺序会不同（语义等价），需显式 ALLOW_OTHER_JDK=1。
#   - Go 不需要预装：脚本按固定版本下载并校验 sha256。
#
# 这个脚本只负责 Android。iOS / macOS 的 xcframework 同源可编，见 README。

set -euo pipefail

# ---------------------------------------------------------------- 固定参数
# 内核上游仓库与提交（该提交的 go.mod / go.sum 锁定了现发布版的全部依赖版本）
UPSTREAM_REPO="${LIBCORE_UPSTREAM_REPO:?需要设置 LIBCORE_UPSTREAM_REPO}"
UPSTREAM_COMMIT="5098951147c4208d79c57dbbc059b5b4a8e67624"

GO_VERSION="1.22.0"
# gomobile 命令本身用 v0.1.1（与上游构建配方一致）；绑定运行时 v0.1.3 由 go.mod 决定
GOMOBILE_MODULE="github.com/sagernet/gomobile"
GOMOBILE_VERSION="v0.1.1"
NDK_VERSION="28.2.13676358"   # r28c
ANDROID_API="21"
BUILD_TAGS="with_gvisor,with_quic,with_wireguard,with_ech,with_utls,with_clash_api,with_grpc"
# Java 包名与 .so 名是现有 Kotlin 代码依赖的 ABI，不能改
JAVA_PKG="io.nekohasekai"
LIB_NAME="box"
BIND_PKGS=("github.com/sagernet/sing-box/experimental/libbox" "./mobile")
EXT_LDFLAGS="-Wl,-z,max-page-size=16384"
ABIS=(arm64-v8a armeabi-v7a x86 x86_64)

# 现发布版 classes.jar 的 sha256（JDK 17 编出来应逐字节一致）
EXPECTED_CLASSES_JAR_SHA256="f921f85e436e9698dd4b9b7466459ee408cb4ea890e75bcf396cb7b9b04f912a"

# 依赖锁定校验：buildinfo 里必须出现这些替换版本
EXPECTED_PINS=(
  "v1.8.9-0.20240730122343-cc4e2cf4fb24"
  "v0.0.0-20240717223357-4f3122e0d11d"
  "v0.0.0-20240727191222-383c1da14ff1"
  "v0.0.0-20240729110224-c3df022f042a"
  "v0.0.0-20240730213853-fc0aab6bc5e7"
)

# ---------------------------------------------------------------- 工具函数
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/build/libcore}"

log()  { printf '\033[0;32m[libcore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[libcore]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[libcore]\033[0m %s\n' "$*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os/$host_arch" in
  Darwin/arm64)  GO_PLATFORM="darwin-arm64"; GO_SHA256="bf8e388b09134164717cd52d3285a4ab3b68691b80515212da0e9f56f518fb1e"; NDK_HOST="darwin-x86_64" ;;
  Darwin/x86_64) GO_PLATFORM="darwin-amd64"; GO_SHA256="ebca81df938d2d1047cc992be6c6c759543cf309d401b86af38a6aed3d4090f4"; NDK_HOST="darwin-x86_64" ;;
  Linux/x86_64)  GO_PLATFORM="linux-amd64";  GO_SHA256="f6c8a87aa03b92c4b0bf3d558e28ea03006eb29db78917daec5cfb6ec1046265"; NDK_HOST="linux-x86_64" ;;
  *) die "不支持的构建主机：$host_os/$host_arch" ;;
esac

# ---------------------------------------------------------------- 环境检查
for tool in git curl unzip; do
  command -v "$tool" >/dev/null || die "缺少 $tool"
done

if [ -z "${ANDROID_HOME:-}" ]; then
  for c in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$c" ] && ANDROID_HOME="$c" && break
  done
fi
[ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] || die "找不到 Android SDK，请设置 ANDROID_HOME"
NDK_ROOT="$ANDROID_HOME/ndk/$NDK_VERSION"
[ -f "$NDK_ROOT/source.properties" ] || die "缺少 NDK $NDK_VERSION：sdkmanager \"ndk;$NDK_VERSION\""
OBJDUMP="$NDK_ROOT/toolchains/llvm/prebuilt/$NDK_HOST/bin/llvm-objdump"
[ -x "$OBJDUMP" ] || die "NDK 里找不到 llvm-objdump：$OBJDUMP"

if [ -z "${JAVA17_HOME:-}" ] && [ "$host_os" = Darwin ]; then
  JAVA17_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
fi
JAVA_HOME_FOR_BUILD="${JAVA17_HOME:-${JAVA_HOME:-}}"
[ -n "$JAVA_HOME_FOR_BUILD" ] && [ -x "$JAVA_HOME_FOR_BUILD/bin/javac" ] || die "找不到 JDK（设置 JAVA17_HOME）"
javac_ver="$("$JAVA_HOME_FOR_BUILD/bin/javac" -version 2>&1 | awk '{print $2}')"
case "$javac_ver" in
  17|17.*) ;;
  *) [ "${ALLOW_OTHER_JDK:-}" = 1 ] || die "需要 JDK 17（当前 javac $javac_ver）；确实要用别的版本请设 ALLOW_OTHER_JDK=1"
     warn "使用 javac $javac_ver：classes.jar 不会与发布版逐字节一致（API 仍相同）" ;;
esac

# ---------------------------------------------------------------- 临时目录
tmp_root="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${tmp_root%/}/libcore-android.XXXXXX")"
cleanup() {
  if [ "${KEEP_WORK:-}" = 1 ]; then log "保留临时目录：$WORK"; return; fi
  # Go 模块缓存是只读的，先放开写权限才删得掉
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT
log "临时目录：$WORK"

# ---------------------------------------------------------------- Go 工具链
go_tgz="go${GO_VERSION}.${GO_PLATFORM}.tar.gz"
log "下载 Go $GO_VERSION ($GO_PLATFORM)"
curl -fsSL -o "$WORK/$go_tgz" "https://go.dev/dl/$go_tgz"
[ "$(sha256 "$WORK/$go_tgz")" = "$GO_SHA256" ] || die "Go 压缩包 sha256 不匹配"
tar -xzf "$WORK/$go_tgz" -C "$WORK"

export GOROOT="$WORK/go"
export GOPATH="$WORK/gopath"
export GOMODCACHE="${GOMODCACHE_OVERRIDE:-$GOPATH/pkg/mod}"
export GOBIN="$WORK/gobin"
export GOTOOLCHAIN=local   # go.mod 里有 toolchain 行，必须禁止自动切换到更高版本
export GOFLAGS=""
export CGO_ENABLED=1
export ANDROID_HOME ANDROID_NDK_HOME="$NDK_ROOT"
export JAVA_HOME="$JAVA_HOME_FOR_BUILD"
export PATH="$GOBIN:$GOROOT/bin:$JAVA_HOME/bin:$PATH"
[ "$(go env GOVERSION)" = "go$GO_VERSION" ] || die "Go 版本不对：$(go env GOVERSION)"

# ---------------------------------------------------------------- 源码
log "获取内核源码 @ $UPSTREAM_COMMIT"
git init -q "$WORK/src"
git -C "$WORK/src" remote add origin "$UPSTREAM_REPO"
git -C "$WORK/src" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$WORK/src" checkout -q --detach FETCH_HEAD
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$UPSTREAM_COMMIT" ] || die "源码提交不符"
for pin in "${EXPECTED_PINS[@]}"; do
  grep -q -- "$pin" "$WORK/src/go.mod" || die "go.mod 中缺少锁定版本 $pin"
done

# ---------------------------------------------------------------- gomobile
log "安装 gomobile/gobind $GOMOBILE_VERSION"
gomobile_ldflags=""
if [ "$host_os" = Darwin ]; then
  # Go 1.22.0 内部链接器产出的 Mach-O 缺 LC_UUID，新版 macOS 的 dyld 拒绝加载；
  # 宿主工具改走外部链接，再补一次 ad-hoc 签名。不影响 Android 产物。
  gomobile_ldflags="-linkmode=external"
fi
(cd "$WORK" && go install -ldflags="$gomobile_ldflags" \
  "$GOMOBILE_MODULE/cmd/gomobile@$GOMOBILE_VERSION" \
  "$GOMOBILE_MODULE/cmd/gobind@$GOMOBILE_VERSION")
if [ "$host_os" = Darwin ]; then
  codesign -f -s - "$GOBIN/gomobile" "$GOBIN/gobind" >/dev/null 2>&1
fi

# ---------------------------------------------------------------- 构建
log "gomobile bind（NDK $NDK_VERSION，API $ANDROID_API）"
mkdir -p "$WORK/out"   # gomobile 不会替你建输出目录
(cd "$WORK/src" && gomobile bind -v \
  -androidapi="$ANDROID_API" \
  -javapkg="$JAVA_PKG" \
  -libname="$LIB_NAME" \
  -tags="$BUILD_TAGS" \
  -trimpath \
  -ldflags="-extldflags=$EXT_LDFLAGS" \
  -target=android \
  -o "$WORK/out/libcore.aar" \
  "${BIND_PKGS[@]}") >"$WORK/bind.log" 2>&1 || { tail -40 "$WORK/bind.log" >&2; die "gomobile bind 失败"; }

# ---------------------------------------------------------------- 校验
log "校验产物"
mkdir -p "$WORK/check"
unzip -q -o "$WORK/out/libcore.aar" -d "$WORK/check"

fail=0
for abi in "${ABIS[@]}"; do
  so="$WORK/check/jni/$abi/libbox.so"
  [ -f "$so" ] || { warn "缺少 $abi/libbox.so"; fail=1; continue; }
  aligns="$("$OBJDUMP" -p "$so" | grep -E '^ *LOAD' | sed -E 's/.*align 2\*\*([0-9]+).*/\1/')"
  [ -n "$aligns" ] || { warn "$abi：读不到 LOAD 段"; fail=1; continue; }
  min=99
  for a in $aligns; do [ "$a" -lt "$min" ] && min="$a"; done
  if [ "$min" -ge 14 ]; then
    log "$abi：$(echo "$aligns" | wc -l | tr -d ' ') 个 LOAD 段，最小对齐 2**$min ✓"
  else
    warn "$abi：存在 2**$min 对齐的 LOAD 段（需要 >= 2**14）"; fail=1
  fi

  info="$(go version -m "$so")"
  # 用 here-string 而不是 echo | grep -q：后者在 pipefail 下会因 SIGPIPE 误判
  [ "$(sed -n 1p <<<"$info" | awk '{print $NF}')" = "go$GO_VERSION" ] || { warn "$abi：Go 版本不符"; fail=1; }
  grep -q -- "-tags=$BUILD_TAGS\$" <<<"$info" || { warn "$abi：build tags 不符"; fail=1; }
  for pin in "${EXPECTED_PINS[@]}"; do
    grep -q -- "$pin" <<<"$info" || { warn "$abi：buildinfo 缺 $pin"; fail=1; }
  done
done
[ "$fail" = 0 ] || die "校验失败"

classes_sha="$(sha256 "$WORK/check/classes.jar")"
if [ "$classes_sha" = "$EXPECTED_CLASSES_JAR_SHA256" ]; then
  log "classes.jar 与发布版逐字节一致 ✓"
else
  warn "classes.jar sha256 与发布版不同（$classes_sha）——多半是 JDK 版本差异，请用 REFERENCE_AAR 做 API 对比"
fi

if [ -n "${REFERENCE_AAR:-}" ]; then
  log "与参考 aar 对比 Java 公共 API：$REFERENCE_AAR"
  mkdir -p "$WORK/ref"
  unzip -q -o "$REFERENCE_AAR" classes.jar -d "$WORK/ref"
  javap_public() {
    unzip -Z1 "$1" | grep '\.class$' | sed -e 's/\.class$//' -e 's#/#.#g' | sort \
      | xargs "$JAVA_HOME/bin/javap" -public -cp "$1"
  }
  if diff <(javap_public "$WORK/ref/classes.jar") <(javap_public "$WORK/check/classes.jar") >"$WORK/api.diff"; then
    log "公共 API 零差异 ✓"
  else
    cat "$WORK/api.diff" >&2
    die "公共 API 与参考 aar 不一致"
  fi
fi

# ---------------------------------------------------------------- 输出
mkdir -p "$OUT_DIR"
cp -f "$WORK/out/libcore.aar" "$OUT_DIR/libcore.aar"
(cd "$OUT_DIR" && sha256 libcore.aar | sed 's/$/  libcore.aar/' > libcore.aar.sha256)
log "完成：$OUT_DIR/libcore.aar"
log "sha256：$(cut -d' ' -f1 "$OUT_DIR/libcore.aar.sha256")"
log "本地使用：cp \"$OUT_DIR/libcore.aar\" android/app/libs/libcore.aar"
