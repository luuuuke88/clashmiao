#!/usr/bin/env bash
# macOS 烟雾测试：起 app → 等 mixed inbound 监听 → curl --proxy 验流量 → 关 app。
#
# macOS 没有 TUN（用户进程没 root），所以验证流量必须显式走 127.0.0.1:2080，
# 不能像 Android 那样 TUN 自动接管。
#
# 前置：~/.clashmiao_dev_subscription_url 必须有合法订阅 URL（DevBoot 会读它自动添加 + 连接）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/macos/Build/Products/Debug/clashmiao.app"
PORT=2080
TARGET_HOST="api.ipify.org"

# ============ 0. 前置检查 ============
if [[ ! -f "$HOME/.clashmiao_dev_subscription_url" ]]; then
  echo "error: $HOME/.clashmiao_dev_subscription_url not found"
  echo "       (该文件由 DevBoot 读取自动添加订阅 + 连接)"
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  echo "==> building debug macOS app (cold ~2 min)"
  flutter build macos --debug
fi

# ============ 1. 收 baseline IP（未启动 app）============
echo "==> baseline IP (no VPN)"
BASELINE=$(curl -sS --max-time 10 "https://$TARGET_HOST" || echo "FAIL")
if [[ "$BASELINE" == "FAIL" || -z "$BASELINE" ]]; then
  echo "error: 取不到 baseline IP（网络挂了或 DNS 解析失败）"
  exit 3
fi
echo "    baseline = $BASELINE"

# ============ 2. 启动 app（背景）============
# pkill 旧实例避免冲突
pkill -x clashmiao 2>/dev/null || true
sleep 1

echo "==> launching $APP"
open "$APP"

# ============ 3. 等 mixed inbound 起来 ============
echo "==> waiting for sing-box mixed inbound on 127.0.0.1:$PORT"
for i in {1..60}; do
  if nc -z 127.0.0.1 $PORT 2>/dev/null; then
    echo "    listening after ${i}s"
    break
  fi
  sleep 1
done

if ! nc -z 127.0.0.1 $PORT 2>/dev/null; then
  echo "error: 端口 $PORT 一直没监听（sing-box 没启动或挂了）"
  pkill -x clashmiao 2>/dev/null || true
  exit 4
fi

# 给 sing-box 多 3s 完成 outbound 链路建立
sleep 3

# ============ 4. 走 proxy 验证流量 ============
echo "==> proxied IP (via 127.0.0.1:$PORT HTTP CONNECT)"
PROXIED=$(curl -sS --max-time 30 --proxy "http://127.0.0.1:$PORT" "https://$TARGET_HOST" || echo "FAIL")
echo "    proxied  = $PROXIED"

# ============ 5. cleanup ============
echo "==> killing app"
pkill -x clashmiao 2>/dev/null || true
sleep 1

# ============ 6. 断言 ============
if [[ "$PROXIED" == "FAIL" || -z "$PROXIED" ]]; then
  echo "FAIL: 走 proxy 的请求超时 / 失败"
  exit 5
fi

if ! [[ "$PROXIED" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: proxied 返回不是 IPv4: $PROXIED"
  exit 6
fi

if [[ "$BASELINE" == "$PROXIED" ]]; then
  echo "FAIL: 出口 IP 没变（VPN 没生效？）$BASELINE → $PROXIED"
  exit 7
fi

echo ""
echo "✓ macOS smoke OK: $BASELINE → $PROXIED"
