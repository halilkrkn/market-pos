# stop_isolated_test_hub.ps1
# Stops ONLY the isolated test Hub process tracked in hub.pid.
# Preserves market_master_test.db and NEVER touches MarketMmsSpike01 or port 8085.
[CmdletBinding()]
param(
    [string]$TestRoot = (Join-Path $env:LOCALAPPDATA "MarketMMS_Isolated_Test")
)

$ErrorActionPreference = "Stop"
$hubDir = Join-Path $TestRoot "hub"
$pidFile = Join-Path $hubDir "hub.pid"

if (-not (Test-Path $pidFile)) {
    Write-Output "Izole Test Hub PID dosyasi bulunamadi ($pidFile); calisan izole surec yok."
    exit 0
}

$rawPid = (Get-Content -Path $pidFile -Raw).Trim()
$pidInt = 0
if (-not [int]::TryParse($rawPid, [ref]$pidInt) -or $pidInt -le 0) {
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
    Write-Output "Gecersiz PID dosyasi temizlendi."
    exit 0
}

$proc = Get-Process -Id $pidInt -ErrorAction SilentlyContinue
if ($null -eq $proc) {
    Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue
    Write-Output "PID $pidInt artik calismiyor; hub.pid temizlendi."
    exit 0
}

$exePath = ""
try { $exePath = $proc.MainModule.FileName } catch {}
$expectedPrefix = (Join-Path $hubDir "bin").ToLowerInvariant()
if (-not [string]::IsNullOrWhiteSpace($exePath) -and -not $exePath.ToLowerInvariant().StartsWith($expectedPrefix)) {
    throw "Guvenlik engeli: PID $pidInt izole test dizinine ait degil ($exePath)."
}

Stop-Process -Id $pidInt -Force
$proc.WaitForExit(5000) | Out-Null
Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue

$dbPath = Join-Path $hubDir "data\market_master_test.db"
$dbExists = Test-Path $dbPath
Write-Output "Izole Test Hub durduruldu (PID: $pidInt). Test DB korundu: $dbExists ($dbPath)"
