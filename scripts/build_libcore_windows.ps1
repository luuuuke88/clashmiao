$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CoreSource = $env:CLASHMIAO_LIBCORE_SOURCE
if (-not $CoreSource) {
  $LocalCoreSource = 'C:/code/baseproxy/libcore'
  if (Test-Path -LiteralPath $LocalCoreSource) {
    $CoreSource = $LocalCoreSource
  } else {
    throw 'libcore source not found. Set CLASHMIAO_LIBCORE_SOURCE to the libcore checkout path.'
  }
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
