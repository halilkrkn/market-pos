# start_isolated_windows_client.ps1
# Launches the Windows Release Client with LOCALAPPDATA redirected to
# %LOCALAPPDATA%\MarketMMS_Isolated_Test\client_win so real
# %LOCALAPPDATA%\MarketMMS\client_local.db is NEVER touched.
[CmdletBinding()]
param(
    [string]$TestRoot = (Join-Path $env:LOCALAPPDATA "MarketMMS_Isolated_Test"),
    [string]$ClientExePath = "",
    [int]$SmokeCheckSeconds = 0
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ([string]::IsNullOrWhiteSpace($ClientExePath)) {
    $trayClient = Join-Path $repoRoot "dist\windows_release_v1_0_0_tray\client\market_pos.exe"
    $relClient = Join-Path $repoRoot "dist\windows_release\client\market_pos.exe"
    if (Test-Path $trayClient) {
        $ClientExePath = $trayClient
    } elseif (Test-Path $relClient) {
        $ClientExePath = $relClient
    } else {
        throw "Derlenmis market_pos.exe bulunamadi."
    }
}

if (-not (Test-Path $ClientExePath)) {
    throw "Client exe bulunamadi: $ClientExePath"
}

$isolatedLocalAppData = Join-Path $TestRoot "client_win"
$logsDir = Join-Path $isolatedLocalAppData "logs"
foreach ($d in @($isolatedLocalAppData, $logsDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$stdoutLog = Join-Path $logsDir "client_stdout.log"
$stderrLog = Join-Path $logsDir "client_stderr.log"
$pidFile = Join-Path $isolatedLocalAppData "client.pid"
$isolatedDbPath = Join-Path $isolatedLocalAppData "MarketMMS\client_local.db"

$prevLocalAppData = [Environment]::GetEnvironmentVariable("LOCALAPPDATA", "Process")
[Environment]::SetEnvironmentVariable("LOCALAPPDATA", $isolatedLocalAppData, "Process")
try {
    $proc = Start-Process -FilePath $ClientExePath `
        -WorkingDirectory (Split-Path -Parent $ClientExePath) `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru
} finally {
    [Environment]::SetEnvironmentVariable("LOCALAPPDATA", $prevLocalAppData, "Process")
}

if ($null -eq $proc) {
    throw "Izole Windows Client baslatilamadi."
}
Set-Content -Path $pidFile -Value ([string]$proc.Id) -Encoding ASCII

if ($SmokeCheckSeconds -gt 0) {
    Start-Sleep -Seconds $SmokeCheckSeconds
    $proc.Refresh()
    $aliveBeforeClose = (-not $proc.HasExited)
    $hwndBeforeClose = [int64]$proc.MainWindowHandle
    $dbExists = Test-Path $isolatedDbPath
    $dbSize = if ($dbExists) { (Get-Item $isolatedDbPath).Length } else { 0 }

    $aliveAfterWmClose = $false
    $hwndAfterWmClose = -1
    if ($aliveBeforeClose) {
        $null = $proc.CloseMainWindow()
        Start-Sleep -Seconds 2
        $proc.Refresh()
        $aliveAfterWmClose = (-not $proc.HasExited)
        $hwndAfterWmClose = [int64]$proc.MainWindowHandle
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force
            $proc.WaitForExit(3000) | Out-Null
        }
    }

    $smokeResult = [ordered]@{
        status = if ($aliveBeforeClose -and $dbExists) { "SMOKE_PASS" } else { "SMOKE_FAIL" }
        pid = $proc.Id
        exe = $ClientExePath
        isolated_local_appdata = $isolatedLocalAppData
        isolated_db_path = $isolatedDbPath
        isolated_db_exists = $dbExists
        isolated_db_bytes = $dbSize
        alive_before_close = $aliveBeforeClose
        hwnd_before_close = $hwndBeforeClose
        alive_after_wm_close = $aliveAfterWmClose
        hwnd_after_wm_close = $hwndAfterWmClose
    }
    Write-Output ($smokeResult | ConvertTo-Json -Compress)
    if (-not $aliveBeforeClose -or -not $dbExists) {
        exit 1
    }
    exit 0
}

$result = [ordered]@{
    status = "LAUNCHED"
    pid = $proc.Id
    exe = $ClientExePath
    isolated_local_appdata = $isolatedLocalAppData
    isolated_db_path = $isolatedDbPath
}
Write-Output ($result | ConvertTo-Json -Compress)
