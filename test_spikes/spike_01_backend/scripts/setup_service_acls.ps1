# setup_service_acls.ps1 - Market MMS Service SID & Temel NTFS ACL Betigi (v2.1)
[CmdletBinding()]
param(
    [string]$BaseDir = "$env:ProgramData\MarketMMS",
    [string]$ServiceName = "MarketMMSService",
    [string]$ServiceSid = "",
    [switch]$TestSandboxMode
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS - NTFS Guvenlik ve Erisim Kontrol Betigi" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

function Invoke-AclCommand {
    param([string]$cmd, [string[]]$cmdArgs)
    $rawOut = & $cmd @cmdArgs 2>&1
    $ec = $LASTEXITCODE
    if ($ec -ne 0) {
        $outText = if ($null -ne $rawOut) { ($rawOut | ForEach-Object { "$_" }) -join " | " } else { "" }
        throw "Komut basarisiz oldu ($cmd $($cmdArgs -join ' ')) - Cikis Kodu: $ec - Cikti: $outText"
    }
}

function Resolve-ServiceSidValue {
    param(
        [string]$TargetServiceName,
        [string]$ExplicitServiceSid = ""
    )

    $ciOpts = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    if (-not [string]::IsNullOrWhiteSpace($ExplicitServiceSid)) {
        $trimmed = $ExplicitServiceSid.Trim().TrimStart('*')
        if ([regex]::IsMatch($trimmed, '^S-1-\d+(?:-\d+)+$', $ciOpts)) {
            return $trimmed
        }
        throw "HATA: Gecersiz ServiceSid parametresi: $ExplicitServiceSid"
    }

    if ([string]::IsNullOrWhiteSpace($TargetServiceName)) {
        throw "HATA: ServiceName bos olamaz."
    }

    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount("NT SERVICE\$TargetServiceName")
        $sidObj = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        if ($null -ne $sidObj -and -not [string]::IsNullOrWhiteSpace($sidObj.Value)) {
            return $sidObj.Value
        }
    }
    catch {
        # Fallback to deterministic sc.exe showsid below when service is not yet registered in SCM.
    }

    try {
        $scOut = & sc.exe showsid $TargetServiceName 2>&1
        if ($LASTEXITCODE -eq 0 -and $null -ne $scOut) {
            foreach ($line in $scOut) {
                $m = [regex]::Match("$line", '\b(S-1-5-80(?:-\d+){5})\b', $ciOpts)
                if ($m.Success) {
                    return $m.Groups[1].Value
                }
            }
        }
    }
    catch {
        # Throw deterministic fail-closed error below.
    }

    throw "HATA: Service SID cozumlenemedi: $TargetServiceName"
}

function Get-AceSidString {
    param([System.Security.Principal.IdentityReference]$IdentityRef)
    if ($null -eq $IdentityRef) { return "" }
    if ($IdentityRef -is [System.Security.Principal.SecurityIdentifier]) {
        return $IdentityRef.Value
    }
    try {
        return $IdentityRef.Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        return $IdentityRef.Value
    }
}

function Assert-NoReparsePointsInTree {
    param([string]$RootPath)
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return
    }
    $rootItem = Get-Item -LiteralPath $RootPath -Force -ErrorAction Stop
    if ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "GUVENLIK IHLALI: Kok dizinin kendisi reparse point veya junction! Konum: $($rootItem.FullName)"
    }
    $allItems = Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction Stop
    foreach ($item in $allItems) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "GUVENLIK IHLALI: Dizin agacinda reparse point veya junction tespit edildi! Konum: $($item.FullName)"
        }
    }
}

