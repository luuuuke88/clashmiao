#!/usr/bin/env bash
# build-android.sh — 从源码重编 Android 内核库 libcore.aar（16 KB 页对齐）。
#
# 产物与 GitHub Release 里分发的 libcore.aar 同源同 API：
#   - 同一个内核上游提交、同一组 build tags、同一个 Go 次版本（1.22，取最新补丁版）、
#     同一版 gomobile / JDK；
#   - 唯一的刻意差异：链接时加 -z max-page-size=16384，并换用 NDK r28
#     （默认就是 16 KB），使 libbox.so 的所有 LOAD 段都按 16 KB 对齐，
#     满足 Android 15+ 16 KB 页设备与 Google Play 的要求。
#
# 用法：
#   tools/libcore/build-android.sh                 # 产物写到 build/libcore/
#   OUT_DIR=/some/dir tools/libcore/build-android.sh
#   REFERENCE_AAR=old/libcore.aar tools/libcore/build-android.sh
#       # 额外与参考 aar 做 Java 公共 API 对比（javap -public，期望零差异）
#   KEEP_WORK=1 ...                                # 保留构建目录便于排查
#   tools/libcore/build-android.sh --self-test     # 故障注入自测（不联网、不构建）
#
# 依赖：
#   - git、curl、unzip、shasum/sha256sum
#   - Android SDK（ANDROID_HOME，默认 ~/Library/Android/sdk 或 ~/Android/Sdk），
#     其中装好 NDK 28.2.13676358（r28c，脚本会读 source.properties 的 Pkg.Revision 核对）：
#       sdkmanager "ndk;28.2.13676358"
#   - JDK 17（JAVA17_HOME，或 macOS 上 /usr/libexec/java_home -v 17 能找到）。
#     用 17 是为了让 classes.jar 与现有发布版逐字节一致。别的 JDK 编出的字节码常量池
#     顺序不同（语义等价），默认直接失败；确实要用，须同时给 REFERENCE_AAR（做公共 API
#     对比）并设 ALLOW_JDK_MISMATCH=1，API 对比通过才放行。
#   - Go 不需要预装：脚本按固定版本下载并校验 sha256。
#
# 可复现性：
#   构建一律在固定绝对路径 BUILD_ROOT（默认 /tmp/clashmiao-libcore-build）里进行，
#   每次开始前清空，源码路径会写进 Go buildinfo，路径固定产物才稳定。
#   在同一台机器、同一套工具链下，两次全新构建的四个 libbox.so 与 classes.jar
#   逐字节相同；是否连 aar 整体也相同，见 README 的说明。改了 BUILD_ROOT 就会得到
#   不同的 buildinfo，也就是不同的哈希。
#
# 这个脚本只负责 Android。iOS / macOS 的 xcframework 同源可编，见 README。

set -euo pipefail

# ---------------------------------------------------------------- 固定参数
# 内核上游仓库与提交（该提交的 go.mod / go.sum 锁定了现发布版的全部依赖版本）
UPSTREAM_REPO="${LIBCORE_UPSTREAM_REPO:?需要设置 LIBCORE_UPSTREAM_REPO}"
UPSTREAM_COMMIT="5098951147c4208d79c57dbbc059b5b4a8e67624"

# 1.22 系列的最后一个补丁版：语言与运行时语义与原发布版（1.22.0）相同，
# 同时带上 crypto/tls、net/http、x509 等标准库的后续安全修复
GO_VERSION="1.22.12"
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
# 注意：macOS 自带 Bash 3.2 在 UTF-8 环境下会把紧跟在 $name 后的中文标点
# 当成变量名的一部分，set -u 下直接报错。所以含中文的字符串里一律写成 ${name}。
log()  { printf '\033[0;32m[libcore]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[libcore]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[libcore]\033[0m %s\n' "$*" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# ---------------------------------------------------------------- 校验函数
# 下面每个函数失败时都会 die（exit 1），并且不依赖 set -e 的行为，
# 所以 --self-test 能在子 shell 里直接对它们做故障注入。

# 读 NDK 的 Pkg.Revision，必须正好等于固定版本
check_ndk_revision() {
  local ndk_root="$1" expected="$2" props rev
  props="${ndk_root}/source.properties"
  [ -f "$props" ] || die "缺少 NDK：${props}（sdkmanager \"ndk;${expected}\"）"
  rev="$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$props" | head -n 1 | tr -d '[:space:]')" \
    || die "读取 ${props} 失败"
  [ -n "$rev" ] || die "${props} 里没有 Pkg.Revision"
  [ "$rev" = "$expected" ] || die "NDK 版本不符：Pkg.Revision=${rev}，需要 ${expected}"
}

# 一个 .so 的所有 LOAD 段都必须 >= 2**14 对齐
check_alignment() {
  local objdump="$1" so="$2" label="$3" out aligns a min=99 n
  [ -f "$so" ] || die "缺少 ${label}/libbox.so"
  out="$("$objdump" -p "$so")" || die "${label}：objdump 执行失败"
  aligns="$(grep -E '^ *LOAD' <<<"$out" | sed -E 's/.*align 2\*\*([0-9]+).*/\1/' || true)"
  [ -n "$aligns" ] || die "${label}：读不到 LOAD 段"
  n=0
  for a in $aligns; do
    case "$a" in ''|*[!0-9]*) die "${label}：解析不出对齐值（${a}）" ;; esac
    n=$((n + 1))
    [ "$a" -lt "$min" ] && min="$a"
  done
  [ "$min" -ge 14 ] || die "${label}：存在 2**${min} 对齐的 LOAD 段（需要 >= 2**14）"
  log "${label}：${n} 个 LOAD 段，最小对齐 2**${min} ✓"
}

# buildinfo：Go 版本、build tags、5 个锁定依赖
check_buildinfo() {
  local so="$1" label="$2" go_version="$3" tags="$4" info first pin
  info="$(go version -m "$so")" || die "${label}：go version -m 失败"
  first="$(sed -n 1p <<<"$info" | awk '{print $NF}')"
  [ "$first" = "go${go_version}" ] || die "${label}：Go 版本不符（${first}）"
  grep -q -- "-tags=${tags}\$" <<<"$info" || die "${label}：build tags 不符"
  shift 4
  for pin in "$@"; do
    # 用 here-string 而不是 echo | grep -q：后者在 pipefail 下会因 SIGPIPE 误判
    grep -q -- "$pin" <<<"$info" || die "${label}：buildinfo 缺 ${pin}"
  done
}

# classes.jar 与发布版的字节码哈希。默认不一致即失败；只有显式
# ALLOW_JDK_MISMATCH=1 且给了 REFERENCE_AAR（之后必须通过 API 对比）才放行。
check_classes_hash() {
  local jar="$1" expected="$2" reference="${3:-}" actual
  actual="$(sha256 "$jar")" || die "读取 ${jar} 失败"
  if [ "$actual" = "$expected" ]; then
    log "classes.jar 与发布版逐字节一致 ✓"
    return 0
  fi
  if [ "${ALLOW_JDK_MISMATCH:-}" = 1 ]; then
    [ -n "$reference" ] || die "classes.jar 哈希与发布版不同（${actual}）；ALLOW_JDK_MISMATCH=1 还需要 REFERENCE_AAR 做公共 API 对比"
    warn "classes.jar 哈希与发布版不同（${actual}）；已设 ALLOW_JDK_MISMATCH=1，下面的公共 API 对比必须通过"
    return 0
  fi
  die "classes.jar 哈希与发布版不同（${actual}，期望 ${expected}）；多半是 JDK 不是 17。确需放行：REFERENCE_AAR=… ALLOW_JDK_MISMATCH=1"
}

