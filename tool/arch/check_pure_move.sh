#!/usr/bin/env bash
# check_pure_move.sh — 校验当前工作区相对 <base> 的改动是"纯移动"。
#
# 用法：tool/arch/check_pure_move.sh <base>      （在仓库内任意目录执行）
#
# "纯移动"的定义：
#   - 文件只做重命名（git 识别为 R），内容里唯一允许变化的是
#       import 'package:clashmiao/...'  /  export 'package:clashmiao/...'
#     这样的行（move.dart 改写的就是这类行）；
#   - 原地修改的文件同样只允许改这类行；
#   - 不允许新增、删除、改权限、二进制文件变动（哪怕新文件只有 import 也不行，
#     因为新增文件不是重命名）。
#
# 实现：`git diff -M --find-renames=<阈值> -U0 <base>`，逐行检查 +/- 行。
#   重命名阈值不能设成 100%（-M100% 之后的 --find-renames 还会把阈值改回默认 50%）：
#   被改写 import 的文件相似度必然低于 100%，小文件甚至低于 50%，会被拆成
#   "删除 + 新增"而误报。所以阈值取最低的 1%，并用 -l0 取消重命名数量上限。
#   阈值低只会让更多改动被识别为重命名；被识别为重命名的文件里任何非 import 行的
#   变化仍然会被逐行检查拦下，所以不影响判定。
#   已知局限：整个文件内容全是 import/export 行、且每一行都被改写的文件，与旧文件
#   没有任何相同内容，git 无法配对，会被判违规（宁可误报，不会漏报），需要人工确认。
#
# 比较对象是 <base> 与**工作区**（含已暂存和未暂存的改动），所以既可以在提交前跑，
# 也可以在提交后用 merge-base 跑。未跟踪的新文件不会出现在 diff 里，这里单独检查
# 并判为违规。
#
# 本脚本和 move.dart 没有任何豁免：它们若已在 <base> 里，不在 diff 里就不会被检查；
# 若本次改动里修改了它们，会像其他文件一样被检查。
#
# 退出码：0 纯移动；1 有违规（逐条打印）；2 参数或 git 错误。
# 兼容 bash 3.2（macOS 自带）与 Linux CI。
set -u

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "用法：$0 <base>" >&2
  exit 2
fi
base="$1"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "错误：当前目录不在 git 仓库内。" >&2
  exit 2
fi
if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "错误：找不到 base 提交：${base}" >&2
  exit 2
fi

# 在仓库根目录运行，保证 ls-files / diff 看到的是整个仓库。
cd "$(git rev-parse --show-toplevel)" || exit 2

diff_out="$(git -c core.quotepath=false diff --no-color --no-ext-diff \
  -M --find-renames=1% -l0 -U0 "${base}")" || {
  echo "错误：git diff 失败。" >&2
  exit 2
}

status=0

# 逐行状态机：
#   - 遇到 "diff --git" 进入文件头，直到第一个 "@@" 之前都是头部行；
#   - 头部里只放行 index / --- / +++ / similarity / rename / dissimilarity；
#     new file / deleted file / mode 变化 / 二进制 一律违规；
#   - "@@" 之后的 +/- 行是内容行，必须匹配 ^[+-](import|export) 'package:clashmiao/ ；
#     另外放行条件 import 的续行 ^[+-]\s+if \(dart.library.<x>\) 'package:clashmiao/ 。
violations="$(printf '%s\n' "${diff_out}" | awk '
  /^diff --git / { file = $0; sub(/^diff --git a\//, "", file); inhdr = 1; next }
  inhdr && /^@@/ { inhdr = 0; next }
  inhdr {
    if ($0 ~ /^(index |--- |\+\+\+ |similarity index |rename from |rename to )/) next
    if ($0 ~ /^(new file mode|deleted file mode|old mode|new mode|copy from|copy to|dissimilarity index)/ ||
        $0 ~ /^Binary files / || $0 ~ /^GIT binary patch/) {
      printf "%s: 不是纯重命名（%s）\n", file, $0
    }
    next
  }
  /^[+-]/ {
    if ($0 !~ /^[+-](import|export) \047package:clashmiao\// &&
        $0 !~ /^[+-][ \t]+if \(dart\.library\.[A-Za-z_]+\) \047package:clashmiao\//) {
      printf "%s: %s\n", file, $0
    }
  }
')"

if [ -n "${violations}" ]; then
  echo "纯移动检查失败，下列改动不是重命名或 package import/export 改写：" >&2
  printf '%s\n' "${violations}" >&2
  status=1
fi

untracked="$(git ls-files --others --exclude-standard)"
if [ -n "${untracked}" ]; then
  echo "纯移动检查失败，存在未跟踪的新文件（新增文件不是重命名）：" >&2
  printf '%s\n' "${untracked}" >&2
  status=1
fi

if [ "${status}" -eq 0 ]; then
  echo "纯移动检查通过：相对 ${base} 只有重命名与 package import/export 改写。"
fi
exit "${status}"
