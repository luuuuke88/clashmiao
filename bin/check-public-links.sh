#!/usr/bin/env bash
# 检查对外暴露的链接是否真的可达。
#
# 起因：build_config.dart 里那个"源码仓库"的兜底默认值曾长期指向一个 404 的
# 地址（仓库改名后没人更新），而它的注释还写着"这一项有兜底默认值，所以永远
# 可用"。关于页那个「源代码」入口在任何没传 dart-define 的构建里都是死链——
# 用户会以为是软件坏了，而不是"这个链接配错了"。
#
# 单元测试查不出 404，只能在 CI 里实打实请求一次。
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# 从源码里抽出所有写死的 https 链接（排除注释里的示例与协议命名空间）
urls=$(grep -rhoE 'https://[a-zA-Z0-9._~:/?#@!$&*+,;=%-]+' \
        lib/core/config/build_config.dart README.md 2>/dev/null \
      | sed 's/[.,)"]*$//' \
      | grep -vE 'example\.(com|test)|schemas\.android\.com|www\.w3\.org|keepachangelog\.com' \
      | sort -u)

while IFS= read -r url; do
  [ -z "$url" ] && continue
  code=$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 20 "$url" 2>/dev/null || echo 000)
  if [ "$code" = "200" ] || [ "$code" = "429" ]; then
    printf '  OK   %s (%s)\n' "$url" "$code"
  else
    printf '  DEAD %s (%s)\n' "$url" "$code"
    fail=1
  fi
done <<< "$urls"

if [ "$fail" -ne 0 ]; then
  echo
  echo '有对外链接不可达。绝不能让用户点到一个死链——要么修好，要么把入口去掉。'
  exit 1
fi
echo '对外链接全部可达。'
