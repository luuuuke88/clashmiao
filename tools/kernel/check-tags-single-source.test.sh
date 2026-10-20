#!/usr/bin/env bash
# check-tags-single-source.test.sh — check-tags-single-source.sh 的自测。
# 在临时目录里布置一份仿仓库；字面量一律在运行时从 env.sh 的变量取值，本脚本源码不含字面量。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_ENV="$HERE/env.sh"
SRC_CHECK="$HERE/check-tags-single-source.sh"
# shellcheck source=/dev/null
source "$SRC_ENV"
FIRST_TAG="${KERNEL_TAGS%%,*}"

T="$(mktemp -d "${TMPDIR:-/tmp}/tags-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0; total=0

fresh() { # fresh <name> → 建一份干净的仿仓库并 echo 路径
  local r="$T/$1"
  mkdir -p "$r/tools/kernel" "$r/tools/libcore" "$r/docs" "$r/.github/workflows" "$r/kernel"
  cp "$SRC_ENV" "$r/tools/kernel/env.sh"
  printf '#!/bin/sh\nsource "$(dirname "$0")/env.sh"\necho "$KERNEL_TAGS"\n' >"$r/tools/kernel/ok.sh"
  printf 'steps:\n  - run: tools/kernel/gotest.sh\n' >"$r/.github/workflows/ci.yml"
  echo "$r"
}
expect() { # expect ok|fail <name> <repo>
  local want="$1" name="$2" repo="$3" rc=0
  bash "$SRC_CHECK" "$repo" >/dev/null 2>&1 || rc=$?
  total=$((total + 1))
  if { [ "$want" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "自测 ✓ ${name}"
  else
    echo "自测 ✗ ${name}（期望 ${want}，退出码 ${rc}）" >&2
  fi
}

r="$(fresh base)"
expect ok   "仅 env.sh 含字面量 → 通过" "$r"

r="$(fresh dup-script)"
printf '#!/bin/sh\ngo test -tags "%s" ./...\n' "$KERNEL_TAGS" >"$r/tools/kernel/foo.sh"
expect fail "新链路脚本重复写 tags 字面量 → 失败" "$r"

r="$(fresh one-tag)"
printf '#!/bin/sh\necho %s\n' "$FIRST_TAG" >"$r/tools/kernel/foo.sh"
expect fail "新链路脚本只写了其中一个 tag → 失败" "$r"

r="$(fresh frozen)"
printf '#!/bin/sh\nTAGS="%s"\nLD="%s"\n' "$KERNEL_TAGS" "$KERNEL_LDFLAGS_LINK" >"$r/tools/libcore/build-android.sh"
expect ok   "冻结的回滚脚本含字面量 → 被忽略" "$r"

r="$(fresh docs)"
printf '推荐 tags：%s，链接参数 %s\n' "$KERNEL_TAGS" "$KERNEL_LDFLAGS_LINK" >"$r/docs/ARCH.md"
expect ok   "docs 里含字面量 → 通过" "$r"

r="$(fresh ci-dup)"
printf 'steps:\n  - run: go test -tags %s ./...\n' "$KERNEL_TAGS" >"$r/.github/workflows/ci.yml"
expect fail "CI 步骤重复 tags 字面量 → 失败" "$r"

r="$(fresh ld-script)"
printf '#!/bin/sh\ngo build -ldflags "%s" ./...\n' "$KERNEL_LDFLAGS_LINK" >"$r/tools/kernel/bar.sh"
expect fail "链接参数字面量按同样规则处理 → 失败" "$r"

r="$(fresh makefile)"
printf 'test:\n\tgo test -tags %s ./...\n' "$KERNEL_TAGS" >"$r/kernel/Makefile"
expect fail "kernel/Makefile 重复字面量 → 失败" "$r"

r="$(fresh no-env)"
rm "$r/tools/kernel/env.sh"
expect fail "缺 env.sh → 失败" "$r"

echo "check-tags-single-source.test: ${pass}/${total} 通过"
[ "$pass" -eq "$total" ]
