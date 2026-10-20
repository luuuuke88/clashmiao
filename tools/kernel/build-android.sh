#!/usr/bin/env bash
# build-android.sh — 从源码构建 Android 内核库 libcore.aar（官方 sing-box 1.14 线 + 自有 Go 模块 kernel/）。
#
# 与旧脚本 tools/libcore/build-android.sh 的关系：沿用其写法（固定版本 + 校验 + 故障注入自测），
# 但是**复制函数而不是 source**——旧脚本冻结，作为回滚工具保持原样。
#
# 用法：
#   tools/kernel/build-android.sh                 # 产物写到 build/kernel/
#   OUT_DIR=/some/dir tools/kernel/build-android.sh
#   KEEP_WORK=1 ...                               # 保留构建目录便于排查
#   UPDATE_API=1 ...                              # 重新生成 kernel/api/java-api.txt（U12 起）
#   tools/kernel/build-android.sh --self-test     # 故障注入自测（不联网、不构建）
#
# 依赖：curl、unzip、zip（自测）、shasum/sha256sum；Android SDK（ANDROID_HOME，默认
#   ~/Library/Android/sdk 或 ~/Android/Sdk）里装好 NDK 28.2.13676358（脚本核对 Pkg.Revision）；
#   JDK 17 或 21（JAVA_HOME，macOS 上也会用 java_home 找）。Go 不需要预装：按固定版本下载并校验 sha256。
#
# 共享构建参数（tags、链接参数）只来自 env.sh，这里不写字面量；
# check-tags-single-source.sh 会拦截任何第二份来源。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=tools/kernel/env.sh
source "$SCRIPT_DIR/env.sh"

# ---------------------------------------------------------------- 固定参数
GO_VERSION="1.27.3"
# 各主机平台的 Go 压缩包 sha256（来自 go.dev/dl 的发布清单）
GO_SHA256_DARWIN_ARM64="dd3908cf20959d798c1e06ebe5b72213f0505ce01373b40ce3110975a6cd99c2"
GO_SHA256_DARWIN_AMD64="b6f8e931e4ab497fcde6da8ae4499a58f9d258e55c8a80824a516eae5950a750"
GO_SHA256_LINUX_AMD64="65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40"
NDK_VERSION="28.2.13676358"   # r28c
ANDROID_API="26"              # = App 的 minSdk
JAVA_PKG="com.clashmiao.libcore"
LIB_NAME="clashmiao"
BIND_PKG="./core"
ABI_DIR="arm64-v8a"           # 只出 arm64（与 abiFilters 一致）
SINGBOX_MODULE="github.com/sagernet/sing-box"
# 发布构建追加的链接参数（版本覆盖由下面按 go.mod 的 sing-box 版本拼接）
GODEBUG_DEFAULT="multipathtcp=0,tlssha1=1"
EXTRA_LDFLAGS_TAIL="-X runtime.godebugDefault=${GODEBUG_DEFAULT} -s -w -buildid="
# 期望的 proguard 规则：只保留门面包，绝不能覆盖 App 自己的包
PROGUARD_KEEP='-keep class com.clashmiao.libcore.** { *; }'
PROGUARD_FORBIDDEN='com.clashmiao.**'

# ---------------------------------------------------------------- 工具函数
# macOS 自带 Bash 3.2 在 UTF-8 环境下会把紧跟在 $name 后的中文标点当成变量名的一部分，
# set -u 下直接报错。所以含中文的字符串里一律写成 ${name}。
log()  { printf '\033[0;32m[kernel]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[kernel]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[kernel]\033[0m %s\n' "$*" >&2; exit 1; }

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

# 文件的 sha256 必须等于期望值
check_sha256() {
  local file="$1" expected="$2" label="$3" actual
  [ -f "$file" ] || die "${label}：文件不存在 ${file}"
  actual="$(sha256 "$file")" || die "${label}：计算 sha256 失败"
  [ "$actual" = "$expected" ] || die "${label}：sha256 不匹配（${actual}，期望 ${expected}）"
}

