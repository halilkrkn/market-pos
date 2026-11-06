# setup_service_acls.ps1 — Market MMS Service SID & Temel NTFS ACL Betigi (v2.0)
[CmdletBinding()]
param(
    [string]$BaseDir = "$env:ProgramData\MarketMMS",
    [string]$ServiceName = "MarketMMSService",
    [string]$ServiceSid = ""
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS — NTFS Guvenlik ve Erisim Kontrol Betigi" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 0. Yonetici Haklari Denetimi
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$isAdmin) {
    throw "HATA: Bu betik yerel Yonetici (Administrator) yetkisiyle calistirilmalidir!"
}

function Invoke-AclCommand {
    param([string]$cmd, [string[]]$cmdArgs)
    $p = Start-Process -FilePath $cmd -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "Komut basarisiz oldu ($cmd $($cmdArgs -join ' ')) - Cikis Kodu: $($p.ExitCode)"
    }
}

# 1. Reparse Point / Junction / Symlink Denetimi (Adim 1 - Fail-Closed)
Write-Host "[1/7] Reparse Point / Junction denetimi yapiliyor..." -ForegroundColor Yellow
if (Test-Path $BaseDir) {
    $allItems = Get-ChildItem -Path $BaseDir -Recurse -Force -ErrorAction Stop
    foreach ($item in $allItems) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "GUVENLIK IHLALI: Dizin agacinda reparse point veya junction tespit edildi! Konum: $($item.FullName)"
        }
    }
}
Write-Host "  -> Reparse point denetimi temiz." -ForegroundColor Green

# 2. ca.key Guvenlik Denetimi (Adim 2 - Fail-Closed)
Write-Host "[2/7] ca.key dosya taramasi yapiliyor..." -ForegroundColor Yellow
if (Test-Path $BaseDir) {
    $caKeys = Get-ChildItem -Path $BaseDir -Filter "ca.key" -Recurse -ErrorAction Stop
    if ($caKeys -and $caKeys.Count -gt 0) {
        throw "KRITIK GUVENLIK IHLALI: ca.key dosyasi sunucu dizininde bulundu! Konum: $($caKeys[0].FullName)"
    }
}
Write-Host "  -> ca.key denetimi temiz (Disk uzerinde ca.key yok)." -ForegroundColor Green

# 3. Service SID Belirleme
Write-Host "[3/7] Service SID cozumleniyor: $ServiceName ..." -ForegroundColor Yellow
$sidTarget = ""
if (![string]::IsNullOrWhiteSpace($ServiceSid)) {
    $sidTarget = "*$ServiceSid"
    Write-Host "  -> Parametre olarak verilen Service SID kullaniliyor: $sidTarget" -ForegroundColor Green
} else {
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount("NT SERVICE\$ServiceName")
        $sidVal = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        $sidTarget = "*$sidVal"
        Write-Host "  -> Service SID basariyla cozuldu: $sidTarget" -ForegroundColor Green
    } catch {
        Write-Host "  -> NT SERVICE\$ServiceName SID dizesine cevrilemedi; doğrudan hesap adi kullanilacak." -ForegroundColor Yellow
        $sidTarget = "NT SERVICE\$ServiceName"
    }
}

# Sabit SID Tanimlari
$sidSystem = "*S-1-5-18"
$sidAdmin  = "*S-1-5-32-544"
$sidUsers  = "*S-1-5-32-545"

# 4. Dizin Yapisi Olusturma
Write-Host "[4/7] Dizin yapisi hazirlaniyor: $BaseDir ..." -ForegroundColor Yellow
$dirs = @("bin", "bin\broker", "config", "certs", "data", "security", "logs", "backups", "run")
if (!(Test-Path $BaseDir)) {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
}
foreach ($d in $dirs) {
    $p = Join-Path $BaseDir $d
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}
Write-Host "  -> 9 standart alt dizin hazirlandi." -ForegroundColor Green

# 5. Sahiplik ve Kalitim Kirma
Write-Host "[5/7] Sahiplik Administrators grubuna ataniyor ve kalitim kiriliyor..." -ForegroundColor Yellow
Invoke-AclCommand "takeown" @("/F", $BaseDir, "/A", "/D", "Y")
Invoke-AclCommand "icacls" @($BaseDir, "/reset", "/C", "/Q")
Invoke-AclCommand "icacls" @($BaseDir, "/inheritance:r", "/C", "/Q")
Write-Host "  -> Kalitim basariyla kirildi." -ForegroundColor Green

# 6. Service SID ve Traverse Tabanli Izinlerin Uygulanmasi
Write-Host "[6/7] NTFS ACL izin matrisi uygulaniyor..." -ForegroundColor Yellow

# Kok dizin: System F, Admin F, Service SID Traverse (NP)X, Users Traverse (NP)X
Invoke-AclCommand "icacls" @($BaseDir, "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant", "${sidTarget}:(NP)X", "/grant", "${sidUsers}:(NP)X")

# bin/: Users Traverse Only ((NP)X), Service SID RX
Invoke-AclCommand "icacls" @("$BaseDir\bin", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)RX", "/grant", "${sidUsers}:(NP)X")

# bin/broker/: Users Read & Execute (RX), Service SID RX
Invoke-AclCommand "icacls" @("$BaseDir\bin\broker", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)RX", "/grant:r", "${sidUsers}:(OI)(CI)RX")

# data/, logs/, backups/, run/: Service SID Modify (M), Users ERISIM YOK
Invoke-AclCommand "icacls" @("$BaseDir\data", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$BaseDir\logs", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$BaseDir\backups", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$BaseDir\run", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)M")

# config/, certs/, security/: Service SID Read (R), Users ERISIM YOK
Invoke-AclCommand "icacls" @("$BaseDir\config", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)R")
Invoke-AclCommand "icacls" @("$BaseDir\certs", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)R")
Invoke-AclCommand "icacls" @("$BaseDir\security", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "${sidTarget}:(OI)(CI)R")
Write-Host "  -> Izin matrisi basariyla uygulandi." -ForegroundColor Green

# 7. Bildirimsel SID Denetimi (Self-Check)
Write-Host "[7/7] Bildirimsel SID denetimi yapiliyor..." -ForegroundColor Yellow
$criticalPaths = @("$BaseDir\data", "$BaseDir\config", "$BaseDir\certs", "$BaseDir\security", "$BaseDir\run", "$BaseDir\logs")
foreach ($p in $criticalPaths) {
    $acl = Get-Acl -Path $p
    foreach ($access in $acl.Access) {
        $sidVal = $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($sidVal -eq "S-1-5-32-545" -or $sidVal -eq "S-1-1-0" -or $sidVal -eq "S-1-5-11") {
            throw "GUVENLIK IHLALI: $p dizininde yetkisiz SID izni tespit edildi: $sidVal"
        }
    }
}
Write-Host "  -> Tum kritik dizinler (data, config, certs, security, run, logs) standart kullanici erisimine basariyla kapatildi!" -ForegroundColor Green

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Market MMS NTFS ACL Yapilandirmasi Tamamlandi!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan

