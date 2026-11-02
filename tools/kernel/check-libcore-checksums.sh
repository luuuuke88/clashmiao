#!/usr/bin/env bash
# check-libcore-checksums.sh — 保证 libcore 校验和文件覆盖了实际在用的每个 tag。
#
# 在用的 tag 取自三处：ci.yml、release.yml 的 env（LIBCORE_TAG / ANDROID_LIBCORE_TAG），
# 以及 bin/fetch-libcore.sh 里的默认值。每个 tag 必须在 tools/kernel/libcore-checksums.txt
# 里有它被下载的全部资产的条目：
#   ANDROID_LIBCORE_TAG → libcore.aar
#   LIBCORE_TAG         → libcore.dylib / libcore.dll / libcore.so / Libcore.xcframework.zip
# 同时检查校验和文件本身的格式（64 位十六进制 + 两个空格 + <tag>/<asset>）与重复条目。
#
# 用法：tools/kernel/check-libcore-checksums.sh [仓库根目录]
# 只用 grep/sed/awk 的 POSIX 子集，macOS（bash 3.2）与 Ubuntu 通用。
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SUMS="${LIBCORE_CHECKSUMS:-$ROOT/tools/kernel/libcore-checksums.txt}"
FETCH="$ROOT/bin/fetch-libcore.sh"

bad=0
fail() { echo "check-libcore-checksums: $*" >&2; bad=1; }

[ -f "$SUMS" ]  || { echo "check-libcore-checksums: 缺少 ${SUMS}" >&2; exit 1; }
[ -f "$FETCH" ] || { echo "check-libcore-checksums: 缺少 ${FETCH}" >&2; exit 1; }

# 格式
if grep -vE '^[0-9a-f]{64}  [A-Za-z0-9._-]+/[A-Za-z0-9._-]+$|^#|^$' "$SUMS" >/dev/null; then
  fail "校验和文件有格式不对的行："
  grep -nvE '^[0-9a-f]{64}  [A-Za-z0-9._-]+/[A-Za-z0-9._-]+$|^#|^$' "$SUMS" >&2 || true
fi
dups="$(grep -vE '^#|^$' "$SUMS" | awk '{print $2}' | sort | uniq -d)"
[ -z "$dups" ] || fail "校验和文件有重复条目：$(echo "$dups" | tr '\n' ' ')"

# 从 workflow 的 env 行取值：`  LIBCORE_TAG: libcore-v1.8.9-16k`
tags_from() { # <var> <file...>
  local var="$1"; shift
  grep -hE "^[[:space:]]*${var}:[[:space:]]*[^[:space:]]+" "$@" 2>/dev/null \
    | sed -E "s/^[[:space:]]*${var}:[[:space:]]*([^[:space:]#]+).*/\1/"
}
# 从脚本里取默认值：`TAG="${LIBCORE_TAG:-libcore-v1.8.9-16k}"`
default_from() { # <var>
  grep -hE "\\\$\{${1}:-[^}]+\}" "$FETCH" | sed -E "s/.*\\\$\{${1}:-([^}]+)\}.*/\1/"
}

wf="$ROOT/.github/workflows/ci.yml $ROOT/.github/workflows/release.yml"
# shellcheck disable=SC2086
main_tags="$( { tags_from LIBCORE_TAG $wf; default_from LIBCORE_TAG; } | sort -u )"
# shellcheck disable=SC2086
android_tags="$( { tags_from ANDROID_LIBCORE_TAG $wf; default_from ANDROID_LIBCORE_TAG; } | sort -u )"

[ -n "$main_tags" ]    || fail "没有找到 LIBCORE_TAG（ci.yml / release.yml / fetch-libcore.sh）"
[ -n "$android_tags" ] || fail "没有找到 ANDROID_LIBCORE_TAG（ci.yml / release.yml / fetch-libcore.sh）"

need() { # <tag> <asset>
  if ! awk -v k="$1/$2" '$1 !~ /^#/ && $2 == k { f = 1 } END { exit f ? 0 : 1 }' "$SUMS"; then
    fail "缺少校验和：${1}/${2}"
  fi
}
for t in $main_tags; do
  for a in libcore.dylib libcore.dll libcore.so Libcore.xcframework.zip; do need "$t" "$a"; done
done
for t in $android_tags; do need "$t" libcore.aar; done

[ "$bad" = 0 ] || exit 1
echo "check-libcore-checksums: OK（$(echo $main_tags $android_tags | tr ' ' '\n' | sort -u | tr '\n' ' ')）"
