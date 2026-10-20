#!/usr/bin/env bash
# check-no-sleep.sh — kernel/ 下的测试不得用 time.Sleep 等「应该已经发生了」。
#
# 同步一律用 channel / WaitGroup / 回调通知，超时（>= 30 s）只作失败兜底。
# 白名单（相对仓库根的精确路径，每条写明理由）：
ALLOW=(
  # （目前为空。新增前先确认确实无法用事件同步，并在这里写理由。）
)
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"

bad=0
while IFS= read -r f; do
  skip=0
  for a in "${ALLOW[@]+"${ALLOW[@]}"}"; do [ "$f" = "$a" ] && skip=1; done
  [ "$skip" = 1 ] && continue
  if grep -nE 'time\.Sleep\(' "$f" >/dev/null; then
    grep -nE 'time\.Sleep\(' "$f" | sed "s#^#${f}:#" >&2
    bad=1
  fi
done < <(find kernel -name '*_test.go' -type f 2>/dev/null | sort)
if [ "$bad" = 1 ]; then
  echo "check-no-sleep: kernel 的测试里出现 time.Sleep；改用事件同步" >&2
  exit 1
fi
echo "check-no-sleep: 通过"
