#!/usr/bin/env bash
# Background watcher: auto-tap VPN consent / permission dialogs on the emulator.
# Runs in a loop for up to 300s so the integration test can proceed unattended.
set -uo pipefail

echo "[grant-vpn] started at $(date -u +%H:%M:%S)"

for i in $(seq 1 600); do
  # Re-apply appops every ~10s in case it resets between emulator cycles
  if [ $((i % 20)) -eq 1 ]; then
    adb shell cmd appops set com.clashmiao.clashmiao ESTABLISH_VPN_SERVICE allow >/dev/null 2>&1 || true
    adb shell cmd appops set com.clashmiao.clashmiao ACTIVATE_VPN allow >/dev/null 2>&1 || true
  fi

  # Detect VPN/permission dialog via window focus AND activity stack
  win=$(adb shell dumpsys window windows 2>/dev/null | grep -iE "Focus|vpndialogs|permissioncontroller" || true)
  if echo "$win" | grep -qi "vpndialogs\|permissioncontroller"; then
    echo "[grant-vpn] dialog in focus: $(echo "$win" | head -1)"
    sleep 0.2
    adb shell uiautomator dump /sdcard/uidump.xml >/dev/null 2>&1 && \
      adb shell cat /sdcard/uidump.xml > /tmp/uidump.xml 2>/dev/null || true
    if python3 bin/tap-allow-button.py; then
      sleep 1
    else
      echo "[grant-vpn] no button found in uidump, sending ENTER"
      adb shell input keyevent 66 || true
    fi
  fi
  sleep 0.5
done
