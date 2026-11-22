# install_mms_service.ps1 - Market MMS Windows Servis Kurulum, Guncelleme ve Baslatma Betigi (v2.1)
#
# v2.1 (21.11.2026): Guncellemede servis, ikililer kopyalanmadan ONCE durdurulur (calisan
# mms_backend.exe kilitlidir). Onceki surum ikilileri bin.previous altinda saklanir; yeni
# surum baslamazsa/saglik kontrolu gecmezse otomatik olarak onceki surume donulur.
# Yapilandirma, sirlar, sertifikalar ve veritabani hicbir adimda silinmez veya ezilmez.
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

$sqliteDllCandidates = @(
    (Join-Path $spikeRoot "build\sqlite3.dll"),
    (Join-Path $spikeRoot "build\lib\sqlite3.dll"),
    (Join-Path $spikeRoot "build\bundle\bundle\lib\sqlite3.dll")
)
$sqliteDllSrc = $sqliteDllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($sqliteDllSrc)) {
    throw "HATA: sqlite3.dll bulunamadi ($spikeRoot\build\). Once build_aot.ps1 calistirin."
}

# 3. Dizin Yapisi ve Temel NTFS ACL Yapilandirmasi
Write-Host "[1/5] Hedef dizin ve NTFS ACL yapilandiriliyor: $TargetBaseDir ..." -ForegroundColor Yellow
& "$scriptDir\setup_service_acls.ps1" -BaseDir $TargetBaseDir -ServiceName $ServiceName

# 4. Hedef yollar
$targetBinDir = Join-Path $TargetBaseDir "bin"
$targetBinLibDir = Join-Path $targetBinDir "lib"
$targetRootLibDir = Join-Path $TargetBaseDir "lib"
$previousBinDir = Join-Path $TargetBaseDir "bin.previous"
$deployedWrapperExe = Join-Path $targetBinDir "MarketMMSService.exe"
$deployedWrapperXml = Join-Path $targetBinDir "MarketMMSService.xml"
$deployedBackendExe = Join-Path $targetBinDir "mms_backend.exe"
$deployedSqliteDll = Join-Path $targetBinDir "sqlite3.dll"
$deployedBinLibSqliteDll = Join-Path $targetBinLibDir "sqlite3.dll"
$deployedRootLibSqliteDll = Join-Path $targetRootLibDir "sqlite3.dll"
foreach ($dirPath in @($targetBinDir, $targetBinLibDir, $targetRootLibDir)) {
    if (!(Test-Path $dirPath)) { New-Item -ItemType Directory -Path $dirPath -Force | Out-Null }
}

# 4b. REL-01: Tek yapilandirma kaynagi (config\hub_config.json)
#     Mevcut yapilandirma ASLA uzerine yazilmaz (guncellemede ayarlar ve sirlar korunur).
#     Bu adimlar CALISAN SERVISE DOKUNULMADAN yapilir: eksik sertifika vb. durumda
#     mevcut kurulum calismaya devam eder (fail-closed, kesintisiz).
Write-Host "[2/5] Yapilandirma, admin secret ve TLS sertifikasi denetleniyor..." -ForegroundColor Yellow
$configDir = Join-Path $TargetBaseDir "config"
$securityDir = Join-Path $TargetBaseDir "security"
$configFile = Join-Path $configDir "hub_config.json"
$configTemplate = Join-Path $spikeRoot "config\hub_config.example.json"
if (!(Test-Path $configFile)) {
    Copy-Item -Path $configTemplate -Destination $configFile
    Write-Host "  -> Yeni yapilandirma olusturuldu: $configFile (magaza/tenant degerlerini duzenleyin)" -ForegroundColor Yellow
} else {
    Write-Host "  -> Mevcut yapilandirma korundu: $configFile" -ForegroundColor Green
}

# Admin secret: varsayilan/sabit deger YOK. Yoksa kriptografik rastgele uretilir (ACL korumali security\).
$adminSecretFile = Join-Path $securityDir "admin_secret.txt"
if (!(Test-Path $adminSecretFile)) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $secret = [Convert]::ToBase64String($bytes)
    Set-Content -Path $adminSecretFile -Value $secret -NoNewline -Encoding ASCII
    Write-Host "  -> Admin secret uretildi: $adminSecretFile (degeri ekrana yazilmaz)" -ForegroundColor Green
}