# 把一个 jar 里所有类的 javap -public 输出写到文件；javap 失败或输出为空都算失败
javap_public_to() {
  local javap="$1" jar="$2" out="$3" classes
  classes="$(unzip -Z1 "$jar" | grep '\.class$' | sed -e 's/\.class$//' -e 's#/#.#g' | sort)" || return 1
  [ -n "$classes" ] || return 1
  printf '%s\n' "$classes" | xargs "$javap" -public -cp "$jar" >"$out" || return 1
  [ -s "$out" ] || return 1
}

# 两个 jar 的 Java 公共 API 必须零差异；两侧各自生成文件、检查状态，再 diff
compare_public_api() {
  local javap="$1" ref_jar="$2" new_jar="$3" dir="$4"
  mkdir -p "$dir" || die "建不了目录 ${dir}"
  javap_public_to "$javap" "$ref_jar" "$dir/api.ref" || die "参考 jar 的 javap 失败或输出为空"
  javap_public_to "$javap" "$new_jar" "$dir/api.new" || die "新 jar 的 javap 失败或输出为空"
  if ! diff "$dir/api.ref" "$dir/api.new" >"$dir/api.diff"; then
    cat "$dir/api.diff" >&2
    die "公共 API 与参考 aar 不一致"
  fi
}

# ---------------------------------------------------------------- 自测
# 对每条失败路径做故障注入，断言非零退出；每条配一个正向对照，防止自测空转。
run_self_test() {
  local t pass=0 total=0
  t="$(mktemp -d "${TMPDIR:-/tmp}/libcore-selftest.XXXXXX")"
  # shellcheck disable=SC2064  # 有意在此刻展开：函数返回后 $t 已不在作用域
  trap "rm -rf '$t'" EXIT

  expect_fail() {
    local name="$1" rc=0
    shift
    ( "$@" ) >/dev/null 2>&1 || rc=$?
    total=$((total + 1))
    if [ "$rc" -ne 0 ]; then pass=$((pass + 1)); log "自测 ✓ 应失败且已失败：${name}（exit ${rc}）"
    else warn "自测 ✗ 应失败却成功：${name}"; fi
  }
  expect_ok() {
    local name="$1" rc=0
    shift
    ( "$@" ) >/dev/null 2>&1 || rc=$?
    total=$((total + 1))
    if [ "$rc" -eq 0 ]; then pass=$((pass + 1)); log "自测 ✓ 应成功且已成功：${name}"
    else warn "自测 ✗ 应成功却失败：${name}（exit ${rc}）"; fi
  }

  # --- 假 NDK
  mkdir -p "$t/ndk-ok" "$t/ndk-bad"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s\n' "$NDK_VERSION" >"$t/ndk-ok/source.properties"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = 27.1.12297006\n' >"$t/ndk-bad/source.properties"
  mkdir -p "$t/ndk-none"
  expect_ok   "NDK 版本正确" check_ndk_revision "$t/ndk-ok" "$NDK_VERSION"
  expect_fail "NDK 修订号不符" check_ndk_revision "$t/ndk-bad" "$NDK_VERSION"
  expect_fail "NDK 缺 source.properties" check_ndk_revision "$t/ndk-none" "$NDK_VERSION"

  # --- 假 objdump：输出由 FAKE_ALIGN 决定
  cat >"$t/objdump" <<'EOF'
#!/bin/sh
case "$FAKE_ALIGN" in
  good)  for i in 1 2 3 4; do echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**14"; done ;;
  bad)   echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**14"
         echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**12" ;;
  none)  echo "no program headers" ;;
  crash) echo "boom" >&2; exit 3 ;;
