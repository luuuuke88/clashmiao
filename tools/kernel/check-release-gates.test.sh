#!/usr/bin/env bash
# check-release-gates.sh 的自测：把真实工作流拷到临时目录，逐个破坏闸门，守卫必须失败。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mutate() { # 名称 sed 表达式 文件
  rm -rf "$tmp/w"; mkdir -p "$tmp/w/.github/workflows"
  cp "$ROOT"/.github/workflows/*.yml "$tmp/w/.github/workflows/"
  sed -i.bak "$2" "$tmp/w/.github/workflows/$3"
  if "$ROOT/tools/kernel/check-release-gates.sh" "$tmp/w" >/dev/null 2>&1; then
    echo "自测失败：破坏「$1」后守卫仍然通过" >&2; exit 1
  fi
}
"$ROOT/tools/kernel/check-release-gates.sh" "$ROOT" >/dev/null
mutate "android 不再依赖 kernel" 's/needs: \[quality, kernel\]/needs: [quality]/' release.yml
mutate "publish 不再依赖 kernel" 's/needs: \[kernel, android, macos, windows, linux\]/needs: [android, macos, windows, linux]/' release.yml
mutate "publish 的 if 不再要求 kernel 成功" "s/if: \${{ always() \&\& needs.kernel.result == 'success' }}/if: always()/" release.yml
mutate "CI 的 build-android 不再依赖 kernel" 's/test-android-unit, kernel\]/test-android-unit]/' ci.yml
echo "check-release-gates.test: 通过"
