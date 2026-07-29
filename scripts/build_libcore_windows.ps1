$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
# 核心源码路径必须显式给出。此前这里有一个写死的本机路径作为兜底——在别人机器
# 上它永远不存在，只会让报错晚一步出现，而且把某台机器的目录结构写进了仓库。
$CoreSource = $env:CLASHMIAO_LIBCORE_SOURCE
if (-not $CoreSource) {
  throw 'Set CLASHMIAO_LIBCORE_SOURCE to the libcore checkout path.'
}
if (-not (Test-Path -LiteralPath $CoreSource)) {
  throw "CLASHMIAO_LIBCORE_SOURCE points to a path that does not exist: $CoreSource"
}

$OutputDir = ($RepoRoot -replace '\\', '/') + '/windows/libs'
$BuildScript = ($RepoRoot -replace '\\', '/') + '/scripts/build_libcore_windows_docker.sh'

docker run --rm `
  -v "${CoreSource}:/src" `
  -v "${OutputDir}:/out" `
  -v "${BuildScript}:/build_libcore_windows_docker.sh" `
  -w /src `
  golang:1.22-bookworm `
  bash /build_libcore_windows_docker.sh
