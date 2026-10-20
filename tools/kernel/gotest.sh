#!/usr/bin/env bash
# gotest.sh — 内核模块唯一合法的 Go 验证入口。
#
#   tools/kernel/gotest.sh                 # go vet + go test -race ./...
#   tools/kernel/gotest.sh ./internal/...  # 只跑指定包（参数原样追加在包路径位置）
#   GOTEST_RUN='TestA|TestB' GOTEST_ARGS="-count=1 -v" tools/kernel/gotest.sh ./engine
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
run_args=()
[ -z "${GOTEST_RUN:-}" ] || run_args=(-run "$GOTEST_RUN")

# 第一遍：带 -race（测试默认都带）。
# shellcheck disable=SC2086  # GOTEST_ARGS 有意按空白拆分（带空格的 -run 模式请用 GOTEST_RUN）
go test -race -tags "$KERNEL_TAGS" -ldflags "$KERNEL_LDFLAGS_LINK" ${GOTEST_ARGS:-} ${run_args[@]+"${run_args[@]}"} "${pkgs[@]}"

# 第二遍：不带 -race，只跑含 `//go:build !race` 测试文件的包。
# 原因：官方 sing-box 的 urltest 出站在启动时有一处上游的数据竞争
# （protocol/group 的 URLTest.References 无锁读取 selectedOutboundTCP，与首次探测后的写入并发），
# 任何真起了 urltest 的测试在 -race 下都会确定性失败，而构建器产出的配置里一定有 `auto` 这个 urltest。
# 所以「真起带 urltest 配置」的测试放在 !race 文件里，在这一遍里照常运行；
# 其余（含取消 / 清理 / 分类等我们自己的并发逻辑）都用不带 urltest 的配置，仍在第一遍的 -race 下。
# 上游修复后（升 sing-box 时复查）可以去掉这一遍与对应的 build tag。
selected=()
while read -r importpath dir; do
  [ -n "$importpath" ] || continue
  if grep -lqE '^//go:build .*!race' "$dir"/*_test.go 2>/dev/null; then selected+=("$importpath"); fi
done < <(go list -tags "$KERNEL_TAGS" -f '{{.ImportPath}} {{.Dir}}' "${pkgs[@]}")
if [ "${#selected[@]}" -gt 0 ]; then
  echo "== 第二遍（无 -race）：${selected[*]}"
  # shellcheck disable=SC2086
  go test -tags "$KERNEL_TAGS" -ldflags "$KERNEL_LDFLAGS_LINK" ${GOTEST_ARGS:-} ${run_args[@]+"${run_args[@]}"} "${selected[@]}"
fi
