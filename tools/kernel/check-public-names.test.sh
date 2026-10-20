#!/usr/bin/env bash
# check-public-names.test.sh — check-public-names.sh 的自测。
# 在临时 git 仓库里跑，使用自造的词表，不碰真实词表；本脚本里的「违规词」都是占位。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/check-public-names.sh"

BAD="zorblax"            # 占位违规词
TOKEN="io.zorblax.libbox" # 占位的允许 token（完整 token 单独出现应通过）

T="$(mktemp -d "${TMPDIR:-/tmp}/names-selftest.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0; total=0

new_repo() { # new_repo <name> → 路径；已有干净的 README 并提交一次
  local r="$T/$1"
  mkdir -p "$r/tools/kernel" "$r/kernel" "$r/docs"
  git -C "$r" init -q
  git -C "$r" config user.email t@example.com
  git -C "$r" config user.name t
  cp "$SRC" "$r/tools/kernel/check-public-names.sh"
  printf '%s\n' "$BAD" >"$r/tools/kernel/denylist.local"
  printf '# 允许表\n%s\n' "$TOKEN" >"$r/tools/kernel/check-public-names.allow"
  printf 'clean\n' >"$r/README.md"
  git -C "$r" add -A && git -C "$r" commit -q -m "初始"
  echo "$r"
}
run() { (cd "$1/tools/kernel" && bash ./check-public-names.sh "${@:2}") >/dev/null 2>&1; }
expect() { # expect ok|fail <name> <rc>
  total=$((total + 1))
  if { [ "$1" = ok ] && [ "$3" -eq 0 ]; } || { [ "$1" = fail ] && [ "$3" -ne 0 ]; }; then
    pass=$((pass + 1)); echo "自测 ✓ $2"
  else
    echo "自测 ✗ $2（期望 $1，退出码 $3）" >&2
  fi
}
rc_of() { local rc=0; "$@" || rc=$?; echo "$rc"; }

# (1) 干净输入通过
r="$(new_repo clean)"
expect ok "干净输入通过" "$(rc_of run "$r")"

# (2) 违规分别出现在 Go 注释 / 夹具 JSON / Markdown 文档
r="$(new_repo go-comment)"; printf 'package x\n\n// 参考了 %s 的实现\n' "$BAD" >"$r/kernel/a.go"
expect fail "违规词在 Go 源码注释里 → 失败" "$(rc_of run "$r")"
r="$(new_repo json)"; mkdir -p "$r/kernel/testdata"; printf '{"name":"%s-node"}\n' "$BAD" >"$r/kernel/testdata/f.json"
expect fail "违规词在测试夹具 JSON 里 → 失败" "$(rc_of run "$r")"
r="$(new_repo md)"; printf '# 文档\n\n来自 %s。\n' "$BAD" >"$r/docs/a.md"
expect fail "违规词在 Markdown 文档里 → 失败" "$(rc_of run "$r")"

# (3) 词表缺失
r="$(new_repo no-list)"; rm "$r/tools/kernel/denylist.local"
expect fail "词表缺失 → 失败" "$(rc_of run "$r")"

# (4) 词表为空（只有空行与注释也算空）
r="$(new_repo empty-list)"; printf '\n  \n# 只有注释\n' >"$r/tools/kernel/denylist.local"
expect fail "词表为空 → 失败" "$(rc_of run "$r")"

# (5) 词表文件自身含违规词，其它文件干净 → 通过（排除生效）；已入库也一样
r="$(new_repo self-exclude)"
git -C "$r" add -f tools/kernel/denylist.local
expect ok "词表文件自身含违规词（已跟踪）→ 通过" "$(rc_of run "$r")"

# (6) 违规词只在提交信息里：--commits 失败，默认模式通过
r="$(new_repo commit-msg)"
printf 'more\n' >>"$r/README.md"; git -C "$r" commit -q -am "提到 ${BAD} 的改动"
expect fail "违规词在提交信息里：--commits 失败" "$(rc_of run "$r" --commits HEAD~1..HEAD)"
expect ok   "违规词在提交信息里：默认模式通过" "$(rc_of run "$r")"
expect ok   "空范围的 --commits 通过" "$(rc_of run "$r" --commits HEAD..HEAD)"

# (7) 大小写变体
r="$(new_repo case)"; printf 'x ZoRbLaX y\n' >"$r/docs/c.md"
expect fail "大小写变体命中" "$(rc_of run "$r")"

# (8) 允许 token 单独出现通过；同一行另有词表名字仍失败；token 的变体（多一段）失败
r="$(new_repo allow-ok)"; printf 'import %s.Libbox\n' "$TOKEN" >"$r/docs/d.md"
expect ok   "允许 token 单独出现 → 通过" "$(rc_of run "$r")"
r="$(new_repo allow-mixed)"; printf 'import %s.Libbox // 来自 %s\n' "$TOKEN" "$BAD" >"$r/docs/d.md"
expect fail "同一行里 token 之外另有词表名字 → 失败" "$(rc_of run "$r")"
r="$(new_repo allow-variant)"; printf 'io.zorblax.other\n' >"$r/docs/d.md"
expect fail "不是完整 token 的变体 → 失败" "$(rc_of run "$r")"

# (9) 正文里以 @@ 开头的行不会被当成分隔符吞掉违规
r="$(new_repo at-at)"; printf '@@ x\n%s\n' "$BAD" >"$r/docs/e.md"
expect fail "正文含 @@ 行也不漏扫" "$(rc_of run "$r")"

# (10) 未跟踪文件也要扫（提交前就能拦住）；被 .gitignore 忽略的不扫
r="$(new_repo untracked)"; printf '%s\n' "$BAD" >"$r/docs/new.md"
expect fail "未跟踪（未忽略）的文件也被扫" "$(rc_of run "$r")"
r="$(new_repo ignored)"; printf 'docs/new.md\n' >"$r/.gitignore"; printf '%s\n' "$BAD" >"$r/docs/new.md"
expect ok   "被忽略的文件不扫" "$(rc_of run "$r")"

# (11) 范围之外的目录不扫
r="$(new_repo outside)"; mkdir -p "$r/ios"; printf '%s\n' "$BAD" >"$r/ios/x.swift"
expect ok   "范围之外（ios/）不扫" "$(rc_of run "$r")"

echo "check-public-names.test: ${pass}/${total} 通过"
[ "$pass" -eq "$total" ]
