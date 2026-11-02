#!/usr/bin/env bash
# notify-website.test.sh — bin/notify-website.sh 的单元测试
#
# 用法：bash bin/notify-website.test.sh
# PATH 最前面放一个假的 gh，全程不联网。断言：
#   1 缺 tag 参数           → 退出 1，没有调用 gh
#   2 WEB_DISPATCH_TOKEN 为空 → 退出 1，输出含「未配置」，没有调用 gh
#   3 假 gh 返回 1          → 退出 1，输出含「dispatch 失败」
#   4 正常                  → 退出 0，假 gh 收到 event_type=app-released、tag，并用 token 作为 GH_TOKEN
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/notify-website.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
check() { # <描述> <命令...>
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

[ -f "$SCRIPT" ] || { echo "FAIL  脚本不存在：$SCRIPT"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/fakebin"
cat >"$WORK/fakebin/gh" <<'GH'
#!/usr/bin/env bash
# 假 gh：记录参数与 GH_TOKEN，按 FAKE_GH_EXIT 返回
{ echo "ARGS: $*"; echo "GH_TOKEN=${GH_TOKEN:-}"; } >> "$FAKE_GH_LOG"
exit "${FAKE_GH_EXIT:-0}"
GH
chmod +x "$WORK/fakebin/gh"

OUT="$WORK/out.txt"
LOG="$WORK/gh.log"

# run_case <token> <gh 退出码> [脚本参数...]；结果在 RC，输出在 $OUT，gh 调用记录在 $LOG
run_case() {
  local token="$1" ghexit="$2"; shift 2
  : > "$LOG"
  env PATH="$WORK/fakebin:$PATH" FAKE_GH_LOG="$LOG" FAKE_GH_EXIT="$ghexit" \
    WEB_DISPATCH_TOKEN="$token" bash "$SCRIPT" "$@" >"$OUT" 2>&1
  RC=$?
}

has()    { grep -q -- "$1" "$2"; }
hasnt()  { ! grep -q -- "$1" "$2"; }

# 1 缺 tag
run_case "tok-123" 0
check "缺 tag：退出 1" test "$RC" -eq 1
check "缺 tag：没有调用 gh" test ! -s "$LOG"

# 2 token 为空
run_case "" 0 v1.2.3
check "token 为空：退出 1" test "$RC" -eq 1
check "token 为空：输出含「未配置」" has "未配置" "$OUT"
check "token 为空：没有调用 gh" test ! -s "$LOG"

# 3 gh 失败
run_case "tok-123" 1 v1.2.3
check "gh 失败：退出 1" test "$RC" -eq 1
check "gh 失败：输出含 ::error 与「dispatch 失败」" has "::error::官网 dispatch 失败" "$OUT"

# 4 正常
run_case "tok-123" 0 v1.2.3
check "正常：退出 0" test "$RC" -eq 0
check "正常：gh 收到 event_type=app-released" has "event_type=app-released" "$LOG"
check "正常：gh 收到 tag" has "client_payload\[tag\]=v1.2.3" "$LOG"
check "正常：token 通过 GH_TOKEN 传给 gh" has "GH_TOKEN=tok-123" "$LOG"
check "正常：请求发往 dispatches 端点" has "repos/luuuuke88/clashmiaoweb/dispatches" "$LOG"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
