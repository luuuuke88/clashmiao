#!/usr/bin/env bash
# build-apple.test.sh — 放行门逐成员平台核对的用例（只能在装了 Xcode 的 macOS 上跑）。
# 用 clang 现编几个小目标文件拼成静态库：全对、缺 LC_BUILD_VERSION、错平台、混入一个坏成员。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPT_DIR/build-apple.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clashmiao-apple-gate-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

obj() { # obj <名字> <clang -target>
  printf 'int %s(void) { return 0; }\n' "$1" >"$WORK/$1.c"
  xcrun clang -c -w -target "$2" -o "$WORK/$1.o" "$WORK/$1.c"
}
lib() { # lib <名字> <目标文件...>
  local name="$1"; shift
  xcrun libtool -static -no_warning_for_no_symbols -o "$WORK/$name.a" "$@" 2>/dev/null
}
expect() { # expect <用例> <pass|fail> <静态库> <平台> [输出须含]
  local out rc=0
  out="$("$GATE" --check-platforms "$WORK/$3.a" "$4" 2>&1)" || rc=$?
  if [ "$2" = pass ]; then
    [ "$rc" -eq 0 ] && ok "$1" || bad "$1（应通过）：$out"
  else
    if [ "$rc" -ne 0 ] && { [ -z "${5:-}" ] || grep -qF -- "$5" <<<"$out"; }; then ok "$1"; else bad "$1（应拒绝）：$out"; fi
  fi
}

obj dev1 arm64-apple-ios15.0
obj dev2 arm64-apple-ios15.0
obj sim1 arm64-apple-ios15.0-simulator
obj mac1 arm64-apple-macos12.0
# iOS 12 之前的部署目标只写 LC_VERSION_MIN_IPHONEOS，没有 LC_BUILD_VERSION
obj old1 arm64-apple-ios9.0
otool -l "$WORK/old1.o" | grep -q LC_BUILD_VERSION && { echo "前提不成立：old1.o 带 LC_BUILD_VERSION" >&2; exit 1; }

lib device "$WORK/dev1.o" "$WORK/dev2.o"
lib simulator "$WORK/sim1.o"
lib device-with-old "$WORK/dev1.o" "$WORK/old1.o"
lib device-with-mac "$WORK/dev1.o" "$WORK/mac1.o"
lib device-with-sim "$WORK/dev1.o" "$WORK/sim1.o"

expect "设备库全为平台 2" pass device 2
expect "模拟器库全为平台 7" pass simulator 7
expect "设备库放进模拟器切片" fail device 7 "dev1.o=2"
expect "缺 LC_BUILD_VERSION 的成员" fail device-with-old 2 "old1.o=-"
expect "混入 macOS 目标文件" fail device-with-mac 2 "mac1.o=1"
expect "混入模拟器目标文件" fail device-with-sim 2 "sim1.o=7"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
