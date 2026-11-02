#!/usr/bin/env bash
# fetch-libcore.test.sh — bin/fetch-libcore.sh 与 tools/kernel/check-libcore-checksums.sh 的单元测试
#
# 用法：bash bin/fetch-libcore.test.sh
# 把脚本拷进临时目录当作"仓库根"，PATH 最前面放一个假的 gh（把 FAKE_GH_CONTENT 写到 -O 指定的路径），
# 全程不联网、不碰真实仓库里的文件。断言：
#   1 内容与校验和一致 → 退出 0，文件保留
#   2 下载内容被篡改   → 非 0，文件被删除
#   3 已存在的文件被篡改且没设 FORCE → 非 0，不能直接跳过，文件被删除，也没有发起下载
#   4 tag 不在校验和文件里 → 非 0，提示「缺少校验和」，文件被删除
#   5 ios 缓存 zip 被篡改 → 非 0，ios/Frameworks/ 里没有解压出的内容
#   6 check-libcore-checksums.sh：覆盖完整放行、缺 tag / 缺资产 / 格式错误 / 重复条目拒绝
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$(cd "$HERE/.." && pwd)"
FETCH="$SRC_ROOT/bin/fetch-libcore.sh"
CHECKER="$SRC_ROOT/tools/kernel/check-libcore-checksums.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }
check() { # <描述> <命令...>
  local desc="$1"; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

[ -f "$FETCH" ] || { echo "FAIL  脚本不存在：$FETCH"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

ANDROID_TAG=libcore-v9.9.9-r1
MAIN_TAG=libcore-v8.8.8-x

# 新建一个"仓库根"：bin/fetch-libcore.sh 副本 + 假 gh + 校验和文件
new_root() {
  R="$WORK/root"; rm -rf "$R"; mkdir -p "$R/bin" "$R/fakebin" "$R/tools/kernel"
  cp "$FETCH" "$R/bin/fetch-libcore.sh"
  cat >"$R/fakebin/gh" <<'GH'
#!/usr/bin/env bash
# 假 gh：只认 `gh release download <tag> -p <asset> -O <dest> ...`
out=""
while [ $# -gt 0 ]; do
  case "$1" in -O) out="$2"; shift ;; esac
  shift
done
echo "download" >> "$FAKE_GH_LOG"
[ -n "$out" ] || exit 2
printf '%s' "$FAKE_GH_CONTENT" > "$out"
GH
  chmod +x "$R/fakebin/gh"
  : > "$R/gh.log"
  GOOD="good-aar-content"
  printf '%s' "$GOOD" > "$WORK/good"
  printf '%s  %s/libcore.aar\n' "$(sha "$WORK/good")" "$ANDROID_TAG" > "$R/sums.txt"
}

# run_fetch <content> <args...>：在 $R 里跑；环境变量由调用方 export 补充
run_fetch() {
  local content="$1"; shift
  OUT="$(cd "$R" && env PATH="$R/fakebin:$PATH" FAKE_GH_CONTENT="$content" FAKE_GH_LOG="$R/gh.log" \
        LIBCORE_CHECKSUMS="$R/sums.txt" ANDROID_LIBCORE_TAG="${T_ANDROID:-$ANDROID_TAG}" LIBCORE_TAG="$MAIN_TAG" \
        "$@" 2>&1)"
  RC=$?
}

AAR() { echo "$R/android/app/libs/libcore.aar"; }
downloads() { wc -l <"$R/gh.log" | tr -d ' '; }

echo "== fetch-libcore.sh"

# 1 内容一致
new_root
run_fetch "$GOOD" bash bin/fetch-libcore.sh android
check "1 内容一致：退出 0" test "$RC" -eq 0
check "1 内容一致：文件保留" test -s "$(AAR)"

# 2 下载内容被篡改
new_root
run_fetch "tampered" bash bin/fetch-libcore.sh android
check "2 下载被篡改：退出非 0" test "$RC" -ne 0
check "2 下载被篡改：文件被删除" test ! -e "$(AAR)"
case "$OUT" in *期望*实际*) ok "2 下载被篡改：打印期望值和实际值" ;; *) bad "2 输出里没有期望/实际值：$OUT" ;; esac

# 3 已存在但被篡改，没有 FORCE
new_root
mkdir -p "$R/android/app/libs"; printf '%s' "tampered-existing" > "$(AAR)"
run_fetch "$GOOD" bash bin/fetch-libcore.sh android
check "3 复用文件被篡改：退出非 0" test "$RC" -ne 0
check "3 复用文件被篡改：文件被删除" test ! -e "$(AAR)"
check "3 复用文件被篡改：没有直接跳过也没有静默重下" test "$(downloads)" -eq 0
# 3b 已存在且正确 → 跳过下载，仍然通过
new_root
mkdir -p "$R/android/app/libs"; printf '%s' "$GOOD" > "$(AAR)"
run_fetch "tampered" bash bin/fetch-libcore.sh android
check "3b 复用文件正确：退出 0" test "$RC" -eq 0
check "3b 复用文件正确：未发起下载" test "$(downloads)" -eq 0

