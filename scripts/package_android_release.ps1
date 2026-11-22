param(
    [string]$OutputDir = "dist\android_release",
    [string]$Version = "",
    [string]$GoogleDriveWebClientId = "",
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

    $pubspecPath = Join-Path $repoRoot "pubspec.yaml"
    if (-not (Test-Path $pubspecPath)) {
        throw "pubspec.yaml bulunamadı: $pubspecPath"
    }
    $pubspecLines = Get-Content -Path $pubspecPath -Encoding UTF8
    $versionMatch = $null
    foreach ($line in $pubspecLines) {
        if ($line -match '^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*(?:#.*)?$') {
            $versionMatch = $Matches
            break
        }
    }
    if ($null -eq $versionMatch) {
        throw "pubspec.yaml içinde geçerli 'version: X.Y.Z+N' tanımı bulunamadı."
    }

    $buildName = $versionMatch[1]
    $buildNumber = $versionMatch[2]
    $fullVersion = "$buildName+$buildNumber"

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $trimmedExpected = $Version.Trim()
        if ($trimmedExpected -ne $buildName -and $trimmedExpected -ne $fullVersion) {
            throw "Sürüm uyuşmazlığı: -Version ('$trimmedExpected') ile pubspec.yaml sürümü ('$fullVersion') eşleşmiyor. Önce pubspec.yaml dosyasını güncelleyin."
        }
    }

    Write-Host "Algılanan Flutter sürümü (pubspec.yaml): $fullVersion (build-name=$buildName, build-number=$buildNumber)" -ForegroundColor Cyan

    if (-not $SkipFlutterBuild) {
        $extraDartDefines = @()
        if (-not [string]::IsNullOrWhiteSpace($GoogleDriveWebClientId)) {
            $extraDartDefines += "--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=$($GoogleDriveWebClientId.Trim())"
        }
        if ($BuildAppBundle) {
            Write-Host "[1/3] Android AppBundle (--release) derleniyor..." -ForegroundColor Yellow
            & flutter build appbundle --release "--build-name=$buildName" "--build-number=$buildNumber" @extraDartDefines
        } else {
            Write-Host "[1/3] Android APK (--release) derleniyor..." -ForegroundColor Yellow
            & flutter build apk --release "--build-name=$buildName" "--build-number=$buildNumber" @extraDartDefines
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Android Release derlemesi başarısız oldu ($LASTEXITCODE)."
        }

        $localPropsPath = Join-Path $repoRoot "android\local.properties"
        if (Test-Path $localPropsPath) {
            $localProps = Get-Content -Path $localPropsPath -Encoding UTF8
            $propName = ($localProps | Where-Object { $_ -match '^flutter\.versionName=' } | Select-Object -Last 1)
            $propCode = ($localProps | Where-Object { $_ -match '^flutter\.versionCode=' } | Select-Object -Last 1)
            if ($propName -and $propName -ne "flutter.versionName=$buildName") {
                throw "Flutter Gradle sürüm adı uyuşmazlığı: $propName != flutter.versionName=$buildName"
            }
            if ($propCode -and $propCode -ne "flutter.versionCode=$buildNumber") {
                throw "Flutter Gradle sürüm kodu uyuşmazlığı: $propCode != flutter.versionCode=$buildNumber"
            }
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
    $artifactFileName = "market_mms_v$buildName-b$buildNumber$ext"
    $destFile = Join-Path $targetDir $artifactFileName
    Copy-Item -Force $artifactSource $destFile

    Write-Host "[2/3] SHA-256 checksum hesaplanıyor..." -ForegroundColor Yellow
    $hash = (Get-FileHash -Path $destFile -Algorithm SHA256).Hash
    Set-Content -Path "$destFile.sha256" -Value "$hash  $artifactFileName" -Encoding UTF8

    Write-Host "[3/3] Yerel güncelleme manifest örneği yazılıyor..." -ForegroundColor Yellow
    $manifest = @{
        latest_version = $buildName
        build_number = [int]$buildNumber
        min_supported_version = $buildName
        download_url = "https://<HUB-LAN-IP>:8945/downloads/$artifactFileName"
        sha256 = $hash
        mandatory = $false
        release_notes = "MARKET MMS v$fullVersion Android Release"
    } | ConvertTo-Json -Depth 4
    Set-Content -Path (Join-Path $targetDir "manifest.json") -Value $manifest -Encoding UTF8

    Write-Host "Android Release paketi hazır: $destFile" -ForegroundColor Green
    Write-Host "SHA-256: $hash" -ForegroundColor Green
} finally {
    Pop-Location
}
