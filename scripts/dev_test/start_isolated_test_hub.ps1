# start_isolated_test_hub.ps1
# Starts an isolated MARKET MMS Test Hub process on TCP 8947 / UDP 8948
# using a separate directory under %LOCALAPPDATA%\MarketMMS_Isolated_Test.
# NEVER touches MarketMmsSpike01, port 8085, %ProgramData%\MarketMMS, or real DBs.
[CmdletBinding()]
param(
    [string]$TestRoot = (Join-Path $env:LOCALAPPDATA "MarketMMS_Isolated_Test"),
    [int]$TcpPort = 8947,
    [int]$UdpPort = 8948,
    [string]$HubBinSourceDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if ($TcpPort -eq 8085 -or $TcpPort -eq 8945 -or $UdpPort -eq 8946) {
    throw "Guvenlik engeli: Test Hub portlari 8085, 8945 veya 8946 olamaz."
}

if ([string]::IsNullOrWhiteSpace($HubBinSourceDir)) {
    $trayBin = Join-Path $repoRoot "dist\windows_release_v1_0_0_tray\hub_bin"
    $relBin = Join-Path $repoRoot "dist\windows_release\hub_bin"
    if (Test-Path (Join-Path $trayBin "mms_backend.exe")) {
        $HubBinSourceDir = $trayBin
    } elseif (Test-Path (Join-Path $relBin "mms_backend.exe")) {
        $HubBinSourceDir = $relBin
    } else {
        throw "Derlenmis mms_backend.exe bulunamadi (dist\windows_release_v1_0_0_tray\hub_bin veya dist\windows_release\hub_bin)."
    }
}

$exeSrc = Join-Path $HubBinSourceDir "mms_backend.exe"
$dllSrc = @((Join-Path $HubBinSourceDir "sqlite3.dll"), (Join-Path $HubBinSourceDir "lib\sqlite3.dll")) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not (Test-Path $exeSrc) -or [string]::IsNullOrWhiteSpace($dllSrc)) {
    throw "Hub ikilisi veya sqlite3.dll eksik: $HubBinSourceDir"
}

# Check if isolated test hub is already running
$hubDir = Join-Path $TestRoot "hub"
$pidFile = Join-Path $hubDir "hub.pid"
if (Test-Path $pidFile) {
    $existingPid = [int](Get-Content -Path $pidFile -Raw).Trim()
    $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
    if ($existingProc -and $existingProc.ProcessName -eq "mms_backend") {
        Write-Host "[INFO] Izole Test Hub zaten calisiyor (PID: $existingPid, Port: $TcpPort)." -ForegroundColor Yellow
        exit 0
    }
}

# Verify test ports are free (ignore transient TimeWait sockets)
$tcpBusy = Get-NetTCPConnection -LocalPort $TcpPort -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
if ($tcpBusy) {
    throw "TCP portu $TcpPort su anda mesgul; baska bir izole port secin."
}
$udpBusy = Get-NetUDPEndpoint -LocalPort $UdpPort -ErrorAction SilentlyContinue
if ($udpBusy) {
    throw "UDP portu $UdpPort su anda mesgul; baska bir izole port secin."
}

# Create isolated directory layout
$caOfflineDir = Join-Path $TestRoot "ca_offline"
$binDir = Join-Path $hubDir "bin"
$binLibDir = Join-Path $binDir "lib"
$hubLibDir = Join-Path $hubDir "lib"
$certsDir = Join-Path $hubDir "certs"
$configDir = Join-Path $hubDir "config"
$dataDir = Join-Path $hubDir "data"
$securityDir = Join-Path $hubDir "security"
$backupsDir = Join-Path $hubDir "backups"
$logsDir = Join-Path $hubDir "logs"

foreach ($d in @($TestRoot, $caOfflineDir, $hubDir, $binDir, $binLibDir, $hubLibDir, $certsDir, $configDir, $dataDir, $securityDir, $backupsDir, $logsDir)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

# Copy runtime binaries into isolated folder (including ..\lib\sqlite3.dll relative to hub\bin)
Copy-Item -Path $exeSrc -Destination (Join-Path $binDir "mms_backend.exe") -Force
Copy-Item -Path $dllSrc -Destination (Join-Path $binDir "sqlite3.dll") -Force
Copy-Item -Path $dllSrc -Destination (Join-Path $binLibDir "sqlite3.dll") -Force
Copy-Item -Path $dllSrc -Destination (Join-Path $hubLibDir "sqlite3.dll") -Force

# Detect active physical Wi-Fi / LAN IPv4 (read-only)
$lanIp = $null
$wifiIpObj = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.InterfaceAlias -like "*Wi-Fi*" -and
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*"
    } | Select-Object -First 1
if ($wifiIpObj) {
    $lanIp = $wifiIpObj.IPAddress
} else {
    $anyLan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.InterfaceAlias -notlike "*Loopback*" -and
            $_.InterfaceAlias -notlike "*vEthernet*"
        } | Select-Object -First 1
    if ($anyLan) { $lanIp = $anyLan.IPAddress }
}

# Resolve OpenSSL 3.x
$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
if (-not (Test-Path $openssl)) {
    throw "OpenSSL 3.x bulunamadi: $openssl"
}

$caKey = Join-Path $caOfflineDir "ca.key"
$caCrt = Join-Path $certsDir "ca.crt"
$srvKey = Join-Path $certsDir "server.key"
$srvCrt = Join-Path $certsDir "server.crt"
$sanMarker = Join-Path $certsDir "san_host.txt"

$sanList = @("IP:127.0.0.1", "DNS:localhost")
if (-not [string]::IsNullOrWhiteSpace($lanIp)) {
    $sanList += ("IP:" + $lanIp)
}
$sanString = $sanList -join ","

$needCertGen = (-not (Test-Path $caKey)) -or (-not (Test-Path $caCrt)) -or (-not (Test-Path $srvKey)) -or (-not (Test-Path $srvCrt))
if (-not $needCertGen -and (Test-Path $sanMarker)) {
    if ((Get-Content -Path $sanMarker -Raw).Trim() -ne $sanString) {
        $needCertGen = $true
    }
}

