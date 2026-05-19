# Windows 桌面 smoke（PowerShell 版）：启动 debug GUI app（DevBoot 自动加订阅 + 连接）
# → 等 mixed inbound 监听 → curl --proxy 拿出口 IP → 对比直连 baseline。

$ErrorActionPreference = 'Stop'
$Port = 2080
$Target = 'api.ipify.org'
$WaitTimeout = if ($env:WAIT_TIMEOUT) { [int]$env:WAIT_TIMEOUT } else { 60 }
$SettleAfterListen = if ($env:SETTLE_AFTER_LISTEN) { [int]$env:SETTLE_AFTER_LISTEN } else { 8 }

Push-Location (Split-Path -Parent $PSScriptRoot)

function Log($msg) { Write-Host "[smoke] $msg" }

# ============ 0. 前置 ============
if (-not $env:CLASHMIAO_TEST_SUB_URL) {
  $homeDir = $env:USERPROFILE
  $urlFile = Join-Path $homeDir '.clashmiao_dev_subscription_url'
  if (-not (Test-Path $urlFile)) {
    Write-Error "需要 CLASHMIAO_TEST_SUB_URL env 或 $urlFile"
    exit 2
  }
}

# ============ 1. baseline ============
Log "baseline IP (direct)"
$baseline = ''
try {
  $baseline = (Invoke-WebRequest -Uri "https://$Target" -UseBasicParsing -TimeoutSec 15).Content.Trim()
} catch {
  Write-Error "baseline 直连失败: $_"
  exit 3
}
Log "  baseline = $baseline"

# ============ 2. 启动 app ============
$appExe = 'build\windows\x64\runner\Debug\clashmiao.exe'
if (-not (Test-Path $appExe)) {
  $appExe = 'build\windows\x64\runner\Release\clashmiao.exe'
}
if (-not (Test-Path $appExe)) {
  Write-Error "app exe not found at build\windows\x64\runner\{Debug,Release}\clashmiao.exe"
  exit 4
}

Log "launching $appExe"
$stdoutLog = Join-Path $env:RUNNER_TEMP "clashmiao-stdout.log"
if (-not $env:RUNNER_TEMP) { $stdoutLog = Join-Path $env:TEMP "clashmiao-stdout.log" }
$stderrLog = "$stdoutLog.err"
$proc = Start-Process -FilePath $appExe -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $stdoutLog `
  -RedirectStandardError $stderrLog -ErrorAction SilentlyContinue
if (-not $proc) {
  # fallback: no log redirection
  $proc = Start-Process -FilePath $appExe -PassThru -WindowStyle Hidden
}
Log "PID = $($proc.Id)  stdoutLog=$stdoutLog"

try {
  # ============ 3. wait mixed inbound ============
  Log "wait for 127.0.0.1:$Port (timeout=${WaitTimeout}s)"
  $listening = $false
  for ($i = 1; $i -le $WaitTimeout; $i++) {
    try {
      $c = New-Object System.Net.Sockets.TcpClient
      $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
      $ok = $iar.AsyncWaitHandle.WaitOne(1000, $false)
      if ($ok -and $c.Connected) { $listening = $true; $c.Close(); break }
      $c.Close()
    } catch { }
    Start-Sleep -Seconds 1
  }
  if (-not $listening) {
    Write-Host "FAIL: 端口 $Port 没监听"
    if (Test-Path $stdoutLog) {
      Write-Host "--- stdout tail (last 80 lines) ---"
      Get-Content $stdoutLog -Tail 80
    }
    if (Test-Path $stderrLog) {
      Write-Host "--- stderr tail (last 40 lines) ---"
      Get-Content $stderrLog -Tail 40
    }
    exit 6
  }
  Log "  listening"
  if (Test-Path $stdoutLog) {
    Write-Host "--- stdout tail (last 20) ---"
    Get-Content $stdoutLog -Tail 20
  }

  Log "settle ${SettleAfterListen}s for outbound url-test"
  Start-Sleep -Seconds $SettleAfterListen

  # ============ 4. proxied IP ============
  Log "proxied IP via http://127.0.0.1:$Port"
  $proxied = ''
  try {
    $proxy = New-Object System.Net.WebProxy("http://127.0.0.1:$Port")
    $req = [System.Net.WebRequest]::Create("https://$Target")
    $req.Proxy = $proxy
    $req.Timeout = 30000
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $proxied = $reader.ReadToEnd().Trim()
    $reader.Close(); $resp.Close()
  } catch {
    Write-Host "FAIL: 走 proxy 请求失败: $_"
    exit 7
  }
  Log "  proxied = $proxied"

  # ============ 5. assertions ============
  if (-not ($proxied -match '^\d+\.\d+\.\d+\.\d+$')) {
    Write-Host "FAIL: proxied 不是 IPv4: $proxied"; exit 8
  }
  if ($proxied -eq $baseline) {
    Write-Host "FAIL: 出口 IP 没变: $baseline -> $proxied"; exit 9
  }

  Write-Host ""
  Write-Host "✓ Windows smoke OK: $baseline -> $proxied"
} finally {
  Log "cleanup"
  try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
