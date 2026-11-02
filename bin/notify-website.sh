#!/usr/bin/env bash
# notify-website.sh <tag> — 正式发版成功后，通知官网仓库重建。
#
# 向官网仓库发一个 repository_dispatch（event_type=app-released），官网的
# release-sync 工作流收到后刷新 release 快照并触发重新部署。tag 放在
# client_payload 里，官网不读它，但留在日志里便于排查。
#
# token 从环境变量 WEB_DISPATCH_TOKEN 读取（仓库 secret，对官网仓库有写权限的 PAT）。
# 任何一步失败都输出 ::error 并以 1 退出，让这次发版 run 失败而不是悄悄漏掉。
set -euo pipefail

TAG="${1:-}"
if [ -z "${TAG}" ]; then
  echo "用法：bin/notify-website.sh <tag>" >&2
  echo "::error::缺少 tag 参数，官网不会自动更新"
  exit 1
fi

if [ -z "${WEB_DISPATCH_TOKEN:-}" ]; then
  echo "::error::WEB_DISPATCH_TOKEN 未配置，官网不会自动更新"
  exit 1
fi

if ! GH_TOKEN="${WEB_DISPATCH_TOKEN}" gh api repos/luuuuke88/clashmiaoweb/dispatches \
  -f event_type=app-released -F "client_payload[tag]=${TAG}"; then
  echo "::error::官网 dispatch 失败"
  exit 1
fi

echo "已通知官网重建（${TAG}）"