# TLS sertifikalari kurulmadan uretim servisi baslatilmaz (fail-closed).
$certFile = Join-Path $TargetBaseDir "certs\server.crt"
$keyFile = Join-Path $TargetBaseDir "certs\server.key"
if (!(Test-Path $certFile) -or !(Test-Path $keyFile)) {
    throw "HATA: TLS sertifikasi bulunamadi ($certFile / $keyFile). Once sertifika kurulumunu tamamlayin (bkz. docs/release/WINDOWS_HUB_RELEASE.md)."
}
# PAIR-CA: Eslestirme QR'indaki CA parmak izi icin kok CA sertifikasi (yalnizca GENEL sertifika).
# ca.key bu makinede BULUNMAMALIDIR (setup_service_acls.ps1 bulursa kurulumu durdurur).
$caCertFile = Join-Path $TargetBaseDir "certs\ca.crt"
if (!(Test-Path $caCertFile)) {
    throw "HATA: Eslestirme kok CA sertifikasi bulunamadi ($caCertFile). hub_config.json tls.ca_cert bu dosyayi gostermelidir."
}

function Stop-AndRemoveMmsService {
    param([string]$WrapperExe)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (!$svc) { return }
    if ($svc.Status -ne "Stopped") {
        if (Test-Path $WrapperExe) { & "$WrapperExe" stop | Out-Null } else { sc.exe stop $ServiceName | Out-Null }
        # Graceful shutdown (WinSW stoptimeout 15 sn) + pay: en fazla 30 sn beklenir.
        try {
            $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
        } catch {
            throw "HATA: Servis 30 sn icinde durmadi; ikililer degistirilmedi. Durum: $((Get-Service -Name $ServiceName).Status)"
        }
    }
    if (Test-Path $WrapperExe) { & "$WrapperExe" uninstall | Out-Null } else { sc.exe delete $ServiceName | Out-Null }
    Start-Sleep -Seconds 2
}

function Install-AndStartMmsService {
    $installRes = & "$deployedWrapperExe" install 2>&1
    if ($LASTEXITCODE -ne 0) { throw "HATA: WinSW install basarisiz ($LASTEXITCODE): $installRes" }
    Write-Host "  -> $installRes" -ForegroundColor Green

    # Service SID Tanimlama (sc.exe sidtype) - ACL'ler NT SERVICE\<ad> kimligine verilir.
    $scOutput = sc.exe sidtype $ServiceName unrestricted 2>&1
    if ($LASTEXITCODE -ne 0) { throw "HATA: Service SID atamasi basarisiz oldu: $scOutput" }
    $qsidOutput = sc.exe qsidtype $ServiceName 2>&1
    Write-Host "  -> SCM Yapilandirma Durumu: $qsidOutput"

    # admin_secret.txt dosyasini servis icin salt-okunur (:R) olarak kilitle
    if (Test-Path $adminSecretFile) {
        $sidSvc = "NT SERVICE\$ServiceName"
        try {
            $sidSvc = "*" + (New-Object System.Security.Principal.NTAccount("NT SERVICE\$ServiceName")).Translate([System.Security.Principal.SecurityIdentifier]).Value
        } catch {}
        & icacls $adminSecretFile /inheritance:r /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" /grant:r "${sidSvc}:R" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "HATA: admin_secret.txt salt-okunur ACL atamasi basarisiz oldu ($LASTEXITCODE)."
        }
    }

    $startRes = & "$deployedWrapperExe" start 2>&1
    if ($LASTEXITCODE -ne 0) { throw "HATA: Servis baslatilamadi ($LASTEXITCODE): $startRes" }
    Write-Host "  -> $startRes" -ForegroundColor Green
    Start-Sleep -Seconds 3

    $srv = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($srv.Status -ne "Running") {
        throw "HATA: Servis calismiyor ($($srv.Status)). Loglari inceleyin: $(Join-Path $TargetBaseDir 'logs')"
    }
    $hubPort = (Get-Content $configFile -Raw | ConvertFrom-Json).port
    $tcpOk = Test-NetConnection -ComputerName 127.0.0.1 -Port $hubPort -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $tcpOk) {
        throw "HATA: Hub $hubPort numarali portta yanit vermiyor (health check basarisiz)."
    }
    Write-Host "  -> Health check: 127.0.0.1:$hubPort erisilebilir." -ForegroundColor Green
    return $srv
}

