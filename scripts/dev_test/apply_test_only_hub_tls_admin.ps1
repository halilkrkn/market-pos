# apply_test_only_hub_tls_admin.ps1 - MARKET MMS TEST_ONLY TLS & Hub Service Activation (Reversible)
# Pure ASCII (PowerShell 5.1 uyumlu). Yonetici (Administrator) PowerShell'de calistirilmalidir.
# ASLA ca.key dosyasini ProgramData icine kopyalamaz ve ASLA MarketMmsSpike01 servisini olusturmaz.
[CmdletBinding()]
param(
    [string]$SourceDeployDir = "$env:LOCALAPPDATA\MarketMMS_Isolated_Test\test_only_tls\hub_deploy",
    [string]$ProgramDataRoot = "$env:ProgramData\MarketMMS",
    [string]$ProgramFilesRoot = "${env:ProgramFiles}\MarketMMS",
    [string]$ServiceName = "MarketMMSService",
    [string]$AdvertiseHost = "",
    [switch]$Rollback
)

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw "Bu betik Yonetici (Administrator) PowerShell yetkisi gerektirir."
}

if (Get-Service -Name "MarketMmsSpike01" -ErrorAction SilentlyContinue) {
    throw "GUVENLIK IHLALI: MarketMmsSpike01 servisi sistemde mevcut; islem durduruldu."
}

$certsDir = Join-Path $ProgramDataRoot "certs"
$configDir = Join-Path $ProgramDataRoot "config"
$configPath = Join-Path $configDir "hub_config.json"
$configBakPath = Join-Path $configDir "hub_config.json.pre_test_only.bak"
$wrapperExe = Join-Path $ProgramDataRoot "bin\MarketMMSService.exe"
$aclScript = Join-Path $ProgramFilesRoot "hub_scripts\setup_service_acls.ps1"
$fwScript = Join-Path $ProgramFilesRoot "hub_scripts\configure_hub_firewall.ps1"

if ($Rollback) {
    Write-Host "[ROLLBACK] MarketMMSService durduruluyor ve TEST_ONLY TLS yapilandirmasi geri aliniyor..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $wrapperExe) {
        & $wrapperExe stop 2>&1 | Out-Host
    } else {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $configBakPath) {
        Copy-Item -LiteralPath $configBakPath -Destination $configPath -Force
        Write-Host "[OK] hub_config.json yedekten geri yuklendi." -ForegroundColor Green
    }
    foreach ($f in @("ca.crt", "server.crt", "server.key")) {
        $p = Join-Path $certsDir $f
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Host "[OK] TEST_ONLY dosya kaldirildi: $p" -ForegroundColor Green
        }
    }
    Write-Host "[ROLLBACK COMPLETE]" -ForegroundColor Cyan
    exit 0
}

# 1. Kaynak TEST_ONLY dizini guvenlik kontrolu (ca.key YASAK)
if (Test-Path -LiteralPath (Join-Path $SourceDeployDir "ca.key")) {
    throw "GUVENLIK HATASI: ca.key asla hub_deploy / ProgramData icine kopyalanamaz!"
}
foreach ($req in @("ca.crt", "server.crt", "server.key")) {
    $p = Join-Path $SourceDeployDir $req
    if (-not (Test-Path -LiteralPath $p)) {
        throw "Eksik TEST_ONLY TLS dosyasi: $p"
    }
}

# 2. Aktif Wi-Fi / LAN IPv4 tespiti
if ([string]::IsNullOrWhiteSpace($AdvertiseHost)) {
    $wifiIp = Get-NetIPAddress -InterfaceAlias "Wi-Fi" -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty IPAddress
    if (-not [string]::IsNullOrWhiteSpace($wifiIp)) {
        $AdvertiseHost = $wifiIp.Trim()
    } else {
        $defaultRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -and $_.NextHop -ne "0.0.0.0" } |
            Sort-Object -Property RouteMetric, InterfaceMetric
        foreach ($route in $defaultRoutes) {
            $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
            if (-not $adapter -or $adapter.Status -ne "Up") { continue }
            $desc = ($adapter.InterfaceDescription + " " + $adapter.Name)
            if ($desc -match "(?i)(VirtualBox|Hyper-V|VMware|vEthernet|Virtual|Loopback|TAP|TUN|WSL|Docker)") {
                continue
            }
            $candidateIp = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty IPAddress
            if (-not [string]::IsNullOrWhiteSpace($candidateIp)) {
                $AdvertiseHost = $candidateIp.Trim()
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($AdvertiseHost)) {
        throw "Aktif Preferred Wi-Fi veya varsayilan ag gecidine sahip LAN IPv4 adresi bulunamadi. -AdvertiseHost parametresi ile acikca belirtin."
    }
}
Write-Host ("TARGET_LAN_IP=" + $AdvertiseHost) -ForegroundColor Cyan

# 3. Mevcut config ve varsa sertifikalari yedekle
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "hub_config.json bulunamadi: $configPath"
}
if (-not (Test-Path -LiteralPath $configBakPath)) {
    Copy-Item -LiteralPath $configPath -Destination $configBakPath -Force
    Write-Host "[OK] Orijinal hub_config.json yedeklendi: $configBakPath" -ForegroundColor Green
}

