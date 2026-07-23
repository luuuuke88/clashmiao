param(
  [string[]] $FlutterArgs = @('build', 'windows', '--release', '--no-tree-shake-icons')
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows_portable_env.ps1')

$FlutterBat = $env:FLUTTER_BIN
if (-not $FlutterBat) {
  $LocalFlutter = 'C:\code\tools\flutter\bin\flutter.bat'
  if (Test-Path -LiteralPath $LocalFlutter) {
    $FlutterBat = $LocalFlutter
  } else {
    $FlutterBat = 'flutter'
  }
}

Set-Location $RepoRoot
& $FlutterBat @FlutterArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
