#!/usr/bin/env bash
# 纯 unit + widget 测试（不需要模拟器）。
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
flutter test test/