# 一个 .so 的所有 LOAD 段都必须 >= 2**14 对齐
check_alignment() {
  local objdump="$1" so="$2" label="$3" out aligns a min=99 n
  [ -f "$so" ] || die "缺少 ${label} 的 .so"
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

# go version -m 的输出：Go 版本、tags（与 KERNEL_TAGS 逐项相等）、sing-box 依赖版本。
# 注意：带 -trimpath 时 Go 不把 -ldflags 写进 buildinfo，所以链接参数与 -X 覆盖不能在这里核对，
# 由 check_overrides 看效果（见下）。
# 用法：check_buildinfo <so> <label> <go-version> <tags> <singbox-version-with-v>
# go 命令取自 $GO_BIN（自测里换成假的）
check_buildinfo() {
  local so="$1" label="$2" go_version="$3" tags="$4" sb_ver="$5" info first got_tags
  info="$(${GO_BIN:-go} version -m "$so")" || die "${label}：go version -m 失败"
  first="$(sed -n 1p <<<"$info" | awk '{print $NF}')"
  [ "$first" = "go${go_version}" ] || die "${label}：Go 版本不符（${first}，期望 go${go_version}）"
  got_tags="$(sed -n 's/^[[:space:]]*build[[:space:]]*-tags=//p' <<<"$info" | head -n 1 | tr -d '"')"
  [ -n "$got_tags" ] || die "${label}：buildinfo 里没有 -tags"
  # 逐项相等：排序后比较，顺序不同也算相等，多一项或少一项都不行
  [ "$(tr ',' '\n' <<<"$got_tags" | sort | tr '\n' ',')" = "$(tr ',' '\n' <<<"$tags" | sort | tr '\n' ',')" ] \
    || die "${label}：build tags 与 env.sh 不一致（得到 ${got_tags}）"
  grep -qE "^[[:space:]]*dep[[:space:]]+${SINGBOX_MODULE}[[:space:]]+${sb_ver}([[:space:]]|\$)" <<<"$info" \
    || die "${label}：依赖里没有 ${SINGBOX_MODULE} ${sb_ver}"
  log "${label}：Go ${go_version}、tags、sing-box ${sb_ver} ✓"
}

# 链接期覆盖要看效果：-trimpath 下 buildinfo 不记 -ldflags，所以直接在 .so 的字符串里找
#   - 版本串：sing-box 的 constant.Version 默认值是 unknown，-X 覆盖后应出现独立的 <版本>；
#   - 运行时 GODEBUG 默认值：multipathtcp=0,tlssha1=1。
# （env.sh 里的那个链接参数没有可观察的痕迹：缺了它，用到 linkname 的 libbox 在链接阶段就失败，
#   所以 U12 起真实链接成功本身就是证据；这里只保证传给 bind 的参数里有它，见主流程的断言。）
# 用法：check_overrides <so> <label> <singbox-version-with-v> <godebug-default>
# strings 命令取自 $STRINGS_BIN
check_overrides() {
  local so="$1" label="$2" sb_ver="$3" godebug="$4" strs v
  [ -f "$so" ] || die "${label}：缺少 .so"
  strs="$(${STRINGS_BIN:-strings} -a "$so")" || die "${label}：strings 失败"
  v="${sb_ver#v}"
  # 版本串两侧不能是版本字符，免得把 go1.14.3 / v1.14.3 / 1.14.30 当成命中
  grep -qE "(^|[^0-9A-Za-z.])$(sed 's/\./\\./g' <<<"$v")(\$|[^0-9A-Za-z.])" <<<"$strs" \
    || die "${label}：.so 里找不到独立的版本串 ${v}，-X 版本覆盖没有生效"
  grep -qF -- "$godebug" <<<"$strs" || die "${label}：.so 里找不到 GODEBUG 默认值 ${godebug}，-X runtime.godebugDefault 没有生效"
  log "${label}：版本覆盖与 GODEBUG 默认值已生效 ✓"
}

# proguard.txt 必须含门面包的 keep 规则，且不能含覆盖 App 包的规则
check_proguard() {
  local file="$1" keep="$2" forbidden="$3"
  [ -f "$file" ] || die "缺少 proguard.txt：${file}"
  grep -qxF -- "$keep" "$file" || die "proguard.txt 缺少规则：${keep}"
  if grep -qF -- "$forbidden" "$file"; then die "proguard.txt 含有会覆盖 App 自己包的规则：${forbidden}"; fi
}

# 放行门：对齐、buildinfo、proguard 全部通过之后才写产物。
# 任何一步失败都 die，此前不得往 OUT_DIR 写任何东西。
# 用法：finalize_artifacts <objdump> <check-dir> <built-aar> <out-dir> <go-ver> <tags> <sb-ver> <godebug>
finalize_artifacts() {
  local objdump="$1" check_dir="$2" built_aar="$3" out_dir="$4" go_ver="$5" tags="$6" sb_ver="$7" godebug="$8" so
  so="$check_dir/jni/$ABI_DIR/lib${LIB_NAME}.so"
  check_alignment "$objdump" "$so" "$ABI_DIR"
  check_buildinfo "$so" "$ABI_DIR" "$go_ver" "$tags" "$sb_ver"
  check_overrides "$so" "$ABI_DIR" "$sb_ver" "$godebug"
  check_proguard "$check_dir/proguard.txt" "$PROGUARD_KEEP" "$PROGUARD_FORBIDDEN"
  if [ -n "${API_SNAPSHOT_CHECK:-}" ]; then "$API_SNAPSHOT_CHECK" "$check_dir" || die "Java 公共 API 与快照不一致"; fi
  mkdir -p "$out_dir" || die "建不了输出目录 ${out_dir}"
  cp -f "$built_aar" "$out_dir/libcore.aar" || die "复制产物失败"
  (cd "$out_dir" && sha256 libcore.aar | sed 's/$/  libcore.aar/' > libcore.aar.sha256) || die "写 sha256 失败"
}

# ---------------------------------------------------------------- 构建目录
# 构建目录会被递归 chmod / rm，所以路径必须先规范化并严格限定：
#   - 必须是绝对路径；折叠重复斜杠、去掉尾部斜杠；不允许 . 与 .. 分量；
#   - 最后一级必须是专用目录名 BUILD_DIR_NAME（根目录及其各种写法、$HOME 因此都被拒绝）；
#   - 上级目录必须存在，且目标本身不能是符号链接；
#   - 锁是构建目录的“同级”目录 <规范路径>.lock，用 mkdir 原子创建，不在构建目录里面。
BUILD_DIR_NAME="clashmiao-kernel-build"
BUILD_ROOT_LOGICAL=""
BUILD_ROOT_CANON=""
LOCK_HELD=0

resolve_build_root() {
  local raw="$1" p base parent cparent canon hcanon
  case "$raw" in
    /*) ;;
    *) die "BUILD_ROOT 必须是绝对路径：${raw}" ;;
  esac
  p="$(printf '%s' "$raw" | sed -e 's#//*#/#g' -e 's#/*$##')" || die "BUILD_ROOT 规范化失败"
  [ -n "$p" ] || die "BUILD_ROOT 不能是根目录：${raw}"
  case "${p}/" in
    */./*|*/../*) die "BUILD_ROOT 不能含 . 或 .. 分量：${raw}" ;;
  esac
  base="${p##*/}"
  parent="${p%/*}"
  [ -n "$parent" ] || parent="/"
  [ "$base" = "$BUILD_DIR_NAME" ] || die "BUILD_ROOT 的最后一级必须是专用目录名 ${BUILD_DIR_NAME}：${raw}"
  [ -d "$parent" ] || die "BUILD_ROOT 的上级目录不存在：${parent}"
  cparent="$(cd "$parent" && pwd -P)" || die "解析上级目录失败：${parent}"
  [ -n "$cparent" ] || die "解析上级目录失败：${parent}"
  if [ "$cparent" = "/" ]; then canon="/${base}"; else canon="${cparent}/${base}"; fi
  if [ -n "${HOME:-}" ] && [ -d "$HOME" ]; then
    hcanon="$(cd "$HOME" && pwd -P)" || die "解析 HOME 失败"
    [ "$canon" != "$hcanon" ] || die "BUILD_ROOT 不能是 HOME：${raw}"
  fi
  [ ! -L "$p" ] || die "BUILD_ROOT 不能是符号链接：${raw}"
  if [ -e "$canon" ] && [ ! -d "$canon" ]; then die "BUILD_ROOT 已存在但不是目录：${canon}"; fi
  BUILD_ROOT_LOGICAL="$p"
  BUILD_ROOT_CANON="$canon"
}