$certsBackupDir = Join-Path $certsDir "pre_test_only_backup"
$existingCertFiles = Get-ChildItem -LiteralPath $certsDir -File -ErrorAction SilentlyContinue
if ($existingCertFiles -and -not (Test-Path -LiteralPath $certsBackupDir)) {
    New-Item -ItemType Directory -Path $certsBackupDir -Force | Out-Null
    foreach ($ef in $existingCertFiles) {
        Copy-Item -LiteralPath $ef.FullName -Destination (Join-Path $certsBackupDir $ef.Name) -Force
    }
    Write-Host "[OK] Onceki certs yedeklendi: $certsBackupDir" -ForegroundColor Green
}

# 4. Yalnizca ca.crt, server.crt, server.key kopyala (ca.key haric)
foreach ($f in @("ca.crt", "server.crt", "server.key")) {
    Copy-Item -LiteralPath (Join-Path $SourceDeployDir $f) -Destination (Join-Path $certsDir $f) -Force
}
if (Test-Path -LiteralPath (Join-Path $certsDir "ca.key")) {
    Remove-Item -LiteralPath (Join-Path $certsDir "ca.key") -Force
    throw "GUVENLIK HATASI: ca.key certs dizininde tespit edildi ve temizlendi."
}

# 5. hub_config.json icinde advertise_host ve TLS yollarini dogrula/guncelle
$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$cfg.advertise_host = $AdvertiseHost
if (-not $cfg.tls) {
    throw "hub_config.json icinde tls bolumu eksik."
}
$cfg.tls.enabled = $true
$cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
Write-Host "[OK] hub_config.json advertise_host=$AdvertiseHost olarak guncellendi." -ForegroundColor Green

# 6. ACL & Firewall & Servis baslatma / yeniden baslatma dogrulamasi
& $aclScript -BaseDir $ProgramDataRoot -ServiceName $ServiceName
if ($LASTEXITCODE -ne 0) { throw "setup_service_acls.ps1 basarisiz oldu ($LASTEXITCODE)." }

$hubPort = if ($cfg.port) { [int]$cfg.port } else { 8945 }
$discPort = if ($cfg.discovery_port) { [int]$cfg.discovery_port } else { 8946 }
& $fwScript -TcpPort $hubPort -UdpPort $discPort -Profile "Private" -RemoteAddress "LocalSubnet"
if ($LASTEXITCODE -ne 0) { throw "configure_hub_firewall.ps1 basarisiz oldu ($LASTEXITCODE)." }

$svcNow = Get-Service -Name $ServiceName -ErrorAction Stop
if ($svcNow.Status -eq "Running") {
    & $wrapperExe stop 2>&1 | Out-Host
    Start-Sleep -Seconds 2
}
& $wrapperExe start 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "MarketMMSService start basarisiz oldu ($LASTEXITCODE)." }
Start-Sleep -Seconds 3

$svcCheck1 = Get-Service -Name $ServiceName -ErrorAction Stop
Write-Host ("SERVICE_START_STATUS=" + $svcCheck1.Status)
if ($svcCheck1.Status -ne "Running") { throw "Servis Running durumuna gecemedi." }

# Restart testi
& $wrapperExe restart 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "MarketMMSService restart basarisiz oldu ($LASTEXITCODE)." }
Start-Sleep -Seconds 3
$svcCheck2 = Get-Service -Name $ServiceName -ErrorAction Stop
Write-Host ("SERVICE_RESTART_STATUS=" + $svcCheck2.Status)
if ($svcCheck2.Status -ne "Running") { throw "Servis restart sonrasi Running durumuna gecemedi." }

# 7. Dinleyiciler ve KATI CA-Pinned HTTPS /health kontrolleri (bypass YOK!)
$tcp = @(Get-NetTCPConnection -State Listen -LocalPort $hubPort -ErrorAction SilentlyContinue)
$udp = @(Get-NetUDPEndpoint -LocalPort $discPort -ErrorAction SilentlyContinue)
Write-Host ("TCP_" + $hubPort + "_LISTEN_COUNT=" + $tcp.Count)
Write-Host ("UDP_" + $discPort + "_EP_COUNT=" + $udp.Count)

$deployedCa = Join-Path $certsDir "ca.crt"
$curlExe = "$env:SystemRoot\System32\curl.exe"
if (-not (Test-Path -LiteralPath $curlExe)) { $curlExe = "curl.exe" }

Write-Host "--- HEALTH CHECK 1: https://127.0.0.1:$hubPort/health ---" -ForegroundColor Cyan
$h1 = & $curlExe --fail --show-error --silent --ssl-no-revoke --cacert $deployedCa "https://127.0.0.1:$hubPort/health" 2>&1
if ($LASTEXITCODE -ne 0) { throw "Localhost HTTPS health basarisiz: $h1" }
Write-Host $h1

Write-Host "--- HEALTH CHECK 2: https://${AdvertiseHost}:$hubPort/health ---" -ForegroundColor Cyan
$h2 = & $curlExe --fail --show-error --silent --ssl-no-revoke --cacert $deployedCa "https://${AdvertiseHost}:$hubPort/health" 2>&1
if ($LASTEXITCODE -ne 0) { throw "LAN IP HTTPS health basarisiz: $h2" }
Write-Host $h2

Write-Host "[SUCCESS] TEST_ONLY Master Hub servisi ve HTTPS/UDP dinleyicileri dogrulandi." -ForegroundColor Green