# 4 tag 不在校验和文件里
new_root
T_ANDROID=libcore-v0.0.0-unknown run_fetch "$GOOD" bash bin/fetch-libcore.sh android
check "4 缺条目：退出非 0" test "$RC" -ne 0
case "$OUT" in *缺少校验和*) ok "4 缺条目：提示「缺少校验和」" ;; *) bad "4 输出里没有「缺少校验和」：$OUT" ;; esac
check "4 缺条目：未校验的文件不留在原地" test ! -e "$(AAR)"
unset T_ANDROID

# 5 ios：缓存 zip 被篡改
new_root
mkdir -p "$R/.cache"; printf '%s' "tampered-zip" > "$R/.cache/libcore-ios.zip"
printf '%s  %s/Libcore.xcframework.zip\n' "0000000000000000000000000000000000000000000000000000000000000000" "$MAIN_TAG" >> "$R/sums.txt"
run_fetch "unused" bash bin/fetch-libcore.sh ios
check "5 ios 缓存被篡改：退出非 0" test "$RC" -ne 0
check "5 ios 缓存被篡改：zip 被删除" test ! -e "$R/.cache/libcore-ios.zip"
check "5 ios 缓存被篡改：Frameworks 里没有解压内容" test -z "$(ls -A "$R/ios/Frameworks" 2>/dev/null)"

# 5b ios：缓存 zip 正确 → 解压（需要 zip 命令，没有就跳过）
if command -v zip >/dev/null; then
  new_root
  mkdir -p "$WORK/z/Libcore.xcframework" "$R/.cache"; : > "$WORK/z/Libcore.xcframework/marker"
  (cd "$WORK/z" && zip -qr "$R/.cache/libcore-ios.zip" Libcore.xcframework)
  printf '%s  %s/Libcore.xcframework.zip\n' "$(sha "$R/.cache/libcore-ios.zip")" "$MAIN_TAG" >> "$R/sums.txt"
  run_fetch "unused" bash bin/fetch-libcore.sh ios
  check "5b ios 缓存正确：退出 0" test "$RC" -eq 0
  check "5b ios 缓存正确：已解压" test -e "$R/ios/Frameworks/Libcore.xcframework/marker"
  rm -rf "$WORK/z"
else
  echo "  SKIP  5b 没有 zip 命令"
fi

echo "== check-libcore-checksums.sh"

# 构造一个最小仓库根：fetch-libcore.sh 默认值 + 两个 workflow + 校验和
new_tree() {
  T="$WORK/tree"; rm -rf "$T"; mkdir -p "$T/bin" "$T/.github/workflows" "$T/tools/kernel"
  cat >"$T/bin/fetch-libcore.sh" <<EOS
TAG="\${LIBCORE_TAG:-$MAIN_TAG}"
ANDROID_TAG="\${ANDROID_LIBCORE_TAG:-$ANDROID_TAG}"
EOS
  for w in ci release; do
    printf 'env:\n  LIBCORE_TAG: %s\n  ANDROID_LIBCORE_TAG: %s\n' "$MAIN_TAG" "$ANDROID_TAG" >"$T/.github/workflows/$w.yml"
  done
  H=$(printf '%064d' 1)
  {
    for a in libcore.dylib libcore.dll libcore.so Libcore.xcframework.zip; do echo "$H  $MAIN_TAG/$a"; done
    echo "$H  $ANDROID_TAG/libcore.aar"
  } >"$T/tools/kernel/libcore-checksums.txt"
}
run_checker() { OUT="$(env -u LIBCORE_CHECKSUMS bash "$CHECKER" "$T" 2>&1)"; RC=$?; }

new_tree; run_checker
check "6 完整覆盖：通过" test "$RC" -eq 0

new_tree
sed -i.bak "s/libcore-v8.8.8-x/libcore-v7.7.7-y/" "$T/.github/workflows/release.yml"; run_checker
check "6 workflow 用了没登记的 tag：失败" test "$RC" -ne 0

new_tree
grep -v "libcore.so" "$T/tools/kernel/libcore-checksums.txt" >"$T/x" && mv "$T/x" "$T/tools/kernel/libcore-checksums.txt"; run_checker
check "6 缺资产：失败" test "$RC" -ne 0

new_tree
echo "nothex  $MAIN_TAG/extra" >>"$T/tools/kernel/libcore-checksums.txt"; run_checker
check "6 格式错误：失败" test "$RC" -ne 0

new_tree
echo "$(printf '%064d' 2)  $ANDROID_TAG/libcore.aar" >>"$T/tools/kernel/libcore-checksums.txt"; run_checker
check "6 重复条目：失败" test "$RC" -ne 0

echo "---"
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