# 0. Yonetici Haklari ve Sandbox Guvenlik Denetimi
$curIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$curUserSid = $curIdentity.User.Value
$isAdmin = ([Security.Principal.WindowsPrincipal]$curIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($TestSandboxMode) {
    $progDataFull = [System.IO.Path]::GetFullPath($env:ProgramData).TrimEnd('\')
    $baseFull = [System.IO.Path]::GetFullPath($BaseDir).TrimEnd('\')
    if ($baseFull.Equals($progDataFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $baseFull.StartsWith($progDataFull + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "GUVENLIK IHLALI: TestSandboxMode gercek ProgramData altinda calistirilamaz: $BaseDir"
    }
}
elseif (-not $isAdmin) {
    throw "HATA: Bu betik yerel Yonetici (Administrator) yetkisiyle calistirilmalidir!"
}

# 1. Reparse Point / Junction / Symlink Denetimi (Adim 1 - Fail-Closed)
Write-Host "[1/7] Reparse Point / Junction denetimi yapiliyor..." -ForegroundColor Yellow
Assert-NoReparsePointsInTree -RootPath $BaseDir
Write-Host "  -> Reparse point denetimi temiz." -ForegroundColor Green

# 2. ca.key Guvenlik Denetimi (Adim 2 - Fail-Closed)
Write-Host "[2/7] ca.key dosya taramasi yapiliyor..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $BaseDir) {
    $caKeys = Get-ChildItem -LiteralPath $BaseDir -Filter "ca.key" -Recurse -Force -ErrorAction Stop
    if ($caKeys -and $caKeys.Count -gt 0) {
        throw "KRITIK GUVENLIK IHLALI: ca.key dosyasi sunucu dizininde bulundu! Konum: $($caKeys[0].FullName)"
    }
}
Write-Host "  -> ca.key denetimi temiz (Disk uzerinde ca.key yok)." -ForegroundColor Green

# 3. Service SID Belirleme
Write-Host "[3/7] Service SID cozumleniyor: $ServiceName ..." -ForegroundColor Yellow
$serviceSidValue = Resolve-ServiceSidValue -TargetServiceName $ServiceName -ExplicitServiceSid $ServiceSid
$sidTarget = "*$serviceSidValue"
Write-Host "  -> Service SID cozuldu: $sidTarget" -ForegroundColor Green

$isSidMappedInLsa = $false
try {
    $null = (New-Object System.Security.Principal.SecurityIdentifier($serviceSidValue)).Translate([System.Security.Principal.NTAccount])
    $isSidMappedInLsa = $true
}
catch {
    $isSidMappedInLsa = $false
}

# Sabit SID Tanimlari
$sidSystem = "*S-1-5-18"
$sidAdmin = "*S-1-5-32-544"
$sidUsers = "*S-1-5-32-545"

# 4. Dizin Yapisi Olusturma
Write-Host "[4/7] Dizin yapisi hazirlaniyor: $BaseDir ..." -ForegroundColor Yellow
$dirs = @("bin", "bin\broker", "bin\lib", "lib", "config", "certs", "data", "security", "logs", "backups", "run")
if (-not (Test-Path -LiteralPath $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}
foreach ($d in $dirs) {
    $p = Join-Path $BaseDir $d
    if (-not (Test-Path -LiteralPath $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}
Assert-NoReparsePointsInTree -RootPath $BaseDir
Write-Host "  -> 11 standart alt dizin hazirlandi." -ForegroundColor Green

# 5. Sahiplik Atama (Bos ACL penceresi olusturmadan guvenli takeown)
Write-Host "[5/7] Sahiplik ataniyor (reparse-point atlanarak)..." -ForegroundColor Yellow
if ($TestSandboxMode) {
    Invoke-AclCommand "takeown.exe" @("/F", $BaseDir, "/R", "/D", "Y", "/SKIPSL")
}
else {
    Invoke-AclCommand "takeown.exe" @("/F", $BaseDir, "/A", "/R", "/D", "Y", "/SKIPSL")
}
Write-Host "  -> Sahiplik basariyla yapilandirildi." -ForegroundColor Green

# 6. Service SID ve Traverse Tabanli Izinlerin Atomik Uygulanmasi
Write-Host "[6/7] NTFS ACL izin matrisi uygulaniyor..." -ForegroundColor Yellow

function Get-FilteredRemoveSids {
    param(
        [System.Security.AccessControl.FileSystemSecurity]$AclObj
    )
    $mappedRemove = New-Object System.Collections.Generic.List[string]
    $unmappedPurge = New-Object System.Collections.Generic.List[string]
    $seenMapped = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    $seenUnmapped = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($ace in $AclObj.Access) {
        if ($ace.IsInherited) {
            continue
        }
        $sidStr = Get-AceSidString -IdentityRef $ace.IdentityReference
        if ([string]::IsNullOrWhiteSpace($sidStr) -or -not $sidStr.StartsWith("S-1-")) {
            continue
        }
        $canTranslate = $false
        try {
            $null = (New-Object System.Security.Principal.SecurityIdentifier($sidStr)).Translate([System.Security.Principal.NTAccount])
            $canTranslate = $true
        } catch {
            $canTranslate = $false
        }
        if ($canTranslate) {
            if ($seenMapped.Add($sidStr)) { $mappedRemove.Add($sidStr) }
        } else {
            if ($seenUnmapped.Add($sidStr)) { $unmappedPurge.Add($sidStr) }
        }
    }
    return @{
        MappedRemove  = $mappedRemove.ToArray()
        UnmappedPurge = $unmappedPurge.ToArray()
    }
}

function Set-ProtectedDirectoryAcl {
    param(
        [string]$TargetPath,
        [ValidateSet("X", "RX", "M", "R")][string]$ServiceRights,
        [ValidateSet("", "X", "RX")][string]$UsersRights = "",
        [switch]$ResetRecursive,
        [switch]$SkipReset
    )

    $removeExplicitSids = @()
    $unmappedPurgeSids = @()
    if ($ResetRecursive) {
        Invoke-AclCommand "icacls.exe" @($TargetPath, "/reset", "/T", "/C", "/Q")
    }
    elseif (-not $SkipReset) {
        # Root directory: avoid icacls /reset (which briefly re-enables C:\ProgramData inheritance).
        # Instead collect explicit mapped SIDs for /remove and explicit unmapped SIDs for .NET PurgeAccessRules.
        $diExisting = New-Object System.IO.DirectoryInfo($TargetPath)
        $dsExisting = $diExisting.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $rmInfo = Get-FilteredRemoveSids -AclObj $dsExisting
        $removeExplicitSids = $rmInfo.MappedRemove
        $unmappedPurgeSids = $rmInfo.UnmappedPurge
    }

    $icaclsArgs = New-Object System.Collections.Generic.List[string]
    $icaclsArgs.Add($TargetPath)
    $icaclsArgs.Add("/inheritance:r")
    foreach ($rmSid in $removeExplicitSids) {
        if ($rmSid -eq "S-1-5-18" -or $rmSid -eq "S-1-5-32-544") {
            continue
        }
        if ($TestSandboxMode -and $rmSid -eq $curUserSid) {
            continue
        }
        $icaclsArgs.Add("/remove")
        $icaclsArgs.Add("*$rmSid")
    }
    $icaclsArgs.Add("/grant:r")
    $icaclsArgs.Add("${sidSystem}:(OI)(CI)F")
    $icaclsArgs.Add("/grant:r")
    $icaclsArgs.Add("${sidAdmin}:(OI)(CI)F")

    if ($TestSandboxMode -and -not [string]::IsNullOrWhiteSpace($curUserSid) -and
        $curUserSid -ne "S-1-5-18" -and $curUserSid -ne "S-1-5-32-544") {
        $icaclsArgs.Add("/grant:r")
        $icaclsArgs.Add("*${curUserSid}:(OI)(CI)F")
    }

    if ($isSidMappedInLsa) {
        $svcSpec = switch ($ServiceRights) {
            "X" { "(X)" }
            "RX" { "(OI)(CI)RX" }
            "M" { "(OI)(CI)M" }
            "R" { "(OI)(CI)R" }
        }
        $icaclsArgs.Add("/grant:r")
        $icaclsArgs.Add("${sidTarget}:${svcSpec}")
    }

    if (-not [string]::IsNullOrWhiteSpace($UsersRights)) {
        $usersSpec = switch ($UsersRights) {
            "X" { "(X)" }
            "RX" { "(OI)(CI)RX" }
        }
        $icaclsArgs.Add("/grant:r")
        $icaclsArgs.Add("${sidUsers}:${usersSpec}")
    }

    $icaclsArgs.Add("/C")
    $icaclsArgs.Add("/Q")
    Invoke-AclCommand "icacls.exe" $icaclsArgs.ToArray()

    if ($unmappedPurgeSids.Count -gt 0 -or -not $isSidMappedInLsa) {
        # Purge any explicit unmapped/orphaned SIDs and apply unmapped Service SID cleanly via .NET DirectorySecurity.
        $di = New-Object System.IO.DirectoryInfo($TargetPath)
        $ds = $di.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($uSid in $unmappedPurgeSids) {
            if ($uSid -ne "S-1-5-18" -and $uSid -ne "S-1-5-32-544" -and (-not $TestSandboxMode -or $uSid -ne $curUserSid)) {
                $ds.PurgeAccessRules((New-Object System.Security.Principal.SecurityIdentifier($uSid)))
            }
        }
        if (-not $isSidMappedInLsa) {
            $svcSidObj = New-Object System.Security.Principal.SecurityIdentifier($serviceSidValue)
            switch ($ServiceRights) {
                "X" {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $svcSidObj,
                        [System.Security.AccessControl.FileSystemRights]::ExecuteFile,
                        [System.Security.AccessControl.InheritanceFlags]::None,
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                "RX" {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $svcSidObj,
                        [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                "M" {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $svcSidObj,
                        [System.Security.AccessControl.FileSystemRights]::Modify,
                        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
                "R" {
                    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                        $svcSidObj,
                        [System.Security.AccessControl.FileSystemRights]::Read,
                        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                        [System.Security.AccessControl.PropagationFlags]::None,
                        [System.Security.AccessControl.AccessControlType]::Allow
                    )
                }
            }
            $ds.SetAccessRule($rule)
        }
        $di.SetAccessControl($ds)
    }
}

function Set-ProtectedAdminSecretFileAcl {
    param([string]$SecretFilePath)

    if (-not (Test-Path -LiteralPath $SecretFilePath -PathType Leaf)) {
        return
    }
    $fi = New-Object System.IO.FileInfo($SecretFilePath)
    if ($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "GUVENLIK IHLALI: admin_secret.txt reparse point olamaz: $SecretFilePath"
    }

    $fsExisting = $fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    $rmFileInfo = Get-FilteredRemoveSids -AclObj $fsExisting
    $removeSids = $rmFileInfo.MappedRemove
    $unmappedFilePurge = $rmFileInfo.UnmappedPurge

    $icaclsFileArgs = New-Object System.Collections.Generic.List[string]
    $icaclsFileArgs.Add($SecretFilePath)
    $icaclsFileArgs.Add("/inheritance:r")
    foreach ($rmSid in $removeSids) {
        if ($rmSid -eq "S-1-5-18" -or $rmSid -eq "S-1-5-32-544") {
            continue
        }
        if ($TestSandboxMode -and $rmSid -eq $curUserSid) {
            continue
        }
        $icaclsFileArgs.Add("/remove")
        $icaclsFileArgs.Add("*$rmSid")
    }
    $icaclsFileArgs.Add("/grant:r")
    $icaclsFileArgs.Add("${sidSystem}:F")
    $icaclsFileArgs.Add("/grant:r")
    $icaclsFileArgs.Add("${sidAdmin}:F")

    if ($TestSandboxMode -and -not [string]::IsNullOrWhiteSpace($curUserSid) -and
        $curUserSid -ne "S-1-5-18" -and $curUserSid -ne "S-1-5-32-544") {
        $icaclsFileArgs.Add("/grant:r")
        $icaclsFileArgs.Add("*${curUserSid}:F")
    }

    if ($isSidMappedInLsa) {
        $icaclsFileArgs.Add("/grant:r")
        $icaclsFileArgs.Add("${sidTarget}:R")
    }

    $icaclsFileArgs.Add("/C")
    $icaclsFileArgs.Add("/Q")
    Invoke-AclCommand "icacls.exe" $icaclsFileArgs.ToArray()

    if ($unmappedFilePurge.Count -gt 0 -or -not $isSidMappedInLsa) {
        $fiReload = New-Object System.IO.FileInfo($SecretFilePath)
        $fs = $fiReload.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($uSid in $unmappedFilePurge) {
            if ($uSid -ne "S-1-5-18" -and $uSid -ne "S-1-5-32-544" -and (-not $TestSandboxMode -or $uSid -ne $curUserSid)) {
                $fs.PurgeAccessRules((New-Object System.Security.Principal.SecurityIdentifier($uSid)))
            }
        }
        if (-not $isSidMappedInLsa) {
            $svcSidObj = New-Object System.Security.Principal.SecurityIdentifier($serviceSidValue)
            $fs.PurgeAccessRules($svcSidObj)
            $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $svcSidObj,
                [System.Security.AccessControl.FileSystemRights]::Read,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $fs.SetAccessRule($readRule)
        }
        $fiReload.SetAccessControl($fs)
    }
}

# Kok dizin: System F, Admin F, Service SID Traverse (X), Users Traverse (X) (kalitim yok)
Set-ProtectedDirectoryAcl -TargetPath $BaseDir -ServiceRights "X" -UsersRights "X"

# bin/: Users Traverse Only ((X)), Service SID RX (bin\lib mirasi dahil; onceden kalma explicit ACE'ler /reset /T ile temizlenir)
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\bin" -ServiceRights "RX" -UsersRights "X" -ResetRecursive

# bin/broker/: Users Read & Execute (RX), Service SID RX
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\bin\broker" -ServiceRights "RX" -UsersRights "RX" -ResetRecursive

# lib/ (Dart native assets sqlite3.dll): Service SID Read & Execute (RX), Users ERISIM YOK
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\lib" -ServiceRights "RX" -ResetRecursive

# data/, logs/, backups/, run/, security/: Service SID Modify (M), Users ERISIM YOK
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\data" -ServiceRights "M" -ResetRecursive
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\logs" -ServiceRights "M" -ResetRecursive
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\backups" -ServiceRights "M" -ResetRecursive
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\run" -ServiceRights "M" -ResetRecursive
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\security" -ServiceRights "M" -ResetRecursive

# M-4: security/ altinda admin_secret.txt varsa (standalone calistirma dahil) ServiceSID icin yalniz Read (R) kilitle
$adminSecretPath = Join-Path $BaseDir "security\admin_secret.txt"
Set-ProtectedAdminSecretFileAcl -SecretFilePath $adminSecretPath

# config/, certs/: Service SID Read (R), Users ERISIM YOK
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\config" -ServiceRights "R" -ResetRecursive
Set-ProtectedDirectoryAcl -TargetPath "$BaseDir\certs" -ServiceRights "R" -ResetRecursive

Write-Host "  -> Izin matrisi basariyla uygulandi." -ForegroundColor Green

# 7. Bildirimsel SID Denetimi (Self-Check)
Write-Host "[7/7] Bildirimsel SID denetimi yapiliyor..." -ForegroundColor Yellow
$forbiddenCriticalSids = @("S-1-5-32-545", "S-1-1-0", "S-1-5-11", "S-1-5-7", "S-1-5-4", "S-1-5-32-546")
$forbiddenBroadSids = @("S-1-1-0", "S-1-5-11", "S-1-5-7", "S-1-5-4", "S-1-5-32-546")
$fullControlMask = 0x001F01FF
$traverseOnlyMask = 0x00100020
$readOnlyRequiredMask = 0x00020089
$disallowedWriteMask = 0x500D0156

$explicitProtectedCriticalPaths = @(
    "$BaseDir\data",
    "$BaseDir\config",
    "$BaseDir\certs",
    "$BaseDir\security",
    "$BaseDir\backups",
    "$BaseDir\run",
    "$BaseDir\logs",
    "$BaseDir\lib"
)
$inheritedCriticalPaths = @(
    "$BaseDir\bin\lib"
)
$allCriticalChecks = @()
foreach ($p in $explicitProtectedCriticalPaths) { $allCriticalChecks += @{ Path = $p; RequireProtected = $true } }
foreach ($p in $inheritedCriticalPaths) { $allCriticalChecks += @{ Path = $p; RequireProtected = $false } }

foreach ($entry in $allCriticalChecks) {
    $p = $entry.Path
    $diCheck = New-Object System.IO.DirectoryInfo($p)
    $acl = $diCheck.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    if ($entry.RequireProtected -and -not $acl.AreAccessRulesProtected) {
        throw "GUVENLIK IHLALI: $p dizininde ACL kalitimi kapatilmamis!"
    }
    $hasSysFull = $false
    $hasAdmFull = $false
    $hasSvcAce = $false
    foreach ($access in $acl.Access) {
        $sidVal = Get-AceSidString -IdentityRef $access.IdentityReference
        if ($forbiddenCriticalSids -contains $sidVal) {
            throw "GUVENLIK IHLALI: $p dizininde yetkisiz SID izni tespit edildi: $sidVal"
        }
        $mask = [int]$access.FileSystemRights
        $isNonInheritOnly = ($access.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) -eq 0
        if ($access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and $isNonInheritOnly) {
            if ($sidVal -eq "S-1-5-18" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $hasSysFull = $true }
            if ($sidVal -eq "S-1-5-32-544" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $hasAdmFull = $true }
            if ($sidVal.Equals($serviceSidValue, [System.StringComparison]::OrdinalIgnoreCase)) { $hasSvcAce = $true }
        }
    }
    if (-not ($hasSysFull -and $hasAdmFull -and $hasSvcAce)) {
        throw "GUVENLIK IHLALI: $p dizininde zorunlu SYSTEM/Administrators/ServiceSID izinleri eksik (Sys=$hasSysFull, Adm=$hasAdmFull, Svc=$hasSvcAce)."
    }
}

foreach ($travPath in @($BaseDir, "$BaseDir\bin")) {
    $diTrav = New-Object System.IO.DirectoryInfo($travPath)
    $aclTrav = $diTrav.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    if (-not $aclTrav.AreAccessRulesProtected) {
        throw "GUVENLIK IHLALI: $travPath dizininde ACL kalitimi kapatilmamis!"
    }
    $hasSysFull = $false
    $hasAdmFull = $false
    $hasSvcAce = $false
    foreach ($access in $aclTrav.Access) {
        $sidVal = Get-AceSidString -IdentityRef $access.IdentityReference
        $mask = [int]$access.FileSystemRights
        if ($forbiddenBroadSids -contains $sidVal) {
            throw "GUVENLIK IHLALI: $travPath dizininde yetkisiz genis SID izni tespit edildi: $sidVal"
        }
        if ($sidVal -eq "S-1-5-32-545" -and $access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            if ($access.InheritanceFlags -ne [System.Security.AccessControl.InheritanceFlags]::None -or
                $access.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None -or
                (($mask -band (-bnot $traverseOnlyMask)) -ne 0)) {
                throw "GUVENLIK IHLALI: $travPath dizininde Users ACE traverse-only/non-inheriting degil (Mask=$mask, Inh=$($access.InheritanceFlags), Prop=$($access.PropagationFlags))."
            }
        }
        if ($access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            if ($sidVal -eq "S-1-5-18" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $hasSysFull = $true }
            if ($sidVal -eq "S-1-5-32-544" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $hasAdmFull = $true }
            if ($sidVal.Equals($serviceSidValue, [System.StringComparison]::OrdinalIgnoreCase)) { $hasSvcAce = $true }
        }
    }
    if (-not ($hasSysFull -and $hasAdmFull -and $hasSvcAce)) {
        throw "GUVENLIK IHLALI: $travPath dizininde zorunlu SYSTEM/Administrators/ServiceSID izinleri eksik (Sys=$hasSysFull, Adm=$hasAdmFull, Svc=$hasSvcAce)."
    }
}

# L-1: bin\broker dizini korumali DACL, genis SID yoksullugu ve Users write yoksullugu denetimi
$diBroker = New-Object System.IO.DirectoryInfo("$BaseDir\bin\broker")
$aclBroker = $diBroker.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
if (-not $aclBroker.AreAccessRulesProtected) {
    throw "GUVENLIK IHLALI: $BaseDir\bin\broker dizininde ACL kalitimi kapatilmamis!"
}
$brokerSys = $false
$brokerAdm = $false
$brokerSvc = $false
foreach ($access in $aclBroker.Access) {
    $sidVal = Get-AceSidString -IdentityRef $access.IdentityReference
    $mask = [int]$access.FileSystemRights
    if ($forbiddenBroadSids -contains $sidVal) {
        throw "GUVENLIK IHLALI: $BaseDir\bin\broker dizininde yetkisiz genis SID izni: $sidVal"
    }
    if ($sidVal -eq "S-1-5-32-545" -and $access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
        if (($mask -band $disallowedWriteMask) -ne 0) {
            throw "GUVENLIK IHLALI: $BaseDir\bin\broker dizininde Users yazma izni tespit edildi (Mask=$mask)."
        }
    }
    if ($access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
        if ($sidVal -eq "S-1-5-18" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $brokerSys = $true }
        if ($sidVal -eq "S-1-5-32-544" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $brokerAdm = $true }
        if ($sidVal.Equals($serviceSidValue, [System.StringComparison]::OrdinalIgnoreCase)) { $brokerSvc = $true }
    }
}
if (-not ($brokerSys -and $brokerAdm -and $brokerSvc)) {
    throw "GUVENLIK IHLALI: $BaseDir\bin\broker dizininde zorunlu izinler eksik."
}

# M-4: admin_secret.txt (varsa) salt-okunur ServiceSID ve Users yoksullugu denetimi
if (Test-Path -LiteralPath $adminSecretPath -PathType Leaf) {
    $fiSec = New-Object System.IO.FileInfo($adminSecretPath)
    $aclSec = $fiSec.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
    if (-not $aclSec.AreAccessRulesProtected) {
        throw "GUVENLIK IHLALI: $adminSecretPath dosyasinda ACL kalitimi kapatilmamis!"
    }
    $secSysFull = $false
    $secAdmFull = $false
    $secSvcReadOnly = $false
    foreach ($access in $aclSec.Access) {
        $sidVal = Get-AceSidString -IdentityRef $access.IdentityReference
        $mask = [int]$access.FileSystemRights
        if ($forbiddenCriticalSids -contains $sidVal) {
            throw "GUVENLIK IHLALI: $adminSecretPath dosyasinda yetkisiz SID izni: $sidVal"
        }
        if ($access.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow) {
            if ($sidVal -eq "S-1-5-18" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $secSysFull = $true }
            if ($sidVal -eq "S-1-5-32-544" -and (($mask -band $fullControlMask) -eq $fullControlMask)) { $secAdmFull = $true }
            if ($sidVal.Equals($serviceSidValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (($mask -band $disallowedWriteMask) -ne 0) {
                    throw "GUVENLIK IHLALI: $adminSecretPath uzerinde ServiceSID icin yazma/degistirme hakki yasaktir (Mask=$mask)."
                }
                if (($mask -band $readOnlyRequiredMask) -eq $readOnlyRequiredMask) {
                    $secSvcReadOnly = $true
                }
            }
        }
    }
    if (-not ($secSysFull -and $secAdmFull -and $secSvcReadOnly)) {
        throw "GUVENLIK IHLALI: $adminSecretPath zorunlu SYSTEM/Admins/ServiceSID(ReadOnly) denetimini gecemedi (Sys=$secSysFull, Adm=$secAdmFull, SvcRead=$secSvcReadOnly)."
    }
}

Write-Host "  -> Tum kritik dizinler standart kullanici erisimine kapatildi ve ServiceSID/ACL self-check gecti!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS NTFS ACL Yapilandirmasi Tamamlandi!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
