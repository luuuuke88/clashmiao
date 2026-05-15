#!/usr/bin/env bash
# 重新生成 Pigeon native bridge 代码 + 立即格式化。
# 改完 pigeons/box_api.dart 跑这个，不要直接跑 dart run pigeon —— Pigeon 输出
# 跟 dart format 默认风格略有出入，会让 CI analyze 红。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> generating pigeon code"
dart run pigeon --input pigeons/box_api.dart

echo "==> formatting generated files"
dart format lib/core/box_service/pigeon/

echo "✓ done. 三端 .g.{dart,kt,swift} 已更新 + Dart 端 format。"
echo "  Kotlin / Swift 那两个文件 IDE 保存时会自动 format，不需要手动跑。"
