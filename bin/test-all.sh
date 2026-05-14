#!/usr/bin/env bash
# 全套：format + analyze + unit + widget + 可选 E2E。
# 没有 Android 设备时自动跳过 E2E。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
echo "==> format check"
dart format --set-exit-if-changed lib/ test/ integration_test/
echo "==> analyze"
flutter analyze --fatal-warnings
echo "==> unit + widget"
flutter test test/

if command -v adb >/dev/null 2>&1 && adb devices | grep -qE '\bdevice$'; then
  echo "==> e2e (Android device detected)"
  bash bin/test-e2e.sh
else
  echo "==> skip e2e (no Android device connected)"
fi
