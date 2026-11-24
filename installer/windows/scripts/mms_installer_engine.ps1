# mms_installer_engine.ps1 - Market MMS Phase C Windows Installer Yasam Dongusu Motoru
# Pure ASCII (PowerShell 5.1+ uyumlu).
# MarketMmsSpike01 servisine ve gercek kullanici verilerine ASLA dokunmaz.
[CmdletBinding()]
param(
    [ValidateSet("Install", "Upgrade", "Repair", "Rollback", "Commit", "Uninstall", "VerifyPrerequisites")]
    [string]$Action = "Install",
    [string]$InstallDir = "$env:ProgramFiles\MarketMMS",
    [string]$ProgramDataRoot = "$env:ProgramData\MarketMMS",
    [string]$StagingDir = "",
    [string]$AppVersion = "1.0.0",
    [int]$Port = 8945,
    [int]$DiscoveryPort = 8946,
    [string]$ServiceName = "MarketMMSService",
    [switch]$PurgeUserData,
    [string]$PurgeUserDataValue = "0",
    [string]$ConfirmPurgeToken = "",
    [string]$AllowDeferredTlsStart = "1",
    [string]$HealthCheckUrl = "",
    [switch]$TestSandboxMode,
    [switch]$MsiManaged,
    [string]$MsiContext = "",
    [ValidateSet("None", "MissingRuntime", "ProgramData", "Acl", "ServiceInstall", "ServiceStart", "HealthCheck", "Migration", "UpgradeInterrupt", "UninstallService")]
    [string]$FaultInjectionStage = "None",
    [string]$SimulatedExistingServices = "",
    [string]$AclScriptPath = "",
    [string]$FirewallScriptPath = "",
    [string]$ConfigTemplatePath = ""
)

$ErrorActionPreference = "Stop"

function Normalize-InstallerPath {
    param([string]$RawPath)
    if ([string]::IsNullOrWhiteSpace($RawPath)) {
        return ""
    }
    $clean = $RawPath.Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return ""
    }
    try {
        $full = [System.IO.Path]::GetFullPath($clean)
    } catch {
        $full = $clean
    }
    if ($full.Length -gt 3) {
        $full = $full.TrimEnd('\', '/')
    }
    return $full
}