esac
EOF
  chmod +x "$t/objdump"
  : >"$t/fake.so"
  expect_ok   "对齐 2**14" env FAKE_ALIGN=good bash -c "$(declare -f die log check_alignment); check_alignment '$t/objdump' '$t/fake.so' x86"
  expect_fail "存在 2**12 的 LOAD 段" env FAKE_ALIGN=bad bash -c "$(declare -f die log check_alignment); check_alignment '$t/objdump' '$t/fake.so' x86"
  expect_fail "读不到 LOAD 段" env FAKE_ALIGN=none bash -c "$(declare -f die log check_alignment); check_alignment '$t/objdump' '$t/fake.so' x86"
  expect_fail "objdump 自己失败" env FAKE_ALIGN=crash bash -c "$(declare -f die log check_alignment); check_alignment '$t/objdump' '$t/fake.so' x86"
  expect_fail "libbox.so 缺失" env FAKE_ALIGN=good bash -c "$(declare -f die log check_alignment); check_alignment '$t/objdump' '$t/missing.so' x86"

  # --- 假 jar（内容即“API”）与假 javap
  mkdir -p "$t/j1/a" "$t/j2/a" "$t/j3/a"
  echo "public class A { void f(); }" >"$t/j1/a/A.class"
  echo "public class A { void f(); }" >"$t/j2/a/A.class"
  echo "public class A { void g(); }" >"$t/j3/a/A.class"
  (cd "$t/j1" && zip -q -r ../ref.jar a)
  (cd "$t/j2" && zip -q -r ../same.jar a)
  (cd "$t/j3" && zip -q -r ../diff.jar a)
  printf 'x' >"$t/readme.txt" && (cd "$t" && zip -q noclass2.jar readme.txt)
  cat >"$t/javap" <<'EOF'
#!/bin/sh
# 用法同 javap -public -cp <jar> <class...>；输出取自 jar 里类文件的内容
case "$FAKE_JAVAP" in
  fail)  exit 1 ;;
  empty) exit 0 ;;
esac
jar="$3"; shift 3
for c in "$@"; do unzip -p "$jar" "$(echo "$c" | tr . /).class"; done
EOF
  chmod +x "$t/javap"
  expect_ok   "公共 API 相同" env FAKE_JAVAP=ok bash -c "$(declare -f die log javap_public_to compare_public_api); compare_public_api '$t/javap' '$t/ref.jar' '$t/same.jar' '$t/w1'"
  expect_fail "公共 API 有差异" env FAKE_JAVAP=ok bash -c "$(declare -f die log javap_public_to compare_public_api); compare_public_api '$t/javap' '$t/ref.jar' '$t/diff.jar' '$t/w2'"
  expect_fail "两侧 javap 都失败（不能误报零差异）" env FAKE_JAVAP=fail bash -c "$(declare -f die log javap_public_to compare_public_api); compare_public_api '$t/javap' '$t/ref.jar' '$t/same.jar' '$t/w3'"
  expect_fail "两侧 javap 输出为空" env FAKE_JAVAP=empty bash -c "$(declare -f die log javap_public_to compare_public_api); compare_public_api '$t/javap' '$t/ref.jar' '$t/same.jar' '$t/w4'"
  expect_fail "jar 里没有类" env FAKE_JAVAP=ok bash -c "$(declare -f die log javap_public_to compare_public_api); compare_public_api '$t/javap' '$t/noclass2.jar' '$t/same.jar' '$t/w5'"

  # --- classes.jar 哈希
  local want
  want="$(sha256 "$t/ref.jar")"
  expect_ok   "classes.jar 哈希一致" env -u ALLOW_JDK_MISMATCH bash -c "$(declare -f die log warn sha256 check_classes_hash); check_classes_hash '$t/ref.jar' '$want'"
  expect_fail "classes.jar 哈希不一致" env -u ALLOW_JDK_MISMATCH bash -c "$(declare -f die log warn sha256 check_classes_hash); check_classes_hash '$t/diff.jar' '$want'"
  expect_fail "哈希不一致 + 仅设 ALLOW_JDK_MISMATCH（无 REFERENCE_AAR）" env ALLOW_JDK_MISMATCH=1 bash -c "$(declare -f die log warn sha256 check_classes_hash); check_classes_hash '$t/diff.jar' '$want' ''"
  expect_ok   "哈希不一致 + ALLOW_JDK_MISMATCH + REFERENCE_AAR（之后仍须过 API 对比）" env ALLOW_JDK_MISMATCH=1 bash -c "$(declare -f die log warn sha256 check_classes_hash); check_classes_hash '$t/diff.jar' '$want' 'ref.aar'"

  log "自测：${pass}/${total} 通过"
  [ "$pass" -eq "$total" ] || die "自测有 $((total - pass)) 项未达预期"
}

