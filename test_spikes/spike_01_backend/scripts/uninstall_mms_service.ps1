# uninstall_mms_service.ps1 — Market MMS Windows Servis Durdurma ve Kaldirma Betigi (v2.0)
[CmdletBinding()]
param(
    [string]$ServiceName = "MarketMMSService",
    [string]$TargetBaseDir = "$env:ProgramData\MarketMMS"
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS Backend Engine — Windows Servis Kaldirma" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 0. Yonetici Haklari Denetimi
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    throw "HATA: Bu betik yerel Yonetici (Administrator) yetkisiyle calistirilmalidir!"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$spikeRoot = (Resolve-Path "$scriptDir\..").Path

# Olası wrapper konumları
$deployedWrapperExe = Join-Path $TargetBaseDir "bin\MarketMMSService.exe"
$localWrapperExe = Join-Path $spikeRoot "service_wrapper\MarketMMSService.exe"

$activeWrapperExe = $null
if (Test-Path $deployedWrapperExe) {
    $activeWrapperExe = $deployedWrapperExe
} elseif (Test-Path $localWrapperExe) {
    $activeWrapperExe = $localWrapperExe
}

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (!$existingService) {
    Write-Host "[INFO] Servis '$ServiceName' sistemde kurulu degil." -ForegroundColor Yellow
    return
}

# 1. Servisi Durdur
if ($existingService.Status -eq "Running") {
    Write-Host "[1/2] Servis durduruluyor: $ServiceName ..." -ForegroundColor Yellow
    if ($activeWrapperExe) {
        & "$activeWrapperExe" stop
    } else {
        sc.exe stop $ServiceName
    }
    Start-Sleep -Seconds 3
}

# 2. Servisi Kaldir
Write-Host "[2/2] Servis SCM kaydi siliniyor..." -ForegroundColor Yellow
if ($activeWrapperExe) {
    $uninstallRes = & "$activeWrapperExe" uninstall 2>&1
    Write-Host "  -> $uninstallRes" -ForegroundColor Green
} else {
    sc.exe delete $ServiceName
}
Start-Sleep -Seconds 2

# 3. Dogrulama
$checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($checkService) {
    throw "HATA: Servis kaldirilamadi! Durum: $($checkService.Status)"
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Market MMS Servisi Basariyla Kaldirildi!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
