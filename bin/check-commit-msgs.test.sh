#!/usr/bin/env bash
# check-commit-msgs.test.sh — bin/check-commit-msgs.sh（提交信息检查）的单元测试
#
# 用法：bash bin/check-commit-msgs.test.sh
# 在临时 git 仓库里构造提交，逐条断言退出码：
#   格式（半角冒号、type 白名单）、IPv4（公网拒绝，回环/私网/公共 DNS/fake-ip/文档段放行）、
#   禁用词（大小写不敏感、变量为空时跳过）、merge 提交与 [bot] 作者跳过、参数错误。
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/check-commit-msgs.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$*"; }

if [ ! -f "$CHECK" ]; then
  echo "FAIL  脚本不存在：$CHECK"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 全新的临时仓库，带一个基线提交（基线本身不参与检查）。
new_repo() {
  rm -rf "$WORK/r" && mkdir "$WORK/r" && cd "$WORK/r" || exit 1
  git init -q -b main .
  git config commit.gpgsign false
  git config user.name tester
  git config user.email tester@example.com
  git commit -q --allow-empty -m 'chore: base'
  git tag base
}

# commit_as 作者名 作者邮箱 首行 [正文]
commit_as() {
  local an="$1" ae="$2" subj="$3" body="${4:-}"
  if [ -n "$body" ]; then
    GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" git commit -q --allow-empty -m "$subj" -m "$body"
  else
    GIT_AUTHOR_NAME="$an" GIT_AUTHOR_EMAIL="$ae" git commit -q --allow-empty -m "$subj"
  fi
}

# run_case 说明 期望退出码 首行 [正文] —— 新仓库里提交一条，检查 base..HEAD
run_case() {
  local msg="$1" want="$2" subj="$3" body="${4:-}" rc=0 out
  new_repo
  commit_as tester tester@example.com "$subj" "$body"
  out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
  if [ "$rc" = "$want" ]; then ok "$msg"; else bad "${msg}（期望 rc=${want}，实际 rc=${rc}）：$out"; fi
}

echo "== 格式 =="
run_case 'feat(x): 好 -> 0'                0 'feat(x): 好'
run_case '无 scope 的 fix: 好 -> 0'         0 'fix: 好'
run_case '修复：坏 -> 1'                    1 '修复：坏'
run_case 'docs：全角冒号 -> 1'              1 'docs：全角冒号'
run_case '未知 type -> 1'                   1 'wip(x): 半成品'
run_case '冒号后缺空格 -> 1'                1 'feat(x):好'
run_case '空 scope -> 1'                    1 'feat(): 好'

echo "== IPv4 =="
run_case '正文含公网 IP 11.22.33.44 -> 1'    1 'feat(x): 好' '服务器 11.22.33.44'
run_case '首行含公网 IP -> 1'               1 'fix(x): 改 11.22.33.44 的配置'
run_case '正文含 1.1.1.1 -> 0'              0 'feat(x): 好' '用 1.1.1.1 解析'
run_case '正文含 198.18.0.1 -> 0'           0 'feat(x): 好' 'fake-ip 198.18.0.1'
run_case '198.19.255.1 (fake-ip 上半段) -> 0' 0 'feat(x): 好' '198.19.255.1'
run_case '198.20.0.1 (fake-ip 段之外) -> 1' 1 'feat(x): 好' '198.20.0.1'
run_case '127.0.0.1 / 0.0.0.0 -> 0'         0 'feat(x): 好' '监听 127.0.0.1 与 0.0.0.0'
run_case '10.0.0.1 / 192.168.1.1 -> 0'      0 'feat(x): 好' '内网 10.0.0.1 192.168.1.1'
run_case '172.16.0.1 / 172.31.255.1 -> 0'   0 'feat(x): 好' '172.16.0.1 172.31.255.1'
run_case '172.15.0.1 -> 1'                  1 'feat(x): 好' '172.15.0.1'
run_case '172.32.0.1 -> 1'                  1 'feat(x): 好' '172.32.0.1'
run_case '公共 DNS 全部放行 -> 0'           0 'feat(x): 好' '1.0.0.1 8.8.8.8 8.8.4.4 223.5.5.5 223.6.6.6 119.29.29.29'
run_case '文档示例段 -> 0'                  0 'feat(x): 好' '192.0.2.1 198.51.100.7 203.0.113.9'
run_case '放行地址与公网地址混写 -> 1'      1 'feat(x): 好' '1.1.1.1 和 11.22.33.44'
run_case '句末带句点的公网 IP -> 1'         1 'feat(x): 好' '服务器是 11.22.33.44.'
run_case '五段版本号不算 IP -> 0'           0 'chore(x): 好' '升级到 1.2.3.4.5'
run_case '段值超过 255 不算 IP -> 0'        0 'chore(x): 好' '版本 1.2.3.456'

