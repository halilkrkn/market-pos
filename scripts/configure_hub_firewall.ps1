param(
    [int]$TcpPort = 8945,
    [int]$UdpPort = 8946,
    [string]$Profile = "Private",
    # Hub yalnizca yerel agdan erisilebilir. Farkli VLAN/alt ag topolojisinde ornek:
    # -RemoteAddress "192.168.10.0/24,192.168.20.0/24"
    [string]$RemoteAddress = "LocalSubnet",
    [string]$ConfigPath = "$env:ProgramData\MarketMMS\config\hub_config.json",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

# REL-01: Kurulu Hub yapilandirmasi varsa portlar TEK kaynaktan (hub_config.json) okunur.
if ((Test-Path $ConfigPath) -and -not $PSBoundParameters.ContainsKey('TcpPort')) {
    $hubConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $TcpPort = [int]$hubConfig.port
    $UdpPort = [int]$hubConfig.discovery_port
    Write-Host "Portlar yapilandirmadan okundu: TCP $TcpPort / UDP $UdpPort ($ConfigPath)"
}

$tcpRuleName = "MarketMMS-Hub-API-TCP-$TcpPort"
$udpRuleName = "MarketMMS-Hub-Discovery-UDP-$UdpPort"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " MARKET MMS - Windows Firewall Yapılandırması" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Bu betik Windows Güvenlik Duvarı kuralları için Yönetici (Administrator) yetkisi gerektirir."
    exit 1
}

if ($Remove) {
    foreach ($name in @($tcpRuleName, $udpRuleName)) {
        $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-NetFirewallRule -DisplayName $name
            Write-Host "[KALDIRILDI] $name" -ForegroundColor Yellow
        } else {
            Write-Host "[YOK] $name zaten tanımlı değil." -ForegroundColor Gray
        }
    }
    exit 0
}

# Virgulle ayrilmis adres listesi -> dizi (New/Set-NetFirewallRule string[] bekler).
$remoteList = @($RemoteAddress.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($remoteList.Count -eq 0) { throw "RemoteAddress bos olamaz (varsayilan: LocalSubnet)." }
Write-Host "Izin verilen uzak adresler: $($remoteList -join ', ')"

function Ensure-InboundRule {
    param(
        [string]$RuleName,
        [string]$Protocol,
        [int]$Port,
        [string]$FirewallProfile
    )
    $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -DisplayName $RuleName -Profile $FirewallProfile -RemoteAddress $remoteList -Enabled True -Action Allow | Out-Null
        Write-Host "[GÜNCELLENDİ] $RuleName ($Protocol/$Port -> $FirewallProfile)" -ForegroundColor Green
    } else {
        New-NetFirewallRule -DisplayName $RuleName `
            -Direction Inbound `
            -Protocol $Protocol `
            -LocalPort $Port `
            -Action Allow `
            -Profile $FirewallProfile `
            -RemoteAddress $remoteList `
            -Enabled True `
            -Description "MARKET MMS Local Master Hub LAN iletişimi" | Out-Null
        Write-Host "[OLUŞTURULDU] $RuleName ($Protocol/$Port -> $FirewallProfile)" -ForegroundColor Green
    }
}

Ensure-InboundRule -RuleName $tcpRuleName -Protocol "TCP" -Port $TcpPort -FirewallProfile $Profile
Ensure-InboundRule -RuleName $udpRuleName -Protocol "UDP" -Port $UdpPort -FirewallProfile $Profile

Write-Host "Güvenlik duvarı kuralları başarıyla uygulandı." -ForegroundColor Cyan
