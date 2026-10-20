#!/usr/bin/env bash
# gotest.sh — 内核模块唯一合法的 Go 验证入口。
#
#   tools/kernel/gotest.sh                 # go vet + go test -race ./...
#   tools/kernel/gotest.sh ./internal/...  # 只跑指定包（参数原样追加在包路径位置）
#   GOTEST_ARGS="-run TestX -count=1" tools/kernel/gotest.sh ./engine
#
# tags 与链接参数一律来自 env.sh；裸 `go test ./...` 会让 QUIC / WireGuard 等变成桩实现，
# 不是合法的验证命令。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tools/kernel/env.sh
source "$ROOT/tools/kernel/env.sh"

cd "$ROOT/kernel"
pkgs=("$@")
[ "${#pkgs[@]}" -gt 0 ] || pkgs=(./...)

gofmt_out="$(gofmt -l . 2>&1 || true)"
if [ -n "$gofmt_out" ]; then
  echo "gofmt -l 有输出（需要格式化）：" >&2
  echo "$gofmt_out" >&2
  exit 1
fi

go vet -tags "$KERNEL_TAGS" "${pkgs[@]}"
# shellcheck disable=SC2086  # GOTEST_ARGS 有意按空白拆分
go test -race -tags "$KERNEL_TAGS" -ldflags "$KERNEL_LDFLAGS_LINK" ${GOTEST_ARGS:-} "${pkgs[@]}"
