#!/usr/bin/env bash
# check-public-names.sh — 公开内容里不得出现词表中的名字。
#
# 用法：
#   tools/kernel/check-public-names.sh                    # 扫描仓库里的公开文件
#   tools/kernel/check-public-names.sh --commits <range>  # 扫描 git log 的提交信息，如 origin/main..HEAD
#
# 词表：tools/kernel/denylist.local（不入库，一行一个名字，# 开头为注释）。
#   CI 用仓库 secret KERNEL_DENYLIST 把词表写进该文件；词表缺失、不可读或为空一律失败。
# 允许表：tools/kernel/check-public-names.allow（入库，一行一个完整 token）。
#   比对前先把这些完整 token 从行里剔除；token 以外的出现照常失败。
# 扫描范围：git 已跟踪与未忽略的未跟踪文件里，
#   kernel/ tools/kernel/ docs/ android/ lib/ test/ bin/ README.md CHANGELOG.md；
#   按精确路径排除词表文件与允许表自身。大小写不敏感。
# 输出只给「文件:行号」，不回显命中内容，免得 CI 日志把词表泄露出去。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DENY_REL="tools/kernel/denylist.local"
ALLOW_REL="tools/kernel/check-public-names.allow"
DENY="$ROOT/$DENY_REL"
ALLOW="$ROOT/$ALLOW_REL"
SCOPE=(kernel/ tools/kernel/ docs/ android/ lib/ test/ bin/ README.md CHANGELOG.md)

die() { echo "check-public-names: $*" >&2; exit 1; }

[ -f "$DENY" ] && [ -r "$DENY" ] || die "词表缺失或不可读：${DENY_REL}。请先创建（一行一个名字；CI 里由 secret KERNEL_DENYLIST 写入）"
grep -qE '^[[:space:]]*[^#[:space:]]' "$DENY" || die "词表为空：${DENY_REL}。请先创建"

# perl 一次处理所有输入：读词表与允许表，逐行剔除允许 token 后做大小写不敏感的固定串匹配。
# 输入协议：每个文件/消息前一行 "\x01\x02<label>"（控制字符前缀，正文里不会出现），之后是其内容。
scan() {
  perl -e '
    use strict; use warnings;
    my ($deny, $allow) = @ARGV; @ARGV = ();
    open(my $d, "<:encoding(UTF-8)", $deny) or die "cannot read denylist\n";
    my @names; while (<$d>) { chomp; s/^\s+|\s+$//g; next if $_ eq "" || /^#/; push @names, lc $_; }
    close $d;
    my @allow;
    if (-f $allow) {
      open(my $a, "<:encoding(UTF-8)", $allow) or die "cannot read allow list\n";
      while (<$a>) { chomp; s/^\s+|\s+$//g; next if $_ eq "" || /^#/; push @allow, $_; }
      close $a;
    }
    # 长 token 优先，避免短的先吃掉长的一部分
    @allow = sort { length($b) <=> length($a) } @allow;
    binmode(STDIN, ":encoding(UTF-8)");
    my ($label, $n, $bad) = ("", 0, 0);
    while (my $line = <STDIN>) {
      chomp $line;
      if ($line =~ /^\x01\x02(.*)$/) { $label = $1; $n = 0; next; }
      $n++;
      my $l = $line;
      for my $t (@allow) { my $q = quotemeta($t); $l =~ s/$q//g; }
      $l = lc $l;
      for my $name (@names) {
        if (index($l, $name) >= 0) { print "$label:$n: 命中词表\n"; $bad = 1; last; }
      }
    }
    exit($bad ? 1 : 0);
  ' "$DENY" "$ALLOW"
}

mode="files"
range=""
if [ "${1:-}" = "--commits" ]; then
  mode="commits"; range="${2:-}"
  [ -n "$range" ] || die "--commits 需要一个范围，如 origin/main..HEAD"
fi

cd "$ROOT"
if [ "$mode" = "commits" ]; then
  revs="$(git rev-list "$range")" || die "无法解析提交范围：${range}"
  [ -n "$revs" ] || { echo "check-public-names: 范围 ${range} 内没有提交，通过"; exit 0; }
  if ! {
    for c in $revs; do
      printf '\001\002commit:%s\n' "${c:0:10}"
      git log -1 --format=%B "$c"
    done
  } | scan; then
    die "提交信息命中词表（见上）"
  fi
  echo "check-public-names: 提交信息通过（$(wc -w <<<"$revs" | tr -d ' ') 个提交）"
  exit 0
fi

count=0
if ! {
  while IFS= read -r -d '' f; do
    case "$f" in "$DENY_REL"|"$ALLOW_REL") continue ;; esac
    [ -f "$f" ] || continue
    # 二进制文件（含 NUL）不扫
    if grep -qI . "$f" 2>/dev/null || [ ! -s "$f" ]; then
      printf '\001\002%s\n' "$f"
      cat "$f"
      echo
    fi
  done < <(git ls-files -z --cached --others --exclude-standard -- "${SCOPE[@]}" | sort -zu)
} | scan; then
  die "公开文件命中词表（见上）"
fi
echo "check-public-names: 公开文件通过"