acquire_build_lock() {
  local lock="${BUILD_ROOT_CANON}.lock"
  mkdir "$lock" 2>/dev/null || die "已有构建在用 ${BUILD_ROOT_CANON}（或上次被强杀后残留）；确认没有别的构建后删除 ${lock} 再重试"
  LOCK_HELD=1
}

wipe_dir() {
  local d="$1"
  case "$d" in
    ''|/) die "拒绝清理：${d:-<空>}" ;;
  esac
  # Go 模块缓存是只读的，先放开写权限才删得掉
  chmod -R u+w "$d" 2>/dev/null || true
  rm -rf "$d"
}

cleanup() {
  # 没拿到锁（比如被别的构建占着）就什么都不碰：既不清目录，也不删别人的锁
  [ "$LOCK_HELD" = 1 ] || return 0
  if [ "${KEEP_WORK:-}" = 1 ]; then log "保留构建目录：${BUILD_ROOT_LOGICAL}"
  else wipe_dir "$BUILD_ROOT_LOGICAL"; fi
  rmdir "${BUILD_ROOT_CANON}.lock" 2>/dev/null || true
}
prepare_build_dir() {
  resolve_build_root "$1"
  acquire_build_lock
  wipe_dir "$BUILD_ROOT_LOGICAL"
  mkdir -p "$BUILD_ROOT_LOGICAL" || die "建不了构建目录 ${BUILD_ROOT_LOGICAL}"
}

# ---------------------------------------------------------------- 自测
# 对每条失败路径做故障注入，断言非零退出；每条配一个正向对照，防止自测空转。
# shellcheck disable=SC2329  # 自测里的辅助函数都经 expect_ok / expect_fail 间接调用
run_self_test() {
  local t pass=0 total=0
  local tmp_root="${TMPDIR:-/tmp}"
  t="$(mktemp -d "${tmp_root%/}/kernel-selftest.XXXXXX")"
  # shellcheck disable=SC2064  # 有意在此刻展开：函数返回后 $t 已不在作用域
  trap "rm -rf '$t'" EXIT

  run_quiet() {
    if [ "${SELFTEST_VERBOSE:-}" = 1 ]; then ( "$@" ); else ( "$@" ) >/dev/null 2>&1; fi
  }
  expect_fail() {
    local name="$1" rc=0
    shift
    run_quiet "$@" || rc=$?
    total=$((total + 1))
    if [ "$rc" -ne 0 ]; then pass=$((pass + 1)); log "自测 ✓ 应失败且已失败：${name}（exit ${rc}）"
    else warn "自测 ✗ 应失败却成功：${name}"; fi
  }
  expect_ok() {
    local name="$1" rc=0
    shift
    run_quiet "$@" || rc=$?
    total=$((total + 1))
    if [ "$rc" -eq 0 ]; then pass=$((pass + 1)); log "自测 ✓ 应成功且已成功：${name}"
    else warn "自测 ✗ 应成功却失败：${name}（exit ${rc}）"; fi
  }

  # --- 假 NDK
  mkdir -p "$t/ndk-ok" "$t/ndk-bad" "$t/ndk-none"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s\n' "$NDK_VERSION" >"$t/ndk-ok/source.properties"
  printf 'Pkg.Desc = Android NDK\nPkg.Revision = 27.1.12297006\n' >"$t/ndk-bad/source.properties"
  expect_ok   "NDK 版本正确" check_ndk_revision "$t/ndk-ok" "$NDK_VERSION"
  expect_fail "NDK 修订号不符" check_ndk_revision "$t/ndk-bad" "$NDK_VERSION"
  expect_fail "NDK 缺 source.properties" check_ndk_revision "$t/ndk-none" "$NDK_VERSION"

  # --- sha256
  printf 'hello' >"$t/blob"
  local blob_sum; blob_sum="$(sha256 "$t/blob")"
  expect_ok   "sha256 一致" bash -c "$(declare -f die log sha256 check_sha256); check_sha256 '$t/blob' '$blob_sum' blob"
  expect_fail "sha256 不一致" bash -c "$(declare -f die log sha256 check_sha256); check_sha256 '$t/blob' 'deadbeef' blob"
  expect_fail "sha256 的文件缺失" bash -c "$(declare -f die log sha256 check_sha256); check_sha256 '$t/none' '$blob_sum' blob"

  # --- 假 objdump：输出由 FAKE_ALIGN 决定
  cat >"$t/objdump" <<'FAKE'
#!/bin/sh
case "$FAKE_ALIGN" in
  good)  for i in 1 2 3 4; do echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**14"; done ;;
  bad)   echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**14"
         echo "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**12" ;;
  none)  echo "no program headers" ;;
  crash) echo "boom" >&2; exit 3 ;;
