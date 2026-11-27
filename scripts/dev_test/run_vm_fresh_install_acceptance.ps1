# run_vm_fresh_install_acceptance.ps1 - Market MMS Turnkey Clean VM & Isolated Fresh Install Verification
# Pure ASCII (PowerShell 5.1 compatible).
# Never installs MSI onto host or touches C:\ProgramData\MarketMMS unless -LiveVmExecution -ConfirmCleanTestVm is explicitly passed with elevation.
[CmdletBinding()]
param(
    [switch]$IsolatedSandboxVerification,
    [switch]$LiveVmExecution,
    [switch]$ConfirmCleanTestVm,
    [string]$MsiPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$engineScript = Join-Path $repoRoot "installer\windows\scripts\mms_installer_engine.ps1"
$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"

if (-not $IsolatedSandboxVerification -and -not $LiveVmExecution) {
    throw "Specify either -IsolatedSandboxVerification (safe non-admin host simulation) or -LiveVmExecution -ConfirmCleanTestVm (elevated clean VM only)."
}
if ($IsolatedSandboxVerification -and $LiveVmExecution) {
    throw "Choose only one mode: -IsolatedSandboxVerification OR -LiveVmExecution."
}

function Invoke-NativeSafe {
    param([string]$Exe, [string[]]$ArgList)
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $Exe @ArgList 2>&1
        $ec = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEap
    }
    return @{ exit_code = $ec; output = ($out -join "`n") }
}

$script:MmsTlsProbeType = $null
function Load-MmsTlsProbeType {
    if ($null -ne $script:MmsTlsProbeType) { return }
    $existing = ("MmsTlsHealthProbe" -as [type])
    if ($null -ne $existing) { $script:MmsTlsProbeType = $existing; return }
    $lines = Get-Content -Path $engineScript
    $csLines = @()
    $foundHeader = $false
    $capturing = $false
    foreach ($line in $lines) {
        if (-not $foundHeader) {
            if ($line -match 'if \(-not \("MmsTlsHealthProbe"') { $foundHeader = $true }
            continue
        }
        if (-not $capturing) {
            if ($line -match 'Add-Type .* -TypeDefinition @"') { $capturing = $true }
            continue
        }
        if ($line.Trim() -eq '"@') { break }
        $csLines += $line
    }
    if ($csLines.Count -eq 0) { throw "Could not extract MmsTlsHealthProbe from $engineScript" }
    $types = Add-Type -Language CSharp -ReferencedAssemblies @("System.dll", "System.Core.dll") -TypeDefinition ($csLines -join "`r`n") -PassThru
    $script:MmsTlsProbeType = $types | Where-Object { $_.Name -eq "MmsTlsHealthProbe" } | Select-Object -First 1
    if ($null -eq $script:MmsTlsProbeType) { throw "Failed to compile MmsTlsHealthProbe type" }
}

