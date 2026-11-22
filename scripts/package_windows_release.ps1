param(
    [string]$OutputDir = "dist\windows_release",
    [string]$GoogleDriveClientId = "",
    [string]$GoogleDriveClientSecret = "",
    [switch]$SkipBackendBuild,
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$aotStageDir = $null
Push-Location $repoRoot
try {
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host " MARKET MMS - Windows Release Paketleme" -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    $backendSourceDir = Join-Path $repoRoot "test_spikes\spike_01_backend\build"
    if (-not $SkipBackendBuild) {
        $backendScript = Join-Path $repoRoot "test_spikes\spike_01_backend\scripts\build_aot.ps1"
        if (-not (Test-Path $backendScript)) {
            throw "Backend build betiği bulunamadı: $backendScript"
        }
        $aotStageDir = Join-Path $env:TEMP ("mms_hub_aot_stage_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $aotStageDir | Out-Null
        $backendSourceDir = $aotStageDir
        Write-Host "[1/4] Hub Dart AOT arka plan servisi geçici dizinde derleniyor..." -ForegroundColor Yellow
        & powershell -NoProfile -ExecutionPolicy Bypass -File $backendScript -OutputDir $aotStageDir
        if ($LASTEXITCODE -ne 0) {
            throw "Backend AOT derlemesi başarısız oldu ($LASTEXITCODE)."
        }
    } else {
        Write-Host "[1/4] Backend AOT derlemesi atlandı (-SkipBackendBuild)." -ForegroundColor Gray
    }

    if (-not $SkipFlutterBuild) {
        Write-Host "[2/4] Flutter Windows Release derleniyor..." -ForegroundColor Yellow
        $flutterArgs = @("build", "windows", "--release")
        if (-not [string]::IsNullOrWhiteSpace($GoogleDriveClientId)) {
            $flutterArgs += "--dart-define=MMS_GDRIVE_CLIENT_ID=$($GoogleDriveClientId.Trim())"
        }
        if (-not [string]::IsNullOrWhiteSpace($GoogleDriveClientSecret)) {
            $flutterArgs += "--dart-define=MMS_GDRIVE_CLIENT_SECRET=$($GoogleDriveClientSecret.Trim())"
        }
        & flutter @flutterArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter Windows Release derlemesi başarısız oldu ($LASTEXITCODE)."
        }
    } else {
        Write-Host "[2/4] Flutter Windows Release derlemesi atlandı (-SkipFlutterBuild)." -ForegroundColor Gray
    }

    $flutterReleaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
    if (-not (Test-Path $flutterReleaseDir)) {
        throw "Flutter Windows Release çıktısı bulunamadı: $flutterReleaseDir"
    }

    $targetDir = Join-Path $repoRoot $OutputDir
    if (Test-Path $targetDir) {
        Remove-Item -Recurse -Force $targetDir
    }
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    Write-Host "[3/4] İstemci ikilileri kopyalanıyor..." -ForegroundColor Yellow
    $clientOut = Join-Path $targetDir "client"
    Copy-Item -Recurse -Force $flutterReleaseDir $clientOut

    $hubScriptsOut = Join-Path $targetDir "hub_scripts"
    New-Item -ItemType Directory -Force -Path $hubScriptsOut | Out-Null
    Copy-Item -Force (Join-Path $repoRoot "scripts\configure_hub_firewall.ps1") $hubScriptsOut
    foreach ($scriptName in @("install_mms_service.ps1", "setup_service_acls.ps1", "uninstall_mms_service.ps1")) {
        $src = Join-Path $repoRoot "test_spikes\spike_01_backend\scripts\$scriptName"
        if (Test-Path $src) {
            Copy-Item -Force $src $hubScriptsOut
        }
    }

    $backendExe = Join-Path $backendSourceDir "mms_backend.exe"
    $sqliteDll = @((Join-Path $backendSourceDir "sqlite3.dll"), (Join-Path $backendSourceDir "lib\sqlite3.dll")) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (Test-Path $backendExe) {
        $hubBinOut = Join-Path $targetDir "hub_bin"
        $hubBinLibOut = Join-Path $hubBinOut "lib"
        New-Item -ItemType Directory -Force -Path $hubBinOut | Out-Null
        New-Item -ItemType Directory -Force -Path $hubBinLibOut | Out-Null
        Copy-Item -Force $backendExe $hubBinOut
        if (-not [string]::IsNullOrWhiteSpace($sqliteDll)) {
            Copy-Item -Force $sqliteDll (Join-Path $hubBinOut "sqlite3.dll")
            Copy-Item -Force $sqliteDll (Join-Path $hubBinLibOut "sqlite3.dll")
        }
        foreach ($wrapperFile in @("MarketMMSService.exe", "MarketMMSService.xml")) {
            $wrapperSrc = Join-Path $repoRoot "test_spikes\spike_01_backend\service_wrapper\$wrapperFile"
            if (Test-Path $wrapperSrc) {
                Copy-Item -Force $wrapperSrc $hubBinOut
            }
        }
        $configTemplate = Join-Path $repoRoot "test_spikes\spike_01_backend\config\hub_config.example.json"
        if (Test-Path $configTemplate) {
            Copy-Item -Force $configTemplate $hubBinOut
        }
    }

    Write-Host "[4/4] SHA-256 doğrulama özetleri oluşturuluyor..." -ForegroundColor Yellow
    $checksumLines = Get-ChildItem -Path $targetDir -Recurse -File | ForEach-Object {
        $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $rel = $_.FullName.Substring($targetDir.Length + 1)
        "$hash  $rel"
    }
    Set-Content -Path (Join-Path $targetDir "SHA256SUMS.txt") -Value $checksumLines -Encoding UTF8

    Write-Host "Windows Release paketi hazır: $targetDir" -ForegroundColor Green
} finally {
    if ($aotStageDir -and (Test-Path $aotStageDir)) {
        Remove-Item -Recurse -Force $aotStageDir -ErrorAction SilentlyContinue
    }
    Pop-Location
}
