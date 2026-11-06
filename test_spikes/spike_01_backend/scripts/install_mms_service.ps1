# install_mms_service.ps1 - Market MMS Windows Servis Kurulum ve Baslatma Betigi (v2.0)
[CmdletBinding()]
param(
    [string]$ServiceName = "MarketMMSService",
    [string]$TargetBaseDir = "$env:ProgramData\MarketMMS"
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS Backend Engine - Windows Servis Kurulumu" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 0. Yonetici Haklari Denetimi
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    throw "HATA: Bu betik yerel Yonetici (Administrator) yetkisiyle calistirilmalidir!"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = $PSScriptRoot }
$spikeRoot = (Resolve-Path "$scriptDir\..").Path
$serviceWrapperDir = Join-Path $spikeRoot "service_wrapper"
$wrapperExeSrc = Join-Path $serviceWrapperDir "MarketMMSService.exe"
$wrapperXmlSrc = Join-Path $serviceWrapperDir "MarketMMSService.xml"
$backendExeSrc = Join-Path $spikeRoot "build\mms_backend.exe"

# 1. On Gereksinim Denetimi
if (!(Test-Path $wrapperExeSrc)) {
    throw "HATA: WinSW wrapper dosyasi bulunamadi: $wrapperExeSrc"
}
if (!(Test-Path $wrapperXmlSrc)) {
    throw "HATA: WinSW yapilandirma XML dosyasi bulunamadi: $wrapperXmlSrc"
}

# 2. Dart AOT Derleme (Eksikse)
if (!(Test-Path $backendExeSrc)) {
    Write-Host "[INFO] mms_backend.exe bulunamadi, AOT derleme baslatiliyor..." -ForegroundColor Yellow
    & "$scriptDir\build_aot.ps1"
}

# 3. Dizin Yapisi ve Temel NTFS ACL Yapilandirmasi
Write-Host "[1/5] Hedef dizin ve NTFS ACL yapilandiriliyor: $TargetBaseDir ..." -ForegroundColor Yellow
& "$scriptDir\setup_service_acls.ps1" -BaseDir $TargetBaseDir -ServiceName $ServiceName

# 4. Dosyalarin Hedef ProgramData Dizinine Dagitimi
Write-Host "[2/5] Servis ikilileri ProgramData dizinine kopyalaniyor..." -ForegroundColor Yellow
$targetBinDir = Join-Path $TargetBaseDir "bin"
if (!(Test-Path $targetBinDir)) { New-Item -ItemType Directory -Path $targetBinDir -Force | Out-Null }

$deployedWrapperExe = Join-Path $targetBinDir "MarketMMSService.exe"
$deployedWrapperXml = Join-Path $targetBinDir "MarketMMSService.xml"
$deployedBackendExe = Join-Path $targetBinDir "mms_backend.exe"

Copy-Item -Path $wrapperExeSrc -Destination $deployedWrapperExe -Force
Copy-Item -Path $wrapperXmlSrc -Destination $deployedWrapperXml -Force
Copy-Item -Path $backendExeSrc -Destination $deployedBackendExe -Force

# 5. Mevcut Servis Varsa Once Durdur ve Kaldir
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "[INFO] Servis zaten kurulu. Once durduruluyor ve kaldiriliyor..." -ForegroundColor Yellow
    if ($existingService.Status -eq "Running") {
        & "$deployedWrapperExe" stop
        Start-Sleep -Seconds 2
    }
    & "$deployedWrapperExe" uninstall
    Start-Sleep -Seconds 2
}

# 6. WinSW ile Servisi Kur
Write-Host "[3/5] WinSW v2.12.0 ile servis kuruluyor: $ServiceName ..." -ForegroundColor Yellow
$installRes = & "$deployedWrapperExe" install 2>&1
Write-Host "  -> $installRes" -ForegroundColor Green

# 7. Service SID Tanimlama (sc.exe sidtype)
Write-Host "[4/5] Windows SCM Service SID yapilandiriliyor (UNRESTRICTED)..." -ForegroundColor Yellow
$scOutput = sc.exe sidtype $ServiceName unrestricted 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "HATA: Service SID atamasi basarisiz oldu: $scOutput"
}
Write-Host "  -> Service SID UNRESTRICTED olarak atandi." -ForegroundColor Green

# Dogrulama (sc.exe qsidtype)
$qsidOutput = sc.exe qsidtype $ServiceName 2>&1
Write-Host "  -> SCM Yapilandirma Durumu: $qsidOutput"

# 8. Servisi Baslat
Write-Host "[5/5] Servis baslatiliyor: $ServiceName ..." -ForegroundColor Yellow
$startRes = & "$deployedWrapperExe" start 2>&1
Write-Host "  -> $startRes" -ForegroundColor Green
Start-Sleep -Seconds 3

# 9. Servis Canlilik ve Durum Teyidi
$srv = Get-Service -Name $ServiceName -ErrorAction Stop
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Market MMS Windows Servisi Kuruldu ve Baslatildi!" -ForegroundColor Green
Write-Host "  - Servis Adi: $($srv.Name)"
Write-Host "  - Gorunen Ad: $($srv.DisplayName)"
Write-Host "  - Durum: $($srv.Status)"
Write-Host "  - Baslangic Turu: $($srv.StartType)"
Write-Host "====================================================" -ForegroundColor Cyan