if ($needCertGen) {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if (-not (Test-Path $caKey) -or -not (Test-Path $caCrt)) {
            & $openssl req -x509 -newkey rsa:2048 -nodes -keyout $caKey -out $caCrt -days 365 `
                -subj "/CN=Market MMS Isolated Test Root CA" `
                -addext "basicConstraints=critical,CA:TRUE" `
                -addext "keyUsage=critical,keyCertSign,cRLSign" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $caCrt)) { throw "Test Root CA olusturulamadi." }
        }

        $csrFile = Join-Path $caOfflineDir "server.csr"
        & $openssl req -new -newkey rsa:2048 -nodes -keyout $srvKey -out $csrFile `
            -subj "/CN=localhost" `
            -addext "subjectAltName=$sanString" `
            -addext "keyUsage=digitalSignature,keyEncipherment" `
            -addext "extendedKeyUsage=serverAuth" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $srvKey)) { throw "Test server CSR olusturulamadi." }

        & $openssl x509 -req -in $csrFile -CA $caCrt -CAkey $caKey -CAcreateserial -out $srvCrt -days 365 -copy_extensions copy 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $srvCrt)) { throw "Test server sertifikasi imzalanamadi." }
        Remove-Item -Path $csrFile -Force -ErrorAction SilentlyContinue
        Set-Content -Path $sanMarker -Value $sanString -Encoding ASCII
    } finally {
        $ErrorActionPreference = $prevEap
    }
}

# Generate isolated test-only admin secret (never logged)
$adminSecretFile = Join-Path $securityDir "admin_secret.txt"
if (-not (Test-Path $adminSecretFile)) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $secretBytes = New-Object byte[] 32
    $rng.GetBytes($secretBytes)
    $secretText = [Convert]::ToBase64String($secretBytes)
    Set-Content -Path $adminSecretFile -Value $secretText -NoNewline -Encoding ASCII
}

# Write isolated hub_config.json
$cfgPath = Join-Path $configDir "hub_config.json"
$cfgObj = [ordered]@{
    environment = "production"
    port = $TcpPort
    discovery_port = $UdpPort
    enable_discovery = $true
    db_path = "../data/market_master_test.db"
    backup_dir = "../backups"
    pepper_file = "../security/pepper.dpapi"
    admin_secret_file = "../security/admin_secret.txt"
    tls = [ordered]@{
        enabled = $true
        cert = "../certs/server.crt"
        key = "../certs/server.key"
        ca_cert = "../certs/ca.crt"
    }
    tenant_id = "tenant-isolated-test"
    store_id = "store-isolated-test-01"
    hub_id = "MMS-HUB-ISOLATED-TEST"
    require_tenant_store_headers = $true
    backup_schedule = [ordered]@{
        interval_hours = 0
        daily_retention_days = 7
        monthly_retention_months = 1
    }
}
if (-not [string]::IsNullOrWhiteSpace($lanIp)) {
    $cfgObj["advertise_host"] = $lanIp
}
Set-Content -Path $cfgPath -Value ($cfgObj | ConvertTo-Json -Depth 6) -Encoding UTF8

$stdoutLog = Join-Path $logsDir "hub_stdout.log"
$stderrLog = Join-Path $logsDir "hub_stderr.log"

# Clear any OAuth / production env vars temporarily so child inherits clean env
$clearedVars = @{}
$envNamesToClear = @(
    "MMS_GDRIVE_CLIENT_ID",
    "MMS_GDRIVE_CLIENT_SECRET",
    "GOOGLE_OAUTH_CLIENT_ID",
    "GOOGLE_OAUTH_CLIENT_SECRET",
    "ROOT_CA_CERT_FILE",
    "ADMIN_SECRET",
    "PEPPER_FILE",
    "DB_PATH",
    "PORT",
    "DISCOVERY_PORT"
)
foreach ($varName in $envNamesToClear) {
    $existingVal = [Environment]::GetEnvironmentVariable($varName, "Process")
    if ($null -ne $existingVal) {
        $clearedVars[$varName] = $existingVal
        [Environment]::SetEnvironmentVariable($varName, $null, "Process")
    }
}

try {
    $proc = Start-Process -FilePath (Join-Path $binDir "mms_backend.exe") `
        -ArgumentList @("--config=`"$cfgPath`"") `
        -WorkingDirectory $binDir `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -WindowStyle Hidden `
        -PassThru
} finally {
    foreach ($kv in $clearedVars.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
    }
}

if ($null -eq $proc) {
    throw "Izole Test Hub sureci baslatilamadi."
}
Set-Content -Path $pidFile -Value ([string]$proc.Id) -Encoding ASCII

# Wait for TLS /health using pinned ca.crt
$caCertObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($caCrt)
$healthy = $false
$healthBody = ""

if (-not ("MmsIsolatedTlsProbe" -as [type])) {
    Add-Type -Language CSharp -ReferencedAssemblies @("System.dll", "System.Core.dll") -TypeDefinition @"
using System;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text;

public static class MmsIsolatedTlsProbe
{
    public static string GetHealth(string host, int port, string caPath)
    {
        X509Certificate2 rootCa = new X509Certificate2(caPath);
        try
        {
            using (TcpClient tcp = new TcpClient())
            {
                tcp.ReceiveTimeout = 2000;
                tcp.SendTimeout = 2000;
                tcp.Connect(host, port);
                using (SslStream ssl = new SslStream(tcp.GetStream(), false, (sender, cert, chain, errs) =>
                {
                    if (cert == null) return false;
                    X509Certificate2 leaf = new X509Certificate2(cert);
                    X509Chain customChain = new X509Chain();
                    customChain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                    customChain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
                    customChain.ChainPolicy.ExtraStore.Add(rootCa);
                    if (!customChain.Build(leaf)) return false;
                    if (customChain.ChainElements.Count < 2) return false;
                    byte[] top = customChain.ChainElements[customChain.ChainElements.Count - 1].Certificate.RawData;
                    byte[] expected = rootCa.RawData;
                    if (top.Length != expected.Length) return false;
                    for (int i = 0; i < top.Length; i++) if (top[i] != expected[i]) return false;
                    return true;
                }))
                {
                    ssl.AuthenticateAsClient(host, null, SslProtocols.Tls12 | (SslProtocols)12288, false);
                    byte[] req = Encoding.ASCII.GetBytes("GET /health HTTP/1.1\r\nHost: " + host + ":" + port + "\r\nConnection: close\r\n\r\n");
                    ssl.Write(req, 0, req.Length);
                    ssl.Flush();
                    using (StreamReader sr = new StreamReader(ssl, Encoding.UTF8))
                    {
                        return sr.ReadToEnd();
                    }
                }
            }
        }
        finally
        {
            rootCa.Reset();
        }
    }
}
"@
}

$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) {
        throw "Izole Test Hub beklenmedik sekilde kapandi (ExitCode: $($proc.ExitCode)). Log: $stderrLog"
    }
    try {
        $resp = [MmsIsolatedTlsProbe]::GetHealth("127.0.0.1", $TcpPort, $caCrt)
        if ($resp -match "HTTP/1\.[01]\s+200" -and $resp -match '"status"\s*:\s*"UP"') {
            $healthy = $true
            $healthBody = ($resp -split "`r`n`r`n", 2)[1]
            break
        }
    } catch {
        Start-Sleep -Milliseconds 300
    }
}

if (-not $healthy) {
    try { $proc.Kill() } catch {}
    throw "Izole Test Hub 15 saniye icinde /health 200 UP donmedi."
}

$summary = [ordered]@{
    status = "RUNNING"
    pid = $proc.Id
    tcp_port = $TcpPort
    udp_port = $UdpPort
    lan_ip = $lanIp
    local_https_url = "https://127.0.0.1:$TcpPort"
    lan_https_url = if ($lanIp) { "https://${lanIp}:$TcpPort" } else { $null }
    test_db_path = (Join-Path $dataDir "market_master_test.db")
    ca_cert_path = $caCrt
    config_path = $cfgPath
    health_response = ($healthBody | ConvertFrom-Json)
}
Write-Output ($summary | ConvertTo-Json -Depth 6)
