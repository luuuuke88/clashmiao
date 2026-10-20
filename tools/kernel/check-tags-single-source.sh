#!/usr/bin/env bash
# check-tags-single-source.sh — 保证构建 tags 与链接参数只有 env.sh 一份来源。
#
# 从 env.sh 里取出 KERNEL_TAGS（逐个 tag）与 KERNEL_LDFLAGS_LINK（逐个参数），
# 在「新构建链路的可执行文件」里搜它们的字面量；env.sh 自己放行，其它任何命中都是缺陷。
#
# 扫描范围（相对仓库根）：
#   tools/kernel/*.sh           （env.sh 除外）
#   .github/workflows/*.yml
#   kernel/Makefile、kernel/**/Makefile（若有）
# 显式不扫：冻结的回滚脚本 tools/libcore/build-android.sh（自带同样的字面量，保持原样）、
#   全部文档（docs/**、README、CHANGELOG）。
#
# 本脚本自身只读 env.sh 的变量，源码里不含任何字面量。
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
ENV_SH="$ROOT/tools/kernel/env.sh"
[ -f "$ENV_SH" ] || { echo "缺少 $ENV_SH" >&2; exit 1; }

# shellcheck source=/dev/null
( source "$ENV_SH" && [ -n "${KERNEL_TAGS:-}" ] && [ -n "${KERNEL_LDFLAGS_LINK:-}" ] ) \
  || { echo "env.sh 没有导出 KERNEL_TAGS / KERNEL_LDFLAGS_LINK" >&2; exit 1; }
KERNEL_TAGS="$(source "$ENV_SH" && printf '%s' "$KERNEL_TAGS")"
KERNEL_LDFLAGS_LINK="$(source "$ENV_SH" && printf '%s' "$KERNEL_LDFLAGS_LINK")"

# 待查字面量：每个 tag；链接参数里每个以 - 开头的词（去掉 =值，匹配参数名）
needles=()
IFS=',' read -r -a tag_list <<<"$KERNEL_TAGS"
for t in "${tag_list[@]}"; do needles+=("$t"); done
for w in $KERNEL_LDFLAGS_LINK; do needles+=("${w%%=*}"); done

files=()
shopt -s nullglob
for f in "$ROOT"/tools/kernel/*.sh "$ROOT"/.github/workflows/*.yml; do
  [ "$(basename "$f")" = "env.sh" ] && [ "$(dirname "$f")" = "$ROOT/tools/kernel" ] && continue
  files+=("$f")
done
while IFS= read -r f; do files+=("$f"); done < <(find "$ROOT/kernel" -name Makefile -type f 2>/dev/null || true)

bad=0
for f in "${files[@]}"; do
  for n in "${needles[@]}"; do
    if grep -nF -- "$n" "$f" >/dev/null 2>&1; then
      echo "${f#"$ROOT"/}: 出现了 env.sh 里的字面量「${n}」；应改为读取 env.sh 的变量" >&2
      bad=1
    fi
  done
done
[ "$bad" = 0 ] || exit 1
echo "check-tags-single-source: 通过（扫描 ${#files[@]} 个文件）"