echo "== 禁用词 =="
new_repo; commit_as tester tester@example.com 'feat(x): 好' '提到了 Foo 项目'
rc=0; PUBLIC_NAME_DENYLIST='foo' bash "$CHECK" base HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] && ok 'DENYLIST=foo 且正文含 Foo -> 1' || bad "DENYLIST=foo 且正文含 Foo（期望 1，实际 ${rc}）"

rc=0; PUBLIC_NAME_DENYLIST=$'bar\nfoo\n' bash "$CHECK" base HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] && ok '多行 denylist 命中其中一行 -> 1' || bad "多行 denylist（期望 1，实际 ${rc}）"

rc=0; PUBLIC_NAME_DENYLIST=$'bar\nbaz' bash "$CHECK" base HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && ok 'denylist 未命中 -> 0' || bad "denylist 未命中（期望 0，实际 ${rc}）"

new_repo; commit_as tester tester@example.com 'feat(x): 提到 Foo 的首行'
rc=0; PUBLIC_NAME_DENYLIST='foo' bash "$CHECK" base HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] && ok '首行命中 denylist -> 1' || bad "首行命中 denylist（期望 1，实际 ${rc}）"

new_repo; commit_as tester tester@example.com 'feat(x): 好' 'Foo'
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'denylist 未提供，跳过禁用词检查'; then
  ok 'denylist 为空 -> 打印跳过提示并返回 0'
else
  bad "denylist 为空（期望 0 且有跳过提示，实际 rc=${rc}）：$out"
fi

rc=0; out="$(PUBLIC_NAME_DENYLIST='' bash "$CHECK" base HEAD 2>&1)" || rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'denylist 未提供' && ok 'denylist 设为空串同样跳过' || bad "空串 denylist（rc=${rc}）：$out"

# denylist 为空时其余规则仍然生效
new_repo; commit_as tester tester@example.com '坏格式'
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
[ "$rc" = 1 ] && ok 'denylist 为空时格式规则仍生效 -> 1' || bad "denylist 为空时格式规则（期望 1，实际 ${rc}）"

echo "== 跳过与输出 =="
# merge 提交：首行不合规，但被 --no-merges 跳过；两条分支上的提交本身合规。
new_repo
git checkout -q -b side
commit_as tester tester@example.com 'feat(x): 侧枝'
git checkout -q main
commit_as tester tester@example.com 'feat(x): 主线'
git merge -q --no-ff -m 'Merge branch side into main' side
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
[ "$rc" = 0 ] && ok 'merge 提交（首行不合规）被跳过 -> 0' || bad "merge 提交（期望 0，实际 ${rc}）：$out"

new_repo; commit_as 'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com' 'Bump foo from 1 to 2'
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
[ "$rc" = 0 ] && ok '作者名含 [bot] 被跳过 -> 0' || bad "bot 作者名（期望 0，实际 ${rc}）：$out"

new_repo; commit_as 'someone' '49699333+dependabot[bot]@users.noreply.github.com' 'Bump foo from 1 to 2'
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
[ "$rc" = 0 ] && ok '仅邮箱含 [bot] 也被跳过 -> 0' || bad "bot 邮箱（期望 0，实际 ${rc}）：$out"

# 违规输出：逐条 "<短SHA> <原因>"，合规提交不输出
new_repo
commit_as tester tester@example.com 'feat(x): 好'
commit_as tester tester@example.com '修复：坏'
bad_sha="$(git rev-parse --short HEAD)"
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q "^${bad_sha} " \
   && [ "$(printf '%s\n' "$out" | grep -c "^[0-9a-f]\{7,\} ")" = 1 ]; then
  ok '违规逐条输出 "<短SHA> <原因>"，合规提交不输出'
else
  bad "违规输出格式（rc=${rc}）：$out"
fi

# 一条提交多个问题：每个问题各占一行
new_repo; commit_as tester tester@example.com '坏格式' '服务器 11.22.33.44'
rc=0; out="$(env -u PUBLIC_NAME_DENYLIST bash "$CHECK" base HEAD 2>&1)" || rc=$?
n="$(printf '%s\n' "$out" | grep -c "^[0-9a-f]\{7,\} ")"
[ "$rc" = 1 ] && [ "$n" = 2 ] && ok '同一提交的格式与 IPv4 问题各占一行' || bad "多问题输出（rc=${rc}，行数 ${n}）：$out"

echo "== 参数 =="
new_repo
rc=0; bash "$CHECK" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok '不带参数 -> 2' || bad "不带参数（期望 2，实际 ${rc}）"
rc=0; bash "$CHECK" base >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok '只带一个参数 -> 2' || bad "只带一个参数（期望 2，实际 ${rc}）"
rc=0; bash "$CHECK" base HEAD extra >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok '参数多于两个 -> 2' || bad "参数过多（期望 2，实际 ${rc}）"
rc=0; bash "$CHECK" no-such-ref HEAD >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && ok '不存在的 base 引用 -> 2（不能当作通过）' || bad "不存在的引用（期望 2，实际 ${rc}）"

echo
echo "通过 ${PASS}，失败 $FAIL"
[ "$FAIL" = 0 ]
