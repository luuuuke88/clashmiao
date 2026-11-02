#!/usr/bin/env bash
# commit-msgs.sh — 提交信息检查（本文件在多个仓库里逐字节相同，自包含，不依赖仓库里的其他脚本）
#
# 用法：commit-msgs.sh <base> <head>
#   检查 git rev-list --no-merges <base>..<head> 里的每条提交；作者名或邮箱含 [bot] 的跳过。
#   规则 1 格式：首行必须是  type(scope): 描述  （半角冒号 + 空格；scope 可省）
#            type ∈ feat|fix|refactor|perf|test|docs|chore|ci|build
#   规则 2 IPv4：首行和正文里不得出现公网 IPv4。放行：127.* 0.0.0.0、10.*、192.168.*、172.16-31.*、
#            公共 DNS（1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 223.5.5.5 223.6.6.6 119.29.29.29）、
#            fake-ip 198.18.0.0/15、文档示例段（192.0.2.* 198.51.100.* 203.0.113.*）
#   规则 3 禁用词：环境变量 PUBLIC_NAME_DENYLIST，每行一个词，不区分大小写，命中即违规；
#            变量为空时打印提示并跳过本规则。
# 退出码：0 全部合规；1 有违规（逐条打印 "<短SHA> <原因>"）；2 参数或引用错误。
# 兼容 bash 3.2（macOS 自带）与 Linux CI。
set -u

usage() { echo "用法：$0 <base> <head>" >&2; exit 2; }
[ "$#" -eq 2 ] || usage
base="$1"; head="$2"

git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || { echo "无法解析 base 引用：${base}" >&2; exit 2; }
git rev-parse --verify --quiet "${head}^{commit}" >/dev/null || { echo "无法解析 head 引用：${head}" >&2; exit 2; }
shas="$(git rev-list --no-merges "${base}..${head}")" || { echo "git rev-list 失败" >&2; exit 2; }

# ---- 规则 3 的前置：禁用词 ----
denylist="${PUBLIC_NAME_DENYLIST:-}"
if [ -z "$denylist" ]; then
  echo "denylist 未提供，跳过禁用词检查"
fi

# 首行格式（正则放进变量，bash 3.2 的 [[ =~ ]] 需要这样写）
subject_re='^(feat|fix|refactor|perf|test|docs|chore|ci|build)(\([^)]+\))?: .+'

# 是否放行的 IPv4：参数为四个十进制八位组（可能带前导零）
ip_allowed() {
  local a=$((10#$1)) b=$((10#$2)) c=$((10#$3)) d=$((10#$4))
  [ "$a" -eq 127 ] && return 0
  [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$c" -eq 0 ] && [ "$d" -eq 0 ] && return 0
  [ "$a" -eq 10 ] && return 0
  [ "$a" -eq 192 ] && [ "$b" -eq 168 ] && return 0
  [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ] && return 0
  [ "$a" -eq 198 ] && { [ "$b" -eq 18 ] || [ "$b" -eq 19 ]; } && return 0
  [ "$a" -eq 192 ] && [ "$b" -eq 0 ] && [ "$c" -eq 2 ] && return 0
  [ "$a" -eq 198 ] && [ "$b" -eq 51 ] && [ "$c" -eq 100 ] && return 0
  [ "$a" -eq 203 ] && [ "$b" -eq 0 ] && [ "$c" -eq 113 ] && return 0
  case "$a.$b.$c.$d" in
    1.1.1.1|1.0.0.1|8.8.8.8|8.8.4.4|223.5.5.5|223.6.6.6|119.29.29.29) return 0 ;;
  esac
  return 1
}

failed=0
report() { # report <sha> <原因>
  printf '%s %s\n' "$1" "$2"
  failed=1
}

for sha in $shas; do
  short="$(git rev-parse --short "$sha")"
  author="$(git log -1 --format='%an <%ae>' "$sha")"
  case "$author" in *'[bot]'*) continue ;; esac

  msg="$(git log -1 --format=%B "$sha")"
  subject="$(printf '%s\n' "$msg" | head -n 1)"

  # 规则 1：格式
  if ! [[ "$subject" =~ $subject_re ]]; then
    report "$short" "首行不符合 type(scope): 描述（半角冒号）：$subject"
  fi

  # 规则 2：IPv4。取出所有由 4 段及以上的点分数字组成的片段；恰好 4 段且每段 ≤255 才算 IPv4。
  # 句末的句点不会被带上（片段必须以数字结尾）；5 段以上的版本号不算。
  for tok in $(printf '%s\n' "$msg" | LC_ALL=C grep -Eo '[0-9]+(\.[0-9]+){3,}' | sort -u); do
    oldifs="$IFS"; IFS=.
    # shellcheck disable=SC2086  # 有意按 IFS=. 拆分
    set -- $tok
    IFS="$oldifs"
    [ "$#" -eq 4 ] || continue
    valid=1
    for o in "$@"; do
      [ "${#o}" -le 3 ] && [ "$((10#$o))" -le 255 ] || { valid=0; break; }
    done
    [ "$valid" -eq 1 ] || continue
    ip_allowed "$1" "$2" "$3" "$4" && continue
    report "$short" "含公网 IPv4：$tok"
  done

  # 规则 3：禁用词（不区分大小写，按字面匹配）
  if [ -n "$denylist" ]; then
    while IFS= read -r word; do
      [ -n "$word" ] || continue
      if printf '%s\n' "$msg" | grep -qiF -e "$word"; then
        report "$short" "含禁用词：$word"
      fi
    done <<EOF_DENY
$denylist
EOF_DENY
  fi
done

exit "$failed"