if [ "${1:-}" = "--self-test" ]; then
  command -v zip >/dev/null || die "自测需要 zip"
  run_self_test
  exit 0
fi

# ---------------------------------------------------------------- 主流程
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/build/libcore}"
# 固定的绝对构建路径：源码路径会进 buildinfo，所以不能随机
BUILD_ROOT="${BUILD_ROOT:-/tmp/clashmiao-libcore-build}"
case "$BUILD_ROOT" in
  /?*) ;;
  *) die "BUILD_ROOT 必须是非根目录的绝对路径：${BUILD_ROOT}" ;;
esac

host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os/$host_arch" in
  Darwin/arm64)  GO_PLATFORM="darwin-arm64"; GO_SHA256="416c35218edb9d20990b5d8fc87be655d8b39926f15524ea35c66ee70273050d"; NDK_HOST="darwin-x86_64" ;;
  Darwin/x86_64) GO_PLATFORM="darwin-amd64"; GO_SHA256="e7bbe07e96f0bd3df04225090fe1e7852ed33af37c43a23e16edbbb3b90a5b7c"; NDK_HOST="darwin-x86_64" ;;
  Linux/x86_64)  GO_PLATFORM="linux-amd64";  GO_SHA256="4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43"; NDK_HOST="linux-x86_64" ;;
  *) die "不支持的构建主机：${host_os}/${host_arch}" ;;
esac

# ---------------------------------------------------------------- 环境检查
for tool in git curl unzip; do
  command -v "$tool" >/dev/null || die "缺少 ${tool}"
done

if [ -z "${ANDROID_HOME:-}" ]; then
  for c in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    [ -d "$c" ] && ANDROID_HOME="$c" && break
  done
fi
[ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ] || die "找不到 Android SDK，请设置 ANDROID_HOME"
NDK_ROOT="$ANDROID_HOME/ndk/$NDK_VERSION"
check_ndk_revision "$NDK_ROOT" "$NDK_VERSION"
OBJDUMP="$NDK_ROOT/toolchains/llvm/prebuilt/$NDK_HOST/bin/llvm-objdump"
[ -x "$OBJDUMP" ] || die "NDK 里找不到 llvm-objdump：${OBJDUMP}"

if [ -z "${JAVA17_HOME:-}" ] && [ "$host_os" = Darwin ]; then
  JAVA17_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
fi
JAVA_HOME_FOR_BUILD="${JAVA17_HOME:-${JAVA_HOME:-}}"
[ -n "$JAVA_HOME_FOR_BUILD" ] && [ -x "$JAVA_HOME_FOR_BUILD/bin/javac" ] || die "找不到 JDK（设置 JAVA17_HOME）"
javac_ver="$("$JAVA_HOME_FOR_BUILD/bin/javac" -version 2>&1 | awk '{print $2}')"
case "$javac_ver" in
  17|17.*) ;;
  *) [ "${ALLOW_JDK_MISMATCH:-}" = 1 ] || die "需要 JDK 17（当前 javac ${javac_ver}）；确实要用别的版本请同时设 REFERENCE_AAR 与 ALLOW_JDK_MISMATCH=1"
     [ -n "${REFERENCE_AAR:-}" ] || die "ALLOW_JDK_MISMATCH=1 必须配合 REFERENCE_AAR（需要做公共 API 对比）"
     warn "使用 javac ${javac_ver}：classes.jar 不会与发布版逐字节一致，只做公共 API 对比" ;;
esac
if [ -n "${REFERENCE_AAR:-}" ]; then
  [ -f "$REFERENCE_AAR" ] || die "REFERENCE_AAR 不存在：${REFERENCE_AAR}"
fi

