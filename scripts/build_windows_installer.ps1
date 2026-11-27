# build_windows_installer.ps1 - Market MMS Phase C WiX MSI Kurulum Paketi Derleyicisi
# Pure ASCII (PowerShell 5.1 uyumlu).
# Mevcut test_spikes\spike_01_backend\build\spike_service.exe uzerine ASLA yazmaz.
[CmdletBinding()]
param(
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release",
    [string]$OutputDir = "dist\installer",
    [string]$StagingDir = "",
    [switch]$SkipFlutterBuild,
    [switch]$SkipBackendBuild,
    [switch]$SyntheticStagingForTest,
    [string]$OverrideVersion = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    # 1. Surumu pubspec.yaml'dan oku
    $pubspec = Get-Content -Path (Join-Path $repoRoot "pubspec.yaml") -Raw
    $verMatch = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
    if (-not $verMatch.Success) {
        throw "pubspec.yaml icinde gecerli surum bulunamadi."
    }
    $appVersion = if ([string]::IsNullOrWhiteSpace($OverrideVersion)) { $verMatch.Groups[1].Value } else { $OverrideVersion.Trim() }

    if ([string]::IsNullOrWhiteSpace($StagingDir)) {
        $StagingDir = Join-Path $repoRoot "build\installer_staging"
    }
    if (Test-Path $StagingDir) {
        Remove-Item -Path $StagingDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

    $clientOut = Join-Path $StagingDir "client"
    $hubBinOut = Join-Path $StagingDir "hub_bin"
    $hubBinLibOut = Join-Path $hubBinOut "lib"
    $hubScriptsOut = Join-Path $StagingDir "hub_scripts"
    foreach ($d in @($clientOut, $hubBinOut, $hubBinLibOut, $hubScriptsOut)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }

    if ($SyntheticStagingForTest) {
        Set-Content -Path (Join-Path $clientOut "market_pos.exe") -Value "SYNTHETIC_CLIENT_EXE" -Encoding ASCII
        Set-Content -Path (Join-Path $clientOut "flutter_windows.dll") -Value "SYNTHETIC_FLUTTER_DLL" -Encoding ASCII
        Set-Content -Path (Join-Path $hubBinOut "mms_backend.exe") -Value "SYNTHETIC_HUB_EXE" -Encoding ASCII
        Set-Content -Path (Join-Path $hubBinOut "sqlite3.dll") -Value "SYNTHETIC_SQLITE_DLL" -Encoding ASCII
        Set-Content -Path (Join-Path $hubBinOut "MarketMMSService.exe") -Value "SYNTHETIC_WINSW_EXE" -Encoding ASCII
    } else {
        # 2. Hub AOT derlemesi (izole temp dizinde; spike_service.exe'ye dokunmaz)
        $aotDir = Join-Path $env:TEMP ("mms_msi_aot_" + [guid]::NewGuid().ToString("N"))
        try {
            if (-not $SkipBackendBuild) {
                $buildAot = Join-Path $repoRoot "test_spikes\spike_01_backend\scripts\build_aot.ps1"
                New-Item -ItemType Directory -Path $aotDir -Force | Out-Null
                & powershell -NoProfile -ExecutionPolicy Bypass -File $buildAot -OutputDir $aotDir
                if ($LASTEXITCODE -ne 0) {
                    throw "Hub AOT derlemesi basarisiz oldu ($LASTEXITCODE)."
                }
                $backendSrcDir = $aotDir
            } else {
                $backendSrcDir = Join-Path $repoRoot "dist\windows_release\hub_bin"
            }

            $exeSrc = Join-Path $backendSrcDir "mms_backend.exe"
            if (-not (Test-Path $exeSrc)) {
                throw "mms_backend.exe bulunamadi: $exeSrc"
            }
            Copy-Item -Path $exeSrc -Destination (Join-Path $hubBinOut "mms_backend.exe") -Force
            $dllSrc = @((Join-Path $backendSrcDir "sqlite3.dll"), (Join-Path $backendSrcDir "lib\sqlite3.dll")) | Where-Object { Test-Path $_ } | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($dllSrc)) {
                throw "sqlite3.dll bulunamadi: $backendSrcDir"
            }
            Copy-Item -Path $dllSrc -Destination (Join-Path $hubBinOut "sqlite3.dll") -Force
            Copy-Item -Path $dllSrc -Destination (Join-Path $hubBinLibOut "sqlite3.dll") -Force
        } finally {
            if (Test-Path $aotDir) {
                Remove-Item -Path $aotDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # 3. Flutter Windows derlemesi
        if (-not $SkipFlutterBuild) {
            $modeFlag = if ($Configuration -eq "Debug") { "--debug" } else { "--release" }
            & flutter build windows $modeFlag
            if ($LASTEXITCODE -ne 0) {
                throw "Flutter Windows derlemesi basarisiz oldu ($LASTEXITCODE)."
            }
        }
        $runnerDir = Join-Path $repoRoot ("build\windows\x64\runner\{0}" -f $Configuration)
        if (-not (Test-Path (Join-Path $runnerDir "market_pos.exe"))) {
            $fallbackDir = Join-Path $repoRoot "dist\windows_release\client"
            if (Test-Path (Join-Path $fallbackDir "market_pos.exe")) {
                $runnerDir = $fallbackDir
            } else {
                throw "Flutter Windows cikti dizini bulunamadi: $runnerDir"
            }
        }
        Copy-Item -Path (Join-Path $runnerDir "*") -Destination $clientOut -Recurse -Force
    }

    # 4. Ortak WinSW, XML, config template ve kurulum betiklerini kopyala
    foreach ($wrapperName in @("MarketMMSService.exe", "MarketMMSService.xml")) {
        $src = Join-Path $repoRoot "test_spikes\spike_01_backend\service_wrapper\$wrapperName"
        if ((Test-Path $src) -and (-not (Test-Path (Join-Path $hubBinOut $wrapperName)) -or -not $SyntheticStagingForTest -or $wrapperName -eq "MarketMMSService.xml")) {
            Copy-Item -Path $src -Destination (Join-Path $hubBinOut $wrapperName) -Force
        }
    }
    $cfgExample = Join-Path $repoRoot "test_spikes\spike_01_backend\config\hub_config.example.json"
    if (Test-Path $cfgExample) {
        Copy-Item -Path $cfgExample -Destination (Join-Path $hubBinOut "hub_config.example.json") -Force
    }

    Copy-Item -Path (Join-Path $repoRoot "installer\windows\scripts\mms_installer_engine.ps1") -Destination $hubScriptsOut -Force
    Copy-Item -Path (Join-Path $repoRoot "scripts\configure_hub_firewall.ps1") -Destination $hubScriptsOut -Force
    foreach ($sName in @("setup_service_acls.ps1", "install_mms_service.ps1", "uninstall_mms_service.ps1")) {
        $sPath = Join-Path $repoRoot "test_spikes\spike_01_backend\scripts\$sName"
        if (Test-Path $sPath) {
            Copy-Item -Path $sPath -Destination $hubScriptsOut -Force
        }
    }

    # 5. GeneratedPayload.wxs olustur (tum staging alt agacini deterministik paketler)
    $wixDir = Join-Path $repoRoot "installer\windows"
    $payloadWxsPath = Join-Path $StagingDir "GeneratedPayload.wxs"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')

    $dirIndex = 0
    $dirIdMap = @{}
    $dirIdMap["client"] = "ClientFolder"
    $dirIdMap["hub_bin"] = "HubPayloadFolder"
    $dirIdMap["hub_scripts"] = "HubScriptsFolder"

    $relDirs = Get-ChildItem -Path $StagingDir -Recurse -Directory | Sort-Object FullName
    $childDirsByParent = @{}
    foreach ($d in $relDirs) {
        $rel = $d.FullName.Substring($StagingDir.Length + 1)
        if ($dirIdMap.ContainsKey($rel)) { continue }
        $dirIndex++
        $id = "Dir_$dirIndex"
        $dirIdMap[$rel] = $id
        $parentRel = Split-Path -Parent $rel
        if (-not $childDirsByParent.ContainsKey($parentRel)) {
            $childDirsByParent[$parentRel] = @()
        }
        $childDirsByParent[$parentRel] += [pscustomobject]@{
            Rel  = $rel
            Id   = $id
            Name = $d.Name
        }
    }

    function Append-DirectoryTree {
        param([string]$ParentRel, [int]$Indent)
        if (-not $childDirsByParent.ContainsKey($ParentRel)) { return }
        $pad = " " * $Indent
        foreach ($entry in $childDirsByParent[$ParentRel]) {
            $escName = [System.Security.SecurityElement]::Escape($entry.Name)
            [void]$sb.AppendLine("$pad<Directory Id=`"$($entry.Id)`" Name=`"$escName`">")
            Append-DirectoryTree -ParentRel $entry.Rel -Indent ($Indent + 2)
            [void]$sb.AppendLine("$pad</Directory>")
        }
    }

    [void]$sb.AppendLine('  <Fragment>')
    [void]$sb.AppendLine('    <DirectoryRef Id="ClientFolder">')
    Append-DirectoryTree -ParentRel "client" -Indent 6
    [void]$sb.AppendLine('    </DirectoryRef>')
    [void]$sb.AppendLine('    <DirectoryRef Id="HubPayloadFolder">')
    Append-DirectoryTree -ParentRel "hub_bin" -Indent 6
    [void]$sb.AppendLine('    </DirectoryRef>')
    [void]$sb.AppendLine('    <DirectoryRef Id="HubScriptsFolder">')
    Append-DirectoryTree -ParentRel "hub_scripts" -Indent 6
    [void]$sb.AppendLine('    </DirectoryRef>')
    [void]$sb.AppendLine('  </Fragment>')

    [void]$sb.AppendLine('  <Fragment>')
    [void]$sb.AppendLine('    <ComponentGroup Id="MmsStagingPayload">')
    $fileIdx = 0
    $allFiles = Get-ChildItem -Path $StagingDir -Recurse -File | Sort-Object FullName
    foreach ($f in $allFiles) {
        $relDir = (Split-Path -Parent $f.FullName).Substring($StagingDir.Length + 1)
        $targetDirId = $dirIdMap[$relDir]
        if ([string]::IsNullOrWhiteSpace($targetDirId)) { continue }
        $fileIdx++
        $compId = "CmpPayload_$fileIdx"
        $fileId = "FilPayload_$fileIdx"
        $escSrc = [System.Security.SecurityElement]::Escape($f.FullName)
        $escName = [System.Security.SecurityElement]::Escape($f.Name)
        [void]$sb.AppendLine("      <Component Id=`"$compId`" Directory=`"$targetDirId`" Guid=`"*`">")
        [void]$sb.AppendLine("        <File Id=`"$fileId`" Name=`"$escName`" Source=`"$escSrc`" KeyPath=`"yes`" />")
        [void]$sb.AppendLine("      </Component>")
    }
    [void]$sb.AppendLine('    </ComponentGroup>')
    [void]$sb.AppendLine('  </Fragment>')
    [void]$sb.AppendLine('</Wix>')

    Set-Content -Path $payloadWxsPath -Value $sb.ToString() -Encoding UTF8

    # 6. dotnet build ile izole gecici obj/bin dizininde WiX MSI derle (NTFS hardlink izolasyonu)
    $outTarget = if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path $repoRoot $OutputDir }
    if (-not (Test-Path $outTarget)) { New-Item -ItemType Directory -Path $outTarget -Force | Out-Null }

    $wixProj = Join-Path $wixDir "MarketMMSInstaller.wixproj"
    $wixTempRoot = Join-Path $env:TEMP ("mms_wix_build_" + [guid]::NewGuid().ToString("N"))
    $wixObjDir = ((Join-Path $wixTempRoot "obj") -replace '\\', '/') + "/"
    $wixBinDir = ((Join-Path $wixTempRoot "bin") -replace '\\', '/') + "/"
    $wixOutBuildDir = Join-Path $wixTempRoot "out"
    New-Item -ItemType Directory -Path $wixOutBuildDir -Force | Out-Null

    try {
        & dotnet build $wixProj -c $Configuration `
            "-p:MmsVersion=$appVersion" `
            "-p:MmsStagingDir=$StagingDir" `
            "-p:GeneratedPayloadWxs=$payloadWxsPath" `
            "-p:BaseIntermediateOutputPath=$wixObjDir" `
            "-p:BaseOutputPath=$wixBinDir" `
            "-p:CreateHardLinksForCopyFilesToOutputDirectoryIfPossible=false" `
            "-p:CreateHardLinksForAdditionalFilesIfPossible=false" `
            "-p:CreateHardLinksForPublishFilesIfPossible=false" `
            "-p:OutputPath=$wixOutBuildDir"
        if ($LASTEXITCODE -ne 0) {
            throw "WiX MSI derlemesi basarisiz oldu ($LASTEXITCODE)."
        }

        $builtMsi = Join-Path $wixOutBuildDir ("MarketMMS-Setup-{0}-x64.msi" -f $appVersion)
        if (-not (Test-Path -LiteralPath $builtMsi)) {
            $found = Get-ChildItem -Path $wixTempRoot -Recurse -Filter "*.msi" | Select-Object -First 1
            if ($found) {
                $builtMsi = $found.FullName
            } else {
                throw "Beklenen MSI paketi uretilemedi: $builtMsi"
            }
        }

        $expectedMsi = Join-Path $outTarget ("MarketMMS-Setup-{0}-x64.msi" -f $appVersion)
        $expectedPdb = Join-Path $outTarget ("MarketMMS-Setup-{0}-x64.wixpdb" -f $appVersion)
        foreach ($oldTarget in @($expectedMsi, $expectedPdb)) {
            if (Test-Path -LiteralPath $oldTarget) {
                Remove-Item -LiteralPath $oldTarget -Force
            }
        }
        [System.IO.File]::Copy($builtMsi, $expectedMsi, $true)

        $builtPdb = [System.IO.Path]::ChangeExtension($builtMsi, ".wixpdb")
        if (Test-Path -LiteralPath $builtPdb) {
            [System.IO.File]::Copy($builtPdb, $expectedPdb, $true)
        }
    } finally {
        if (Test-Path -LiteralPath $wixTempRoot) {
            Remove-Item -Path $wixTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $msiHash = (Get-FileHash -Path $expectedMsi -Algorithm SHA256).Hash
    Set-Content -Path (Join-Path $outTarget "SHA256SUMS.txt") -Value ("{0}  {1}" -f $msiHash, (Split-Path -Leaf $expectedMsi)) -Encoding UTF8

    Write-Host "[SUCCESS] Windows Installer MSI hazir: $expectedMsi (SHA-256: $msiHash)" -ForegroundColor Green
} finally {
    Pop-Location
}