esac
FAKE
  chmod +x "$t/objdump"
  : >"$t/fake.so"
  local align_fns; align_fns="$(declare -f die log check_alignment)"
  expect_ok   "对齐 2**14" env FAKE_ALIGN=good bash -c "$align_fns; check_alignment '$t/objdump' '$t/fake.so' arm64"
  expect_fail "存在 2**12 的 LOAD 段" env FAKE_ALIGN=bad bash -c "$align_fns; check_alignment '$t/objdump' '$t/fake.so' arm64"
  expect_fail "读不到 LOAD 段" env FAKE_ALIGN=none bash -c "$align_fns; check_alignment '$t/objdump' '$t/fake.so' arm64"
  expect_fail "objdump 自己失败" env FAKE_ALIGN=crash bash -c "$align_fns; check_alignment '$t/objdump' '$t/fake.so' arm64"
  expect_fail ".so 缺失" env FAKE_ALIGN=good bash -c "$align_fns; check_alignment '$t/objdump' '$t/missing.so' arm64"

  # --- 假 go：go version -m 的输出由 FAKE_INFO 选择
  local sbv="v9.9.9" gov="9.9" tags="${KERNEL_TAGS}" link="${KERNEL_LDFLAGS_LINK}"
  mk_info() { # mk_info <go> <tags> <dep-version>
    printf 'fake.so: go%s\n\tpath\tgithub.com/example/core\n\tdep\t%s\t%s\th1:x=\n\tbuild\t-buildmode=c-shared\n\tbuild\t-tags=%s\n' \
      "$1" "$SINGBOX_MODULE" "$3" "$2"
  }
  mk_info "$gov" "$tags" "$sbv" >"$t/info-good"
  mk_info "9.8" "$tags" "$sbv" >"$t/info-gover"
  mk_info "$gov" "${tags},with_clash_api" "$sbv" >"$t/info-tags-extra"
  mk_info "$gov" "${tags%,*}" "$sbv" >"$t/info-tags-missing"
  mk_info "$gov" "$(tr ',' '\n' <<<"$tags" | sort -r | paste -sd, -)" "$sbv" >"$t/info-tags-reordered"
  mk_info "$gov" "$tags" "v9.9.8" >"$t/info-dep"
  printf 'fake.so: go%s\n\tpath\tx\n\tdep\t%s\t%s\n' "$gov" "$SINGBOX_MODULE" "$sbv" >"$t/info-notags"
  cat >"$t/go" <<'FAKE'
