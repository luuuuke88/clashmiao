#!/usr/bin/env bash
# check-release-gates.sh — 发版闸门的静态检查：内核验证（kernel-verify.yml）必须是 Android 构建与发布的必需依赖。
#
#   tools/kernel/check-release-gates.sh          # 检查 .github/workflows/release.yml 与 ci.yml
#
# 检查内容（任何一条不满足都失败）：
#   1. release.yml 与 ci.yml 里有 kernel 作业，且是复用 kernel-verify.yml 的 reusable workflow 调用；
#   2. release.yml 的 android 作业 needs 含 kernel；
#   3. release.yml 的 publish 作业 needs 含 kernel，且它的 if 明确要求 needs.kernel.result == 'success'
#      （publish 带 always()，光有 needs 会在 kernel 失败时照样发布）；
#   4. ci.yml 的 build-android 作业 needs 含 kernel。
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT"
ruby -Ku -ryaml -e '
  def load(f) YAML.safe_load(File.read(f), aliases: true) end
  def needs(job) Array(job["needs"]) end
  bad = []
  rel = load(".github/workflows/release.yml")["jobs"]
  ci  = load(".github/workflows/ci.yml")["jobs"]
  { "release.yml" => rel, "ci.yml" => ci }.each do |name, jobs|
    k = jobs["kernel"]
    if k.nil? || k["uses"].to_s !~ /kernel-verify\.yml\z/
      bad << "#{name}: 缺少复用 kernel-verify.yml 的 kernel 作业"
    end
  end
  bad << "release.yml: android 作业没有 needs kernel" unless needs(rel["android"]).include?("kernel")
  pub = rel["publish"]
  bad << "release.yml: publish 作业没有 needs kernel" unless needs(pub).include?("kernel")
  bad << "release.yml: publish 的 if 没有要求 needs.kernel.result == success（always() 会绕过 needs）" unless pub["if"].to_s.include?("needs.kernel.result") && pub["if"].to_s.include?("success")
  bad << "ci.yml: build-android 作业没有 needs kernel" unless needs(ci["build-android"]).include?("kernel")
  if bad.empty?
    puts "check-release-gates: 通过"
  else
    bad.each { |b| warn b }
    exit 1
  end
'
