#!/usr/bin/env bash
# Android E2E：需要已连接的 emulator 或真机。
# 订阅 URL 优先 CLASHMIAO_TEST_SUB_URL，否则读 ~/.clashmiao_dev_subscription_url。
set -euo pipefail
cd "$(dirname "$0")/.."

URL="${CLASHMIAO_TEST_SUB_URL:-}"
if [[ -z "$URL" && -f "$HOME/.clashmiao_dev_subscription_url" ]]; then
  URL=$(tr -d '[:space:]' < "$HOME/.clashmiao_dev_subscription_url")
fi
if [[ -z "$URL" ]]; then
  echo "error: no test subscription URL"
  echo "  set CLASHMIAO_TEST_SUB_URL=... or create ~/.clashmiao_dev_subscription_url"
  exit 2
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "error: adb not found in PATH"
  exit 3
fi
if ! adb devices | grep -qE $'\tdevice$'; then
  echo "error: no Android device connected (run an AVD or plug a phone)"
  adb devices
  exit 4
fi

DEVICE=$(adb devices | awk '/\tdevice$/ {print $1; exit}')
echo "==> running e2e on device: $DEVICE"

flutter test integration_test/android_smart_mode_test.dart \
  -d "$DEVICE" \
  --dart-define=CLASHMIAO_TEST_SUB_URL="$URL"