#!/bin/sh
# 用法同 go version -m <file>；输出取自 $FAKE_INFO 指向的文件
[ "$FAKE_INFO" = fail ] && exit 1
cat "$FAKE_INFO"
FAKE
  chmod +x "$t/go"
  local bi_fns; bi_fns="$(declare -f die log check_buildinfo); SINGBOX_MODULE='$SINGBOX_MODULE'"
  bi() { env FAKE_INFO="$t/info-$1" GO_BIN="$t/go" bash -c "$bi_fns; check_buildinfo '$t/fake.so' x '$gov' '$tags' '$sbv'"; }
  expect_ok   "buildinfo 全部吻合" bi good
  expect_ok   "buildinfo：tags 顺序不同但集合相同" bi tags-reordered
  expect_fail "buildinfo：Go 版本不符" bi gover
  expect_fail "buildinfo：tags 多一项" bi tags-extra
  expect_fail "buildinfo：tags 少一项" bi tags-missing
  expect_fail "buildinfo：依赖的 sing-box 版本不符" bi dep
  expect_fail "buildinfo：根本没有 tags" bi notags
  expect_fail "buildinfo：go version -m 自己失败" env FAKE_INFO=fail GO_BIN="$t/go" bash -c "$bi_fns; check_buildinfo '$t/fake.so' x '$gov' '$tags' '$sbv'"

  # --- 链接期覆盖（用假 strings：直接把文件内容当成 .so 里的字符串）
  printf '\001\002\n%s\n\003multipathtcp=0,tlssha1=1\n' "${sbv#v}" >"$t/so-good"
  printf '\001\002\nunknown\n\003multipathtcp=0,tlssha1=1\n' >"$t/so-nover"
  printf '\001\002\ngo%s\nv%s\n%s0\n\003multipathtcp=0,tlssha1=1\n' "${sbv#v}" "${sbv#v}" "${sbv#v}" >"$t/so-lookalike"
  printf '\001\002\n%s\n\003\n' "${sbv#v}" >"$t/so-nodebug"
  printf '#!/bin/sh\nshift\ncat "$1"\n' >"$t/strings"; chmod +x "$t/strings"
  local ov_fns; ov_fns="$(declare -f die log check_overrides)"
  ov() { env STRINGS_BIN="$t/strings" bash -c "$ov_fns; check_overrides '$t/so-$1' x '$sbv' '$GODEBUG_DEFAULT'"; }
  expect_ok   "覆盖：版本与 GODEBUG 默认值都在" ov good
  expect_fail "覆盖：版本仍是默认的 unknown" ov nover
  expect_fail "覆盖：只有相似串（go9.9.9 / v9.9.9 / 9.9.90）不算命中" ov lookalike
  expect_fail "覆盖：GODEBUG 默认值缺失" ov nodebug
  expect_fail "覆盖：.so 缺失" env STRINGS_BIN="$t/strings" bash -c "$ov_fns; check_overrides '$t/none' x '$sbv' '$GODEBUG_DEFAULT'"

  # --- proguard
  printf '%s\n-keep class go.** { *; }\n' "$PROGUARD_KEEP" >"$t/pg-ok"
  printf -- '-keep class go.** { *; }\n' >"$t/pg-nokeep"
  printf '%s\n-keep class %s { *; }\n' "$PROGUARD_KEEP" "$PROGUARD_FORBIDDEN" >"$t/pg-wide"
  local pg_fns; pg_fns="$(declare -f die check_proguard)"
  expect_ok   "proguard 规则正确" bash -c "$pg_fns; check_proguard '$t/pg-ok' '$PROGUARD_KEEP' '$PROGUARD_FORBIDDEN'"
  expect_fail "proguard 缺门面包规则" bash -c "$pg_fns; check_proguard '$t/pg-nokeep' '$PROGUARD_KEEP' '$PROGUARD_FORBIDDEN'"
  expect_fail "proguard 含覆盖 App 包的规则" bash -c "$pg_fns; check_proguard '$t/pg-wide' '$PROGUARD_KEEP' '$PROGUARD_FORBIDDEN'"
  expect_fail "proguard 缺文件" bash -c "$pg_fns; check_proguard '$t/none' '$PROGUARD_KEEP' '$PROGUARD_FORBIDDEN'"

  # --- 放行门（真实的 finalize_artifacts，端到端）：任何一道不过都不写产物
  gate() { # gate <case> <align> <info> <proguard> <so-fixture> [API_SNAPSHOT_CHECK=...]
    local c="$1" align="$2" info="$3" pg="$4" d="$t/gate-$c"
    mkdir -p "$d/check/jni/$ABI_DIR" "$d/work"
    cp "$t/$pg" "$d/check/proguard.txt"
    printf 'aar' >"$d/built.aar"
    local so="$5"
    shift 5
    local kv; for kv in "$@"; do export "${kv%%=*}=${kv#*=}"; done
    cp "$t/so-$so" "$d/check/jni/$ABI_DIR/lib${LIB_NAME}.so"
    FAKE_ALIGN="$align" FAKE_INFO="$t/info-$info" GO_BIN="$t/go" STRINGS_BIN="$t/strings" \
      finalize_artifacts "$t/objdump" "$d/check" "$d/built.aar" "$d/out" "$gov" "$tags" "$sbv" "$GODEBUG_DEFAULT"
  }
  has_artifact() { [ -s "$t/gate-$1/out/libcore.aar" ] && [ -s "$t/gate-$1/out/libcore.aar.sha256" ]; }
  no_artifact()  { [ ! -e "$t/gate-$1/out/libcore.aar" ] && [ ! -e "$t/gate-$1/out/libcore.aar.sha256" ]; }
  gate_ok()   { local c="$1"; shift; ( gate "$c" "$@" ) >/dev/null 2>&1 && has_artifact "$c"; }
  gate_fail() { local c="$1" rc=0; shift; ( gate "$c" "$@" ) >/dev/null 2>&1 || rc=$?; [ "$rc" -ne 0 ] && no_artifact "$c"; }
  printf '#!/bin/sh\nexit 0\n' >"$t/api-ok"; printf '#!/bin/sh\nexit 1\n' >"$t/api-bad"; chmod +x "$t/api-ok" "$t/api-bad"
  expect_ok "放行门：全部通过 → 写出产物与 sha256" gate_ok g1 good good pg-ok good
  expect_ok "放行门：对齐不过 → 不写产物" gate_fail g2 bad good pg-ok good
  expect_ok "放行门：buildinfo 不过 → 不写产物" gate_fail g3 good tags-extra pg-ok good
  expect_ok "放行门：proguard 不过 → 不写产物" gate_fail g4 good good pg-wide good
  expect_ok "放行门：API 快照不一致 → 不写产物" gate_fail g5 good good pg-ok good API_SNAPSHOT_CHECK="$t/api-bad"
  expect_ok "放行门：API 快照一致 → 写出产物" gate_ok g6 good good pg-ok good API_SNAPSHOT_CHECK="$t/api-ok"
  expect_ok "放行门：版本覆盖没生效 → 不写产物" gate_fail g7 good good pg-ok nover

  # --- API 快照：假 javap + 只含类名的假 classes.jar（真实 javap 的输出由 bind 后的真实构建验证）
  mkdir -p "$t/api/jar/com/clashmiao/libcore/core" "$t/api/jar/go" "$t/api/aar"
  : >"$t/api/jar/com/clashmiao/libcore/core/Core.class"; : >"$t/api/jar/com/clashmiao/libcore/core/Engine.class"; : >"$t/api/jar/go/Seq.class"
  (cd "$t/api/jar" && zip -q -r "$t/api/aar/classes.jar" .)
  cat >"$t/api/javap" <<'FAKE'
