#!/usr/bin/env bash
# check-java-api.sh — 门面公共 Java API 与快照 kernel/api/java-api.txt 的零差异放行门。
#
# 用法（由 build-android.sh 的放行门调用，参数是解开的 aar 目录）：
#   tools/kernel/check-java-api.sh <aar 解开的目录>
#   UPDATE_API=1 tools/kernel/check-java-api.sh <目录>    # 重新生成快照（任何公共 API 变化必须同时改快照并过评审）
#
# 快照 = classes.jar 里门面包 com.clashmiao.libcore.core 下每个类的 `javap -public` 输出，按类名排序。
# gomobile 的运行时类（go.*）不在快照里：它们不是我们的 API。
#
# 环境变量（测试用）：API_SNAPSHOT（快照路径）、JAVAP_BIN、REPO_ROOT、JAVA_HOME。
set -euo pipefail

die() { printf '\033[0;31m[java-api]\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[0;32m[java-api]\033[0m %s\n' "$*"; }

[ $# -eq 1 ] || die "用法：$0 <aar 解开的目录>"
check_dir="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SNAPSHOT="${API_SNAPSHOT:-$REPO_ROOT/kernel/api/java-api.txt}"
if [ -n "${JAVAP_BIN:-}" ]; then JAVAP="$JAVAP_BIN"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javap" ]; then JAVAP="$JAVA_HOME/bin/javap"
else JAVAP="$(command -v javap || true)"; fi
[ -n "$JAVAP" ] && [ -x "$JAVAP" ] || die "找不到 javap（设置 JAVA_HOME）"

jar="$check_dir/classes.jar"
[ -f "$jar" ] || die "aar 里没有 classes.jar：${jar}"

list="$(unzip -Z1 "$jar")" || die "解不开 classes.jar"
classes="$(printf '%s\n' "$list" | grep -E '^com/clashmiao/libcore/core/[^/]+\.class$' | LC_ALL=C sort | sed -e 's/\.class$//' -e 's#/#.#g' || true)"
[ -n "$classes" ] || die "classes.jar 里没有门面包 com.clashmiao.libcore.core 的类"

actual="$(mktemp "${TMPDIR:-/tmp}/java-api.XXXXXX")"
trap 'rm -f "$actual"' EXIT
while IFS= read -r c; do
  "$JAVAP" -public -cp "$jar" "$c" >>"$actual" || die "javap 失败：${c}"
done <<<"$classes"
[ -s "$actual" ] || die "javap 没有输出"

if [ "${UPDATE_API:-}" = 1 ]; then
  mkdir -p "$(dirname "$SNAPSHOT")"
  cp "$actual" "$SNAPSHOT"
  log "已重新生成快照：${SNAPSHOT}（$(wc -l <"$SNAPSHOT" | tr -d ' ') 行），请连同 API 变化一起评审"
  exit 0
fi

[ -f "$SNAPSHOT" ] || die "缺少快照 ${SNAPSHOT}（首次生成用 UPDATE_API=1）"
if ! diff -u "$SNAPSHOT" "$actual" >&2; then
  die "门面公共 Java API 与快照不一致；确属有意变化时用 UPDATE_API=1 重新生成并评审"
fi
log "公共 API 与快照一致（$(printf '%s\n' "$classes" | wc -l | tr -d ' ') 个类）"
