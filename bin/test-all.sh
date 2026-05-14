#!/usr/bin/env bash
# 全套：format + analyze + unit + widget + 可选 Android E2E + 可选 macOS 烟雾。
# 后两者按设备 / 平台自动检测，没有就跳过。
# Android 和 macOS 同时存在时**并行**跑两个 E2E，节省时间。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
echo "==> format check"
dart format --set-exit-if-changed lib/ test/ integration_test/
echo "==> analyze"
flutter analyze --fatal-warnings
echo "==> unit + widget"
flutter test test/

# 检测平台可用性
HAS_ANDROID=0
HAS_MACOS=0
if command -v adb >/dev/null 2>&1 && adb devices | grep -qE $'\tdevice$'; then
  HAS_ANDROID=1
fi
if [[ "$(uname)" == "Darwin" ]]; then
  HAS_MACOS=1
fi

# 并行启动可用的 E2E（先并行，再 wait + 收集 exit code）
pids=()
labels=()
if [[ $HAS_ANDROID -eq 1 ]]; then
  echo "==> launching Android E2E in parallel"
  bash bin/test-e2e.sh > /tmp/clashmiao-e2e-android.log 2>&1 &
  pids+=($!)
  labels+=("android")
fi
if [[ $HAS_MACOS -eq 1 ]]; then
  echo "==> launching macOS smoke in parallel"
  bash bin/test-e2e-macos.sh > /tmp/clashmiao-e2e-macos.log 2>&1 &
  pids+=($!)
  labels+=("macos")
fi

if [[ ${#pids[@]} -eq 0 ]]; then
  echo "==> skip e2e (no Android device, not on macOS)"
  exit 0
fi

# wait 每一个 + 汇总
overall=0
for i in "${!pids[@]}"; do
  if wait "${pids[$i]}"; then
    echo "✓ ${labels[$i]} E2E OK"
  else
    code=$?
    echo "✗ ${labels[$i]} E2E FAIL (exit $code)"
    echo "  see /tmp/clashmiao-e2e-${labels[$i]}.log"
    tail -20 "/tmp/clashmiao-e2e-${labels[$i]}.log"
    overall=1
  fi
done

exit $overall