#!/bin/sh
# 最后一个参数是类名；FAKE_EXTRA 非空时给 Core 多加一个方法
for c; do :; done
echo "public final class $c {"
[ "$c" = com.clashmiao.libcore.core.Core ] && [ -n "${FAKE_EXTRA:-}" ] && echo "  public static native void extra();"
echo "}"
FAKE
  chmod +x "$t/api/javap"
  api_check() { JAVAP_BIN="$t/api/javap" API_SNAPSHOT="$t/api/snap.txt" REPO_ROOT="$REPO_ROOT" "$SCRIPT_DIR/check-java-api.sh" "$@"; }
  api_gen()   { UPDATE_API=1 api_check "$t/api/aar"; }
  expect_fail "API 快照：快照缺失 → 失败（不静默放行）" api_check "$t/api/aar"
  expect_ok   "API 快照：UPDATE_API=1 生成快照" api_gen
  expect_ok   "API 快照：生成后零差异" api_check "$t/api/aar"
  expect_ok   "API 快照：快照只含门面包的类（不含 go.*）" bash -c "! grep -q 'go.Seq' '$t/api/snap.txt' && grep -q 'libcore.core.Engine' '$t/api/snap.txt'"
  expect_fail "API 快照：公共 API 多了一个方法 → 失败" env FAKE_EXTRA=1 bash -c "$(declare -f api_check); t='$t'; SCRIPT_DIR='$SCRIPT_DIR'; REPO_ROOT='$REPO_ROOT'; api_check '$t/api/aar'"
  mkdir -p "$t/api/empty" && (cd "$t/api/empty" && mkdir go && : >go/Seq.class && zip -q -r "$t/api/aar-empty.jar" .)
  mkdir -p "$t/api/aar-nofacade" && cp "$t/api/aar-empty.jar" "$t/api/aar-nofacade/classes.jar"
  expect_fail "API 快照：门面包没有类 → 失败" api_check "$t/api/aar-nofacade"
  expect_fail "API 快照：aar 里没有 classes.jar → 失败" api_check "$t/api/empty"

  # --- BUILD_ROOT 规范化与目录锁（rm / chmod 全部换成只记日志的桩，不会真删任何东西）
  local rmlog="$t/rm.log"
  stubbed() {
    rm() { printf 'rm %s\n' "$*" >>"$rmlog"; }
    chmod() { printf 'chmod %s\n' "$*" >>"$rmlog"; }
    "$@"
  }
  reject_root() {
    local raw="$1" rc=0
    : >"$rmlog"
    ( stubbed prepare_build_dir "$raw" ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ] && [ ! -s "$rmlog" ]
  }
  mkdir -p "$t/p" "$t/home" "$t/other"
  ln -s "$t/p" "$t/plink"
  local dir="$t/p/$BUILD_DIR_NAME"
  expect_ok   "BUILD_ROOT 拒绝根目录写法：/"      reject_root "/"
  expect_ok   "BUILD_ROOT 拒绝根目录写法：//"     reject_root "//"
  expect_ok   "BUILD_ROOT 拒绝根目录写法：/./"    reject_root "/./"
  expect_ok   "BUILD_ROOT 拒绝根目录写法：/.."    reject_root "/.."
  expect_ok   "BUILD_ROOT 拒绝相对路径"            reject_root "${BUILD_DIR_NAME}"
  expect_ok   "BUILD_ROOT 拒绝空串"                reject_root ""
  expect_ok   "BUILD_ROOT 拒绝非专用目录：随意目录" reject_root "$t/other"
  expect_ok   "BUILD_ROOT 拒绝非专用目录：/tmp"    reject_root "/tmp"
  expect_ok   "BUILD_ROOT 拒绝非专用目录：前缀相同的别名" reject_root "$t/p/${BUILD_DIR_NAME}-x"
  expect_ok   "BUILD_ROOT 拒绝含 .. 的路径"        reject_root "$t/p/../p/$BUILD_DIR_NAME"
  expect_ok   "BUILD_ROOT 拒绝含 . 的路径"         reject_root "$t/p/./$BUILD_DIR_NAME"
  expect_ok   "BUILD_ROOT 拒绝 \$HOME（HOME 指向非专用目录）" env HOME="$t/home" bash -c "$(declare -f die log resolve_build_root); BUILD_DIR_NAME='$BUILD_DIR_NAME'; ! (resolve_build_root '$t/home') 2>/dev/null"
  mkdir -p "$t/p2/$BUILD_DIR_NAME"
  expect_ok   "BUILD_ROOT 拒绝 \$HOME（HOME 恰好就是专用名目录）" env HOME="$t/p2/$BUILD_DIR_NAME" bash -c "$(declare -f die log resolve_build_root); BUILD_DIR_NAME='$BUILD_DIR_NAME'; ! (resolve_build_root '$t/p2/$BUILD_DIR_NAME') 2>/dev/null"
  mkdir -p "$t/q" && ln -s "$t/other" "$t/q/$BUILD_DIR_NAME"
  expect_ok   "BUILD_ROOT 拒绝符号链接目标"        reject_root "$t/q/$BUILD_DIR_NAME"

  lock_is_sibling() {
    : >"$rmlog"
    stubbed prepare_build_dir "$dir/" || return 1
    [ "$BUILD_ROOT_LOGICAL" = "$dir" ] || return 1
    [ -d "${BUILD_ROOT_CANON}.lock" ] || return 1
    [ ! -e "$dir/.lock" ] || return 1
    [ "${BUILD_ROOT_CANON}.lock" = "$(cd "$t/p" && pwd -P)/${BUILD_DIR_NAME}.lock" ] || return 1
    grep -qx "rm -rf $dir" "$rmlog" || return 1
    [ "$(grep -c '^rm ' "$rmlog")" = 1 ]
  }
  expect_ok   "尾斜杠：规范化为同一路径，锁建在构建目录之外" lock_is_sibling
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true

  contend() {
    local alt="$1" rc=0
    : >"$rmlog"
    stubbed prepare_build_dir "$dir" >/dev/null || return 1
    local first
    first="$(wc -l <"$rmlog" | tr -d ' ')"
    ( stubbed prepare_build_dir "$alt" ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || return 1
    [ "$(wc -l <"$rmlog" | tr -d ' ')" = "$first" ]
  }
  expect_ok   "锁：同一路径第二次进入被拒绝且不清理"       contend "$dir"
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true
  expect_ok   "锁：尾斜杠写法与无斜杠写法互斥"             contend "$dir/"
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true
  expect_ok   "锁：重复斜杠写法与规范写法互斥"             contend "$t/p//$BUILD_DIR_NAME"
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true
  expect_ok   "锁：经符号链接上级的等价路径与规范路径互斥" contend "$t/plink/$BUILD_DIR_NAME"
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true

  cleanup_without_lock() {
    : >"$rmlog"
    mkdir -p "$dir" "$dir.lock"
    BUILD_ROOT_LOGICAL="$dir"; BUILD_ROOT_CANON="$dir"; LOCK_HELD=0
    stubbed cleanup
    [ -d "$dir.lock" ] && [ ! -s "$rmlog" ]
  }
  expect_ok   "清理：没拿到锁时不动别人的锁和目录" cleanup_without_lock
  rmdir "$dir.lock" 2>/dev/null || true; rmdir "$dir" 2>/dev/null || true

  log "自测：${pass}/${total} 通过"
  [ "$pass" -eq "$total" ] || die "自测有 $((total - pass)) 项未达预期"
}

