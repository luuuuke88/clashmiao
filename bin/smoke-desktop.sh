#!/usr/bin/env bash
# 跨平台桌面 smoke：启动 GUI app（DevBoot 自动加订阅 + 连接） →
# 等 mixed inbound 监听 → curl --proxy 拿出口 IP → 对比直连 baseline。
#
# 输入：CLASHMIAO_TEST_SUB_URL env，或 ~/.clashmiao_dev_subscription_url 文件
# 平台：macOS / Linux
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=2080
TARGET_HOST="api.ipify.org"
WAIT_TIMEOUT=${WAIT_TIMEOUT:-90}    # mixed inbound listen
SETTLE_AFTER_LISTEN=${SETTLE_AFTER_LISTEN:-8}  # 等节点 url-test 完成

OS=$(uname -s)
log() { echo "[smoke $(date +%H:%M:%S)] $*"; }

# ============ 0. 前置检查 ============
if [[ -z "${CLASHMIAO_TEST_SUB_URL:-}" && ! -f "$HOME/.clashmiao_dev_subscription_url" ]]; then
  echo "error: 需要 CLASHMIAO_TEST_SUB_URL env 或 ~/.clashmiao_dev_subscription_url"
  exit 2
fi

# ============ 1. baseline ============
log "baseline IP (direct, no proxy)"
BASELINE=$(curl -sS --max-time 15 "https://$TARGET_HOST" || echo "FAIL")
if [[ "$BASELINE" == "FAIL" || -z "$BASELINE" ]]; then
  echo "error: baseline 直连失败"; exit 3
fi
log "  baseline = $BASELINE"

# ============ 2. 启动 app ============
APP_PID=""
cleanup() {
  log "cleanup..."
  if [[ -n "$APP_PID" ]]; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  case "$OS" in
    Darwin) pkill -x clashmiao 2>/dev/null || true ;;
    Linux)  pkill -f bundle/clashmiao 2>/dev/null || true ;;
  esac
}
trap cleanup EXIT

case "$OS" in
  Darwin)
    APP="build/macos/Build/Products/Debug/clashmiao.app"
    [[ -d "$APP" ]] || APP="build/macos/Build/Products/Release/clashmiao.app"
    [[ -d "$APP" ]] || { echo "error: $APP not built (run flutter build macos --{debug,release})"; exit 4; }
    pkill -x clashmiao 2>/dev/null || true
    sleep 1
    log "launching $APP/Contents/MacOS/clashmiao"
    # 直接 exec binary，stdout 留给 CI 排错；`open` 拿不到子进程 PID 不好 kill
    "$APP/Contents/MacOS/clashmiao" > /tmp/clashmiao-stdout.log 2>&1 &
    APP_PID=$!
    ;;
  Linux)
    BIN="build/linux/x64/debug/bundle/clashmiao"
    [[ -f "$BIN" ]] || BIN="build/linux/x64/release/bundle/clashmiao"
    [[ -f "$BIN" ]] || { echo "error: linux bundle not found (build/linux/x64/{debug,release}/bundle/clashmiao)"; exit 4; }
    log "launching $BIN under xvfb-run"
    xvfb-run -a "$BIN" > /tmp/clashmiao-stdout.log 2>&1 &
    APP_PID=$!
    ;;
  *)
    echo "error: unsupported OS=$OS — use smoke-desktop.ps1 for windows"; exit 5
    ;;
esac

# ============ 3. 等 mixed inbound ============
log "waiting for sing-box mixed inbound on 127.0.0.1:$PORT (timeout=${WAIT_TIMEOUT}s)"
for i in $(seq 1 $WAIT_TIMEOUT); do
  if (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
    log "  listening after ${i}s"
    break
  fi
  sleep 1
done
if ! (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
  echo "FAIL: 端口 $PORT 没监听 (sing-box 没启动)"
  if [[ -f /tmp/clashmiao-stdout.log ]]; then
    echo "--- app stdout/stderr tail (last 80) ---"
    tail -80 /tmp/clashmiao-stdout.log
  fi
  echo "--- pgrep clashmiao ---"
  pgrep -a clashmiao 2>&1 || pgrep -lf clashmiao 2>&1 || true
  exit 6
fi
log "  app stdout tail (last 30):"
[[ -f /tmp/clashmiao-stdout.log ]] && tail -30 /tmp/clashmiao-stdout.log | sed 's/^/  | /'

# 给 sing-box 多点时间完成节点 url-test（避免还没选好出 outbound）
log "settle ${SETTLE_AFTER_LISTEN}s for outbound url-test"
sleep $SETTLE_AFTER_LISTEN

# ============ 4. 走代理拿 IP ============
log "proxied IP (via http://127.0.0.1:$PORT)"
PROXIED=$(curl -sS --max-time 30 --proxy "http://127.0.0.1:$PORT" "https://$TARGET_HOST" || echo "FAIL")
log "  proxied  = $PROXIED"

# ============ 5. 断言 ============
if [[ "$PROXIED" == "FAIL" || -z "$PROXIED" ]]; then
  echo "FAIL: 走 proxy 的请求失败"; exit 7
fi
if ! [[ "$PROXIED" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: proxied 不是 IPv4: $PROXIED"; exit 8
fi
if [[ "$BASELINE" == "$PROXIED" ]]; then
  echo "FAIL: 出口 IP 没变 (sing-box 没真接管): $BASELINE → $PROXIED"; exit 9
fi

echo ""
echo "✓ $OS smoke OK: $BASELINE → $PROXIED"