# ---------------------------------------------------------------- 构建目录（固定路径）
WORK="$BUILD_ROOT"
LOCK="${BUILD_ROOT}.lock"
mkdir "$LOCK" 2>/dev/null || die "已有构建在用 ${BUILD_ROOT}（或上次被强杀后残留）；确认没有别的构建后删除 ${LOCK} 再重试"
wipe_work() {
  # Go 模块缓存是只读的，先放开写权限才删得掉
  chmod -R u+w "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
}
cleanup() {
  if [ "${KEEP_WORK:-}" = 1 ]; then log "保留构建目录：${WORK}"
  else wipe_work; fi
  rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT
wipe_work
mkdir -p "$WORK"
log "构建目录（固定路径）：${WORK}"

# ---------------------------------------------------------------- Go 工具链
go_tgz="go${GO_VERSION}.${GO_PLATFORM}.tar.gz"
log "下载 Go ${GO_VERSION} (${GO_PLATFORM})"
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
[ "$(go version | awk '{print $3}')" = "go$GO_VERSION" ] || die "go version 与固定版本不符"

# ---------------------------------------------------------------- 源码
log "获取内核源码 @ ${UPSTREAM_COMMIT}"
git init -q "$WORK/src"
git -C "$WORK/src" remote add origin "$UPSTREAM_REPO"
git -C "$WORK/src" fetch -q --depth 1 origin "$UPSTREAM_COMMIT"
git -C "$WORK/src" checkout -q --detach FETCH_HEAD
[ "$(git -C "$WORK/src" rev-parse HEAD)" = "$UPSTREAM_COMMIT" ] || die "源码提交不符"
for pin in "${EXPECTED_PINS[@]}"; do
  grep -q -- "$pin" "$WORK/src/go.mod" || die "go.mod 中缺少锁定版本 ${pin}"
done

# ---------------------------------------------------------------- gomobile
log "安装 gomobile/gobind ${GOMOBILE_VERSION}"
gomobile_ldflags=""
if [ "$host_os" = Darwin ]; then
  # Go 1.22 内部链接器产出的 Mach-O 缺 LC_UUID，新版 macOS 的 dyld 拒绝加载；
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
log "gomobile bind（NDK ${NDK_VERSION}，API ${ANDROID_API}）"
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
unzip -q -o "$WORK/out/libcore.aar" -d "$WORK/check" || die "产物 aar 解压失败"

for abi in "${ABIS[@]}"; do
  so="$WORK/check/jni/$abi/libbox.so"
  check_alignment "$OBJDUMP" "$so" "$abi"
  check_buildinfo "$so" "$abi" "$GO_VERSION" "$BUILD_TAGS" "${EXPECTED_PINS[@]}"
  log "${abi}：libbox.so sha256 $(sha256 "$so")"
done

check_classes_hash "$WORK/check/classes.jar" "$EXPECTED_CLASSES_JAR_SHA256" "${REFERENCE_AAR:-}"

if [ -n "${REFERENCE_AAR:-}" ]; then
  log "与参考 aar 对比 Java 公共 API：${REFERENCE_AAR}"
  mkdir -p "$WORK/ref"
  unzip -q -o "$REFERENCE_AAR" classes.jar -d "$WORK/ref" || die "参考 aar 里取不到 classes.jar"
  compare_public_api "$JAVA_HOME/bin/javap" "$WORK/ref/classes.jar" "$WORK/check/classes.jar" "$WORK/apicmp"
  log "公共 API 零差异 ✓"
fi

# ---------------------------------------------------------------- 输出
mkdir -p "$OUT_DIR"
cp -f "$WORK/out/libcore.aar" "$OUT_DIR/libcore.aar"
(cd "$OUT_DIR" && sha256 libcore.aar | sed 's/$/  libcore.aar/' > libcore.aar.sha256)
log "完成：${OUT_DIR}/libcore.aar"
log "sha256：$(cut -d' ' -f1 "$OUT_DIR/libcore.aar.sha256")"
log "本地使用：cp \"${OUT_DIR}/libcore.aar\" android/app/libs/libcore.aar"