if [ "${1:-}" = "--self-test" ]; then
  run_self_test
  exit 0
fi

# ---------------------------------------------------------------- 主流程
OUT_DIR="${OUT_DIR:-$REPO_ROOT/build/kernel}"
host_os="$(uname -s)"
host_arch="$(uname -m)"
case "$host_os/$host_arch" in
  Darwin/arm64)  GO_PLATFORM="darwin-arm64"; GO_SHA256="$GO_SHA256_DARWIN_ARM64"; NDK_HOST="darwin-x86_64" ;;
  Darwin/x86_64) GO_PLATFORM="darwin-amd64"; GO_SHA256="$GO_SHA256_DARWIN_AMD64"; NDK_HOST="darwin-x86_64" ;;
  Linux/x86_64)  GO_PLATFORM="linux-amd64";  GO_SHA256="$GO_SHA256_LINUX_AMD64";  NDK_HOST="linux-x86_64" ;;
  *) die "不支持的构建主机：${host_os}/${host_arch}" ;;
esac

for tool in curl unzip; do
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

# JDK：gomobile bind 要用 javac。优先 JAVA_HOME，其次 macOS 的 java_home（21 → 17）。
JDK_HOME="${JAVA_HOME:-}"
if [ -z "$JDK_HOME" ] || [ ! -x "$JDK_HOME/bin/javac" ]; then
  JDK_HOME=""
  if [ "$host_os" = Darwin ]; then
    for v in 21 17; do
      JDK_HOME="$(/usr/libexec/java_home -v "$v" 2>/dev/null || true)"
      [ -n "$JDK_HOME" ] && break
    done
  fi
fi
[ -n "$JDK_HOME" ] && [ -x "$JDK_HOME/bin/javac" ] || die "找不到 JDK 17 / 21（设置 JAVA_HOME）"
javac_ver="$("$JDK_HOME/bin/javac" -version 2>&1 | awk '{print $2}')"
case "$javac_ver" in
  17|17.*|21|21.*) ;;
  *) die "需要 JDK 17 或 21（当前 javac ${javac_ver}）" ;;
esac

# Go 压缩包缓存放在构建目录之外（每次构建清空构建目录，下载一次 80 MB 太浪费）；每次都重新校验 sha256
CACHE_DIR="${KERNEL_BUILD_CACHE:-$REPO_ROOT/build/kernel-cache}"
mkdir -p "$CACHE_DIR"
go_tgz="go${GO_VERSION}.${GO_PLATFORM}.tar.gz"
if [ ! -f "$CACHE_DIR/$go_tgz" ] || [ "$(sha256 "$CACHE_DIR/$go_tgz")" != "$GO_SHA256" ]; then
  log "下载 Go ${GO_VERSION} (${GO_PLATFORM})"
  curl -fsSL -o "$CACHE_DIR/$go_tgz.part" "https://go.dev/dl/$go_tgz"
  mv "$CACHE_DIR/$go_tgz.part" "$CACHE_DIR/$go_tgz"
fi
check_sha256 "$CACHE_DIR/$go_tgz" "$GO_SHA256" "Go 压缩包"