# 5. Mevcut servis varsa ONCE durdur ve kaldir. (Calisan mms_backend.exe kilitlidir;
#    ikililer servis durmadan kopyalanamaz. Veri, config ve sirlar korunur.)
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "[INFO] Servis zaten kurulu (guncelleme). Once durduruluyor ve kaldiriliyor..." -ForegroundColor Yellow
    Stop-AndRemoveMmsService -WrapperExe $deployedWrapperExe
}

# 6. Geri donus (rollback) icin mevcut ikilileri sakla, sonra yenilerini kopyala.
$hasPrevious = $false
if (Test-Path $deployedBackendExe) {
    if (Test-Path $previousBinDir) { Remove-Item -Recurse -Force $previousBinDir }
    New-Item -ItemType Directory -Path $previousBinDir -Force | Out-Null
    foreach ($f in @($deployedWrapperExe, $deployedWrapperXml, $deployedBackendExe, $deployedSqliteDll)) {
        if (Test-Path $f) { Copy-Item -Path $f -Destination $previousBinDir -Force }
    }
    $hasPrevious = $true
    Write-Host "  -> Onceki surum ikilileri saklandi: $previousBinDir" -ForegroundColor Gray
}

Write-Host "[3/5] Servis ikilileri ProgramData dizinine kopyalaniyor..." -ForegroundColor Yellow
Copy-Item -Path $wrapperExeSrc -Destination $deployedWrapperExe -Force
Copy-Item -Path $wrapperXmlSrc -Destination $deployedWrapperXml -Force
Copy-Item -Path $backendExeSrc -Destination $deployedBackendExe -Force
Copy-Item -Path $sqliteDllSrc -Destination $deployedSqliteDll -Force
Copy-Item -Path $sqliteDllSrc -Destination $deployedBinLibSqliteDll -Force
Copy-Item -Path $sqliteDllSrc -Destination $deployedRootLibSqliteDll -Force

# 7-9. Kur, SID ata, baslat, saglik kontrolu. Basarisizsa onceki ikililere otomatik don.
Write-Host "[4/5] WinSW v2.12.0 ile servis kuruluyor ve baslatiliyor: $ServiceName ..." -ForegroundColor Yellow
try {
    $srv = Install-AndStartMmsService
} catch {
    $installError = $_.Exception.Message
    if (-not $hasPrevious) { throw }
    Write-Host "[ROLLBACK] Yeni surum baslatilamadi: $installError" -ForegroundColor Red
    Write-Host "[ROLLBACK] Onceki surum ikililerine donuluyor ($previousBinDir)..." -ForegroundColor Yellow
    Stop-AndRemoveMmsService -WrapperExe $deployedWrapperExe
    foreach ($name in @("MarketMMSService.exe", "MarketMMSService.xml", "mms_backend.exe")) {
        $prev = Join-Path $previousBinDir $name
        if (Test-Path $prev) { Copy-Item -Path $prev -Destination (Join-Path $targetBinDir $name) -Force }
    }
    $prevSqlite = Join-Path $previousBinDir "sqlite3.dll"
    if (Test-Path $prevSqlite) {
        Copy-Item -Path $prevSqlite -Destination $deployedSqliteDll -Force
        Copy-Item -Path $prevSqlite -Destination $deployedBinLibSqliteDll -Force
        Copy-Item -Path $prevSqlite -Destination $deployedRootLibSqliteDll -Force
    }
    $srv = Install-AndStartMmsService
    throw "GUNCELLEME BASARISIZ: Onceki surume geri donuldu ve servis calisiyor. Neden: $installError. Yeni surum veritabani semasini yukselttiyse bkz. docs/release/WINDOWS_HUB_RELEASE.md (Guncelleme ve Geri Donus)."
}

Write-Host "[5/5] Kurulum dogrulandi." -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Market MMS Windows Servisi Kuruldu ve Baslatildi!" -ForegroundColor Green
Write-Host "  - Servis Adi: $($srv.Name)"
Write-Host "  - Gorunen Ad: $($srv.DisplayName)"
Write-Host "  - Durum: $($srv.Status)"
Write-Host "  - Baslangic Turu: $($srv.StartType)"
Write-Host "====================================================" -ForegroundColor Cyan