function Resolve-BundledScript {
    param(
        [string]$ExplicitPath,
        [string]$ScriptFileName
    )
    $normalizedExplicit = Normalize-InstallerPath $ExplicitPath
    if (-not [string]::IsNullOrWhiteSpace($normalizedExplicit)) {
        return $normalizedExplicit
    }
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($StagingDir)) {
        $candidates.Add((Join-Path $StagingDir ("hub_scripts\" + $ScriptFileName)))
    }
    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $candidates.Add((Join-Path $InstallDir ("hub_scripts\" + $ScriptFileName)))
    }
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $candidates.Add((Join-Path $PSScriptRoot $ScriptFileName))
    }
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand) {
            return (Normalize-InstallerPath $cand)
        }
    }
    if ($candidates.Count -gt 0) {
        return (Normalize-InstallerPath $candidates[0])
    }
    return ""
}

if (-not [string]::IsNullOrWhiteSpace($MsiContext)) {
    $ctxParts = $MsiContext.Split('|')
    $ctxMode = $ctxParts[0].Trim()
    if ($ctxMode -eq "Install") {
        if ($ctxParts.Length -ne 6) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Install MsiContext beklenen 6 alani icermiyor.")
            exit 71
        }
        $Action = "Install"
        $InstallDir = $ctxParts[1]
        $StagingDir = $ctxParts[1]
        $AppVersion = $ctxParts[2].Trim()
        $parsedPort = 0
        $parsedDiscPort = 0
        if (-not [int]::TryParse($ctxParts[3].Trim(), [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Gecersiz HUB_PORT: $($ctxParts[3])")
            exit 71
        }
        if (-not [int]::TryParse($ctxParts[4].Trim(), [ref]$parsedDiscPort) -or $parsedDiscPort -lt 1 -or $parsedDiscPort -gt 65535) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Gecersiz DISCOVERY_PORT: $($ctxParts[4])")
            exit 71
        }
        $Port = $parsedPort
        $DiscoveryPort = $parsedDiscPort
        $AllowDeferredTlsStart = $ctxParts[5].Trim()
        $MsiManaged = $true
    } elseif ($ctxMode -eq "Uninstall") {
        if ($ctxParts.Length -lt 7 -or ($ctxParts[$ctxParts.Length - 1].Trim() -ne "END")) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Uninstall MsiContext beklenen bicimde degil.")
            exit 71
        }
        $Action = "Uninstall"
        $InstallDir = $ctxParts[1]
        $parsedPort = 0
        $parsedDiscPort = 0
        if (-not [int]::TryParse($ctxParts[2].Trim(), [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Gecersiz HUB_PORT: $($ctxParts[2])")
            exit 71
        }
        if (-not [int]::TryParse($ctxParts[3].Trim(), [ref]$parsedDiscPort) -or $parsedDiscPort -lt 1 -or $parsedDiscPort -gt 65535) {
            [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Gecersiz DISCOVERY_PORT: $($ctxParts[3])")
            exit 71
        }
        $Port = $parsedPort
        $DiscoveryPort = $parsedDiscPort
        $PurgeUserDataValue = $ctxParts[4].Trim()
        $ConfirmPurgeToken = ($ctxParts[5..($ctxParts.Length - 2)] -join '|').Trim()
        $MsiManaged = $true
    } else {
        [Console]::Error.WriteLine("[ERR_INVALID_MSI_CONTEXT] Bilinmeyen MsiContext modu: $ctxMode")
        exit 71
    }
}

$InstallDir = Normalize-InstallerPath $InstallDir
$ProgramDataRoot = Normalize-InstallerPath $ProgramDataRoot
$StagingDir = Normalize-InstallerPath $StagingDir
$ConfigTemplatePath = Normalize-InstallerPath $ConfigTemplatePath

if ([string]::IsNullOrWhiteSpace($StagingDir)) {
    $StagingDir = $InstallDir
}

$AclScriptPath = Resolve-BundledScript -ExplicitPath $AclScriptPath -ScriptFileName "setup_service_acls.ps1"
$FirewallScriptPath = Resolve-BundledScript -ExplicitPath $FirewallScriptPath -ScriptFileName "configure_hub_firewall.ps1"

$AllowDeferredTlsStartBool = @("1", "true", "$true", "yes") -contains $AllowDeferredTlsStart.Trim().ToLowerInvariant()
$PurgeUserDataEffective = $PurgeUserData.IsPresent -or (@("1", "true", "$true", "yes") -contains $PurgeUserDataValue.Trim().ToLowerInvariant())

$SimulatedServicesList = @()
if (-not [string]::IsNullOrWhiteSpace($SimulatedExistingServices)) {
    $SimulatedServicesList = $SimulatedExistingServices -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

$ProtectedServices = @("MarketMmsSpike01")
$RequiredStagingClientFiles = @("market_pos.exe", "flutter_windows.dll")
$RequiredStagingHubFiles = @("mms_backend.exe", "MarketMMSService.exe", "MarketMMSService.xml", "sqlite3.dll")
$StandardProgramDataSubdirs = @("bin", "bin\broker", "bin\lib", "lib", "config", "certs", "data", "security", "logs", "backups", "run")

if (-not ("MmsTlsHealthProbe" -as [type])) {
    Add-Type -Language CSharp -ReferencedAssemblies @("System.dll", "System.Core.dll") -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography.X509Certificates;
using System.Text;

public static class MmsTlsHealthProbe
{
    private static byte[] LoadCanonicalSingleCertificateDer(string caCertPath)
    {
        if (string.IsNullOrWhiteSpace(caCertPath) || !File.Exists(caCertPath))
        {
            throw new InvalidOperationException("ERR_CA_CERT_MISSING: Root CA dosyasi bulunamadi.");
        }
        string rawText = File.ReadAllText(caCertPath, Encoding.UTF8);
        const string beginMarker = "-----BEGIN CERTIFICATE-----";
        const string endMarker = "-----END CERTIFICATE-----";
        int firstBegin = rawText.IndexOf(beginMarker, StringComparison.Ordinal);
        if (firstBegin >= 0)
        {
            int secondBegin = rawText.IndexOf(beginMarker, firstBegin + beginMarker.Length, StringComparison.Ordinal);
            if (secondBegin >= 0)
            {
                throw new InvalidOperationException("ERR_CA_CERT_MULTI_BUNDLE: Root CA dosyasinda yalnizca tek bir sertifika bulunmalidir.");
            }
            int endIdx = rawText.IndexOf(endMarker, firstBegin + beginMarker.Length, StringComparison.Ordinal);
            if (endIdx < 0)
            {
                throw new InvalidOperationException("ERR_CA_CERT_INVALID_PEM: Root CA PEM sonu bulunamadi.");
            }
            string base64Body = rawText.Substring(
                firstBegin + beginMarker.Length,
                endIdx - (firstBegin + beginMarker.Length)
            ).Replace("\r", "").Replace("\n", "").Replace(" ", "").Trim();
            return Convert.FromBase64String(base64Body);
        }
        return File.ReadAllBytes(caCertPath);
    }

    private static bool BytesEqual(byte[] left, byte[] right)
    {
        if (left == null || right == null || left.Length != right.Length) return false;
        int diff = 0;
        for (int i = 0; i < left.Length; i++)
        {
            diff |= (left[i] ^ right[i]);
        }
        return diff == 0;
    }

    private static int ReadDerLength(byte[] data, ref int idx)
    {
        if (idx >= data.Length) throw new InvalidOperationException("ASN1 EOF");
        byte first = data[idx++];
        if ((first & 0x80) == 0) return first;
        int numBytes = first & 0x7F;
        if (numBytes == 0 || numBytes > 4 || idx + numBytes > data.Length)
        {
            throw new InvalidOperationException("Invalid ASN1 length");
        }
        int len = 0;
        for (int i = 0; i < numBytes; i++)
        {
            len = (len << 8) | data[idx++];
        }
        return len;
    }

    private static bool MatchEndpointSan(X509Certificate2 leaf, string host, SslPolicyErrors sslErrors)
    {
        X509Extension sanExt = leaf.Extensions["2.5.29.17"];
        if (sanExt == null || sanExt.RawData == null || sanExt.RawData.Length < 2)
        {
            return false;
        }
        byte[] raw = sanExt.RawData;
        int idx = 0;
        if (raw[idx++] != 0x30) return false;
        int seqLen = ReadDerLength(raw, ref idx);
        int end = idx + seqLen;
        if (seqLen < 0 || end > raw.Length) return false;

        List<IPAddress> sanIps = new List<IPAddress>();
        List<string> sanDns = new List<string>();
        while (idx < end)
        {
            byte tag = raw[idx++];
            int itemLen = ReadDerLength(raw, ref idx);
            if (itemLen < 0 || idx + itemLen > end) return false;
            if (tag == 0x87 && (itemLen == 4 || itemLen == 16))
            {
                byte[] ipBytes = new byte[itemLen];
                Buffer.BlockCopy(raw, idx, ipBytes, 0, itemLen);
                sanIps.Add(new IPAddress(ipBytes));
            }
            else if (tag == 0x82 && itemLen > 0)
            {
                sanDns.Add(Encoding.ASCII.GetString(raw, idx, itemLen));
            }
            idx += itemLen;
        }

        IPAddress targetIp;
        if (IPAddress.TryParse(host, out targetIp))
        {
            foreach (IPAddress ip in sanIps)
            {
                if (ip.Equals(targetIp)) return true;
            }
            return false;
        }

        if ((sslErrors & SslPolicyErrors.RemoteCertificateNameMismatch) != 0)
        {
            return false;
        }
        foreach (string dns in sanDns)
        {
            if (string.Equals(dns, host, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static string ReadHttpResponseBody(Stream stream)
    {
        MemoryStream ms = new MemoryStream();
        byte[] buf = new byte[4096];
        int headerEnd = -1;
        while (headerEnd < 0)
        {
            int read = stream.Read(buf, 0, buf.Length);
            if (read <= 0) break;
            ms.Write(buf, 0, read);
            byte[] current = ms.ToArray();
            for (int i = 0; i <= current.Length - 4; i++)
            {
                if (current[i] == 13 && current[i + 1] == 10 && current[i + 2] == 13 && current[i + 3] == 10)
                {
                    headerEnd = i;
                    break;
                }
            }
        }
        if (headerEnd < 0)
        {
            throw new InvalidOperationException("ERR_INVALID_HTTP_RESPONSE: HTTP baslik sonu okunamadi.");
        }

        byte[] allInitial = ms.ToArray();
        string headerText = Encoding.ASCII.GetString(allInitial, 0, headerEnd);
        string[] lines = headerText.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        if (lines.Length == 0 || !lines[0].StartsWith("HTTP/", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("ERR_INVALID_HTTP_STATUS: Gecersiz HTTP durum satiri.");
        }
        string[] statusParts = lines[0].Split(' ');
        int statusCode;
        if (statusParts.Length < 2 || !int.TryParse(statusParts[1], out statusCode) || statusCode != 200)
        {
            throw new InvalidOperationException(string.Format("HTTP {0}", statusParts.Length >= 2 ? statusParts[1] : "UNKNOWN"));
        }

        int contentLength = -1;
        bool isChunked = false;
        for (int i = 1; i < lines.Length; i++)
        {
            int colon = lines[i].IndexOf(':');
            if (colon <= 0) continue;
            string name = lines[i].Substring(0, colon).Trim().ToLowerInvariant();
            string val = lines[i].Substring(colon + 1).Trim();
            if (name == "content-length")
            {
                int parsedLen;
                if (int.TryParse(val, out parsedLen) && parsedLen >= 0) contentLength = parsedLen;
            }
            else if (name == "transfer-encoding" && val.ToLowerInvariant().Contains("chunked"))
            {
                isChunked = true;
            }
        }

        MemoryStream bodyStream = new MemoryStream();
        int bodyOffset = headerEnd + 4;
        if (allInitial.Length > bodyOffset)
        {
            bodyStream.Write(allInitial, bodyOffset, allInitial.Length - bodyOffset);
        }

        if (contentLength >= 0)
        {
            while (bodyStream.Length < contentLength)
            {
                int needed = (int)Math.Min(buf.Length, contentLength - bodyStream.Length);
                int read = stream.Read(buf, 0, needed);
                if (read <= 0) break;
                bodyStream.Write(buf, 0, read);
            }
            byte[] bodyBytes = bodyStream.ToArray();
            return Encoding.UTF8.GetString(bodyBytes, 0, (int)Math.Min(contentLength, bodyBytes.Length));
        }

        while (true)
        {
            if (isChunked)
            {
                byte[] cur = bodyStream.ToArray();
                string decoded;
                if (TryDecodeChunked(cur, out decoded)) return decoded;
            }
            int read = stream.Read(buf, 0, buf.Length);
            if (read <= 0) break;
            bodyStream.Write(buf, 0, read);
        }

        byte[] finalBytes = bodyStream.ToArray();
        if (isChunked)
        {
            string decoded;
            if (TryDecodeChunked(finalBytes, out decoded)) return decoded;
        }
        return Encoding.UTF8.GetString(finalBytes);
    }

    private static bool TryDecodeChunked(byte[] raw, out string decoded)
    {
        decoded = null;
        MemoryStream outMs = new MemoryStream();
        int pos = 0;
        while (true)
        {
            int lineEnd = -1;
            for (int i = pos; i <= raw.Length - 2; i++)
            {
                if (raw[i] == 13 && raw[i + 1] == 10)
                {
                    lineEnd = i;
                    break;
                }
            }
            if (lineEnd < 0) return false;
            string sizeStr = Encoding.ASCII.GetString(raw, pos, lineEnd - pos);
            int semi = sizeStr.IndexOf(';');
            if (semi >= 0) sizeStr = sizeStr.Substring(0, semi);
            int chunkLen = Convert.ToInt32(sizeStr.Trim(), 16);
            pos = lineEnd + 2;
            if (chunkLen == 0)
            {
                decoded = Encoding.UTF8.GetString(outMs.ToArray());
                return true;
            }
            if (pos + chunkLen + 2 > raw.Length) return false;
            outMs.Write(raw, pos, chunkLen);
            pos += chunkLen + 2;
        }
    }

    public static string VerifyHttpsHealth(string url, string caCertPath, int timeoutMs)
    {
        Uri uri = new Uri(url);
        if (!string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("ERR_TLS_REQUIRED: HTTPS URL zorunludur.");
        }

        byte[] rootDer = LoadCanonicalSingleCertificateDer(caCertPath);
        X509Certificate2 rootCa = new X509Certificate2(rootDer);
        try
        {
            DateTime nowUtc = DateTime.UtcNow;
            if (nowUtc < rootCa.NotBefore.ToUniversalTime() || nowUtc > rootCa.NotAfter.ToUniversalTime())
            {
                throw new InvalidOperationException("[TLS_VALIDATION_FAILED] Root CA sertifikasinin suresi gecmis veya henuz baslamamis.");
            }
            X509BasicConstraintsExtension rootBc = null;
            foreach (X509Extension ext in rootCa.Extensions)
            {
                X509BasicConstraintsExtension candidate = ext as X509BasicConstraintsExtension;
                if (candidate != null)
                {
                    rootBc = candidate;
                    break;
                }
            }
            if (rootBc == null || !rootBc.CertificateAuthority)
            {
                throw new InvalidOperationException("[TLS_VALIDATION_FAILED] Root CA sertifikasinda CA=TRUE basicConstraints yok.");
            }

            string tlsRejectReason = null;
            TcpClient tcp = new TcpClient();
            try
            {
                tcp.ReceiveTimeout = timeoutMs;
                tcp.SendTimeout = timeoutMs;
                IAsyncResult ar = tcp.BeginConnect(uri.Host, uri.Port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(timeoutMs, false))
                {
                    throw new TimeoutException(string.Format("[SOCKET_TIMEOUT] TCP baglantisi zaman asimina ugradi: {0}:{1}", uri.Host, uri.Port));
                }
                tcp.EndConnect(ar);

                SslStream ssl = new SslStream(
                    tcp.GetStream(),
                    false,
                    delegate(object sender, X509Certificate certificate, X509Chain chainArg, SslPolicyErrors sslErrors)
                    {
                        if (certificate == null)
                        {
                            tlsRejectReason = "[TLS_VALIDATION_FAILED] Sunucu TLS sertifikasi sunmadi.";
                            return false;
                        }
                        X509Certificate2 leaf = new X509Certificate2(certificate);
                        try
                        {
                            DateTime checkNow = DateTime.UtcNow;
                            if (checkNow < leaf.NotBefore.ToUniversalTime() || checkNow > leaf.NotAfter.ToUniversalTime())
                            {
                                tlsRejectReason = "[TLS_VALIDATION_FAILED] Sunucu sertifikasinin suresi gecmis veya henuz baslamamis.";
                                return false;
                            }
                            if (!MatchEndpointSan(leaf, uri.Host, sslErrors))
                            {
                                tlsRejectReason = string.Format("[TLS_VALIDATION_FAILED] Sunucu sertifikasi SAN listesi '{0}' hedefiyle eslesmiyor.", uri.Host);
                                return false;
                            }
                            X509Chain customChain = new X509Chain();
                            customChain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                            customChain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
                            customChain.ChainPolicy.ExtraStore.Add(rootCa);
                            if (!customChain.Build(leaf))
                            {
                                tlsRejectReason = "[TLS_VALIDATION_FAILED] Ozel Root CA zinciri olusturulamadi.";
                                return false;
                            }
                            foreach (X509ChainStatus st in customChain.ChainStatus)
                            {
                                if ((st.Status & ~X509ChainStatusFlags.UntrustedRoot) != X509ChainStatusFlags.NoError)
                                {
                                    tlsRejectReason = string.Format("[TLS_VALIDATION_FAILED] Sertifika zincir hatasi: {0}", st.StatusInformation.Trim());
                                    return false;
                                }
                            }
                            if (customChain.ChainElements.Count < 2)
                            {
                                tlsRejectReason = "[TLS_VALIDATION_FAILED] Sunucu sertifikasinda ozel Root CA zinciri eksik.";
                                return false;
                            }
                            byte[] topDer = customChain.ChainElements[customChain.ChainElements.Count - 1].Certificate.RawData;
                            if (!BytesEqual(topDer, rootCa.RawData))
                            {
                                tlsRejectReason = "[TLS_VALIDATION_FAILED] Sunucu sertifikasi beklenen ozel MMS Root CA ile imzalanmamis.";
                                return false;
                            }
                            return true;
                        }
                        finally
                        {
                            leaf.Reset();
                        }
                    }
                );

                try
                {
                    ssl.ReadTimeout = timeoutMs;
                    ssl.WriteTimeout = timeoutMs;
                    SslProtocols allowedProtocols = SslProtocols.Tls12 | (SslProtocols)12288;
                    try
                    {
                        ssl.AuthenticateAsClient(uri.Host, null, allowedProtocols, false);
                    }
                    catch (Exception ex)
                    {
                        if (!string.IsNullOrEmpty(tlsRejectReason))
                        {
                            throw new AuthenticationException(tlsRejectReason, ex);
                        }
                        throw;
                    }
                    if (!string.IsNullOrEmpty(tlsRejectReason))
                    {
                        throw new AuthenticationException(tlsRejectReason);
                    }
                    if (ssl.SslProtocol != SslProtocols.Tls12 && (int)ssl.SslProtocol != 12288)
                    {
                        throw new AuthenticationException(string.Format("[TLS_VALIDATION_FAILED] Zayif TLS protokolu reddedildi: {0}", ssl.SslProtocol));
                    }

                    string reqStr = string.Format(
                        "GET {0} HTTP/1.1\r\nHost: {1}\r\nConnection: close\r\nAccept: application/json\r\n\r\n",
                        uri.PathAndQuery,
                        uri.Authority
                    );
                    byte[] reqBytes = Encoding.ASCII.GetBytes(reqStr);
                    ssl.Write(reqBytes, 0, reqBytes.Length);
                    ssl.Flush();
                    return ReadHttpResponseBody(ssl);
                }
                finally
                {
                    ssl.Dispose();
                }
            }
            finally
            {
                tcp.Close();
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

if (-not ("MmsSqliteNativeBackup" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class MmsSqliteNativeBackup
{
    private const int SQLITE_OK = 0;
    private const int SQLITE_OPEN_READONLY = 0x00000001;
    private const int SQLITE_OPEN_READWRITE = 0x00000002;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string lpFileName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr hModule);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteOpenV2Delegate(IntPtr filenameUtf8, out IntPtr ppDb, int flags, IntPtr zVfs);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteExecDelegate(IntPtr db, IntPtr sqlUtf8, SqliteExecCallback callback, IntPtr arg, out IntPtr errMsg);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteExecCallback(IntPtr arg, int colCount, IntPtr colValues, IntPtr colNames);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr SqliteErrmsgDelegate(IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteCloseV2Delegate(IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void SqliteFreeDelegate(IntPtr ptr);

    private static IntPtr AllocUtf8(string s)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(s);
        IntPtr ptr = Marshal.AllocHGlobal(bytes.Length + 1);
        Marshal.Copy(bytes, 0, ptr, bytes.Length);
        Marshal.WriteByte(ptr, bytes.Length, 0);
        return ptr;
    }

    private static string PtrToUtf8(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero) return string.Empty;
        int len = 0;
        while (Marshal.ReadByte(ptr, len) != 0) len++;
        if (len == 0) return string.Empty;
        byte[] bytes = new byte[len];
        Marshal.Copy(ptr, bytes, 0, len);
        return Encoding.UTF8.GetString(bytes);
    }

    private static T GetDelegate<T>(IntPtr hMod, string procName) where T : class
    {
        IntPtr proc = GetProcAddress(hMod, procName);
        if (proc == IntPtr.Zero)
        {
            throw new InvalidOperationException(string.Format("sqlite3 exported symbol missing: {0}", procName));
        }
        return Marshal.GetDelegateForFunctionPointer(proc, typeof(T)) as T;
    }

    private static void ExecSql(
        SqliteExecDelegate execFn,
        SqliteFreeDelegate freeFn,
        IntPtr db,
        string sql,
        List<string> firstColResults)
    {
        IntPtr sqlPtr = AllocUtf8(sql);
        IntPtr errPtr = IntPtr.Zero;
        SqliteExecCallback cb = null;
        if (firstColResults != null)
        {
            cb = delegate(IntPtr arg, int colCount, IntPtr colValues, IntPtr colNames)
            {
                if (colCount > 0 && colValues != IntPtr.Zero)
                {
                    IntPtr valPtr = Marshal.ReadIntPtr(colValues, 0);
                    firstColResults.Add(PtrToUtf8(valPtr));
                }
                return 0;
            };
        }
        try
        {
            int rc = execFn(db, sqlPtr, cb, IntPtr.Zero, out errPtr);
            if (cb != null) GC.KeepAlive(cb);
            if (rc != SQLITE_OK)
            {
                string err = PtrToUtf8(errPtr);
                throw new InvalidOperationException(string.Format("SQLite hata ({0}): {1}", rc, err));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(sqlPtr);
            if (errPtr != IntPtr.Zero)
            {
                freeFn(errPtr);
            }
        }
    }

    public static void CreateConsolidatedBackup(string sqliteDllPath, string stagedDbPath, string targetBackupPath)
    {
        IntPtr hMod = LoadLibraryW(sqliteDllPath);
        if (hMod == IntPtr.Zero)
        {
            int winErr = Marshal.GetLastWin32Error();
            throw new InvalidOperationException(string.Format("sqlite3.dll yuklenemedi ({0}): Win32={1}", sqliteDllPath, winErr));
        }
        try
        {
            SqliteOpenV2Delegate openFn = GetDelegate<SqliteOpenV2Delegate>(hMod, "sqlite3_open_v2");
            SqliteExecDelegate execFn = GetDelegate<SqliteExecDelegate>(hMod, "sqlite3_exec");
            SqliteErrmsgDelegate errFn = GetDelegate<SqliteErrmsgDelegate>(hMod, "sqlite3_errmsg");
            SqliteCloseV2Delegate closeFn = GetDelegate<SqliteCloseV2Delegate>(hMod, "sqlite3_close_v2");
            SqliteFreeDelegate freeFn = GetDelegate<SqliteFreeDelegate>(hMod, "sqlite3_free");

            if (File.Exists(targetBackupPath))
            {
                File.Delete(targetBackupPath);
            }

            IntPtr srcDb = IntPtr.Zero;
            IntPtr srcPathPtr = AllocUtf8(stagedDbPath);
            try
            {
                int rc = openFn(srcPathPtr, out srcDb, SQLITE_OPEN_READWRITE, IntPtr.Zero);
                if (rc != SQLITE_OK || srcDb == IntPtr.Zero)
                {
                    string msg = srcDb != IntPtr.Zero ? PtrToUtf8(errFn(srcDb)) : "open failed";
                    throw new InvalidOperationException(string.Format("Staging SQLite acilamadi ({0}): {1}", rc, msg));
                }
                ExecSql(execFn, freeFn, srcDb, "PRAGMA busy_timeout = 5000;", null);
                ExecSql(execFn, freeFn, srcDb, "PRAGMA wal_checkpoint(FULL);", null);
                string escapedTarget = targetBackupPath.Replace("'", "''");
                ExecSql(execFn, freeFn, srcDb, string.Format("VACUUM INTO '{0}';", escapedTarget), null);
            }
            finally
            {
                Marshal.FreeHGlobal(srcPathPtr);
                if (srcDb != IntPtr.Zero) closeFn(srcDb);
            }

            IntPtr verifyDb = IntPtr.Zero;
            IntPtr dstPathPtr = AllocUtf8(targetBackupPath);
            try
            {
                int rc = openFn(dstPathPtr, out verifyDb, SQLITE_OPEN_READONLY, IntPtr.Zero);
                if (rc != SQLITE_OK || verifyDb == IntPtr.Zero)
                {
                    string msg = verifyDb != IntPtr.Zero ? PtrToUtf8(errFn(verifyDb)) : "verify open failed";
                    throw new InvalidOperationException(string.Format("Yedek DB dogrulama icin acilamadi ({0}): {1}", rc, msg));
                }
                List<string> integrityRows = new List<string>();
                ExecSql(execFn, freeFn, verifyDb, "PRAGMA integrity_check;", integrityRows);
                if (integrityRows.Count != 1 || !string.Equals(integrityRows[0], "ok", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Pre-upgrade SQLite integrity_check basarisiz oldu.");
                }
            }
            finally
            {
                Marshal.FreeHGlobal(dstPathPtr);
                if (verifyDb != IntPtr.Zero) closeFn(verifyDb);
            }
        }
        finally
        {
            FreeLibrary(hMod);
        }
    }
}
"@
}

function Fail-Installer {
    param(
        [int]$ExitCode,
        [string]$Code,
        [string]$Message
    )
    [Console]::Error.WriteLine("[$Code] $Message")
    exit $ExitCode
}

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ServiceProtection {
    if ($ProtectedServices -contains $ServiceName) {
        Fail-Installer -ExitCode 70 -Code "ERR_PROTECTED_SERVICE_CONFLICT" `
            -Message "Hedef servis korunan '$ServiceName' olamaz."
    }
    foreach ($simSvc in $SimulatedServicesList) {
        if ($ProtectedServices -contains $simSvc) {
            Fail-Installer -ExitCode 70 -Code "ERR_PROTECTED_SERVICE_CONFLICT" `
                -Message "Korunan servis '$simSvc' algilandi; cakisma ve mudahale riski nedeniyle kurulum durduruldu (servis degistirilmedi)."
        }
    }
    if (-not $TestSandboxMode) {
        $existingProtected = Get-Service -Name "MarketMmsSpike01" -ErrorAction SilentlyContinue
        if ($existingProtected -and $existingProtected.Status -eq "Running") {
            Fail-Installer -ExitCode 70 -Code "ERR_PROTECTED_SERVICE_CONFLICT" `
                -Message "Sistemde calisan korunan 'MarketMmsSpike01' servisi mevcut. Uretim/spike cakismasini onlemek icin kurulum fail-closed durduruldu."
        }
    }
}

function Assert-StagingPrerequisites {
    param([string]$RootStaging)

    if ($FaultInjectionStage -eq "MissingRuntime") {
        Fail-Installer -ExitCode 71 -Code "ERR_MISSING_RUNTIME_ARTIFACT" `
            -Message "Simule edilmis eksik runtime hatasi: zorunlu uygulama/servis ikilisi eksik."
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        Fail-Installer -ExitCode 71 -Code "ERR_UNSUPPORTED_ARCH" `
            -Message "Market MMS yalnizca 64-bit Windows isletim sisteminde calisir."
    }
    if ([string]::IsNullOrWhiteSpace($RootStaging) -or -not (Test-Path $RootStaging)) {
        Fail-Installer -ExitCode 71 -Code "ERR_MISSING_STAGING_DIR" `
            -Message "Kurulum kaynak dizini bulunamadi: $RootStaging"
    }

    $clientSrc = Join-Path $RootStaging "client"
    foreach ($f in $RequiredStagingClientFiles) {
        $p = Join-Path $clientSrc $f
        if (-not (Test-Path $p) -or ((Get-Item $p).Length -le 0)) {
            Fail-Installer -ExitCode 71 -Code "ERR_MISSING_RUNTIME_ARTIFACT" `
                -Message "Zorunlu Windows istemci ikilisi eksik veya bos: $p"
        }
    }

    $hubSrc = Join-Path $RootStaging "hub_bin"
    foreach ($f in $RequiredStagingHubFiles) {
        $p = Join-Path $hubSrc $f
        if (-not (Test-Path $p) -or ((Get-Item $p).Length -le 0)) {
            Fail-Installer -ExitCode 71 -Code "ERR_MISSING_RUNTIME_ARTIFACT" `
                -Message "Zorunlu Hub servis ikilisi eksik veya bos: $p"
        }
    }

    if ($MsiManaged) {
        foreach ($scriptReq in @($AclScriptPath, $FirewallScriptPath)) {
            if ([string]::IsNullOrWhiteSpace($scriptReq) -or -not (Test-Path -LiteralPath $scriptReq) -or ((Get-Item -LiteralPath $scriptReq).Length -le 0)) {
                Fail-Installer -ExitCode 71 -Code "ERR_MISSING_RUNTIME_ARTIFACT" `
                    -Message "Zorunlu MSI yonetim betigi eksik veya bos: $scriptReq"
            }
        }
    }
}

function Assert-ProgramDataSafety {
    param([string]$DataRoot)
    if (-not (Test-Path $DataRoot)) { return }

    $items = Get-ChildItem -Path $DataRoot -Recurse -Force -ErrorAction Stop
    foreach ($item in $items) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            Fail-Installer -ExitCode 72 -Code "ERR_SECURITY_VIOLATION" `
                -Message "Guvenlik ihlali: Reparse point / junction tespit edildi: $($item.FullName)"
        }
    }
    $caKeys = Get-ChildItem -Path $DataRoot -Filter "ca.key" -Recurse -Force -ErrorAction SilentlyContinue
    if ($caKeys -and $caKeys.Count -gt 0) {
        Fail-Installer -ExitCode 72 -Code "ERR_SECURITY_VIOLATION" `
            -Message "Kritik guvenlik ihlali: ca.key sunucu dizininde bulunamaz: $($caKeys[0].FullName)"
    }
}

function Compare-SemVer {
    param([string]$Left, [string]$Right)
    $lVer = [Version]::Parse(($Left -replace '\+.*$', ''))
    $rVer = [Version]::Parse(($Right -replace '\+.*$', ''))
    return $lVer.CompareTo($rVer)
}

function Get-SandboxScmFile {
    param([string]$DataRoot)
    return Join-Path $DataRoot "run\sandbox_scm.json"
}

function Read-SandboxService {
    param([string]$DataRoot)
    $f = Get-SandboxScmFile $DataRoot
    if (-not (Test-Path $f)) { return $null }
    return (Get-Content -Path $f -Raw | ConvertFrom-Json)
}

function Write-SandboxService {
    param(
        [string]$DataRoot,
        [string]$Name,
        [string]$Status,
        [string]$Version,
        [string]$BinPath,
        [string]$Account = "NT AUTHORITY\LocalService",
        [string]$SidType = "UNRESTRICTED"
    )
    $f = Get-SandboxScmFile $DataRoot
    $dir = Split-Path -Parent $f
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $payload = [ordered]@{
        service_name = $Name
        status       = $Status
        version      = $Version
        bin_path     = $BinPath
        account      = $Account
        sid_type     = $SidType
        updated_at   = (Get-Date).ToUniversalTime().ToString("o")
    }
    Set-Content -Path $f -Value ($payload | ConvertTo-Json -Depth 4) -Encoding UTF8
}

function Remove-SandboxService {
    param([string]$DataRoot)
    $f = Get-SandboxScmFile $DataRoot
    if (Test-Path $f) { Remove-Item -Path $f -Force }
}

function Get-InstallerTxStateFile {
    param([string]$DataRoot)
    return Join-Path $DataRoot "run\installer_tx_state.json"
}

function Read-InstallerTxState {
    param([string]$DataRoot)
    $f = Get-InstallerTxStateFile $DataRoot
    if (-not (Test-Path $f)) { return $null }
    return (Get-Content -Path $f -Raw | ConvertFrom-Json)
}

function Write-InstallerTxState {
    param(
        [string]$DataRoot,
        [string]$Status
    )
    $f = Get-InstallerTxStateFile $DataRoot
    $dir = Split-Path -Parent $f
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $payload = [ordered]@{
        status                       = $Status
        mode                         = $script:Tx.Mode
        target_version               = $AppVersion
        previous_version             = $script:Tx.PreviousVersion
        had_existing_service         = [bool]$script:Tx.HadExistingService
        had_previous_service_running = [bool]$script:Tx.HadPreviousServiceRunning
        backed_up_bin                = [bool]$script:Tx.BackedUpBin
        backed_up_client             = [bool]$script:Tx.BackedUpClient
        backed_up_manifest           = [bool]$script:Tx.BackedUpManifest
        copied_client                = [bool]$script:Tx.CopiedClient
        copied_bin                   = [bool]$script:Tx.CopiedBin
        service_modified             = [bool]$script:Tx.ServiceModified
        manifest_written             = [bool]$script:Tx.ManifestWritten
        updated_at_utc               = (Get-Date).ToUniversalTime().ToString("o")
    }
    Set-Content -Path $f -Value ($payload | ConvertTo-Json -Depth 4) -Encoding UTF8
}

function Remove-InstallerTxArtifacts {
    param(
        [string]$TargetInstallDir,
        [string]$TargetDataRoot
    )
    $artifacts = @(
        (Join-Path $TargetDataRoot "bin.previous"),
        (Join-Path $TargetInstallDir "client.previous"),
        (Join-Path $TargetDataRoot "config\install_manifest.previous.json"),
        (Get-InstallerTxStateFile $TargetDataRoot)
    )
    foreach ($art in $artifacts) {
        if (Test-Path $art) {
            Remove-Item -Path $art -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-IsRealSqliteHeader {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
    $item = Get-Item -LiteralPath $FilePath
    if ($item.Length -lt 100) { return $false }
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        $hdr = New-Object byte[] 16
        $read = $fs.Read($hdr, 0, 16)
        if ($read -lt 16) { return $false }
        $txt = [System.Text.Encoding]::ASCII.GetString($hdr)
        return ($txt -eq "SQLite format 3`0")
    } finally {
        $fs.Dispose()
    }
}

function Test-IsPeBinary {
    param([string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath)) { return $false }
    $item = Get-Item -LiteralPath $FilePath
    if ($item.Length -le 4096) { return $false }
    $fs = [System.IO.File]::OpenRead($FilePath)
    try {
        $hdr = New-Object byte[] 2
        $read = $fs.Read($hdr, 0, 2)
        return ($read -eq 2 -and $hdr[0] -eq 0x4D -and $hdr[1] -eq 0x5A)
    } finally {
        $fs.Dispose()
    }
}

function Invoke-SafePreUpgradeSqliteBackup {
    param(
        [string]$SourceDbPath,
        [string]$TargetBackupPath,
        [string[]]$CandidateSqliteDlls
    )
    $targetDir = Split-Path -Parent $TargetBackupPath
    $stageWalDir = Join-Path $targetDir (".staging_wal_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stageWalDir -Force | Out-Null
    try {
        $stagedDb = Join-Path $stageWalDir "market_master.db"
        Copy-Item -LiteralPath $SourceDbPath -Destination $stagedDb -Force
        foreach ($suffix in @("-wal", "-shm")) {
            $sidecar = $SourceDbPath + $suffix
            if (Test-Path -LiteralPath $sidecar) {
                Copy-Item -LiteralPath $sidecar -Destination ($stagedDb + $suffix) -Force
            }
        }

        $realSqliteDll = $null
        foreach ($cand in $CandidateSqliteDlls) {
            if (Test-IsPeBinary -FilePath $cand) {
                $realSqliteDll = $cand
                break
            }
        }

        if ((Test-IsRealSqliteHeader -FilePath $stagedDb) -and (-not [string]::IsNullOrWhiteSpace($realSqliteDll))) {
            $stagedDll = Join-Path $stageWalDir "sqlite3.dll"
            Copy-Item -LiteralPath $realSqliteDll -Destination $stagedDll -Force
            [MmsSqliteNativeBackup]::CreateConsolidatedBackup($stagedDll, $stagedDb, $TargetBackupPath)
        } else {
            Copy-Item -LiteralPath $stagedDb -Destination $TargetBackupPath -Force
            foreach ($suffix in @("-wal", "-shm")) {
                $stagedSidecar = $stagedDb + $suffix
                if (Test-Path -LiteralPath $stagedSidecar) {
                    Copy-Item -LiteralPath $stagedSidecar -Destination ($TargetBackupPath + $suffix) -Force
                }
            }
        }
    } finally {
        if (Test-Path -LiteralPath $stageWalDir) {
            Remove-Item -LiteralPath $stageWalDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Apply-DirectoryAcls {
    param([string]$DataRoot)
    if ($FaultInjectionStage -eq "Acl") {
        throw "[ERR_ACL_FAILED] Simule edilmis NTFS ACL atama hatasi."
    }

    if ($TestSandboxMode) {
        $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        $sidUserSelf = "*$currentSid"
        $sidSystem = "*S-1-5-18"
        $sidAdmin = "*S-1-5-32-544"

        foreach ($sub in $StandardProgramDataSubdirs) {
            $p = Join-Path $DataRoot $sub
            if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
        }

        $null = & icacls $DataRoot /inheritance:r /grant:r "${sidUserSelf}:(OI)(CI)F" /grant:r "${sidSystem}:(OI)(CI)F" /grant:r "${sidAdmin}:(OI)(CI)F" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "[ERR_ACL_FAILED] Sandbox root ACL atanamadi ($LASTEXITCODE)."
        }

        $criticalSubs = @("data", "config", "certs", "security", "backups", "run", "logs", "lib")
        foreach ($sub in $criticalSubs) {
            $subPath = Join-Path $DataRoot $sub
            $null = & icacls $subPath /inheritance:r /grant:r "${sidUserSelf}:(OI)(CI)F" /grant:r "${sidSystem}:(OI)(CI)F" /grant:r "${sidAdmin}:(OI)(CI)F" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_ACL_FAILED] Sandbox ACL hatasi ($subPath): $LASTEXITCODE"
            }
            $acl = Get-Acl -Path $subPath
            foreach ($access in $acl.Access) {
                $sidVal = $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
                if ($sidVal -eq "S-1-5-32-545" -or $sidVal -eq "S-1-1-0" -or $sidVal -eq "S-1-5-11") {
                    throw "[ERR_SECURITY_VIOLATION] $subPath dizininde yetkisiz SID saptandi: $sidVal"
                }
            }
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($AclScriptPath) -or -not (Test-Path $AclScriptPath)) {
        throw "[ERR_ACL_SCRIPT_MISSING] setup_service_acls.ps1 bulunamadi: $AclScriptPath"
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AclScriptPath -BaseDir $DataRoot -ServiceName $ServiceName
    if ($LASTEXITCODE -ne 0) {
        throw "[ERR_ACL_FAILED] setup_service_acls.ps1 basarisiz oldu ($LASTEXITCODE)."
    }
}

function Resolve-HealthCaCertPath {
    param([string]$DataRoot)
    $defaultCa = Join-Path $DataRoot "certs\ca.crt"
    $cfgPath = Join-Path $DataRoot "config\hub_config.json"
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
            if ($cfg.tls -and -not [string]::IsNullOrWhiteSpace([string]$cfg.tls.ca_cert)) {
                $rawRel = [string]$cfg.tls.ca_cert
                $resolved = if ([System.IO.Path]::IsPathRooted($rawRel)) {
                    $rawRel
                } else {
                    Join-Path (Split-Path -Parent $cfgPath) $rawRel
                }
                return (Normalize-InstallerPath $resolved)
            }
        } catch {}
    }
    return $defaultCa
}

function Invoke-HealthVerification {
    param(
        [string]$Url,
        [string]$DataRoot
    )
    if ($FaultInjectionStage -eq "HealthCheck") {
        throw "[ERR_HEALTH_CHECK_FAILED] Simule edilmis /health dogrulama hatasi."
    }
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return @{
            verified = $false
            recovery_key_configured = $false
            status = "SKIPPED_NO_LIVE_ENDPOINT"
        }
    }
    try {
        $content = ""
        if ($Url.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
            $caCertPath = Resolve-HealthCaCertPath -DataRoot $DataRoot
            $maxAttempts = 3
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    $content = [MmsTlsHealthProbe]::VerifyHttpsHealth($Url, $caCertPath, 5000)
                    break
                } catch {
                    $exMsg = $_.Exception.Message
                    if ($_.Exception.InnerException -and [string]::IsNullOrWhiteSpace($exMsg)) {
                        $exMsg = $_.Exception.InnerException.Message
                    }
                    $isTlsValidationError = $exMsg.Contains("[TLS_VALIDATION_FAILED]") -or $exMsg.Contains("ERR_CA_CERT_")
                    if ($isTlsValidationError -or ($attempt -eq $maxAttempts)) {
                        throw
                    }
                    Start-Sleep -Milliseconds 500
                }
            }
        } elseif ($TestSandboxMode) {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($resp.StatusCode -ne 200) {
                throw "HTTP $($resp.StatusCode)"
            }
            $content = $resp.Content
        } else {
            throw "[ERR_INSECURE_HEALTH_URL] Uretim ortaminda sifresiz HTTP health URL kullanilamaz: $Url"
        }

        $json = $content | ConvertFrom-Json
        if ($json.status -ne "UP") {
            throw "Beklenmeyen health durumu: $($json.status)"
        }
        $recConfigured = $false
        if ($json.backup -and $null -ne $json.backup.recovery_key_configured) {
            $recConfigured = [bool]$json.backup.recovery_key_configured
        }
        return @{
            verified = $true
            recovery_key_configured = $recConfigured
            status = $json.status
        }
    } catch {
        throw "[ERR_HEALTH_CHECK_FAILED] Hub health kontrolu basarisiz ($Url): $($_.Exception.Message)"
    }
}

$script:Tx = @{
    Mode                      = "FreshInstall"
    PreviousVersion           = $null
    HadExistingService        = $false
    HadPreviousServiceRunning = $false
    BackedUpBin               = $false
    BackedUpClient            = $false
    BackedUpManifest          = $false
    CopiedClient              = $false
    CopiedBin                 = $false
    ServiceModified           = $false
    ManifestWritten           = $false
}

function Invoke-MarketMmsRollback {
    param(
        [string]$TargetInstallDir,
        [string]$TargetDataRoot,
        [string]$TargetServiceName,
        [switch]$ForceMarkRolledBack
    )
    Write-Host "[ROLLBACK] Kurulum/guncelleme geri aliniyor (kullanici verileri korunuyor)..." -ForegroundColor Yellow

    if ($TestSandboxMode) {
        $svc = Read-SandboxService $TargetDataRoot
        if ($svc) {
            if (-not $script:Tx.HadExistingService) {
                Remove-SandboxService $TargetDataRoot
            } else {
                Write-SandboxService -DataRoot $TargetDataRoot -Name $TargetServiceName -Status "Stopped" -Version $svc.version -BinPath $svc.bin_path
            }
        }
    } else {
        $svc = Get-Service -Name $TargetServiceName -ErrorAction SilentlyContinue
        $wrapperExe = Join-Path $TargetDataRoot "bin\MarketMMSService.exe"
        if ($svc -and $svc.Status -ne "Stopped") {
            if (Test-Path $wrapperExe) { & $wrapperExe stop 2>&1 | Out-Null } else { sc.exe stop $TargetServiceName 2>&1 | Out-Null }
            Start-Sleep -Seconds 2
        }
        if ($svc -and (-not $script:Tx.HadExistingService -or $script:Tx.ServiceModified)) {
            if (Test-Path $wrapperExe) { & $wrapperExe uninstall 2>&1 | Out-Null } else { sc.exe delete $TargetServiceName 2>&1 | Out-Null }
        }
    }

    $binDir = Join-Path $TargetDataRoot "bin"
    $prevBinDir = Join-Path $TargetDataRoot "bin.previous"
    if (Test-Path $prevBinDir) {
        if (Test-Path $binDir) { Remove-Item -Path $binDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item -Path (Join-Path $prevBinDir "*") -Destination $binDir -Recurse -Force
        $restoredSqlite = Join-Path $binDir "sqlite3.dll"
        if (Test-Path $restoredSqlite) {
            $binLibDir = Join-Path $binDir "lib"
            $rootLibDir = Join-Path $TargetDataRoot "lib"
            if (-not (Test-Path $binLibDir)) { New-Item -ItemType Directory -Path $binLibDir -Force | Out-Null }
            if (-not (Test-Path $rootLibDir)) { New-Item -ItemType Directory -Path $rootLibDir -Force | Out-Null }
            Copy-Item -Path $restoredSqlite -Destination (Join-Path $binLibDir "sqlite3.dll") -Force
            Copy-Item -Path $restoredSqlite -Destination (Join-Path $rootLibDir "sqlite3.dll") -Force
        }
        Remove-Item -Path $prevBinDir -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $script:Tx.HadExistingService -and $script:Tx.CopiedBin) {
        if (Test-Path $binDir) { Remove-Item -Path $binDir -Recurse -Force -ErrorAction SilentlyContinue }
        $freshRootSqlite = Join-Path $TargetDataRoot "lib\sqlite3.dll"
        if (Test-Path $freshRootSqlite) { Remove-Item -Path $freshRootSqlite -Force -ErrorAction SilentlyContinue }
    }

    $clientDir = Join-Path $TargetInstallDir "client"
    $prevClientDir = Join-Path $TargetInstallDir "client.previous"
    if (Test-Path $prevClientDir) {
        if (Test-Path $clientDir) { Remove-Item -Path $clientDir -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Path $clientDir -Force | Out-Null
        Copy-Item -Path (Join-Path $prevClientDir "*") -Destination $clientDir -Recurse -Force
        Remove-Item -Path $prevClientDir -Recurse -Force -ErrorAction SilentlyContinue
    } elseif (-not $script:Tx.HadExistingService -and $script:Tx.CopiedClient -and (Test-Path $clientDir)) {
        Remove-Item -Path $clientDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $manifestFile = Join-Path $TargetDataRoot "config\install_manifest.json"
    $prevManifestFile = Join-Path $TargetDataRoot "config\install_manifest.previous.json"
    if (Test-Path $prevManifestFile) {
        Copy-Item -Path $prevManifestFile -Destination $manifestFile -Force
        Remove-Item -Path $prevManifestFile -Force -ErrorAction SilentlyContinue
    } elseif (-not $script:Tx.HadExistingService -and $script:Tx.ManifestWritten -and (Test-Path $manifestFile)) {
        Remove-Item -Path $manifestFile -Force -ErrorAction SilentlyContinue
    }

    if ($script:Tx.HadExistingService) {
        if ($TestSandboxMode) {
            $restoredVer = "previous"
            if (Test-Path $manifestFile) {
                $m = Get-Content -Path $manifestFile -Raw | ConvertFrom-Json
                if ($m.app_version) { $restoredVer = $m.app_version }
            }
            $restoredStatus = if ($script:Tx.HadPreviousServiceRunning) { "Running" } else { "Stopped" }
            Write-SandboxService -DataRoot $TargetDataRoot -Name $TargetServiceName -Status $restoredStatus -Version $restoredVer -BinPath (Join-Path $binDir "MarketMMSService.exe")
        } else {
            $restoredWrapper = Join-Path $binDir "MarketMMSService.exe"
            if (Test-Path $restoredWrapper) {
                & $restoredWrapper install 2>&1 | Out-Null
                sc.exe sidtype $TargetServiceName unrestricted 2>&1 | Out-Null
                if ($script:Tx.HadPreviousServiceRunning) {
                    & $restoredWrapper start 2>&1 | Out-Null
                }
            }
        }
    }

    if ($ForceMarkRolledBack -or (Test-Path (Get-InstallerTxStateFile $TargetDataRoot))) {
        Write-InstallerTxState -DataRoot $TargetDataRoot -Status "ROLLED_BACK"
    }

    Write-Host "[ROLLBACK] Tamamlandi; data/, backups/, security/, certs/ ve config/ korundu." -ForegroundColor Green
}

# ==============================================================================
# ANA AKIS
# ==============================================================================
Assert-ServiceProtection

if (-not $TestSandboxMode -and -not (Test-IsAdministrator)) {
    Fail-Installer -ExitCode 5 -Code "ERR_ADMIN_REQUIRED" `
        -Message "Bu kurulum islemi yerel Yonetici (Administrator) yetkisi gerektirir."
}

if ($Action -eq "VerifyPrerequisites") {
    Assert-StagingPrerequisites -RootStaging $StagingDir
    Assert-ProgramDataSafety -DataRoot $ProgramDataRoot
    $out = [ordered]@{
        status               = "OK"
        action               = $Action
        app_version          = $AppVersion
        acl_script_path      = $AclScriptPath
        firewall_script_path = $FirewallScriptPath
        sandbox              = [bool]$TestSandboxMode
    }
    Write-Output ($out | ConvertTo-Json -Compress)
    exit 0
}

if ($Action -eq "Commit") {
    Remove-InstallerTxArtifacts -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot
    $out = [ordered]@{
        status      = "COMMITTED"
        app_version = $AppVersion
        msi_managed = [bool]$MsiManaged
    }
    Write-Output ($out | ConvertTo-Json -Compress)
    exit 0
}

if ($Action -eq "Rollback") {
    $txState = Read-InstallerTxState -DataRoot $ProgramDataRoot
    if ($null -ne $txState) {
        if ($txState.status -eq "ROLLED_BACK") {
            Write-Host "[ROLLBACK] Geri alma zaten uygulanmis (idempotent no-op)." -ForegroundColor Gray
            exit 0
        }
        $script:Tx.Mode = [string]$txState.mode
        $script:Tx.PreviousVersion = $txState.previous_version
        $script:Tx.HadExistingService = [bool]$txState.had_existing_service
        $script:Tx.HadPreviousServiceRunning = [bool]$txState.had_previous_service_running
        $script:Tx.BackedUpBin = [bool]$txState.backed_up_bin
        $script:Tx.BackedUpClient = [bool]$txState.backed_up_client
        $script:Tx.BackedUpManifest = [bool]$txState.backed_up_manifest
        $script:Tx.CopiedClient = [bool]$txState.copied_client
        $script:Tx.CopiedBin = [bool]$txState.copied_bin
        $script:Tx.ServiceModified = [bool]$txState.service_modified
        $script:Tx.ManifestWritten = [bool]$txState.manifest_written
        Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
        exit 0
    }

    $manifestPrev = Join-Path $ProgramDataRoot "config\install_manifest.previous.json"
    $binPrev = Join-Path $ProgramDataRoot "bin.previous"
    if ((Test-Path $binPrev) -or (Test-Path $manifestPrev)) {
        $script:Tx.HadExistingService = $true
        $script:Tx.HadPreviousServiceRunning = $true
        $script:Tx.BackedUpBin = (Test-Path $binPrev)
        $script:Tx.BackedUpManifest = (Test-Path $manifestPrev)
        Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
    } else {
        Write-Host "[ROLLBACK] Aktif islem gunlugu veya .previous yedegi yok; idempotent no-op." -ForegroundColor Gray
    }
    exit 0
}

if ($Action -eq "Uninstall") {
    if ($FaultInjectionStage -eq "UninstallService") {
        Fail-Installer -ExitCode 75 -Code "ERR_UNINSTALL_SERVICE_FAILED" `
            -Message "Simule edilmis uninstall servis durdurma/kaldirma hatasi; kullanici verileri korundu."
    }

    if ($TestSandboxMode) {
        $svc = Read-SandboxService $ProgramDataRoot
        if ($svc) {
            Remove-SandboxService $ProgramDataRoot
        }
    } else {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            $wrapper = Join-Path $ProgramDataRoot "bin\MarketMMSService.exe"
            if ($svc.Status -ne "Stopped") {
                if (Test-Path $wrapper) { & $wrapper stop 2>&1 | Out-Null } else { sc.exe stop $ServiceName 2>&1 | Out-Null }
                $svc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            }
            if (Test-Path $wrapper) { & $wrapper uninstall 2>&1 | Out-Null } else { sc.exe delete $ServiceName 2>&1 | Out-Null }
        }
        if (-not [string]::IsNullOrWhiteSpace($FirewallScriptPath) -and (Test-Path $FirewallScriptPath)) {
            $cfgForFw = Join-Path $ProgramDataRoot "config\hub_config.json"
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FirewallScriptPath -TcpPort $Port -UdpPort $DiscoveryPort -ConfigPath $cfgForFw -Remove | Out-Null
        }
        $fwRule = Get-NetFirewallRule -DisplayName "MarketMMS-Hub-*" -ErrorAction SilentlyContinue
        if ($fwRule) {
            Remove-NetFirewallRule -DisplayName "MarketMMS-Hub-*" -ErrorAction SilentlyContinue
        }
        $legacyFwRule = Get-NetFirewallRule -DisplayName "MarketMMS Local Master Hub*" -ErrorAction SilentlyContinue
        if ($legacyFwRule) {
            Remove-NetFirewallRule -DisplayName "MarketMMS Local Master Hub*" -ErrorAction SilentlyContinue
        }
    }

    if (-not $MsiManaged) {
        if (Test-Path $InstallDir) {
            Remove-Item -Path $InstallDir -Recurse -Force
        }
    }

    foreach ($ephemeralDir in @("bin", "bin.previous", "lib")) {
        $p = Join-Path $ProgramDataRoot $ephemeralDir
        if (Test-Path $p) {
            Remove-Item -Path $p -Recurse -Force
        }
    }
    foreach ($ephemeralFile in @(
        (Join-Path $ProgramDataRoot "config\install_manifest.json"),
        (Join-Path $ProgramDataRoot "config\install_manifest.previous.json"),
        (Get-InstallerTxStateFile $ProgramDataRoot)
    )) {
        if (Test-Path $ephemeralFile) {
            Remove-Item -Path $ephemeralFile -Force -ErrorAction SilentlyContinue
        }
    }

    $userDataPurged = $false
    if ($PurgeUserDataEffective) {
        if ($ConfirmPurgeToken -ne "CONFIRM_DELETE_ALL_MARKET_MMS_DATA") {
            Fail-Installer -ExitCode 76 -Code "ERR_PURGE_CONFIRMATION_REQUIRED" `
                -Message "Kullanici verisi silme islemi acik onay jetonu olmadan reddedildi; data/backups/security korundu."
        }
        if (Test-Path $ProgramDataRoot) {
            Remove-Item -Path $ProgramDataRoot -Recurse -Force
            $userDataPurged = $true
        }
    }

    $res = [ordered]@{
        status              = "UNINSTALLED"
        msi_managed         = [bool]$MsiManaged
        user_data_purged    = $userDataPurged
        user_data_preserved = (-not $userDataPurged)
    }
    Write-Output ($res | ConvertTo-Json -Compress)
    exit 0
}

# Install / Upgrade / Repair ortak is akisi
Assert-StagingPrerequisites -RootStaging $StagingDir
Assert-ProgramDataSafety -DataRoot $ProgramDataRoot

$manifestPath = Join-Path $ProgramDataRoot "config\install_manifest.json"
$prevManifestPath = Join-Path $ProgramDataRoot "config\install_manifest.previous.json"
$existingVersion = $null
if (Test-Path $manifestPath) {
    $existingManifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    $existingVersion = $existingManifest.app_version
    $script:Tx.PreviousVersion = $existingVersion
    if ($existingVersion) {
        $cmp = Compare-SemVer -Left $AppVersion -Right $existingVersion
        if ($cmp -lt 0) {
            Fail-Installer -ExitCode 73 -Code "ERR_DOWNGRADE_NOT_ALLOWED" `
                -Message "Kurulu surum ($existingVersion) yeni paketten ($AppVersion) daha yuksek; downgrade engellendi."
        } elseif ($cmp -eq 0) {
            $script:Tx.Mode = "Repair"
        } else {
            $script:Tx.Mode = "Upgrade"
        }
    }
}

try {
    if ($FaultInjectionStage -eq "ProgramData") {
        if ($TestSandboxMode) {
            Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
        }
        throw "[ERR_PROGRAMDATA_FAILED] Simule edilmis ProgramData dizin olusturma hatasi."
    }

    # 0. Transaction durumunu kayda al
    foreach ($sub in $StandardProgramDataSubdirs) {
        $subDir = Join-Path $ProgramDataRoot $sub
        if (-not (Test-Path $subDir)) {
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        }
    }
    if ($TestSandboxMode) {
        $existingSvcCheck = Read-SandboxService $ProgramDataRoot
        if ($existingSvcCheck) {
            $script:Tx.HadExistingService = $true
            $script:Tx.HadPreviousServiceRunning = ($existingSvcCheck.status -eq "Running")
        }
    } else {
        $existingSvcCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($existingSvcCheck) {
            $script:Tx.HadExistingService = $true
            $script:Tx.HadPreviousServiceRunning = ($existingSvcCheck.Status -eq "Running")
        }
    }
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    # 1. Mevcut servisi durdur (ikililere dokunmadan ONCE)
    if ($TestSandboxMode) {
        $existingSvc = Read-SandboxService $ProgramDataRoot
        if ($existingSvc) {
            Write-SandboxService -DataRoot $ProgramDataRoot -Name $ServiceName -Status "Stopped" -Version $existingSvc.version -BinPath $existingSvc.bin_path
        }
    } else {
        $existingSvc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($existingSvc) {
            $wrapper = Join-Path $ProgramDataRoot "bin\MarketMMSService.exe"
            if ($existingSvc.Status -ne "Stopped") {
                if (Test-Path $wrapper) { & $wrapper stop 2>&1 | Out-Null } else { sc.exe stop $ServiceName 2>&1 | Out-Null }
                $existingSvc.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
            }
            if (Test-Path $wrapper) { & $wrapper uninstall 2>&1 | Out-Null } else { sc.exe delete $ServiceName 2>&1 | Out-Null }
            Start-Sleep -Seconds 2
        }
    }

    # 2. NTFS ACL yapilandirmasi
    Apply-DirectoryAcls -DataRoot $ProgramDataRoot

    # 3. Upgrade/Repair oncesi mevcut ikililer ve DB (+ WAL/SHM VACUUM INTO) yedeklemesi
    $preUpgradeBackupPath = $null
    $liveDbPath = Join-Path $ProgramDataRoot "data\market_master.db"
    if ($script:Tx.Mode -eq "Upgrade" -and (Test-Path $liveDbPath)) {
        $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
        $preUpgradeDir = Join-Path $ProgramDataRoot ("backups\pre_upgrade_{0}_to_{1}_{2}" -f $existingVersion, $AppVersion, $stamp)
        New-Item -ItemType Directory -Path $preUpgradeDir -Force | Out-Null
        $preUpgradeBackupPath = Join-Path $preUpgradeDir "market_master.db.pre_upgrade"
        $sqliteCandidates = @(
            (Join-Path $StagingDir "hub_bin\sqlite3.dll"),
            (Join-Path $ProgramDataRoot "bin\sqlite3.dll"),
            (Join-Path $ProgramDataRoot "lib\sqlite3.dll")
        )
        Invoke-SafePreUpgradeSqliteBackup -SourceDbPath $liveDbPath -TargetBackupPath $preUpgradeBackupPath -CandidateSqliteDlls $sqliteCandidates
    }

    $binDir = Join-Path $ProgramDataRoot "bin"
    $prevBinDir = Join-Path $ProgramDataRoot "bin.previous"
    if (Test-Path (Join-Path $binDir "mms_backend.exe")) {
        if (Test-Path $prevBinDir) { Remove-Item -Path $prevBinDir -Recurse -Force }
        New-Item -ItemType Directory -Path $prevBinDir -Force | Out-Null
        Copy-Item -Path (Join-Path $binDir "*") -Destination $prevBinDir -Recurse -Force
        $script:Tx.BackedUpBin = $true
    }

    $clientDir = Join-Path $InstallDir "client"
    $prevClientDir = Join-Path $InstallDir "client.previous"
    $srcClient = Join-Path $StagingDir "client"
    if (-not $MsiManaged -and (Test-Path (Join-Path $clientDir "market_pos.exe"))) {
        $resolvedSrcClient = (Resolve-Path $srcClient).Path
        $resolvedDstClient = (Resolve-Path $clientDir).Path
        if ($resolvedSrcClient -ne $resolvedDstClient) {
            if (Test-Path $prevClientDir) { Remove-Item -Path $prevClientDir -Recurse -Force }
            New-Item -ItemType Directory -Path $prevClientDir -Force | Out-Null
            Copy-Item -Path (Join-Path $clientDir "*") -Destination $prevClientDir -Recurse -Force
            $script:Tx.BackedUpClient = $true
        }
    }

    if (Test-Path $manifestPath) {
        Copy-Item -Path $manifestPath -Destination $prevManifestPath -Force
        $script:Tx.BackedUpManifest = $true
    }
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    # 4. Config ve Admin Secret (mevcutsa ASLA ezilmez; Recovery Key DPAPI olusturulmaz/dokunulmaz)
    $configFile = Join-Path $ProgramDataRoot "config\hub_config.json"
    if (-not (Test-Path $configFile)) {
        $tmpl = $ConfigTemplatePath
        if ([string]::IsNullOrWhiteSpace($tmpl)) {
            $cand = Join-Path $StagingDir "hub_bin\hub_config.example.json"
            if (Test-Path $cand) { $tmpl = $cand }
        }
        if (-not [string]::IsNullOrWhiteSpace($tmpl) -and (Test-Path $tmpl)) {
            $cfgObj = Get-Content -Path $tmpl -Raw | ConvertFrom-Json
            $cfgObj.port = $Port
            $cfgObj.discovery_port = $DiscoveryPort
            Set-Content -Path $configFile -Value ($cfgObj | ConvertTo-Json -Depth 8) -Encoding UTF8
        } else {
            $defaultCfg = [ordered]@{
                schema_version = 1
                environment    = "production"
                port           = $Port
                discovery_port = $DiscoveryPort
                enable_discovery = $true
                db_path        = "../data/market_master.db"
                backup_dir     = "../backups"
                pepper_file    = "../security/pepper.dpapi"
                admin_secret_file = "../security/admin_secret.txt"
                tls = [ordered]@{
                    enabled = $true
                    cert    = "../certs/server.crt"
                    key     = "../certs/server.key"
                    ca_cert = "../certs/ca.crt"
                }
                tenant_id      = "tenant-default"
                store_id       = "store-main-01"
                hub_id         = "MMS-HUB-01"
                require_tenant_store_headers = $true
            }
            Set-Content -Path $configFile -Value ($defaultCfg | ConvertTo-Json -Depth 8) -Encoding UTF8
        }
    }

    $adminSecretFile = Join-Path $ProgramDataRoot "security\admin_secret.txt"
    if (-not (Test-Path $adminSecretFile)) {
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $secretBytes = New-Object byte[] 32
        $rng.GetBytes($secretBytes)
        $secretText = [Convert]::ToBase64String($secretBytes)
        Set-Content -Path $adminSecretFile -Value $secretText -NoNewline -Encoding ASCII
        if (-not $TestSandboxMode) {
            $sidSvc = "NT SERVICE\$ServiceName"
            try {
                $sidSvc = "*" + (New-Object System.Security.Principal.NTAccount("NT SERVICE\$ServiceName")).Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch {}
            & icacls $adminSecretFile /inheritance:r /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" /grant:r "${sidSvc}:R" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_ADMIN_SECRET_ACL_FAILED] admin_secret.txt ACL atamasi basarisiz oldu ($LASTEXITCODE)."
            }
        }
    }

    # 5. Istemci ve Hub ikililerinin kopyalanmasi
    if ($FaultInjectionStage -eq "UpgradeInterrupt") {
        throw "[ERR_UPGRADE_INTERRUPTED] Simule edilmis yukseltme kesintisi."
    }
    if (-not (Test-Path $clientDir)) { New-Item -ItemType Directory -Path $clientDir -Force | Out-Null }
    if ((Resolve-Path $srcClient).Path -ne (Resolve-Path $clientDir).Path) {
        Copy-Item -Path (Join-Path $srcClient "*") -Destination $clientDir -Recurse -Force
        $script:Tx.CopiedClient = $true
    }

    $srcHub = Join-Path $StagingDir "hub_bin"
    Copy-Item -Path (Join-Path $srcHub "*") -Destination $binDir -Recurse -Force
    $sqliteInBin = Join-Path $binDir "sqlite3.dll"
    if (Test-Path $sqliteInBin) {
        Copy-Item -Path $sqliteInBin -Destination (Join-Path $ProgramDataRoot "bin\lib\sqlite3.dll") -Force
        Copy-Item -Path $sqliteInBin -Destination (Join-Path $ProgramDataRoot "lib\sqlite3.dll") -Force
    }
    $script:Tx.CopiedBin = $true
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    if ($FaultInjectionStage -eq "Migration") {
        throw "[ERR_MIGRATION_FAILED] Simule edilmis veritabani migration hatasi."
    }

    # 6. Servis kurulumu ve TLS hazirlik kontrolu
    if ($FaultInjectionStage -eq "ServiceInstall") {
        throw "[ERR_SERVICE_INSTALL_FAILED] Simule edilmis servis kayit hatasi."
    }

    $deployedWrapper = Join-Path $binDir "MarketMMSService.exe"
    if ($TestSandboxMode) {
        Write-SandboxService -DataRoot $ProgramDataRoot -Name $ServiceName -Status "Stopped" -Version $AppVersion -BinPath $deployedWrapper
    } else {
        $instOut = & $deployedWrapper install 2>&1
        if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_INSTALL_FAILED] WinSW install basarisiz: $instOut" }
        $sidOut = sc.exe sidtype $ServiceName unrestricted 2>&1
        if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_SID_FAILED] sc.exe sidtype basarisiz: $sidOut" }
        if (-not [string]::IsNullOrWhiteSpace($FirewallScriptPath) -and (Test-Path $FirewallScriptPath)) {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FirewallScriptPath -TcpPort $Port -UdpPort $DiscoveryPort -ConfigPath $configFile | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_FIREWALL_FAILED] configure_hub_firewall.ps1 basarisiz oldu ($LASTEXITCODE)."
            }
        }
    }
    $script:Tx.ServiceModified = $true
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    $hasTlsCerts = (Test-Path (Join-Path $ProgramDataRoot "certs\ca.crt")) -and `
                   (Test-Path (Join-Path $ProgramDataRoot "certs\server.crt")) -and `
                   (Test-Path (Join-Path $ProgramDataRoot "certs\server.key"))

    $serviceState = "PENDING_TLS_PROVISIONING"
    $healthResult = @{ verified = $false; recovery_key_configured = (Test-Path (Join-Path $ProgramDataRoot "security\backup_recovery_key.dpapi")); status = "DEFERRED_NO_CERTS" }

    if ($FaultInjectionStage -eq "ServiceStart") {
        throw "[ERR_SERVICE_START_FAILED] Simule edilmis servis baslatma hatasi."
    }

    if ($hasTlsCerts) {
        if ($TestSandboxMode) {
            Write-SandboxService -DataRoot $ProgramDataRoot -Name $ServiceName -Status "Running" -Version $AppVersion -BinPath $deployedWrapper
            $serviceState = "RUNNING"
        } else {
            $startOut = & $deployedWrapper start 2>&1
            if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_START_FAILED] Servis baslatilamadi: $startOut" }
            Start-Sleep -Seconds 3
            $svcCheck = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($svcCheck.Status -ne "Running") {
                throw "[ERR_SERVICE_START_FAILED] Servis calisma durumuna gecemedi: $($svcCheck.Status)"
            }
            $serviceState = "RUNNING"
        }

        if (-not [string]::IsNullOrWhiteSpace($HealthCheckUrl)) {
            $healthResult = Invoke-HealthVerification -Url $HealthCheckUrl -DataRoot $ProgramDataRoot
        } elseif (-not $TestSandboxMode) {
            $healthPort = $Port
            if (Test-Path $configFile) {
                try { $healthPort = [int](Get-Content $configFile -Raw | ConvertFrom-Json).port } catch {}
            }
            $healthResult = Invoke-HealthVerification -Url ("https://127.0.0.1:{0}/health" -f $healthPort) -DataRoot $ProgramDataRoot
        } elseif ($FaultInjectionStage -eq "HealthCheck") {
            $healthResult = Invoke-HealthVerification -Url "" -DataRoot $ProgramDataRoot
        }
    } else {
        if (-not $AllowDeferredTlsStartBool) {
            throw "[ERR_TLS_CERTS_MISSING] TLS sertifikalari (ca.crt, server.crt, server.key) eksik ve ertelenmis baslangic kapali."
        }
        if ($FaultInjectionStage -eq "HealthCheck") {
            $null = Invoke-HealthVerification -Url $HealthCheckUrl -DataRoot $ProgramDataRoot
        }
    }

    # 7. Kurulum manifestini kaydet (Yalnizca TUM adimlar basariliysa!)
    $hasRecoveryKeyFile = Test-Path (Join-Path $ProgramDataRoot "security\backup_recovery_key.dpapi")
    $manifest = [ordered]@{
        app_version             = $AppVersion
        install_dir             = $InstallDir
        program_data_root       = $ProgramDataRoot
        service_name            = $ServiceName
        service_state           = $serviceState
        mode                    = $script:Tx.Mode
        previous_version        = $existingVersion
        pre_upgrade_backup_path = $preUpgradeBackupPath
        acl_script_path         = $AclScriptPath
        firewall_script_path    = $FirewallScriptPath
        msi_managed             = [bool]$MsiManaged
        recovery_key_configured = ($hasRecoveryKeyFile -or [bool]$healthResult.recovery_key_configured)
        health_verified         = [bool]$healthResult.verified
        installed_at_utc        = (Get-Date).ToUniversalTime().ToString("o")
    }
    Set-Content -Path $manifestPath -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding UTF8
    $script:Tx.ManifestWritten = $true

    if ($MsiManaged) {
        # MSI modunda gecici .previous yedekleri CA_CommitInstall calisana dek korunur
        Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "INSTALL_ACTION_SUCCEEDED"
    } else {
        Remove-InstallerTxArtifacts -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot
    }

    Write-Output ($manifest | ConvertTo-Json -Compress)
    exit 0
} catch {
    $errMsg = $_.Exception.Message
    if ($MsiManaged) {
        Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
        Fail-Installer -ExitCode 74 -Code "ERR_INSTALLER_STEP_FAILED" -Message $errMsg
    } else {
        Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
        Fail-Installer -ExitCode 74 -Code "ERR_INSTALLER_ROLLED_BACK" -Message $errMsg
    }
}