# ---------------------------------------------------------------- 构建目录（固定路径）
trap cleanup EXIT
prepare_build_dir "${BUILD_ROOT:-/tmp/${BUILD_DIR_NAME}}"
WORK="$BUILD_ROOT_LOGICAL"
log "构建目录（固定路径）：${WORK}"
started_at="$(date +%s)"

tar -xzf "$CACHE_DIR/$go_tgz" -C "$WORK"
export GOROOT="$WORK/go"
export GOPATH="$WORK/gopath"
export GOMODCACHE="${GOMODCACHE_OVERRIDE:-$GOPATH/pkg/mod}"
export GOBIN="$WORK/gobin"
export GOTOOLCHAIN=local   # go.mod 不得悄悄切换工具链
export GOFLAGS="-mod=readonly"
export CGO_ENABLED=1
export ANDROID_HOME ANDROID_NDK_HOME="$NDK_ROOT"
export JAVA_HOME="$JDK_HOME"
export PATH="$GOBIN:$GOROOT/bin:$JAVA_HOME/bin:$PATH"
[ "$(go env GOVERSION)" = "go$GO_VERSION" ] || die "Go 版本不对：$(go env GOVERSION)"
[ "$(go version | awk '{print $3}')" = "go$GO_VERSION" ] || die "go version 与固定版本不符"

cd "$REPO_ROOT/kernel"
SINGBOX_VERSION="$(go list -m -f '{{.Version}}' "$SINGBOX_MODULE")"
case "$SINGBOX_VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) die "go.mod 里的 sing-box 版本不是正式 tag：${SINGBOX_VERSION}" ;;
esac
log "sing-box ${SINGBOX_VERSION}，Go ${GO_VERSION}，tags=${KERNEL_TAGS}"

# ---------------------------------------------------------------- gomobile（版本由 kernel/go.mod 决定，装进私有 GOBIN）
log "安装 gomobile / gobind（版本取自 go.mod）"
go install github.com/sagernet/gomobile/cmd/gomobile github.com/sagernet/gomobile/cmd/gobind
if [ "$host_os" = Darwin ]; then
  codesign -f -s - "$GOBIN/gomobile" "$GOBIN/gobind" >/dev/null 2>&1 || true
fi
gomobile init >"$WORK/gomobile-init.log" 2>&1 || { tail -20 "$WORK/gomobile-init.log" >&2; die "gomobile init 失败"; }

# ---------------------------------------------------------------- 构建
LDFLAGS_ALL="${KERNEL_LDFLAGS_LINK} -X ${SINGBOX_MODULE}/constant.Version=${SINGBOX_VERSION#v} ${EXTRA_LDFLAGS_TAIL}"
for w in $KERNEL_LDFLAGS_LINK; do
  case " $LDFLAGS_ALL " in *" $w "*|*" $w="*) ;; *) die "传给 bind 的链接参数里缺少 ${w}" ;; esac
done
log "gomobile bind（NDK ${NDK_VERSION}，API ${ANDROID_API}，目标 android/arm64）"
mkdir -p "$WORK/out"   # gomobile 不会替你建输出目录
gomobile bind -v \
  -target android/arm64 \
  -androidapi "$ANDROID_API" \
  -javapkg="$JAVA_PKG" \
  -libname="$LIB_NAME" \
  -trimpath \
  -buildvcs=false \
  -tags "$KERNEL_TAGS" \
  -ldflags "$LDFLAGS_ALL" \
  -o "$WORK/out/libcore.aar" \
  "$BIND_PKG" >"$WORK/bind.log" 2>&1 || { tail -40 "$WORK/bind.log" >&2; die "gomobile bind 失败"; }

# gomobile 会在 kernel/ 下留下空的 build/<arch> 目录，顺手清掉（不空就留着，说明不是它建的）
rmdir "$REPO_ROOT/kernel/build/arm64" "$REPO_ROOT/kernel/build" 2>/dev/null || true

# ---------------------------------------------------------------- 校验与放行
log "校验产物"
mkdir -p "$WORK/check"
unzip -q -o "$WORK/out/libcore.aar" -d "$WORK/check" || die "产物 aar 解压失败"
# API 快照放行门是必选项（U12 起）：快照缺失同样失败，首次生成用 UPDATE_API=1。
API_SNAPSHOT_CHECK="$SCRIPT_DIR/check-java-api.sh"
[ -x "$API_SNAPSHOT_CHECK" ] || die "缺少 ${API_SNAPSHOT_CHECK}"
export API_SNAPSHOT_CHECK REPO_ROOT JAVA_HOME UPDATE_API
finalize_artifacts "$OBJDUMP" "$WORK/check" "$WORK/out/libcore.aar" "$OUT_DIR" \
  "$GO_VERSION" "$KERNEL_TAGS" "$SINGBOX_VERSION" "$GODEBUG_DEFAULT"

elapsed=$(( $(date +%s) - started_at ))
so_size="$(wc -c <"$WORK/check/jni/$ABI_DIR/lib${LIB_NAME}.so" | tr -d ' ')"
aar_size="$(wc -c <"$OUT_DIR/libcore.aar" | tr -d ' ')"
log "完成：${OUT_DIR}/libcore.aar（${aar_size} 字节），lib${LIB_NAME}.so ${so_size} 字节，耗时 ${elapsed}s"
log "sha256：$(cut -d' ' -f1 "$OUT_DIR/libcore.aar.sha256")"
log "本地使用：cp \"${OUT_DIR}/libcore.aar\" android/app/libs/libcore.aar"
