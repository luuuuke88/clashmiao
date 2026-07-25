#!/usr/bin/env bash
# regen-i18n.sh — 重新生成翻译代码，并**顺手格式化**。
#
#   bash bin/regen-i18n.sh
#
# ## 为什么要有这个脚本，而不是直接跑 `dart run slang`
#
# slang 生成出来的 `lib/core/localization/gen/translations.g.dart` 不满足
# `dart format` 的规范，而 CI 的 analyze job 跑的是
# `dart format --set-exit-if-changed lib/ test/ integration_test/`——直接
# 一句 `dart run slang` 之后提交，CI 必红。
#
# 关键点：`analysis_options.yaml` 里对 `lib/core/localization/gen/**` 的 exclude
# 只对 **analyzer** 生效，`dart format` 完全不看它。所以生成物必须以格式化后的
# 形态提交。
#
# 实际踩过：加了一个翻译 key、跑 slang、只格式化了自己改的那几个文件，CI 的
# analyze 就以 `Formatted 202 files (1 changed)` 失败——而报出来的那个"1 changed"
# 是生成物，跟本次改动的代码毫无关系，很容易看半天不知道错在哪。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '\033[0;32m[i18n]\033[0m %s\n' "$*"; }

log "生成翻译代码…"
dart run slang

log "格式化生成物…"
dart format lib/core/localization/gen/

log "校验：CI 的那条命令现在应该是干净的"
if ! dart format --set-exit-if-changed --output=none lib/ test/ integration_test/ >/dev/null; then
  printf '\033[0;31m[i18n]\033[0m 还有文件没格式化，跑一下 dart format lib/ test/ integration_test/\n' >&2
  exit 1
fi

log "完成。别忘了新增 key 要补齐全部语言——门禁见 test/core/localization/translations_completeness_test.dart"
