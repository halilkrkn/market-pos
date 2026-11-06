# build_aot.ps1 — Market MMS Dart AOT Derleme Betigi
[CmdletBinding()]
param(
    [string]$OutputDir,
    [string]$TargetExe = "mms_backend.exe"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = $PSScriptRoot
}
$spikeRoot = (Resolve-Path "$scriptDir\..").Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = "$spikeRoot\build"
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS Backend Engine -- Dart AOT Derleme" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Dart SDK Denetimi
try {
    $dartVersion = dart --version 2>&1
    Write-Host "[OK] Dart SDK bulundu: $dartVersion" -ForegroundColor Green
} catch {
    throw "HATA: Dart SDK sistem PATH ortaminda bulunamadi!"
}

# 2. Cikti Dizini Hazirligi
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Host "[INFO] Cikti dizini olusturuldu: $OutputDir"
}

$outputExePath = Join-Path $OutputDir $TargetExe
$serverDartPath = Join-Path $spikeRoot "bin\server.dart"

if (!(Test-Path $serverDartPath)) {
    throw "HATA: bin\server.dart dosyasi bulunamadi: $serverDartPath"
}

Write-Host "[BUILD] Dart AOT derleniyor: $serverDartPath -> $outputExePath ..." -ForegroundColor Yellow
$sw = [System.Diagnostics.Stopwatch]::StartNew()

Push-Location $spikeRoot
try {
    $compileOutput = dart compile exe bin\server.dart -o $outputExePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Dart AOT derleme basarisiz oldu (Exit code: $LASTEXITCODE)`n$compileOutput"
    }
} finally {
    Pop-Location
}
$sw.Stop()

# 3. Ikili Dogrulamasi
if (!(Test-Path $outputExePath)) {
    throw "HATA: Beklenen derleme ciktisi uretilemedi: $outputExePath"
}

$fileItem = Get-Item $outputExePath
$fileHash = Get-FileHash -Path $outputExePath -Algorithm SHA256
$sizeMb = [math]::Round($fileItem.Length / 1MB, 2)
$hashStr = $fileHash.Hash
$elapsedMs = $sw.ElapsedMilliseconds

Write-Host "[SUCCESS] Dart AOT Basariyla Derlendi!" -ForegroundColor Green
Write-Host ("  Path: " + $fileItem.FullName)
Write-Host ("  Size: " + $sizeMb + " MB (" + $fileItem.Length + " bytes)")
Write-Host ("  SHA-256: " + $hashStr)
Write-Host ("  Time: " + $elapsedMs + " ms")
Write-Host "====================================================" -ForegroundColor Cyan