if ($IsolatedSandboxVerification) {
    if (-not (Test-Path $openssl)) {
        throw "Git OpenSSL 3.x not found at $openssl"
    }
    Load-MmsTlsProbeType

    $simRoot = Join-Path $env:LOCALAPPDATA "MarketMMS_Isolated_Test\vm_acceptance_sim"
    $instV10 = Join-Path $simRoot "program_files_v10"
    $instV11 = Join-Path $simRoot "program_files_v11"
    $dataRoot = Join-Path $simRoot "program_data"
    $stage10 = Join-Path $simRoot "staging_v10"
    $stage11 = Join-Path $simRoot "staging_v11"
    $caScratch = Join-Path $simRoot "ca_scratch"

    $oldKey = Join-Path $dataRoot "certs\server.key"
    if (Test-Path $oldKey) {
        $null = Invoke-NativeSafe -Exe "icacls.exe" -ArgList @($oldKey, "/grant:r", ("{0}:(F)" -f "$env:USERDOMAIN\$env:USERNAME"))
    }
    if (Test-Path $simRoot) { Remove-Item -Path $simRoot -Recurse -Force }
    foreach ($d in @($simRoot, $instV10, $instV11, $dataRoot, $stage10, $stage11, $caScratch)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    # Build isolated staging payloads from current tray binaries & scripts (no host side effects)
    $trayHub = Join-Path $repoRoot "dist\windows_release_v1_0_0_tray\hub_bin"
    $trayClient = Join-Path $repoRoot "dist\windows_release_v1_0_0_tray\client"
    if (-not (Test-Path (Join-Path $trayHub "mms_backend.exe"))) {
        $trayHub = Join-Path $repoRoot "dist\windows_release\hub_bin"
        $trayClient = Join-Path $repoRoot "dist\windows_release\client"
    }
    foreach ($st in @($stage10, $stage11)) {
        foreach ($sub in @("client", "hub_bin", "hub_bin\lib", "hub_scripts")) {
            New-Item -ItemType Directory -Path (Join-Path $st $sub) -Force | Out-Null
        }
        Copy-Item (Join-Path $trayClient "market_pos.exe") (Join-Path $st "client\market_pos.exe") -Force
        Copy-Item (Join-Path $trayClient "flutter_windows.dll") (Join-Path $st "client\flutter_windows.dll") -Force
        Copy-Item (Join-Path $trayHub "mms_backend.exe") (Join-Path $st "hub_bin\mms_backend.exe") -Force
        Copy-Item (Join-Path $trayHub "sqlite3.dll") (Join-Path $st "hub_bin\sqlite3.dll") -Force
        Copy-Item (Join-Path $trayHub "sqlite3.dll") (Join-Path $st "hub_bin\lib\sqlite3.dll") -Force
        Copy-Item (Join-Path $repoRoot "test_spikes\spike_01_backend\service_wrapper\MarketMMSService.exe") (Join-Path $st "hub_bin\MarketMMSService.exe") -Force
        Copy-Item (Join-Path $repoRoot "test_spikes\spike_01_backend\service_wrapper\MarketMMSService.xml") (Join-Path $st "hub_bin\MarketMMSService.xml") -Force
        Copy-Item (Join-Path $repoRoot "test_spikes\spike_01_backend\config\hub_config.example.json") (Join-Path $st "hub_bin\hub_config.example.json") -Force
        Copy-Item (Join-Path $repoRoot "test_spikes\spike_01_backend\scripts\setup_service_acls.ps1") (Join-Path $st "hub_scripts\setup_service_acls.ps1") -Force
        Copy-Item (Join-Path $repoRoot "scripts\configure_hub_firewall.ps1") (Join-Path $st "hub_scripts\configure_hub_firewall.ps1") -Force
    }
    Add-Content -Path (Join-Path $stage11 "hub_bin\MarketMMSService.xml") -Value "<!-- sim-v1.1.0 -->" -Encoding ASCII

    $checks = New-Object System.Collections.Generic.List[object]
    function Record-Check {
        param([string]$Id, [bool]$Passed, [string]$Detail)
        $checks.Add([ordered]@{ id = $Id; status = $(if ($Passed) { "PASS" } else { "FAIL" }); detail = $Detail })
        if (-not $Passed) { throw "Check $Id failed: $Detail" }
    }

    $liveHubProc = $null
    try {
        # 1. FreshInstall v1.0.0 with deferred TLS (ports 8947/8948)
        $instRes = Invoke-NativeSafe -Exe "powershell.exe" -ArgList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engineScript,
            "-Action", "Install",
            "-InstallDir", $instV10,
            "-ProgramDataRoot", $dataRoot,
            "-StagingDir", $stage10,
            "-AppVersion", "1.0.0",
            "-Port", "8947",
            "-DiscoveryPort", "8948",
            "-AllowDeferredTlsStart", "1",
            "-TestSandboxMode"
        )
        Record-Check "SIM_01_FRESH_INSTALL_EXIT0" ($instRes.exit_code -eq 0) ("exit=$($instRes.exit_code)")

        # Verify ProgramData directory structure & key artifacts
        $requiredDirs = @("bin", "bin\broker", "bin\lib", "lib", "config", "certs", "data", "security", "logs", "backups", "run")
        $missingDirs = @($requiredDirs | Where-Object { -not (Test-Path (Join-Path $dataRoot $_)) })
        Record-Check "SIM_02_PROGRAMDATA_DIRS" ($missingDirs.Count -eq 0) ("checked=$($requiredDirs.Count), missing=$($missingDirs.Count)")

        $manifestPath = Join-Path $dataRoot "config\install_manifest.json"
        $hubCfgPath = Join-Path $dataRoot "config\hub_config.json"
        $secretPath = Join-Path $dataRoot "security\admin_secret.txt"
        $xmlPath = Join-Path $dataRoot "bin\MarketMMSService.xml"
        $scmPath = Join-Path $dataRoot "run\sandbox_scm.json"
        Record-Check "SIM_03_REQUIRED_FILES" ((Test-Path $manifestPath) -and (Test-Path $hubCfgPath) -and (Test-Path $secretPath) -and (Test-Path $xmlPath) -and (Test-Path $scmPath)) "manifest, hub_config, admin_secret, xml, scm"

        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $hubCfg = Get-Content $hubCfgPath -Raw | ConvertFrom-Json
        $scm = Get-Content $scmPath -Raw | ConvertFrom-Json
        Record-Check "SIM_04_DEFERRED_TLS_STATE" ($manifest.service_state -eq "PENDING_TLS_PROVISIONING" -and $scm.status -eq "Stopped") ("state=$($manifest.service_state), scm=$($scm.status)")
        Record-Check "SIM_05_HUB_CONFIG_PORTS" ($hubCfg.port -eq 8947 -and $hubCfg.discovery_port -eq 8948 -and $hubCfg.tls.enabled -eq $true) ("port=$($hubCfg.port), disc=$($hubCfg.discovery_port)")
        Record-Check "SIM_06_SCM_IDENTITY_STAMP" ($scm.mms_app_version -eq "1.0.0" -and -not [string]::IsNullOrWhiteSpace($scm.mms_xml_sha256)) ("ver=$($scm.mms_app_version)")
        Record-Check "SIM_07_NO_SPIKE_SERVICE" ($scm.service_name -eq "MarketMMSService" -and $null -eq (Get-Service -Name "MarketMmsSpike01" -ErrorAction SilentlyContinue)) ("service=$($scm.service_name)")

        $secretAcl = Invoke-NativeSafe -Exe "icacls.exe" -ArgList @($secretPath)
        Record-Check "SIM_08_SECRET_FILE_NONEMPTY" ((Get-Item $secretPath).Length -ge 32 -and $secretAcl.exit_code -eq 0) ("bytes=$((Get-Item $secretPath).Length)")

        # 2. Provision TEST_ONLY certs & launch live Hub from installed ProgramData\bin
        $extCnf = Join-Path $caScratch "ext.cnf"
@"
[ v3_ca ]
basicConstraints = critical, CA:TRUE
subjectKeyIdentifier = hash
keyUsage = critical, keyCertSign, cRLSign

[ v3_leaf ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:127.0.0.1,IP:10.0.2.2,DNS:localhost
"@ | Set-Content -Path $extCnf -Encoding ASCII

        $caKey = Join-Path $caScratch "ca.key"
        $caCrt = Join-Path $dataRoot "certs\ca.crt"
        $srvCsr = Join-Path $caScratch "server.csr"
        $srvKey = Join-Path $dataRoot "certs\server.key"
        $srvCrt = Join-Path $dataRoot "certs\server.crt"

        $o1 = Invoke-NativeSafe -Exe $openssl -ArgList @("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", $caKey, "-out", $caCrt, "-days", "365", "-subj", "/CN=MarketMMS-VM-Sim-CA", "-config", $extCnf, "-extensions", "v3_ca")
        $o2 = Invoke-NativeSafe -Exe $openssl -ArgList @("req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", $srvKey, "-out", $srvCsr, "-subj", "/CN=MarketMMS-VM-Sim-Hub")
        $o3 = Invoke-NativeSafe -Exe $openssl -ArgList @("x509", "-req", "-in", $srvCsr, "-CA", $caCrt, "-CAkey", $caKey, "-CAcreateserial", "-out", $srvCrt, "-days", "365", "-sha256", "-extfile", $extCnf, "-extensions", "v3_leaf")
        Record-Check "SIM_09_TLS_CERT_PROVISION" ($o1.exit_code -eq 0 -and $o2.exit_code -eq 0 -and $o3.exit_code -eq 0) "OpenSSL 3.5.9 CA + server leaf generated"

        # Verify hub_config.json works end-to-end with live mms_backend.exe
        $hubOut = Join-Path $simRoot "live_hub.stdout.log"
        $hubErr = Join-Path $simRoot "live_hub.stderr.log"
        $liveHubProc = Start-Process -FilePath (Join-Path $dataRoot "bin\mms_backend.exe") `
            -ArgumentList @("--config=$hubCfgPath") `
            -WorkingDirectory (Join-Path $dataRoot "bin") `
            -RedirectStandardOutput $hubOut -RedirectStandardError $hubErr -PassThru -WindowStyle Hidden
        $null = $liveHubProc.Handle
        $bound = $false
        $deadline = (Get-Date).AddSeconds(12)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 250
            $liveHubProc.Refresh()
            if ($liveHubProc.HasExited) { break }
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $ar = $tcp.BeginConnect("127.0.0.1", 8947, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne(200, $false)) { $tcp.EndConnect($ar); $bound = $true; break }
            } catch {} finally { $tcp.Close() }
        }
        Record-Check "SIM_10_LIVE_HUB_CONFIG_START" $bound ("pid=$($liveHubProc.Id)")

        $probeT = $script:MmsTlsProbeType
        $healthRaw = $probeT::VerifyHttpsHealth("https://127.0.0.1:8947/health", [string]$caCrt, [int]5000)
        $healthJson = $healthRaw | ConvertFrom-Json
        Record-Check "SIM_11_LIVE_TLS_HEALTH_UP" ($healthJson.status -eq "UP") ("status=$($healthJson.status)")

        Stop-Process -Id $liveHubProc.Id -Force
        $liveHubProc.WaitForExit(5000) | Out-Null
        $liveHubProc = $null

        # Preserve marker inside data & backups to prove survival through rollback and uninstall
        $liveDbPath = Join-Path $dataRoot "data\market_master.db"
        Record-Check "SIM_12_HUB_DB_INITIALIZED" (Test-Path $liveDbPath) ("bytes=$((Get-Item $liveDbPath).Length)")
        $preUpgradeSize = (Get-Item $liveDbPath).Length
        $sentinelBackup = Join-Path $dataRoot "backups\manual_sentinel.mmsbak"
        Set-Content -Path $sentinelBackup -Value "SENTINEL_BACKUP_DO_NOT_DELETE" -Encoding ASCII

        # 3. Simulated 1.1.0 Upgrade fault + Rollback verification
        $upgFail = Invoke-NativeSafe -Exe "powershell.exe" -ArgList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engineScript,
            "-Action", "Install",
            "-InstallDir", $instV11,
            "-ProgramDataRoot", $dataRoot,
            "-StagingDir", $stage11,
            "-AppVersion", "1.1.0",
            "-Port", "8947",
            "-DiscoveryPort", "8948",
            "-FaultInjectionStage", "Migration",
            "-MsiManaged",
            "-TestSandboxMode"
        )
        Record-Check "SIM_13_UPGRADE_FAULT_FAIL_CLOSED" ($upgFail.exit_code -eq 74) ("exit=$($upgFail.exit_code)")

        $rbRes = Invoke-NativeSafe -Exe "powershell.exe" -ArgList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engineScript,
            "-Action", "Rollback",
            "-InstallDir", $instV11,
            "-ProgramDataRoot", $dataRoot,
            "-AppVersion", "1.1.0",
            "-MsiManaged",
            "-TestSandboxMode"
        )
        $scmAfterRb = Get-Content $scmPath -Raw | ConvertFrom-Json
        Record-Check "SIM_14_ROLLBACK_RESTORED_V10" ($rbRes.exit_code -eq 0 -and $scmAfterRb.mms_app_version -eq "1.0.0" -and (Get-Item $liveDbPath).Length -eq $preUpgradeSize) ("rb_exit=$($rbRes.exit_code), scm_ver=$($scmAfterRb.mms_app_version)")

        # 4. Uninstall with PURGE_USER_DATA=0 -> user data survives, runtime bin removed
        $uninstRes = Invoke-NativeSafe -Exe "powershell.exe" -ArgList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engineScript,
            "-Action", "Uninstall",
            "-InstallDir", $instV10,
            "-ProgramDataRoot", $dataRoot,
            "-PurgeUserDataValue", "0",
            "-TestSandboxMode"
        )
        Record-Check "SIM_15_UNINSTALL_EXIT0" ($uninstRes.exit_code -eq 0) ("exit=$($uninstRes.exit_code)")
        Record-Check "SIM_16_UNINSTALL_PRESERVES_DATA" ((Test-Path $liveDbPath) -and (Test-Path $sentinelBackup) -and (Test-Path $secretPath) -and (Test-Path $caCrt)) "data, backups, security, certs preserved"
        Record-Check "SIM_17_UNINSTALL_REMOVES_BIN" (-not (Test-Path (Join-Path $dataRoot "bin\mms_backend.exe"))) "bin\mms_backend.exe removed"

        # 5. Clean Reinstall after Uninstall preserves existing data & certs
        $reinstRes = Invoke-NativeSafe -Exe "powershell.exe" -ArgList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $engineScript,
            "-Action", "Install",
            "-InstallDir", $instV10,
            "-ProgramDataRoot", $dataRoot,
            "-StagingDir", $stage10,
            "-AppVersion", "1.0.0",
            "-Port", "8947",
            "-DiscoveryPort", "8948",
            "-AllowDeferredTlsStart", "1",
            "-TestSandboxMode"
        )
        $reinstScm = Get-Content $scmPath -Raw | ConvertFrom-Json
        Record-Check "SIM_18_REINSTALL_EXIT0" ($reinstRes.exit_code -eq 0 -and $reinstScm.mms_app_version -eq "1.0.0") ("exit=$($reinstRes.exit_code)")
        Record-Check "SIM_19_REINSTALL_DATA_INTACT" ((Get-Item $liveDbPath).Length -eq $preUpgradeSize -and (Test-Path $sentinelBackup)) ("db=$((Get-Item $liveDbPath).Length)")

        # Host untouched final guard inside isolated mode
        $hostSvcAbsent = ($null -eq (Get-Service -Name "MarketMMSService" -ErrorAction SilentlyContinue)) -and ($null -eq (Get-Service -Name "MarketMmsSpike01" -ErrorAction SilentlyContinue))
        Record-Check "SIM_20_HOST_SERVICES_UNTOUCHED" $hostSvcAbsent "MarketMMSService and MarketMmsSpike01 both absent on host"
    }
    finally {
        if ($null -ne $liveHubProc -and -not $liveHubProc.HasExited) {
            Stop-Process -Id $liveHubProc.Id -Force -ErrorAction SilentlyContinue
            $liveHubProc.WaitForExit(5000) | Out-Null
        }
    }

    $summary = [ordered]@{
        mode = "ISOLATED_SANDBOX_VERIFICATION"
        total_checks = $checks.Count
        passed_checks = @($checks | Where-Object { $_.status -eq "PASS" }).Count
        checks = $checks
    }
    $summary | ConvertTo-Json -Depth 5 | Write-Output
    exit 0
}

# Elevated Clean VM execution branch
if (-not $ConfirmCleanTestVm) {
    throw "-LiveVmExecution requires -ConfirmCleanTestVm to guard against accidental host execution."
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "BLOCKED: -LiveVmExecution must run from an elevated Administrator PowerShell session inside a clean Windows VM/test machine."
}
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
Write-Output ("VM_HOST_MODEL={0} MANUFACTURER={1}" -f $cs.Model, $cs.Manufacturer)

if ([string]::IsNullOrWhiteSpace($MsiPath)) {
    $MsiPath = Join-Path $repoRoot "dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi"
}
if (-not (Test-Path $MsiPath)) { throw "MSI not found: $MsiPath" }

$logRoot = Join-Path $env:TEMP ("mms_vm_acceptance_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$installLog = Join-Path $logRoot "msi_install.log"
$uninstallLog = Join-Path $logRoot "msi_uninstall.log"

$installRes = Invoke-NativeSafe -Exe "msiexec.exe" -ArgList @("/i", $MsiPath, "/qn", "ALLOW_DEFERRED_TLS_START=1", "HUB_PORT=8945", "DISCOVERY_PORT=8946", "/L*v", $installLog)
if ($installRes.exit_code -ne 0) {
    throw "Live MSI install failed with exit code $($installRes.exit_code). See log: $installLog"
}

$svc = Get-Service -Name "MarketMMSService" -ErrorAction Stop
$regParams = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\MarketMMSService\Parameters" -ErrorAction Stop
$fwTcp = Get-NetFirewallRule -DisplayName "*Market MMS*" -ErrorAction SilentlyContinue
$aclData = Invoke-NativeSafe -Exe "icacls.exe" -ArgList @("$env:ProgramData\MarketMMS\data")
$aclSecret = Invoke-NativeSafe -Exe "icacls.exe" -ArgList @("$env:ProgramData\MarketMMS\security\admin_secret.txt")

Write-Output ([ordered]@{
    mode = "LIVE_VM_EXECUTION"
    msi_install_exit = $installRes.exit_code
    service_status = $svc.Status.ToString()
    scm_stamp_version = $regParams.MmsAppVersion
    scm_stamp_xml_sha256 = $regParams.MmsXmlSha256
    firewall_rules_count = @($fwTcp).Count
    data_acl_exit = $aclData.exit_code
    secret_acl_exit = $aclSecret.exit_code
    install_log = $installLog
} | ConvertTo-Json -Depth 4)

$uninstRes = Invoke-NativeSafe -Exe "msiexec.exe" -ArgList @("/x", $MsiPath, "/qn", "PURGE_USER_DATA=0", "/L*v", $uninstallLog)
if ($uninstRes.exit_code -ne 0) {
    throw "Live MSI uninstall failed with exit code $($uninstRes.exit_code). See log: $uninstallLog"
}
if (-not (Test-Path "$env:ProgramData\MarketMMS\security\admin_secret.txt")) {
    throw "Uninstall with PURGE_USER_DATA=0 did not preserve admin_secret.txt!"
}
Write-Output ("LIVE_VM_UNINSTALL_EXIT={0} LOG={1}" -f $uninstRes.exit_code, $uninstallLog)
