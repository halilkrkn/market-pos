param(
    [string]$OutputDir = "dist\android_release",
    [string]$Version = "1.0.0",
    [switch]$BuildAppBundle,
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " MARKET MMS - Android Release Paketleme" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    if (-not $SkipFlutterBuild) {
        if ($BuildAppBundle) {
            Write-Host "[1/3] Android AppBundle (--release) derleniyor..." -ForegroundColor Yellow
            & flutter build appbundle --release
        } else {
            Write-Host "[1/3] Android APK (--release) derleniyor..." -ForegroundColor Yellow
            & flutter build apk --release
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Android Release derlemesi başarısız oldu ($LASTEXITCODE)."
        }
    } else {
        Write-Host "[1/3] Android derlemesi atlandı (-SkipFlutterBuild)." -ForegroundColor Gray
    }

    $artifactSource = if ($BuildAppBundle) {
        Join-Path $repoRoot "build\app\outputs\bundle\release\app-release.aab"
    } else {
        Join-Path $repoRoot "build\app\outputs\flutter-apk\app-release.apk"
    }
    if (-not (Test-Path $artifactSource)) {
        throw "Derlenmiş Android paketi bulunamadı: $artifactSource"
    }

    $targetDir = Join-Path $repoRoot $OutputDir
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    $ext = [System.IO.Path]::GetExtension($artifactSource)
    $destFile = Join-Path $targetDir "market_mms_v$Version$ext"
    Copy-Item -Force $artifactSource $destFile

    Write-Host "[2/3] SHA-256 checksum hesaplanıyor..." -ForegroundColor Yellow
    $hash = (Get-FileHash -Path $destFile -Algorithm SHA256).Hash
    Set-Content -Path "$destFile.sha256" -Value "$hash  market_mms_v$Version$ext" -Encoding UTF8

    Write-Host "[3/3] Yerel güncelleme manifest örneği yazılıyor..." -ForegroundColor Yellow
    $manifest = @{
        latest_version = $Version
        min_supported_version = $Version
        download_url = "https://<HUB-LAN-IP>:8945/downloads/market_mms_v$Version$ext"
        sha256 = $hash
        mandatory = $false
        release_notes = "MARKET MMS v$Version Android Release"
    } | ConvertTo-Json -Depth 4
    Set-Content -Path (Join-Path $targetDir "manifest.json") -Value $manifest -Encoding UTF8

    Write-Host "Android Release paketi hazır: $destFile" -ForegroundColor Green
    Write-Host "SHA-256: $hash" -ForegroundColor Green
} finally {
    Pop-Location
}
