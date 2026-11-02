$ErrorActionPreference = 'Stop'

function Resolve-FirstExistingPath {
  param(
    [string] $EnvValue,
    [string[]] $Fallbacks,
    [string] $Name
  )

  if ($EnvValue -and (Test-Path -LiteralPath $EnvValue)) {
    return (Resolve-Path -LiteralPath $EnvValue).Path
  }

  foreach ($Fallback in $Fallbacks) {
    if ($Fallback -and (Test-Path -LiteralPath $Fallback)) {
      return (Resolve-Path -LiteralPath $Fallback).Path
    }
  }

  throw "$Name not found. Set the matching environment variable before running this script."
}

$MsvcRoot = Resolve-FirstExistingPath `
  -EnvValue $env:FLUTTER_PORTABLE_MSVC_ROOT `
  -Fallbacks @('C:\code\portable_msvc\Contents\VC\Tools\MSVC\14.40.33807') `
  -Name 'MSVC toolchain'

$SdkRoot = Resolve-FirstExistingPath `
  -EnvValue $env:FLUTTER_PORTABLE_WINSDK_ROOT `
  -Fallbacks @('C:\code\portable_win_sdk\Windows Kits\10') `
  -Name 'Windows SDK'

$CmakeRoot = Resolve-FirstExistingPath `
  -EnvValue $env:FLUTTER_PORTABLE_VS_CMAKE_ROOT `
  -Fallbacks @('C:\code\portable_vs_cmake\Contents\Common7\IDE\CommonExtensions\Microsoft\CMake') `
  -Name 'Visual Studio CMake tools'

$SdkVersion = $env:FLUTTER_PORTABLE_WINSDK_VERSION
if (-not $SdkVersion) {
  $SdkVersion = Get-ChildItem -Directory -LiteralPath (Join-Path $SdkRoot 'Include') |
    Sort-Object Name -Descending |
    Select-Object -First 1 -ExpandProperty Name
}

$env:FLUTTER_PORTABLE_MSVC = $MsvcRoot
$env:FLUTTER_PORTABLE_CMAKE = Join-Path $CmakeRoot 'CMake\bin\cmake.exe'
$env:PATH = @(
  (Join-Path $MsvcRoot 'bin\Hostx64\x64')
  (Join-Path $SdkRoot "bin\$SdkVersion\x64")
  (Join-Path $CmakeRoot 'CMake\bin')
  (Join-Path $CmakeRoot 'Ninja')
  $env:PATH
) -join ';'
$env:INCLUDE = @(
  (Join-Path $MsvcRoot 'include')
  (Join-Path $MsvcRoot 'atlmfc\include')
  (Join-Path $SdkRoot "Include\$SdkVersion\um")
  (Join-Path $SdkRoot "Include\$SdkVersion\shared")
  (Join-Path $SdkRoot "Include\$SdkVersion\ucrt")
  (Join-Path $SdkRoot "Include\$SdkVersion\winrt")
  (Join-Path $SdkRoot "Include\$SdkVersion\cppwinrt")
) -join ';'
$env:LIB = @(
  (Join-Path $MsvcRoot 'lib\x64')
  (Join-Path $MsvcRoot 'atlmfc\lib\x64')
  (Join-Path $SdkRoot "Lib\$SdkVersion\um\x64")
  (Join-Path $SdkRoot "Lib\$SdkVersion\ucrt\x64")
) -join ';'
$env:CC = 'cl.exe'
$env:CXX = 'cl.exe'
$env:RC = 'rc.exe'
