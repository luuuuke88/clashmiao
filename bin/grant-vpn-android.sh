#!/usr/bin/env bash
# Background watcher: auto-tap VPN consent / permission dialogs on the emulator.
# Runs in a loop for up to 60s so the integration test can proceed unattended.
set -uo pipefail

for i in $(seq 1 120); do
  top=$(adb shell dumpsys window windows 2>/dev/null \
        | grep -E "mCurrentFocus|vpndialogs|permissioncontroller" || true)
  if echo "$top" | grep -qi "vpndialogs\|permissioncontroller"; then
    sleep 0.4
    adb shell uiautomator dump /sdcard/uidump.xml >/dev/null 2>&1 && \
      adb shell cat /sdcard/uidump.xml > /tmp/uidump.xml 2>/dev/null || true
    python3 bin/tap-allow-button.py && sleep 1 || true
  fi
  sleep 0.5
done
