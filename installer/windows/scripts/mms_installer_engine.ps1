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
    [ValidateSet("None", "MissingRuntime", "ProgramData", "PrePreviousBackup", "Acl", "ServiceInstall", "ScmStamp", "ServiceStop", "ServiceUninstall", "ScmDeletePending", "ServiceStart", "HealthCheck", "Migration", "UpgradeInterrupt", "UninstallService", "RollbackAcl", "RollbackBinary", "RollbackManifest", "RollbackFirewall", "RollbackService")]
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
    }
    catch {
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

$ProgramDataRoot = Normalize-InstallerPath $ProgramDataRoot
$script:CurrentInstallerStage = "Bootstrap"
$script:DiagnosticIcaclsPath = "icacls.exe"

if (-not ("MmsSafeDiagnosticLogWriter" -as [type])) {
    Add-Type -Language CSharp -ReferencedAssemblies @("System.dll", "System.Core.dll") -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class MmsSafeDiagnosticLogWriter
{
    private const uint READ_CONTROL = 0x00020000;
    private const uint FILE_APPEND_DATA = 0x00000004;
    private const uint FILE_READ_ATTRIBUTES = 0x00000080;
    private const uint DELETE_ACCESS = 0x00010000;
    private const uint SYNCHRONIZE = 0x00100000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_ALL = 0x00000007;
    private const uint OPEN_EXISTING = 3;
    private const uint OPEN_ALWAYS = 4;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    private const uint FILE_NAME_NORMALIZED = 0x0;
    private const uint OWNER_SECURITY_INFORMATION = 0x00000001;
    private const uint DACL_SECURITY_INFORMATION = 0x00000004;
    private const int FILE_RENAME_INFO = 3;
    private const int FILE_DISPOSITION_INFO = 4;
    private const int ERROR_FILE_NOT_FOUND = 2;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;

    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME
    {
        public uint dwLowDateTime;
        public uint dwHighDateTime;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public FILETIME CreationTime;
        public FILETIME LastAccessTime;
        public FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FILE_DISPOSITION_INFO_NATIVE
    {
        [MarshalAs(UnmanagedType.U1)]
        public bool DeleteFile;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle hFile,
        StringBuilder lpszFilePath,
        uint cchFilePath,
        uint dwFlags
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteFile(
        SafeFileHandle hFile,
        byte[] lpBuffer,
        uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten,
        IntPtr lpOverlapped
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle hFile,
        int fileInformationClass,
        IntPtr lpFileInformation,
        uint dwBufferSize
    );

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetKernelObjectSecurity(
        SafeFileHandle Handle,
        uint RequestedInformation,
        byte[] pSecurityDescriptor,
        uint nLength,
        out uint lpnLengthNeeded
    );

    public static void AssertNoReparsePointInPath(string rawPath)
    {
        if (string.IsNullOrWhiteSpace(rawPath))
        {
            throw new InvalidOperationException("Empty path.");
        }
        string full = Path.GetFullPath(rawPath).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string root = Path.GetPathRoot(full);
        if (string.IsNullOrEmpty(root))
        {
            throw new InvalidOperationException("Unrooted path is not allowed: " + rawPath);
        }

        string rootTrimmed = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (full.Length <= rootTrimmed.Length)
        {
            return;
        }

        string remainder = full.Substring(root.Length);
        string[] segments = remainder.Split(new char[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);
        string current = root;
        foreach (string seg in segments)
        {
            current = Path.Combine(current, seg);
            if (Directory.Exists(current) || File.Exists(current))
            {
                FileAttributes attrs;
                try
                {
                    attrs = File.GetAttributes(current);
                }
                catch (Exception ex)
                {
                    throw new UnauthorizedAccessException("Cannot verify path attributes: " + current, ex);
                }
                if ((attrs & FileAttributes.ReparsePoint) != 0)
                {
                    throw new UnauthorizedAccessException("Reparse point detected in path: " + current);
                }
            }
        }
    }

    public static void CreateDirectoryWithStrictSecurity(string dirPath, bool includeCurrentUser)
    {
        AssertNoReparsePointInPath(dirPath);
        DirectorySecurity sec = new DirectorySecurity();
        sec.SetAccessRuleProtection(true, false);

        SecurityIdentifier sidSystem = new SecurityIdentifier("S-1-5-18");
        SecurityIdentifier sidAdmins = new SecurityIdentifier("S-1-5-32-544");
        InheritanceFlags inherit = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

        sec.AddAccessRule(new FileSystemAccessRule(sidSystem, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
        sec.AddAccessRule(new FileSystemAccessRule(sidAdmins, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));

        if (includeCurrentUser)
        {
            SecurityIdentifier sidCur = WindowsIdentity.GetCurrent().User;
            if (sidCur != null && !sidCur.Equals(sidSystem) && !sidCur.Equals(sidAdmins))
            {
                sec.AddAccessRule(new FileSystemAccessRule(sidCur, FileSystemRights.FullControl, inherit, PropagationFlags.None, AccessControlType.Allow));
            }
        }

        Directory.CreateDirectory(dirPath, sec);
        AssertNoReparsePointInPath(dirPath);
    }

    private static string NormalizeKernelFinalPath(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return "";
        string res = raw;
        if (res.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
        {
            res = @"\\" + res.Substring(8);
        }
        else if (res.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
        {
            res = res.Substring(4);
        }
        return res.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static string GetCanonicalHandlePath(SafeFileHandle handle)
    {
        uint needed = GetFinalPathNameByHandleW(handle, null, 0, FILE_NAME_NORMALIZED);
        if (needed == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed.");
        }
        StringBuilder sb = new StringBuilder((int)needed + 2);
        uint got = GetFinalPathNameByHandleW(handle, sb, (uint)sb.Capacity, FILE_NAME_NORMALIZED);
        if (got == 0 || got >= (uint)sb.Capacity)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW(2) failed.");
        }
        return NormalizeKernelFinalPath(sb.ToString());
    }

    private static BY_HANDLE_FILE_INFORMATION ValidateRegularFileHandle(SafeFileHandle handle, string expectedCanonicalPath)
    {
        BY_HANDLE_FILE_INFORMATION info;
        if (!GetFileInformationByHandle(handle, out info))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed.");
        }
        if ((info.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0)
        {
            throw new UnauthorizedAccessException("Handle refers to a reparse point.");
        }
        if ((info.FileAttributes & (uint)FileAttributes.Directory) != 0)
        {
            throw new UnauthorizedAccessException("Handle refers to a directory instead of a file.");
        }
        if (info.NumberOfLinks > 1)
        {
            throw new UnauthorizedAccessException("Hardlink detected (NumberOfLinks=" + info.NumberOfLinks + ").");
        }
        string actualCanonical = GetCanonicalHandlePath(handle);
        if (!string.Equals(actualCanonical, expectedCanonicalPath, StringComparison.OrdinalIgnoreCase))
        {
            throw new UnauthorizedAccessException("Handle canonical path mismatch: " + actualCanonical + " != " + expectedCanonicalPath);
        }
        return info;
    }

    private static void DeleteByHandle(SafeFileHandle handle)
    {
        FILE_DISPOSITION_INFO_NATIVE disp = new FILE_DISPOSITION_INFO_NATIVE();
        disp.DeleteFile = true;
        int size = Marshal.SizeOf(typeof(FILE_DISPOSITION_INFO_NATIVE));
        IntPtr ptr = Marshal.AllocHGlobal(size);
        try
        {
            Marshal.StructureToPtr(disp, ptr, false);
            if (!SetFileInformationByHandle(handle, FILE_DISPOSITION_INFO, ptr, (uint)size))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetFileInformationByHandle(FileDispositionInfo) failed.");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }

    private static void RenameByHandle(SafeFileHandle handle, string destinationFullPath)
    {
        byte[] nameBytes = Encoding.Unicode.GetBytes(destinationFullPath);
        int rootOffset = IntPtr.Size;
        int lenOffset = rootOffset + IntPtr.Size;
        int nameOffset = lenOffset + 4;
        int totalSize = nameOffset + nameBytes.Length + 2;

        IntPtr ptr = Marshal.AllocHGlobal(totalSize);
        try
        {
            byte[] zeros = new byte[totalSize];
            Marshal.Copy(zeros, 0, ptr, totalSize);
            Marshal.WriteByte(ptr, 0, 0); // ReplaceIfExists = false (fail-closed)
            Marshal.WriteIntPtr(ptr, rootOffset, IntPtr.Zero);
            Marshal.WriteInt32(ptr, lenOffset, nameBytes.Length);
            Marshal.Copy(nameBytes, 0, new IntPtr(ptr.ToInt64() + nameOffset), nameBytes.Length);

            if (!SetFileInformationByHandle(handle, FILE_RENAME_INFO, ptr, (uint)totalSize))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetFileInformationByHandle(FileRenameInfo) failed.");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }

    private static CommonSecurityDescriptor ReadSecurityDescriptorFromHandle(SafeFileHandle handle)
    {
        uint reqInfo = OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION;
        uint needed = 0;
        GetKernelObjectSecurity(handle, reqInfo, null, 0, out needed);
        int err = Marshal.GetLastWin32Error();
        if (err != ERROR_INSUFFICIENT_BUFFER || needed == 0)
        {
            throw new Win32Exception(err, "GetKernelObjectSecurity(size) failed.");
        }
        byte[] sdBytes = new byte[needed];
        uint needed2 = 0;
        if (!GetKernelObjectSecurity(handle, reqInfo, sdBytes, needed, out needed2))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetKernelObjectSecurity(read) failed.");
        }
        return new CommonSecurityDescriptor(true, false, sdBytes, 0);
    }

    public static bool ValidateDirectorySecurityFromHandle(
        SafeFileHandle hDir,
        bool isDataRoot,
        bool sandboxMode,
        string serviceSid,
        string overrideOwnerSid
    )
    {
        if (hDir == null || hDir.IsInvalid)
        {
            return false;
        }
        BY_HANDLE_FILE_INFORMATION dirInfo;
        if (!GetFileInformationByHandle(hDir, out dirInfo))
        {
            return false;
        }
        if ((dirInfo.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0 ||
            (dirInfo.FileAttributes & (uint)FileAttributes.Directory) == 0)
        {
            return false;
        }

        CommonSecurityDescriptor sd;
        try
        {
            sd = ReadSecurityDescriptorFromHandle(hDir);
        }
        catch
        {
            return false;
        }

        const string sidSystem = "S-1-5-18";
        const string sidAdmins = "S-1-5-32-544";
        List<string> allowedOwners = new List<string>();
        allowedOwners.Add(sidSystem);
        allowedOwners.Add(sidAdmins);

        string curUserSid = null;
        try
        {
            SecurityIdentifier cur = WindowsIdentity.GetCurrent().User;
            if (cur != null) curUserSid = cur.Value;
        }
        catch
        {
            curUserSid = null;
        }
        if (sandboxMode && !string.IsNullOrEmpty(curUserSid) && !allowedOwners.Contains(curUserSid))
        {
            allowedOwners.Add(curUserSid);
        }

        string ownerSid = !string.IsNullOrWhiteSpace(overrideOwnerSid)
            ? overrideOwnerSid.Trim()
            : (sd.Owner != null ? sd.Owner.Value : "");
        if (string.IsNullOrEmpty(ownerSid) || !allowedOwners.Contains(ownerSid))
        {
            return false;
        }

        if (((sd.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0) || sd.DiscretionaryAcl == null)
        {
            return false;
        }

        List<string> allowedWriters = new List<string>(allowedOwners);
        if (!isDataRoot && !string.IsNullOrWhiteSpace(serviceSid) &&
            serviceSid.StartsWith("S-1-5-80-", StringComparison.OrdinalIgnoreCase) &&
            !allowedWriters.Contains(serviceSid))
        {
            allowedWriters.Add(serviceSid);
        }

        HashSet<string> forbiddenBroadSids = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "S-1-1-0",
            "S-1-5-11",
            "S-1-5-7",
            "S-1-5-4",
            "S-1-5-32-546",
            "S-1-5-32-547"
        };

        const int writeRightsMask =
            0x00000002 | // WriteData / AddFile
            0x00000004 | // AppendData / AddSubdirectory
            0x00000010 | // WriteExtendedAttributes
            0x00000100 | // WriteAttributes
            0x00000040 | // DeleteChild
            0x00010000 | // Delete
            0x00040000 | // WriteDac
            0x00080000 | // WriteOwner
            0x10000000 | // GenericAll
            0x40000000;  // GenericWrite
        const int fullControlMask = 0x001F01FF;
        const int traverseOnlyMask = 0x00100020; // FILE_TRAVERSE | SYNCHRONIZE

        bool hasSystemFull = false;
        bool hasAdminsFull = false;

        foreach (GenericAce rawAce in sd.DiscretionaryAcl)
        {
            CommonAce ca = rawAce as CommonAce;
            if (ca == null || ca.SecurityIdentifier == null)
            {
                return false;
            }
            string sidVal = ca.SecurityIdentifier.Value;
            int mask = ca.AccessMask;

            if (ca.AceType == AceType.AccessDenied)
            {
                if ((allowedOwners.Contains(sidVal) || string.Equals(sidVal, "S-1-1-0", StringComparison.OrdinalIgnoreCase)) &&
                    ((mask & writeRightsMask) != 0))
                {
                    return false;
                }
                continue;
            }

            if (ca.AceType != AceType.AccessAllowed)
            {
                return false;
            }

            if (forbiddenBroadSids.Contains(sidVal))
            {
                return false;
            }

            if (string.Equals(sidVal, "S-1-5-32-545", StringComparison.OrdinalIgnoreCase))
            {
                if (!isDataRoot)
                {
                    return false;
                }
                bool isInheriting = (ca.AceFlags & (AceFlags.ObjectInherit | AceFlags.ContainerInherit)) != 0;
                if (isInheriting || ((mask & ~traverseOnlyMask) != 0))
                {
                    return false;
                }
                continue;
            }

            if ((mask & writeRightsMask) != 0)
            {
                if (!allowedWriters.Contains(sidVal))
                {
                    return false;
                }
            }

            bool isNonInheritOnly = (ca.AceFlags & AceFlags.InheritOnly) == 0;
            if (isNonInheritOnly && (((mask & fullControlMask) == fullControlMask) || ((mask & 0x10000000) != 0)))
            {
                if (string.Equals(sidVal, sidSystem, StringComparison.OrdinalIgnoreCase)) hasSystemFull = true;
                if (string.Equals(sidVal, sidAdmins, StringComparison.OrdinalIgnoreCase)) hasAdminsFull = true;
            }
        }

        return hasSystemFull && hasAdminsFull;
    }

    public static bool ValidateDirectoryPathSecurity(
        string dirPath,
        bool isDataRoot,
        bool sandboxMode,
        string serviceSid,
        string overrideOwnerSid
    )
    {
        if (string.IsNullOrWhiteSpace(dirPath) || !Directory.Exists(dirPath))
        {
            return false;
        }
        try
        {
            AssertNoReparsePointInPath(dirPath);
            using (SafeFileHandle hDir = CreateFileW(
                dirPath,
                FILE_READ_ATTRIBUTES | READ_CONTROL,
                FILE_SHARE_ALL,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero))
            {
                if (hDir.IsInvalid)
                {
                    return false;
                }
                return ValidateDirectorySecurityFromHandle(hDir, isDataRoot, sandboxMode, serviceSid, overrideOwnerSid);
            }
        }
        catch
        {
            return false;
        }
    }

    private static void AppendLogOnCanonicalDir(string canonicalLogsDir, string fileName, string rotatedFileName, byte[] utf8Bytes, long maxBytesBeforeRotate)
    {
        string logPath = Path.Combine(canonicalLogsDir, fileName);
        string expectedCanonicalLog = NormalizeKernelFinalPath(logPath);
        string expectedCanonicalRotated = NormalizeKernelFinalPath(Path.Combine(canonicalLogsDir, rotatedFileName));

        // 1. Handle-based size check & rotation
        using (SafeFileHandle hExisting = CreateFileW(
            logPath,
            FILE_READ_ATTRIBUTES | DELETE_ACCESS | SYNCHRONIZE,
            0,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            if (hExisting.IsInvalid)
            {
                int err = Marshal.GetLastWin32Error();
                if (err != ERROR_FILE_NOT_FOUND)
                {
                    throw new Win32Exception(err, "Cannot open existing diagnostic log for rotation check.");
                }
            }
            else
            {
                BY_HANDLE_FILE_INFORMATION existingInfo = ValidateRegularFileHandle(hExisting, expectedCanonicalLog);
                long fileSize = (((long)existingInfo.FileSizeHigh) << 32) | (uint)existingInfo.FileSizeLow;
                if (fileSize >= maxBytesBeforeRotate)
                {
                    using (SafeFileHandle hRot = CreateFileW(
                        expectedCanonicalRotated,
                        FILE_READ_ATTRIBUTES | DELETE_ACCESS | SYNCHRONIZE,
                        0,
                        IntPtr.Zero,
                        OPEN_EXISTING,
                        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
                        IntPtr.Zero))
                    {
                        if (hRot.IsInvalid)
                        {
                            int rotErr = Marshal.GetLastWin32Error();
                            if (rotErr != ERROR_FILE_NOT_FOUND)
                            {
                                throw new Win32Exception(rotErr, "Cannot inspect existing rotated diagnostic log.");
                            }
                        }
                        else
                        {
                            ValidateRegularFileHandle(hRot, expectedCanonicalRotated);
                            DeleteByHandle(hRot);
                        }
                    }
                    RenameByHandle(hExisting, expectedCanonicalRotated);
                }
            }
        }

        // 2. Handle-based atomic append directly onto verified handle
        using (SafeFileHandle hAppend = CreateFileW(
            logPath,
            FILE_APPEND_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE,
            FILE_SHARE_READ,
            IntPtr.Zero,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            if (hAppend.IsInvalid)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open diagnostic log handle for append.");
            }
            ValidateRegularFileHandle(hAppend, expectedCanonicalLog);

            int offset = 0;
            while (offset < utf8Bytes.Length)
            {
                uint written;
                byte[] chunk = utf8Bytes;
                if (offset > 0)
                {
                    chunk = new byte[utf8Bytes.Length - offset];
                    Buffer.BlockCopy(utf8Bytes, offset, chunk, 0, chunk.Length);
                }
                if (!WriteFile(hAppend, chunk, (uint)chunk.Length, out written, IntPtr.Zero) || written == 0)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteFile to diagnostic log handle failed.");
                }
                offset += (int)written;
            }
        }
    }

    public static void AppendLogUnderValidatedRoot(
        string dataRoot,
        string logsSubDirName,
        string fileName,
        string rotatedFileName,
        byte[] utf8Bytes,
        long maxBytesBeforeRotate,
        bool sandboxMode,
        string serviceSid
    )
    {
        if (utf8Bytes == null) utf8Bytes = new byte[0];
        AssertNoReparsePointInPath(dataRoot);

        // Dual pinned directory handles: hRoot (DataRoot) + hLogs (logs), keeping both open while operating
        using (SafeFileHandle hRoot = CreateFileW(
            dataRoot,
            FILE_READ_ATTRIBUTES | READ_CONTROL,
            FILE_SHARE_ALL,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            if (hRoot.IsInvalid)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open DataRoot handle.");
            }
            if (!ValidateDirectorySecurityFromHandle(hRoot, true, sandboxMode, serviceSid, null))
            {
                throw new UnauthorizedAccessException("DataRoot handle failed ACL or ownership validation.");
            }
            string canonicalRoot = GetCanonicalHandlePath(hRoot);
            string expectedLogsCanonical = NormalizeKernelFinalPath(Path.Combine(canonicalRoot, logsSubDirName));

            using (SafeFileHandle hLogs = CreateFileW(
                expectedLogsCanonical,
                FILE_READ_ATTRIBUTES | READ_CONTROL,
                FILE_SHARE_ALL,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero))
            {
                if (hLogs.IsInvalid)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open logs directory handle under DataRoot.");
                }
                if (!ValidateDirectorySecurityFromHandle(hLogs, false, sandboxMode, serviceSid, null))
                {
                    throw new UnauthorizedAccessException("Logs handle failed ACL or ownership validation.");
                }
                string canonicalLogs = GetCanonicalHandlePath(hLogs);
                if (!string.Equals(canonicalLogs, expectedLogsCanonical, StringComparison.OrdinalIgnoreCase))
                {
                    throw new UnauthorizedAccessException("Logs handle canonical path mismatch: " + canonicalLogs + " != " + expectedLogsCanonical);
                }

                AppendLogOnCanonicalDir(canonicalLogs, fileName, rotatedFileName, utf8Bytes, maxBytesBeforeRotate);
            }
        }
    }

    public static void AppendLogSafely(string logsDir, string fileName, string rotatedFileName, byte[] utf8Bytes, long maxBytesBeforeRotate)
    {
        if (utf8Bytes == null) utf8Bytes = new byte[0];
        AssertNoReparsePointInPath(logsDir);

        string canonicalLogsDir;
        using (SafeFileHandle hDir = CreateFileW(
            logsDir,
            FILE_READ_ATTRIBUTES,
            FILE_SHARE_ALL,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
            IntPtr.Zero))
        {
            if (hDir.IsInvalid)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open logs directory handle.");
            }
            BY_HANDLE_FILE_INFORMATION dirInfo;
            if (!GetFileInformationByHandle(hDir, out dirInfo))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle(dir) failed.");
            }
            if ((dirInfo.FileAttributes & (uint)FileAttributes.ReparsePoint) != 0 ||
                (dirInfo.FileAttributes & (uint)FileAttributes.Directory) == 0)
            {
                throw new UnauthorizedAccessException("Logs directory handle validation failed.");
            }
            canonicalLogsDir = GetCanonicalHandlePath(hDir);
            AppendLogOnCanonicalDir(canonicalLogsDir, fileName, rotatedFileName, utf8Bytes, maxBytesBeforeRotate);
        }
    }
}
"@
}

function Test-IsPathReparsePoint {
    param([string]$TargetPath)

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        return $false
    }
    try {
        [MmsSafeDiagnosticLogWriter]::AssertNoReparsePointInPath($TargetPath)
        return $false
    }
    catch {
        return $true
    }
}

function Resolve-WindowsServiceSid {
    param([string]$TargetServiceName)

    if ([string]::IsNullOrWhiteSpace($TargetServiceName)) {
        return ""
    }

    try {
        $sidObj = (New-Object System.Security.Principal.NTAccount("NT SERVICE\$TargetServiceName")).Translate([System.Security.Principal.SecurityIdentifier])
        if ($null -ne $sidObj -and -not [string]::IsNullOrWhiteSpace($sidObj.Value)) {
            return $sidObj.Value
        }
    }
    catch {
        # Fallback to deterministic sc.exe showsid below when service is not yet created or temporarily removed during upgrade.
    }

    try {
        $ciOpts = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
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
        return ""
    }

    return ""
}

function Test-IsSafeDiagnosticDirectorySecurity {
    param(
        [string]$DirectoryPath,
        [switch]$SandboxMode,
        [switch]$IsDataRoot,
        [string]$ExpectedServiceName = "",
        [string]$OverrideOwnerSid = ""
    )

    if ([string]::IsNullOrWhiteSpace($DirectoryPath) -or -not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        return $false
    }

    $resolvedSvcSid = Resolve-WindowsServiceSid -TargetServiceName $ExpectedServiceName

    return [MmsSafeDiagnosticLogWriter]::ValidateDirectoryPathSecurity(
        $DirectoryPath,
        [bool]$IsDataRoot,
        [bool]$SandboxMode,
        $resolvedSvcSid,
        $OverrideOwnerSid
    )
}

function Protect-InstallerDiagnosticText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $ciOpts = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $icCiOpts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $sanitized = $Text

    # 1. Full PEM private key and certificate/CSR/PKCS7 blocks
    $sanitized = [regex]::Replace(
        $sanitized,
        '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
        '-----BEGIN PRIVATE KEY----- [REDACTED] -----END PRIVATE KEY-----',
        $ciOpts
    )
    $sanitized = [regex]::Replace(
        $sanitized,
        '-----BEGIN (?:[A-Z0-9 ]*CERTIFICATE(?: REQUEST)?|PKCS7)-----[\s\S]*?-----END (?:[A-Z0-9 ]*CERTIFICATE(?: REQUEST)?|PKCS7)-----',
        '-----BEGIN CERTIFICATE----- [REDACTED] -----END CERTIFICATE-----',
        $ciOpts
    )

    # 2. Truncated PEM blocks (without matching END footer, e.g. from stack/log truncation)
    $sanitized = [regex]::Replace(
        $sanitized,
        '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----(?![\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----)[\s\S]*$',
        '-----BEGIN PRIVATE KEY----- [REDACTED_TRUNCATED]',
        $ciOpts
    )
    $sanitized = [regex]::Replace(
        $sanitized,
        '-----BEGIN (?:[A-Z0-9 ]*CERTIFICATE(?: REQUEST)?|PKCS7)-----(?![\s\S]*?-----END (?:[A-Z0-9 ]*CERTIFICATE(?: REQUEST)?|PKCS7)-----)[\s\S]*$',
        '-----BEGIN CERTIFICATE----- [REDACTED_TRUNCATED]',
        $ciOpts
    )

    # 3. Authorization headers and Bearer / Basic credentials (CultureInvariant prevents tr-TR 'I' folding bugs)
    $sanitized = [regex]::Replace(
        $sanitized,
        '\b(Authorization\s*[:=]\s*)(Bearer|Basic)\s+(?!\[REDACTED\])[A-Za-z0-9._~+/=-]+',
        '$1$2 [REDACTED]',
        $icCiOpts
    )
    $sanitized = [regex]::Replace(
        $sanitized,
        '\bBearer\s+(?!\[REDACTED\])[A-Za-z0-9._~+/=-]+',
        'Bearer [REDACTED]',
        $icCiOpts
    )
    $sanitized = [regex]::Replace(
        $sanitized,
        '\bBasic\s+(?!\[REDACTED\])(?=[A-Za-z0-9+/]{8,}={0,2}\b)(?=[A-Za-z0-9+/=]*(?:[0-9+/=]|[A-Z].*[a-z]|[a-z].*[A-Z]))[A-Za-z0-9+/]{8,}={0,2}',
        'Basic [REDACTED]',
        $ciOpts
    )

    # 4. Known prefixed tokens and standalone/2-segment RFC 7519 JWT strings
    $sanitized = [regex]::Replace($sanitized, '\bmms_dt_(?!\[REDACTED\])[A-Za-z0-9._-]+', 'mms_dt_[REDACTED]', $ciOpts)
    $sanitized = [regex]::Replace($sanitized, '\bya29\.[A-Za-z0-9._-]+', '[REDACTED_TOKEN]', $ciOpts)
    $sanitized = [regex]::Replace($sanitized, '\b1//[A-Za-z0-9._-]+', '[REDACTED_TOKEN]', $ciOpts)
    $sanitized = [regex]::Replace($sanitized, '\bGOCSPX-[A-Za-z0-9._-]+', '[REDACTED_TOKEN]', $ciOpts)
    $sanitized = [regex]::Replace($sanitized, '\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{4,}\b', '[REDACTED_JWT]', $ciOpts)
    $sanitized = [regex]::Replace($sanitized, '\beyJ[A-Za-z0-9_-]{6,}\.eyJ[A-Za-z0-9_-]{6,}(?:\.[A-Za-z0-9_-]*)?(?=$|[\s"''\\,;)}\]])', '[REDACTED_JWT]', $ciOpts)

    # 5. Structured secret fields (1..3 backslash escaped JSON, JSON, key=value / key:value)
    # Deliberately preserves non-secret path/boolean fields such as pepper_file, admin_secret_file, recovery_key_configured.
    $secretKeyPattern = '(?:[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|jwt|api[_-]?key|private[_-]?key|recovery[_-]?key|master[_-]?key|encryption[_-]?key|signing[_-]?key|passphrase)|(?:[A-Za-z0-9_.-]*[_.-])?pepper(?:_(?:hex|b64|base64|raw|value|bytes))?)'
    $escapedJsonRegex = '(?<!\\)(\\{1,3})"(' + $secretKeyPattern + ')\1"(\s*:\s*)\1"(?:[^\\"]|(?!\1")\\)*\1"'
    $sanitized = [regex]::Replace($sanitized, $escapedJsonRegex, '$1"$2$1"$3$1"[REDACTED]$1"', $icCiOpts)

    $jsonRegex = '(?<!\\)"(' + $secretKeyPattern + ')(?<!\\)"(\s*:\s*)(?<!\\)"(?:[^"\\]|\\.)*"'
    $sanitized = [regex]::Replace($sanitized, $jsonRegex, '"$1"$2"[REDACTED]"', $icCiOpts)

    $kvRegex = '(?<!\\)(?<![A-Za-z0-9_.-])(' + $secretKeyPattern + ')(\s*[:=]\s*)(?!\[REDACTED\]|"\[REDACTED\]"|''\[REDACTED\]''|\\{1,3}"\[REDACTED\]\\{1,3}")(?:"[^"]*"|''[^'']*''|[^\s,;}\]]+)'
    $sanitized = [regex]::Replace($sanitized, $kvRegex, '$1$2[REDACTED]', $icCiOpts)

    # 6. CLI secret parameters (e.g., -Password ..., -ConfirmPurgeToken ...)
    $cliRegex = '((?:^|[\s,(])--?(?:password|passwd|pwd|confirm[_-]?purge[_-]?token|confirmpurgetoken|admin[_-]?secret|adminsecret|client[_-]?secret|clientsecret|device[_-]?token|devicetoken|access[_-]?token|accesstoken|refresh[_-]?token|refreshtoken|id[_-]?token|idtoken|token|jwt|api[_-]?key|apikey|master[_-]?key|masterkey|encryption[_-]?key|encryptionkey|private[_-]?key|privatekey|recovery[_-]?password|recoverypassword|backup[_-]?password|backuppassword|pepper(?:[_-]?hex|[_-]?b64|hex|b64)?|passphrase))(\s+)(?!\[REDACTED\])(?:"[^"]*"|''[^'']*''|[^\s,;}\]]+)'
    $sanitized = [regex]::Replace($sanitized, $cliRegex, '$1$2[REDACTED]', $icCiOpts)

    return $sanitized
}

function Write-InstallerDiagnosticLog {
    param(
        [string]$DataRoot,
        [int]$ExitCode,
        [string]$Code,
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null,
        [string]$Stage = ""
    )

    try {
        $resolvedStage = if (-not [string]::IsNullOrWhiteSpace($Stage)) {
            $Stage
        }
        elseif (-not [string]::IsNullOrWhiteSpace($script:CurrentInstallerStage)) {
            $script:CurrentInstallerStage
        }
        else {
            "Unknown"
        }

        $safeCode = if ([string]::IsNullOrWhiteSpace($Code)) { "ERR_UNKNOWN" } else { $Code }
        $safeMessage = Protect-InstallerDiagnosticText -Text $Message
        $exceptionType = ""
        $fullyQualifiedErrorId = ""
        $innerEntries = New-Object System.Collections.Generic.List[string]
        $scriptLocation = ""
        $scriptStack = ""
        $clrStack = ""

        if ($null -ne $ErrorRecord) {
            if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.FullyQualifiedErrorId)) {
                $fullyQualifiedErrorId = Protect-InstallerDiagnosticText -Text $ErrorRecord.FullyQualifiedErrorId
            }
            if ($null -ne $ErrorRecord.Exception) {
                $ex = $ErrorRecord.Exception
                $exceptionType = $ex.GetType().FullName

                # Bounded, cycle-safe InnerException chain (max 5 levels, masked at every level)
                $seenExceptions = New-Object System.Collections.Generic.List[object]
                $seenExceptions.Add($ex)
                $queue = New-Object System.Collections.Generic.Queue[object]
                if ($ex -is [System.AggregateException] -and $null -ne $ex.InnerExceptions -and $ex.InnerExceptions.Count -gt 0) {
                    foreach ($aggChild in $ex.InnerExceptions) {
                        if ($null -ne $aggChild) { $queue.Enqueue(@{ ex = $aggChild; depth = 1 }) }
                    }
                }
                elseif ($null -ne $ex.InnerException) {
                    $queue.Enqueue(@{ ex = $ex.InnerException; depth = 1 })
                }

                $truncatedInner = $false
                while ($queue.Count -gt 0) {
                    $node = $queue.Dequeue()
                    $curEx = $node.ex
                    $curDepth = [int]$node.depth
                    if ($curDepth -gt 5 -or $innerEntries.Count -ge 5) {
                        $truncatedInner = $true
                        continue
                    }

                    $alreadySeen = $false
                    foreach ($prevObj in $seenExceptions) {
                        if ([object]::ReferenceEquals($prevObj, $curEx)) {
                            $alreadySeen = $true
                            break
                        }
                    }
                    if ($alreadySeen) {
                        continue
                    }
                    $seenExceptions.Add($curEx)

                    $curMsg = Protect-InstallerDiagnosticText -Text $curEx.Message
                    $innerEntries.Add("InnerException[$curDepth]: $($curEx.GetType().FullName): $curMsg")

                    if ($curEx -is [System.AggregateException] -and $null -ne $curEx.InnerExceptions -and $curEx.InnerExceptions.Count -gt 0) {
                        foreach ($childEx in $curEx.InnerExceptions) {
                            if ($null -ne $childEx) {
                                if ($curDepth -ge 5) {
                                    $truncatedInner = $true
                                }
                                else {
                                    $queue.Enqueue(@{ ex = $childEx; depth = ($curDepth + 1) })
                                }
                            }
                        }
                    }
                    elseif ($null -ne $curEx.InnerException) {
                        if ($curDepth -ge 5) {
                            $truncatedInner = $true
                        }
                        else {
                            $queue.Enqueue(@{ ex = $curEx.InnerException; depth = ($curDepth + 1) })
                        }
                    }
                }
                if ($truncatedInner) {
                    $innerEntries.Add("InnerException[truncated]: Additional inner exceptions omitted (max depth 5).")
                }

                if (-not [string]::IsNullOrWhiteSpace($ex.StackTrace)) {
                    $maskedClr = Protect-InstallerDiagnosticText -Text $ex.StackTrace
                    if ($maskedClr.Length -gt 1500) {
                        $clrStack = (Protect-InstallerDiagnosticText -Text ($maskedClr.Substring(0, 1500))) + "... [TRUNCATED]"
                    }
                    else {
                        $clrStack = $maskedClr
                    }
                }
            }
            if ($null -ne $ErrorRecord.InvocationInfo) {
                $inv = $ErrorRecord.InvocationInfo
                $scriptBase = if (-not [string]::IsNullOrWhiteSpace($inv.ScriptName)) {
                    [System.IO.Path]::GetFileName($inv.ScriptName)
                }
                else {
                    "mms_installer_engine.ps1"
                }
                if ($inv.ScriptLineNumber -gt 0) {
                    $scriptLocation = "${scriptBase}:$($inv.ScriptLineNumber)"
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
                $scriptStack = Protect-InstallerDiagnosticText -Text $ErrorRecord.ScriptStackTrace
            }
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("================================================================================")
        $lines.Add("TimestampUtc: $((Get-Date).ToUniversalTime().ToString('o'))")
        $lines.Add("Action: $Action")
        $lines.Add("AppVersion: $AppVersion")
        $lines.Add("MsiManaged: $([bool]$MsiManaged)")
        $lines.Add("TestSandboxMode: $([bool]$TestSandboxMode)")
        $lines.Add("Stage: $resolvedStage")
        $lines.Add("ExitCode: $ExitCode")
        $lines.Add("ErrorCode: $safeCode")
        if (-not [string]::IsNullOrWhiteSpace($fullyQualifiedErrorId)) {
            $lines.Add("FullyQualifiedErrorId: $fullyQualifiedErrorId")
        }
        $lines.Add("Message: $safeMessage")
        if (-not [string]::IsNullOrWhiteSpace($exceptionType)) {
            $lines.Add("ExceptionType: $exceptionType")
        }
        foreach ($innerLine in $innerEntries) {
            $lines.Add($innerLine)
        }
        if (-not [string]::IsNullOrWhiteSpace($scriptLocation)) {
            $lines.Add("ScriptLocation: $scriptLocation")
        }
        if (-not [string]::IsNullOrWhiteSpace($scriptStack)) {
            $lines.Add("ScriptStackTrace: $scriptStack")
        }
        if (-not [string]::IsNullOrWhiteSpace($clrStack)) {
            $lines.Add("ClrStackTrace: $clrStack")
        }
        $lines.Add("")

        $entryText = ($lines -join [Environment]::NewLine)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

        if (-not [string]::IsNullOrWhiteSpace($DataRoot)) {
            try {
                $icaclsBin = if ([string]::IsNullOrWhiteSpace($script:DiagnosticIcaclsPath)) { "icacls.exe" } else { $script:DiagnosticIcaclsPath }
                $curUserSid = $null
                if ([bool]$TestSandboxMode) {
                    $curUserSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
                }

                $resolvedSvcSid = Resolve-WindowsServiceSid -TargetServiceName $ServiceName

                [MmsSafeDiagnosticLogWriter]::AssertNoReparsePointInPath($DataRoot)
                if (Test-Path -LiteralPath $DataRoot) {
                    if (-not (Test-Path -LiteralPath $DataRoot -PathType Container)) {
                        throw "Unsafe DataRoot path (non-directory): $DataRoot"
                    }
                    if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath $DataRoot -IsDataRoot -SandboxMode:([bool]$TestSandboxMode) -ExpectedServiceName $ServiceName)) {
                        throw "Unsafe existing DataRoot directory ACL or ownership: $DataRoot"
                    }
                }
                else {
                    [MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity($DataRoot, [bool]$TestSandboxMode)
                    $rootIcaclsArgs = @($DataRoot, "/inheritance:r", "/grant:r", "*S-1-5-18:(OI)(CI)F", "/grant:r", "*S-1-5-32-544:(OI)(CI)F")
                    if ([bool]$TestSandboxMode -and -not [string]::IsNullOrWhiteSpace($curUserSid) -and $curUserSid -ne "S-1-5-18" -and $curUserSid -ne "S-1-5-32-544") {
                        $rootIcaclsArgs += @("/grant:r", "*${curUserSid}:(OI)(CI)F")
                    }
                    $null = & $icaclsBin @rootIcaclsArgs 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Diagnostic DataRoot ACL hardening failed ($LASTEXITCODE): $DataRoot"
                    }
                    if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath $DataRoot -IsDataRoot -SandboxMode:([bool]$TestSandboxMode) -ExpectedServiceName $ServiceName)) {
                        throw "Created DataRoot directory failed post-ACL verification: $DataRoot"
                    }
                }

                $logsDir = Join-Path $DataRoot "logs"
                if (Test-Path -LiteralPath $logsDir) {
                    if (-not (Test-Path -LiteralPath $logsDir -PathType Container)) {
                        throw "Unsafe logs path (non-directory): $logsDir"
                    }
                    if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath $logsDir -SandboxMode:([bool]$TestSandboxMode) -ExpectedServiceName $ServiceName)) {
                        throw "Unsafe existing logs directory ACL or ownership: $logsDir"
                    }
                }
                else {
                    [MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity($logsDir, [bool]$TestSandboxMode)
                    $icaclsArgs = @($logsDir, "/inheritance:r", "/grant:r", "*S-1-5-18:(OI)(CI)F", "/grant:r", "*S-1-5-32-544:(OI)(CI)F")
                    if ([bool]$TestSandboxMode -and -not [string]::IsNullOrWhiteSpace($curUserSid) -and $curUserSid -ne "S-1-5-18" -and $curUserSid -ne "S-1-5-32-544") {
                        $icaclsArgs += @("/grant:r", "*${curUserSid}:(OI)(CI)F")
                    }
                    $null = & $icaclsBin @icaclsArgs 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        throw "Diagnostic logs ACL hardening failed ($LASTEXITCODE): $logsDir"
                    }
                    if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath $logsDir -SandboxMode:([bool]$TestSandboxMode) -ExpectedServiceName $ServiceName)) {
                        throw "Created diagnostic logs directory failed post-ACL verification: $logsDir"
                    }
                }

                [MmsSafeDiagnosticLogWriter]::AppendLogUnderValidatedRoot(
                    $DataRoot,
                    "logs",
                    "installer-diagnostics.log",
                    "installer-diagnostics.log.1",
                    $utf8NoBom.GetBytes($entryText),
                    1048576,
                    [bool]$TestSandboxMode,
                    $resolvedSvcSid
                )
            }
            catch {
                # Fail-closed logging: halt log write on any ACL/ownership/TOCTOU/reparse error without masking original installer error
            }
        }
    }
    catch {
        # Never mask or replace original installer error
    }
}

function Fail-Installer {
    param(
        [int]$ExitCode,
        [string]$Code,
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord = $null,
        [string]$Stage = "",
        [switch]$SkipDiagnosticLog
    )
    $safeMessage = Protect-InstallerDiagnosticText -Text $Message
    if (-not $SkipDiagnosticLog) {
        Write-InstallerDiagnosticLog -DataRoot $ProgramDataRoot -ExitCode $ExitCode -Code $Code -Message $safeMessage -ErrorRecord $ErrorRecord -Stage $Stage
    }
    [Console]::Error.WriteLine("[$Code] $safeMessage")
    exit $ExitCode
}

if (-not [string]::IsNullOrWhiteSpace($MsiContext)) {
    $script:CurrentInstallerStage = "ParseMsiContext"
    $MsiManaged = $true
    $ctxParts = $MsiContext.Split('|')
    $ctxMode = $ctxParts[0].Trim()
    if ($ctxMode -eq "Install") {
        $Action = "Install"
        if ($ctxParts.Length -ne 6) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Install MsiContext beklenen 6 alani icermiyor." -Stage "ParseMsiContext"
        }
        $InstallDir = $ctxParts[1]
        $StagingDir = $ctxParts[1]
        $AppVersion = $ctxParts[2].Trim()
        $parsedPort = 0
        $parsedDiscPort = 0
        if (-not [int]::TryParse($ctxParts[3].Trim(), [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Gecersiz HUB_PORT: $($ctxParts[3])" -Stage "ParseMsiContext"
        }
        if (-not [int]::TryParse($ctxParts[4].Trim(), [ref]$parsedDiscPort) -or $parsedDiscPort -lt 1 -or $parsedDiscPort -gt 65535) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Gecersiz DISCOVERY_PORT: $($ctxParts[4])" -Stage "ParseMsiContext"
        }
        $Port = $parsedPort
        $DiscoveryPort = $parsedDiscPort
        $AllowDeferredTlsStart = $ctxParts[5].Trim()
    }
    elseif ($ctxMode -eq "Uninstall") {
        $Action = "Uninstall"
        if ($ctxParts.Length -lt 7 -or ($ctxParts[$ctxParts.Length - 1].Trim() -ne "END")) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Uninstall MsiContext beklenen bicimde degil." -Stage "ParseMsiContext"
        }
        $InstallDir = $ctxParts[1]
        $parsedPort = 0
        $parsedDiscPort = 0
        if (-not [int]::TryParse($ctxParts[2].Trim(), [ref]$parsedPort) -or $parsedPort -lt 1 -or $parsedPort -gt 65535) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Gecersiz HUB_PORT: $($ctxParts[2])" -Stage "ParseMsiContext"
        }
        if (-not [int]::TryParse($ctxParts[3].Trim(), [ref]$parsedDiscPort) -or $parsedDiscPort -lt 1 -or $parsedDiscPort -gt 65535) {
            Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
                -Message "Gecersiz DISCOVERY_PORT: $($ctxParts[3])" -Stage "ParseMsiContext"
        }
        $Port = $parsedPort
        $DiscoveryPort = $parsedDiscPort
        $PurgeUserDataValue = $ctxParts[4].Trim()
        $ConfirmPurgeToken = ($ctxParts[5..($ctxParts.Length - 2)] -join '|').Trim()
    }
    else {
        Fail-Installer -ExitCode 71 -Code "ERR_INVALID_MSI_CONTEXT" `
            -Message "Bilinmeyen MsiContext modu: $ctxMode" -Stage "ParseMsiContext"
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
        [string]$SidType = "UNRESTRICTED",
        [switch]$ClearStamp
    )
    $f = Get-SandboxScmFile $DataRoot
    $dir = Split-Path -Parent $f
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $existing = $null
    if (-not $ClearStamp -and (Test-Path -LiteralPath $f)) {
        try {
            $existing = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        }
        catch {
            $existing = $null
        }
    }

    $payload = [ordered]@{
        service_name = $Name
        status       = $Status
        version      = $Version
        bin_path     = $BinPath
        account      = $Account
        sid_type     = $SidType
        updated_at   = (Get-Date).ToUniversalTime().ToString("o")
    }

    if ($null -ne $existing) {
        foreach ($stampField in @("mms_app_version", "mms_xml_sha256", "mms_previous_version", "mms_tx_id", "mms_wrapper_path", "stamped_at_utc", "delete_pending")) {
            if ($null -ne $existing.PSObject.Properties[$stampField]) {
                $payload[$stampField] = $existing.PSObject.Properties[$stampField].Value
            }
        }
    }

    $tmp = $f + ".tmp"
    Set-Content -LiteralPath $tmp -Value ($payload | ConvertTo-Json -Depth 4) -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $f -Force
}

function Remove-SandboxService {
    param([string]$DataRoot)
    $f = Get-SandboxScmFile $DataRoot
    if (Test-Path $f) { Remove-Item -Path $f -Force }
}

$script:InRollbackFlow = $false

function Add-SandboxScmOp {
    param(
        [string]$DataRoot,
        [string]$Operation
    )
    $f = Join-Path $DataRoot "run\sandbox_scm_ops.log"
    $dir = Split-Path -Parent $f
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $f -Value $Operation -Encoding ASCII
}

function Add-SandboxInstallScmOp {
    param(
        [string]$DataRoot,
        [string]$Operation
    )
    $f = Join-Path $DataRoot "run\sandbox_install_scm_ops.log"
    $dir = Split-Path -Parent $f
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $f -Value $Operation -Encoding ASCII
}

function Get-SandboxFirewallFile {
    param([string]$DataRoot)
    return Join-Path $DataRoot "run\sandbox_firewall.json"
}

function Read-SandboxFirewallRules {
    param([string]$DataRoot)
    $f = Get-SandboxFirewallFile $DataRoot
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $raw = Get-Content -LiteralPath $f -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $parsed) { return @() }
    return @($parsed | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Write-SandboxFirewallRules {
    param(
        [string]$DataRoot,
        [string[]]$Rules
    )
    $f = Get-SandboxFirewallFile $DataRoot
    $dir = Split-Path -Parent $f
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $cleanRules = @()
    if ($null -ne $Rules) {
        $cleanRules = @($Rules | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $tmp = $f + ".tmp"
    Set-Content -LiteralPath $tmp -Value (ConvertTo-Json -InputObject $cleanRules -Depth 3) -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $f -Force
}

function Get-InstallerTxStateFile {
    param([string]$DataRoot)
    return Join-Path $DataRoot "run\installer_tx_state.json"
}

function Get-InstallerTxPrevStateFile {
    param([string]$DataRoot)
    return Join-Path $DataRoot "run\installer_tx_state.previous.json"
}

function Test-ValidTxStateObject {
    param($Obj)
    if ($null -eq $Obj) { return $false }
    $propNames = @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
    if (($propNames -notcontains "status") -or ($propNames -notcontains "mode")) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace([string]$Obj.status) -or [string]::IsNullOrWhiteSpace([string]$Obj.mode)) {
        return $false
    }
    return $true
}

function Read-InstallerTxStateSafe {
    param([string]$DataRoot)

    $primaryFile = Get-InstallerTxStateFile $DataRoot
    $prevFile = Get-InstallerTxPrevStateFile $DataRoot

    $result = [ordered]@{
        State           = $null
        Source          = "NONE"
        PrimaryExists   = (Test-Path -LiteralPath $primaryFile)
        PrimaryCorrupt  = $false
        PreviousExists  = (Test-Path -LiteralPath $prevFile)
        PreviousCorrupt = $false
        ErrorDetail     = ""
    }

    if ($result.PrimaryExists) {
        try {
            $rawPrimary = Get-Content -LiteralPath $primaryFile -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($rawPrimary)) {
                throw "Empty primary transaction state file."
            }
            $objPrimary = $rawPrimary | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-ValidTxStateObject $objPrimary)) {
                throw "Invalid primary transaction state schema (missing status/mode)."
            }
            $result.State = $objPrimary
            $result.Source = "PRIMARY"
            return $result
        }
        catch {
            $result.PrimaryCorrupt = $true
            $result.ErrorDetail = "Primary tx state parse error: $($_.Exception.Message)"
        }
    }

    if ($result.PreviousExists) {
        try {
            $rawPrev = Get-Content -LiteralPath $prevFile -Raw -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($rawPrev)) {
                throw "Empty previous transaction state file."
            }
            $objPrev = $rawPrev | ConvertFrom-Json -ErrorAction Stop
            if (-not (Test-ValidTxStateObject $objPrev)) {
                throw "Invalid previous transaction state schema (missing status/mode)."
            }
            $result.State = $objPrev
            $result.Source = "PREVIOUS"
            return $result
        }
        catch {
            $result.PreviousCorrupt = $true
            $prevErr = "Previous tx state parse error: $($_.Exception.Message)"
            $result.ErrorDetail = if ([string]::IsNullOrWhiteSpace($result.ErrorDetail)) { $prevErr } else { "$($result.ErrorDetail) | $prevErr" }
        }
    }

    if ($result.PrimaryCorrupt) {
        $result.Source = "CORRUPT"
    }
    return $result
}

function Read-InstallerTxState {
    param([string]$DataRoot)
    return (Read-InstallerTxStateSafe -DataRoot $DataRoot).State
}

function Resolve-ValidatedManifestFallback {
    param(
        [string]$DataRoot,
        [string]$ExpectedServiceName
    )

    $manifestPrev = Join-Path $DataRoot "config\install_manifest.previous.json"
    $binPrev = Join-Path $DataRoot "bin.previous"
    $res = [ordered]@{
        IsValid                   = $false
        Reason                    = ""
        PreviousVersion           = $null
        HadPreviousServiceRunning = $false
        ServiceState              = ""
        ManifestPrevPath          = $manifestPrev
        BinPrevPath               = $binPrev
    }

    if (-not (Test-Path -LiteralPath $manifestPrev -PathType Leaf)) {
        $res.Reason = "install_manifest.previous.json missing or not a file"
        return $res
    }
    try {
        $mfItem = Get-Item -LiteralPath $manifestPrev -Force -ErrorAction Stop
        if ($mfItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $res.Reason = "install_manifest.previous.json is a reparse point"
            return $res
        }
        $rawMf = Get-Content -LiteralPath $manifestPrev -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($rawMf)) {
            $res.Reason = "install_manifest.previous.json is empty"
            return $res
        }
        $mfObj = $rawMf | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $res.Reason = "install_manifest.previous.json parse error: $($_.Exception.Message)"
        return $res
    }

    $verText = ([string]$mfObj.app_version).Trim()
    $parsedVer = $null
    if ([string]::IsNullOrWhiteSpace($verText) -or -not [Version]::TryParse(($verText -replace '\+.*$', ''), [ref]$parsedVer)) {
        $res.Reason = "install_manifest.previous.json has missing or invalid app_version: $verText"
        return $res
    }

    $mfSvcName = ([string]$mfObj.service_name).Trim()
    if ([string]::IsNullOrWhiteSpace($mfSvcName) -or -not [string]::Equals($mfSvcName, $ExpectedServiceName, [System.StringComparison]::OrdinalIgnoreCase)) {
        $res.Reason = "install_manifest.previous.json service_name mismatch ($mfSvcName != $ExpectedServiceName)"
        return $res
    }

    $mfState = ([string]$mfObj.service_state).Trim()
    $hadRunning = $false
    if ($mfState -ceq "RUNNING") {
        $hadRunning = $true
    } elseif ($mfState -ceq "PENDING_TLS_PROVISIONING") {
        $hadRunning = $false
    } else {
        $res.Reason = "install_manifest.previous.json has unknown or unsupported service_state: $mfState"
        return $res
    }

    $mfRootProp = $mfObj.PSObject.Properties["program_data_root"]
    if ($null -eq $mfRootProp) {
        $res.Reason = "install_manifest.previous.json missing required program_data_root"
        return $res
    }
    $rawMfRoot = $mfRootProp.Value
    if (($null -eq $rawMfRoot) -or ($rawMfRoot -isnot [string]) -or [string]::IsNullOrWhiteSpace($rawMfRoot)) {
        $res.Reason = "install_manifest.previous.json has null or empty program_data_root"
        return $res
    }
    $trimmedMfRoot = $rawMfRoot.Trim()
    if ([regex]::IsMatch($trimmedMfRoot, '[*?"<>|]')) {
        $res.Reason = "install_manifest.previous.json has invalid characters in program_data_root: $trimmedMfRoot"
        return $res
    }
    foreach ($badCh in [System.IO.Path]::GetInvalidPathChars()) {
        if ($trimmedMfRoot.IndexOf($badCh) -ge 0) {
            $res.Reason = "install_manifest.previous.json has invalid path character in program_data_root"
            return $res
        }
    }
    if (($trimmedMfRoot -notmatch '^[A-Za-z]:[\\/]') -or ($trimmedMfRoot.IndexOf(':', 2) -ge 0)) {
        $res.Reason = "install_manifest.previous.json program_data_root is not a valid rooted local path: $trimmedMfRoot"
        return $res
    }
    try {
        $normMfRoot = [System.IO.Path]::GetFullPath($trimmedMfRoot)
        if ($normMfRoot.Length -gt 3) {
            $normMfRoot = $normMfRoot.TrimEnd('\', '/')
        }
    }
    catch {
        $res.Reason = "install_manifest.previous.json invalid program_data_root ($trimmedMfRoot): $($_.Exception.Message)"
        return $res
    }
    $normExpectedRoot = Normalize-InstallerPath $DataRoot
    if ([string]::IsNullOrWhiteSpace($normExpectedRoot) -or -not [string]::Equals($normMfRoot, $normExpectedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $res.Reason = "install_manifest.previous.json program_data_root mismatch ($normMfRoot != $normExpectedRoot)"
        return $res
    }

    if (-not (Test-Path -LiteralPath $binPrev -PathType Container)) {
        $res.Reason = "bin.previous directory missing (refusing to treat current bin as previous version)"
        return $res
    }
    try {
        $binPrevItem = Get-Item -LiteralPath $binPrev -Force -ErrorAction Stop
        if ($binPrevItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $res.Reason = "bin.previous is a reparse point"
            return $res
        }
    } catch {
        $res.Reason = "bin.previous inspection error: $($_.Exception.Message)"
        return $res
    }

    foreach ($reqBin in @("mms_backend.exe", "MarketMMSService.exe", "MarketMMSService.xml", "sqlite3.dll")) {
        $binFile = Join-Path $binPrev $reqBin
        if (-not (Test-Path -LiteralPath $binFile -PathType Leaf)) {
            $res.Reason = "bin.previous missing required binary: $reqBin"
            return $res
        }
        $bfItem = Get-Item -LiteralPath $binFile -Force -ErrorAction Stop
        if (($bfItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or ($bfItem.Length -le 0)) {
            $res.Reason = "bin.previous binary invalid or empty: $reqBin"
            return $res
        }
    }

    $res.IsValid = $true
    $res.PreviousVersion = $verText
    $res.HadPreviousServiceRunning = $hadRunning
    $res.ServiceState = $mfState
    return $res
}

function Get-FileSha256Upper {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "[ERR_MISSING_RUNTIME_ARTIFACT] SHA-256 icin dosya bulunamadi: $FilePath"
    }
    $item = Get-Item -LiteralPath $FilePath -Force -ErrorAction Stop
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "[ERR_SECURITY_VIOLATION] Reparse point dosya uzerinde SHA-256 hesaplanamaz: $FilePath"
    }
    return (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Test-IsExpectedLocalServiceAccount {
    param([string]$AccountName)
    if ([string]::IsNullOrWhiteSpace($AccountName)) {
        return $false
    }
    $trimmed = $AccountName.Trim()
    return (
        [string]::Equals($trimmed, "NT AUTHORITY\LocalService", [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($trimmed, "LocalService", [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Resolve-WindowsServiceImageExecutable {
    param([string]$TargetServiceName)
    if ([string]::IsNullOrWhiteSpace($TargetServiceName)) {
        return ""
    }
    $regPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$TargetServiceName"
    if (-not (Test-Path -LiteralPath $regPath)) {
        return ""
    }
    try {
        $props = Get-ItemProperty -LiteralPath $regPath -Name "ImagePath" -ErrorAction Stop
        $rawImage = [string]$props.ImagePath
        if ([string]::IsNullOrWhiteSpace($rawImage)) {
            return ""
        }
        $trimmed = [Environment]::ExpandEnvironmentVariables($rawImage.Trim())
        if ($trimmed.StartsWith('"')) {
            $endQuote = $trimmed.IndexOf('"', 1)
            if ($endQuote -gt 1) {
                return (Normalize-InstallerPath ($trimmed.Substring(1, $endQuote - 1)))
            }
        }
        $exeMatch = [regex]::Match($trimmed, '^(.+?\.exe)(?:\s|$)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($exeMatch.Success) {
            return (Normalize-InstallerPath $exeMatch.Groups[1].Value)
        }
        return (Normalize-InstallerPath $trimmed)
    }
    catch {
        return ""
    }
}

function Read-ScmServiceIdentitySnapshot {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName
    )

    $snap = [ordered]@{
        Exists            = $false
        ServiceName       = $TargetServiceName
        Status            = ""
        DeletePending     = $false
        ImageExecutable   = ""
        ObjectName        = ""
        ServiceSidType    = ""
        StampedVersion    = ""
        StampedXmlSha256  = ""
        StampedTxId       = ""
        StampedPrevVer    = ""
    }

    if ($TestSandboxMode) {
        $sb = Read-SandboxService $DataRoot
        if ($null -eq $sb) {
            return $snap
        }
        $snap.Exists = $true
        $snap.ServiceName = [string]$sb.service_name
        $snap.Status = [string]$sb.status
        $snap.DeletePending = ($FaultInjectionStage -eq "ScmDeletePending")
        if ($null -ne $sb.PSObject.Properties["delete_pending"] -and [bool]$sb.delete_pending) {
            $snap.DeletePending = $true
        }
        $snap.ImageExecutable = Normalize-InstallerPath ([string]$sb.bin_path)
        $snap.ObjectName = [string]$sb.account
        $snap.ServiceSidType = ([string]$sb.sid_type).Trim().ToUpperInvariant()
        if ($null -ne $sb.PSObject.Properties["mms_app_version"] -and $null -ne $sb.mms_app_version) {
            $snap.StampedVersion = ([string]$sb.mms_app_version).Trim()
        }
        if ($null -ne $sb.PSObject.Properties["mms_xml_sha256"] -and $null -ne $sb.mms_xml_sha256) {
            $snap.StampedXmlSha256 = ([string]$sb.mms_xml_sha256).Trim().ToUpperInvariant()
        }
        if ($null -ne $sb.PSObject.Properties["mms_tx_id"] -and $null -ne $sb.mms_tx_id) {
            $snap.StampedTxId = ([string]$sb.mms_tx_id).Trim()
        }
        if ($null -ne $sb.PSObject.Properties["mms_previous_version"] -and $null -ne $sb.mms_previous_version) {
            $snap.StampedPrevVer = ([string]$sb.mms_previous_version).Trim()
        }
        return $snap
    }

    $svc = Get-Service -Name $TargetServiceName -ErrorAction SilentlyContinue
    $regPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$TargetServiceName"
    $regExists = Test-Path -LiteralPath $regPath
    if ($null -eq $svc -and -not $regExists) {
        return $snap
    }

    $snap.Exists = $true
    if ($null -ne $svc) {
        $snap.ServiceName = [string]$svc.Name
        $snap.Status = [string]$svc.Status
    }
    $snap.ImageExecutable = Resolve-WindowsServiceImageExecutable -TargetServiceName $TargetServiceName
    if ($FaultInjectionStage -eq "ScmDeletePending") {
        $snap.DeletePending = $true
    }

    if ($regExists) {
        try {
            $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
            if ($null -ne $props.PSObject.Properties["ObjectName"]) {
                $snap.ObjectName = [string]$props.ObjectName
            }
            if ($null -ne $props.PSObject.Properties["ServiceSidType"]) {
                $sidNum = [int]$props.ServiceSidType
                $snap.ServiceSidType = switch ($sidNum) {
                    1 { "UNRESTRICTED" }
                    3 { "RESTRICTED" }
                    default { "NONE" }
                }
            }
            if ($null -ne $props.PSObject.Properties["DeleteFlag"] -and [int]$props.DeleteFlag -ne 0) {
                $snap.DeletePending = $true
            }
        }
        catch {
            # Leave missing registry fields empty so disposition fails closed.
        }

        $paramPath = Join-Path $regPath "Parameters"
        if (Test-Path -LiteralPath $paramPath) {
            try {
                $pProps = Get-ItemProperty -LiteralPath $paramPath -ErrorAction Stop
                if ($null -ne $pProps.PSObject.Properties["MmsAppVersion"] -and $null -ne $pProps.MmsAppVersion) {
                    $snap.StampedVersion = ([string]$pProps.MmsAppVersion).Trim()
                }
                if ($null -ne $pProps.PSObject.Properties["MmsXmlSha256"] -and $null -ne $pProps.MmsXmlSha256) {
                    $snap.StampedXmlSha256 = ([string]$pProps.MmsXmlSha256).Trim().ToUpperInvariant()
                }
                if ($null -ne $pProps.PSObject.Properties["MmsTxId"] -and $null -ne $pProps.MmsTxId) {
                    $snap.StampedTxId = ([string]$pProps.MmsTxId).Trim()
                }
                if ($null -ne $pProps.PSObject.Properties["MmsPreviousVersion"] -and $null -ne $pProps.MmsPreviousVersion) {
                    $snap.StampedPrevVer = ([string]$pProps.MmsPreviousVersion).Trim()
                }
            }
            catch {}
        }
    }

    if (-not $snap.DeletePending) {
        try {
            $null = & sc.exe qc $TargetServiceName 2>&1
            if ($LASTEXITCODE -eq 1072) {
                $snap.DeletePending = $true
            }
        }
        catch {}
    }

    return $snap
}

function Write-ScmServiceIdentityStamp {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName,
        [string]$StampVersion,
        [string]$XmlSha256,
        [string]$PreviousVersion = "",
        [string]$TxId = "",
        [string]$WrapperPath = ""
    )

    if ($FaultInjectionStage -eq "ScmStamp") {
        throw "[ERR_SCM_STAMP_WRITE_FAILED] Simule edilmis SCM registry kimlik damgasi yazma hatasi."
    }
    if ([string]::IsNullOrWhiteSpace($StampVersion) -or [string]::IsNullOrWhiteSpace($XmlSha256)) {
        throw "[ERR_SCM_STAMP_WRITE_FAILED] Gecersiz veya bos SCM kimlik damgasi degerleri."
    }

    $upperSha = $XmlSha256.Trim().ToUpperInvariant()
    $normWrapper = Normalize-InstallerPath $WrapperPath
    $stampedAt = (Get-Date).ToUniversalTime().ToString("o")

    if ($TestSandboxMode) {
        $f = Get-SandboxScmFile $DataRoot
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            throw "[ERR_SCM_STAMP_WRITE_FAILED] Sandbox SCM kaydi bulunamadi."
        }
        $cur = Get-Content -LiteralPath $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $payload = [ordered]@{
            service_name         = [string]$cur.service_name
            status               = [string]$cur.status
            version              = [string]$cur.version
            bin_path             = [string]$cur.bin_path
            account              = [string]$cur.account
            sid_type             = [string]$cur.sid_type
            updated_at           = $stampedAt
            mms_app_version      = $StampVersion.Trim()
            mms_xml_sha256       = $upperSha
            mms_previous_version = [string]$PreviousVersion
            mms_tx_id            = [string]$TxId
            mms_wrapper_path     = $normWrapper
            stamped_at_utc       = $stampedAt
            delete_pending       = $false
        }
        $tmp = $f + ".tmp"
        Set-Content -LiteralPath $tmp -Value ($payload | ConvertTo-Json -Depth 4) -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $f -Force -ErrorAction Stop

        $verifySnap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
        if (-not $verifySnap.Exists -or ($verifySnap.StampedVersion -ne $StampVersion.Trim()) -or ($verifySnap.StampedXmlSha256 -ne $upperSha)) {
            throw "[ERR_SCM_STAMP_WRITE_FAILED] Sandbox SCM kimlik damgasi okuma dogrulamasini gecemedi."
        }
        if ($script:InRollbackFlow) {
            Add-SandboxScmOp -DataRoot $DataRoot -Operation "stamp:$($StampVersion.Trim())"
        }
        else {
            Add-SandboxInstallScmOp -DataRoot $DataRoot -Operation "stamp:$($StampVersion.Trim())"
        }
        return
    }

    $svcRegPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$TargetServiceName"
    if (-not (Test-Path -LiteralPath $svcRegPath)) {
        throw "[ERR_SCM_STAMP_WRITE_FAILED] SCM servis kayit defteri anahtari bulunamadi: $svcRegPath"
    }
    $paramRegPath = Join-Path $svcRegPath "Parameters"
    try {
        if (-not (Test-Path -LiteralPath $paramRegPath)) {
            New-Item -Path $paramRegPath -Force -ErrorAction Stop | Out-Null
        }
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsAppVersion" -Value ($StampVersion.Trim()) -Type String -ErrorAction Stop
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsXmlSha256" -Value $upperSha -Type String -ErrorAction Stop
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsPreviousVersion" -Value ([string]$PreviousVersion) -Type String -ErrorAction Stop
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsTxId" -Value ([string]$TxId) -Type String -ErrorAction Stop
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsWrapperPath" -Value $normWrapper -Type String -ErrorAction Stop
        Set-ItemProperty -LiteralPath $paramRegPath -Name "MmsStampedAtUtc" -Value $stampedAt -Type String -ErrorAction Stop
    }
    catch {
        throw "[ERR_SCM_STAMP_WRITE_FAILED] SCM registry kimlik damgasi yazilamadi ($paramRegPath): $($_.Exception.Message)"
    }

    $verifySnap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
    if (-not $verifySnap.Exists -or ($verifySnap.StampedVersion -ne $StampVersion.Trim()) -or ($verifySnap.StampedXmlSha256 -ne $upperSha)) {
        throw "[ERR_SCM_STAMP_WRITE_FAILED] SCM registry kimlik damgasi geri-okuma dogrulamasi basarisiz."
    }
}

function Invoke-VerifiedServiceStop {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName,
        [string]$ExpectedWrapperPath
    )
    $snap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
    if (-not $snap.Exists) {
        return
    }
    $normExpected = Normalize-InstallerPath $ExpectedWrapperPath
    if ([string]::IsNullOrWhiteSpace($snap.ImageExecutable) -or -not [string]::Equals($snap.ImageExecutable, $normExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "[ERR_FOREIGN_SERVICE_PROTECTED] Yabanci SCM servisi durdurulamaz ($TargetServiceName ImagePath=$($snap.ImageExecutable) != $normExpected)."
    }
    if ($snap.DeletePending -or $FaultInjectionStage -eq "ScmDeletePending") {
        throw "[ERR_SCM_DELETE_PENDING] SCM servisi DELETE_PENDING durumunda durdurulamaz: $TargetServiceName"
    }
    if ($FaultInjectionStage -eq "ServiceStop") {
        throw "[ERR_SERVICE_STOP_FAILED] Simule edilmis servis durdurma hatasi: $TargetServiceName"
    }

    if ($snap.Status -ne "Stopped") {
        if ($TestSandboxMode) {
            $verTag = if (-not [string]::IsNullOrWhiteSpace($snap.StampedVersion)) { $snap.StampedVersion } else { "unstamped" }
            if ($script:InRollbackFlow) {
                Add-SandboxScmOp -DataRoot $DataRoot -Operation "stop:$verTag"
            }
            else {
                Add-SandboxInstallScmOp -DataRoot $DataRoot -Operation "stop:$verTag"
            }
            $sb = Read-SandboxService $DataRoot
            Write-SandboxService -DataRoot $DataRoot -Name $TargetServiceName -Status "Stopped" -Version ([string]$sb.version) -BinPath ([string]$sb.bin_path) -Account ([string]$sb.account) -SidType ([string]$sb.sid_type)
        }
        else {
            if (Test-Path -LiteralPath $normExpected -PathType Leaf) {
                $stopOut = & $normExpected stop 2>&1
            }
            else {
                $stopOut = & sc.exe stop $TargetServiceName 2>&1
            }
            $ec = $LASTEXITCODE
            if ($ec -ne 0 -and $ec -ne 1062) {
                throw "[ERR_SERVICE_STOP_FAILED] Servis durdurma basarisiz ($ec): $stopOut"
            }
            $svcObj = Get-Service -Name $TargetServiceName -ErrorAction SilentlyContinue
            if ($svcObj) {
                $svcObj.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(30))
                $svcVerify = Get-Service -Name $TargetServiceName -ErrorAction SilentlyContinue
                if ($svcVerify -and $svcVerify.Status -ne "Stopped") {
                    throw "[ERR_SERVICE_STOP_FAILED] Servis Stopped durumuna gecmedi: $($svcVerify.Status)"
                }
            }
        }
    }
}

function Invoke-VerifiedServiceUninstall {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName,
        [string]$ExpectedWrapperPath
    )
    $snap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
    if (-not $snap.Exists) {
        return
    }
    $normExpected = Normalize-InstallerPath $ExpectedWrapperPath
    if ([string]::IsNullOrWhiteSpace($snap.ImageExecutable) -or -not [string]::Equals($snap.ImageExecutable, $normExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "[ERR_FOREIGN_SERVICE_PROTECTED] Yabanci SCM servisi kaldirilamaz ($TargetServiceName ImagePath=$($snap.ImageExecutable) != $normExpected)."
    }
    if ($snap.DeletePending -or $FaultInjectionStage -eq "ScmDeletePending") {
        throw "[ERR_SCM_DELETE_PENDING] SCM servisi DELETE_PENDING durumunda kaldirilamadi: $TargetServiceName"
    }
    if ($FaultInjectionStage -eq "ServiceUninstall") {
        throw "[ERR_SERVICE_UNINSTALL_FAILED] Simule edilmis servis kaldirma hatasi: $TargetServiceName"
    }

    Invoke-VerifiedServiceStop -DataRoot $DataRoot -TargetServiceName $TargetServiceName -ExpectedWrapperPath $normExpected

    if ($TestSandboxMode) {
        $verTag = if (-not [string]::IsNullOrWhiteSpace($snap.StampedVersion)) { $snap.StampedVersion } else { "unstamped" }
        if ($script:InRollbackFlow) {
            Add-SandboxScmOp -DataRoot $DataRoot -Operation "uninstall:$verTag"
        }
        else {
            Add-SandboxInstallScmOp -DataRoot $DataRoot -Operation "uninstall:$verTag"
        }
        Remove-SandboxService $DataRoot
        return
    }

    if (Test-Path -LiteralPath $normExpected -PathType Leaf) {
        $uninstOut = & $normExpected uninstall 2>&1
    }
    else {
        $uninstOut = & sc.exe delete $TargetServiceName 2>&1
    }
    $ec = $LASTEXITCODE
    if ($ec -eq 1072) {
        throw "[ERR_SCM_DELETE_PENDING] SCM kaldirma sirasinda DELETE_PENDING (1072) algilandi: $uninstOut"
    }
    if ($ec -ne 0) {
        throw "[ERR_SERVICE_UNINSTALL_FAILED] Servis kaldirilamadi ($ec): $uninstOut"
    }

    $regPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\$TargetServiceName"
    $maxPolls = 60
    for ($poll = 0; $poll -lt $maxPolls; $poll++) {
        $stillSvc = Get-Service -Name $TargetServiceName -ErrorAction SilentlyContinue
        $stillReg = Test-Path -LiteralPath $regPath
        if ($null -eq $stillSvc -and -not $stillReg) {
            return
        }
        $postSnap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
        if ($postSnap.DeletePending) {
            Start-Sleep -Milliseconds 250
            continue
        }
        Start-Sleep -Milliseconds 250
    }

    $finalSnap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
    if ($finalSnap.DeletePending) {
        throw "[ERR_SCM_DELETE_PENDING] Servis kaldirma zaman asimina ugradi; SCM DELETE_PENDING devam ediyor ($TargetServiceName)."
    }
    throw "[ERR_SERVICE_UNINSTALL_FAILED] Servis kaldirildiktan sonra SCM/kayit defteri temizligi dogrulanamadi ($TargetServiceName)."
}

function Resolve-DeterministicScmDisposition {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName,
        [string]$ExpectedWrapperPath,
        [bool]$HadExistingService,
        [string]$ExpectedPreviousVersion = "",
        [string]$ExpectedPrevXmlPath = "",
        [bool]$KnownTxServiceModified = $false,
        [string]$KnownTxId = ""
    )

    $snap = Read-ScmServiceIdentitySnapshot -DataRoot $DataRoot -TargetServiceName $TargetServiceName
    $res = [ordered]@{
        Disposition     = "FAIL_CLOSED"
        ServiceModified = $false
        Reason          = ""
        Snapshot        = $snap
    }

    if (-not $snap.Exists) {
        if ($FaultInjectionStage -eq "ScmDeletePending") {
            $res.Reason = "[ERR_SCM_DELETE_PENDING] Simule edilmis SCM DELETE_PENDING durumu."
            return $res
        }
        $res.Disposition = if ($HadExistingService) { "ABSENT_NEEDS_INSTALL" } else { "ABSENT_CLEAN" }
        $res.ServiceModified = $false
        return $res
    }

    if ($snap.DeletePending -or ($FaultInjectionStage -eq "ScmDeletePending")) {
        $res.Reason = "[ERR_SCM_DELETE_PENDING] SCM servisi DELETE_PENDING durumunda: $TargetServiceName"
        return $res
    }

    $normExpected = Normalize-InstallerPath $ExpectedWrapperPath
    if ([string]::IsNullOrWhiteSpace($snap.ImageExecutable) -or -not [string]::Equals($snap.ImageExecutable, $normExpected, [System.StringComparison]::OrdinalIgnoreCase)) {
        $res.Reason = "[ERR_FOREIGN_SERVICE_PROTECTED] Mevcut SCM servis ImagePath beklenen MarketMMS sarmalayicisi degil ($($snap.ImageExecutable) != $normExpected)."
        return $res
    }

    if (-not (Test-IsExpectedLocalServiceAccount -AccountName $snap.ObjectName)) {
        $res.Reason = "[ERR_SCM_INVALID_ACCOUNT] Beklenmeyen servis hesabi ($($snap.ObjectName)); fail-closed duruldu."
        return $res
    }

    if ($snap.ServiceSidType -ne "UNRESTRICTED") {
        $res.Reason = "[ERR_SCM_INVALID_SIDTYPE] Beklenmeyen servis SID tipi ($($snap.ServiceSidType)); fail-closed duruldu."
        return $res
    }

    if (-not $HadExistingService) {
        $res.Disposition = "REMOVE_NEW_ONLY"
        $res.ServiceModified = $true
        return $res
    }

    $resolvedPrevXml = $ExpectedPrevXmlPath
    if ([string]::IsNullOrWhiteSpace($resolvedPrevXml) -or -not (Test-Path -LiteralPath $resolvedPrevXml -PathType Leaf)) {
        $res.Reason = "[ERR_MISSING_RUNTIME_ARTIFACT] Onceki surume ait MarketMMSService.xml dogrulanamadi: $resolvedPrevXml"
        return $res
    }
    try {
        $expectedPrevXmlSha = Get-FileSha256Upper -FilePath $resolvedPrevXml
    }
    catch {
        $res.Reason = $_.Exception.Message
        return $res
    }

    if ([string]::IsNullOrWhiteSpace($snap.StampedVersion) -or [string]::IsNullOrWhiteSpace($snap.StampedXmlSha256)) {
        if ($KnownTxServiceModified -and -not [string]::IsNullOrWhiteSpace($KnownTxId)) {
            $res.Disposition = "REMOVE_NEW_AND_REINSTALL_PREVIOUS"
            $res.ServiceModified = $true
            return $res
        }
        $res.Reason = "[ERR_SCM_STAMP_MISSING] SCM registry kimlik damgasi eksik (MmsAppVersion/MmsXmlSha256); belirsiz servis durumu nedeniyle fail-closed duruldu."
        return $res
    }

    $versionMatchesPrev = (-not [string]::IsNullOrWhiteSpace($ExpectedPreviousVersion)) -and
        [string]::Equals($snap.StampedVersion, $ExpectedPreviousVersion.Trim(), [System.StringComparison]::OrdinalIgnoreCase)
    $xmlHashMatchesPrev = [string]::Equals($snap.StampedXmlSha256, $expectedPrevXmlSha, [System.StringComparison]::OrdinalIgnoreCase)
    $txModifiedSameVersion = $KnownTxServiceModified -and
        (-not [string]::IsNullOrWhiteSpace($KnownTxId)) -and
        [string]::Equals($snap.StampedTxId, $KnownTxId, [System.StringComparison]::OrdinalIgnoreCase)

    if ($versionMatchesPrev -and $xmlHashMatchesPrev -and (-not $txModifiedSameVersion)) {
        $res.Disposition = "PRESERVE_UNMODIFIED_PREVIOUS"
        $res.ServiceModified = $false
        return $res
    }

    $res.Disposition = "REMOVE_NEW_AND_REINSTALL_PREVIOUS"
    $res.ServiceModified = $true
    return $res
}

function Resolve-ManifestFallbackServiceModified {
    param(
        [string]$DataRoot,
        [string]$TargetServiceName,
        [string]$PreviousVersion
    )
    $expectedWrapper = Join-Path $DataRoot "bin\MarketMMSService.exe"
    $prevXml = Join-Path $DataRoot "bin.previous\MarketMMSService.xml"
    return (Resolve-DeterministicScmDisposition `
        -DataRoot $DataRoot `
        -TargetServiceName $TargetServiceName `
        -ExpectedWrapperPath $expectedWrapper `
        -HadExistingService $true `
        -ExpectedPreviousVersion $PreviousVersion `
        -ExpectedPrevXmlPath $prevXml `
        -KnownTxServiceModified $false `
        -KnownTxId "")
}

function Write-InstallerTxState {
    param(
        [string]$DataRoot,
        [string]$Status,
        [hashtable]$ExtraFields = $null
    )
    $f = Get-InstallerTxStateFile $DataRoot
    $prevFile = Get-InstallerTxPrevStateFile $DataRoot
    $dir = Split-Path -Parent $f
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path -LiteralPath $f) {
        try {
            $existingRaw = Get-Content -LiteralPath $f -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
                $existingObj = $existingRaw | ConvertFrom-Json -ErrorAction Stop
                if (Test-ValidTxStateObject $existingObj) {
                    $prevTmp = $prevFile + ".tmp"
                    Set-Content -LiteralPath $prevTmp -Value $existingRaw -NoNewline -Encoding UTF8
                    Move-Item -LiteralPath $prevTmp -Destination $prevFile -Force
                }
            }
        }
        catch {
            # Do not overwrite installer_tx_state.previous.json if the current primary file is unreadable or corrupt.
        }
    }

    $fwList = @()
    if ($null -ne $script:Tx.CreatedFirewallRules) {
        $fwList = @($script:Tx.CreatedFirewallRules | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    $payload = [ordered]@{
        status                       = $Status
        mode                         = $script:Tx.Mode
        tx_id                        = [string]$script:Tx.TxId
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
        created_firewall_rules       = $fwList
        updated_at_utc               = (Get-Date).ToUniversalTime().ToString("o")
    }
    if ($null -ne $ExtraFields) {
        foreach ($k in $ExtraFields.Keys) {
            $payload[$k] = $ExtraFields[$k]
        }
    }
    $tmp = $f + ".tmp"
    Set-Content -LiteralPath $tmp -Value ($payload | ConvertTo-Json -Depth 6) -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $f -Force
}

function Remove-InstallerTxArtifacts {
    param(
        [string]$TargetInstallDir,
        [string]$TargetDataRoot
    )
    $txFile = Get-InstallerTxStateFile $TargetDataRoot
    $txPrevFile = Get-InstallerTxPrevStateFile $TargetDataRoot
    $artifacts = @(
        (Join-Path $TargetDataRoot "bin.previous"),
        (Join-Path $TargetInstallDir "client.previous"),
        (Join-Path $TargetDataRoot "config\install_manifest.previous.json"),
        $txFile,
        ($txFile + ".tmp"),
        $txPrevFile,
        ($txPrevFile + ".tmp")
    )
    foreach ($art in $artifacts) {
        if (Test-Path -LiteralPath $art) {
            Remove-Item -LiteralPath $art -Recurse -Force -ErrorAction SilentlyContinue
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
    }
    finally {
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
    }
    finally {
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
        }
        else {
            Copy-Item -LiteralPath $stagedDb -Destination $TargetBackupPath -Force
            foreach ($suffix in @("-wal", "-shm")) {
                $stagedSidecar = $stagedDb + $suffix
                if (Test-Path -LiteralPath $stagedSidecar) {
                    Copy-Item -LiteralPath $stagedSidecar -Destination ($TargetBackupPath + $suffix) -Force
                }
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageWalDir) {
            Remove-Item -LiteralPath $stageWalDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-AdminSecretReadOnlyAcl {
    param(
        [string]$FilePath,
        [string]$ExpectedServiceSid = "",
        [switch]$SandboxMode
    )

    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        return $true
    }

    try {
        $fi = New-Object System.IO.FileInfo($FilePath)
        if ($fi.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            return $false
        }
        $acl = $fi.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        if (-not $acl.AreAccessRulesProtected) {
            return $false
        }

        $forbiddenSids = @("S-1-5-32-545", "S-1-1-0", "S-1-5-11", "S-1-5-7", "S-1-5-4", "S-1-5-32-546")
        $fullControlMask = 0x001F01FF
        $readRequiredMask = 0x00020089
        $disallowedWriteMask = 0x500D0156

        $curUserSid = ""
        if ($SandboxMode) {
            $curUserSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
        }

        $hasSysFull = $false
        $hasAdmFull = $false
        $hasSvcReadOnly = [string]::IsNullOrWhiteSpace($ExpectedServiceSid)

        foreach ($access in $acl.Access) {
            $sidVal = if ($access.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) {
                $access.IdentityReference.Value
            }
            else {
                try { $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { $access.IdentityReference.Value }
            }
            if ($forbiddenSids -contains $sidVal) {
                return $false
            }
            if ($access.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
                continue
            }
            $mask = [int]$access.FileSystemRights
            if ($sidVal -eq "S-1-5-18" -and (($mask -band $fullControlMask) -eq $fullControlMask)) {
                $hasSysFull = $true
                continue
            }
            if ($sidVal -eq "S-1-5-32-544" -and (($mask -band $fullControlMask) -eq $fullControlMask)) {
                $hasAdmFull = $true
                continue
            }
            if ($SandboxMode -and -not [string]::IsNullOrWhiteSpace($curUserSid) -and $sidVal -eq $curUserSid) {
                continue
            }
            if (-not [string]::IsNullOrWhiteSpace($ExpectedServiceSid) -and $sidVal.Equals($ExpectedServiceSid, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (($mask -band $disallowedWriteMask) -ne 0) {
                    return $false
                }
                if (($mask -band $readRequiredMask) -eq $readRequiredMask) {
                    $hasSvcReadOnly = $true
                }
                continue
            }
            if (($mask -band $disallowedWriteMask) -ne 0) {
                return $false
            }
        }
        return ($hasSysFull -and $hasAdmFull -and $hasSvcReadOnly)
    }
    catch {
        return $false
    }
}

function Apply-DirectoryAcls {
    param(
        [string]$DataRoot,
        [string]$ServiceSid = "",
        [switch]$IgnoreInstallAclFault
    )
    if (-not $IgnoreInstallAclFault -and $FaultInjectionStage -eq "Acl") {
        throw "[ERR_ACL_FAILED] Simule edilmis NTFS ACL atama hatasi."
    }

    $effectiveSvcSid = if (-not [string]::IsNullOrWhiteSpace($ServiceSid)) {
        $ServiceSid.Trim().TrimStart('*')
    }
    else {
        Resolve-WindowsServiceSid -TargetServiceName $ServiceName
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

        $criticalSubs = @("bin", "data", "config", "certs", "security", "backups", "run", "logs", "lib")
        foreach ($sub in $criticalSubs) {
            $subPath = Join-Path $DataRoot $sub
            $null = & icacls $subPath /inheritance:r /grant:r "${sidUserSelf}:(OI)(CI)F" /grant:r "${sidSystem}:(OI)(CI)F" /grant:r "${sidAdmin}:(OI)(CI)F" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_ACL_FAILED] Sandbox ACL hatasi ($subPath): $LASTEXITCODE"
            }
            $acl = Get-Acl -Path $subPath
            foreach ($access in $acl.Access) {
                $sidVal = if ($access.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) {
                    $access.IdentityReference.Value
                }
                else {
                    $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
                }
                if ($sidVal -eq "S-1-5-32-545" -or $sidVal -eq "S-1-1-0" -or $sidVal -eq "S-1-5-11") {
                    throw "[ERR_SECURITY_VIOLATION] $subPath dizininde yetkisiz SID saptandi: $sidVal"
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($effectiveSvcSid)) {
            $svcSidObj = New-Object System.Security.Principal.SecurityIdentifier($effectiveSvcSid)
            $setSandboxSvcRule = {
                param([string]$DirPath, [System.Security.AccessControl.FileSystemRights]$Rights, [System.Security.AccessControl.InheritanceFlags]$Inh)
                $di = New-Object System.IO.DirectoryInfo($DirPath)
                $ds = $di.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                $ds.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                            $svcSidObj,
                            $Rights,
                            $Inh,
                            [System.Security.AccessControl.PropagationFlags]::None,
                            [System.Security.AccessControl.AccessControlType]::Allow
                        )))
                $di.SetAccessControl($ds)
            }

            $oiCi = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            & $setSandboxSvcRule $DataRoot ([System.Security.AccessControl.FileSystemRights]::ExecuteFile) ([System.Security.AccessControl.InheritanceFlags]::None)
            foreach ($rxSub in @("bin", "lib")) {
                & $setSandboxSvcRule (Join-Path $DataRoot $rxSub) ([System.Security.AccessControl.FileSystemRights]::ReadAndExecute) $oiCi
            }
            foreach ($rwSub in @("data", "logs", "backups", "run", "security")) {
                & $setSandboxSvcRule (Join-Path $DataRoot $rwSub) ([System.Security.AccessControl.FileSystemRights]::Modify) $oiCi
            }
            foreach ($roSub in @("config", "certs")) {
                & $setSandboxSvcRule (Join-Path $DataRoot $roSub) ([System.Security.AccessControl.FileSystemRights]::Read) $oiCi
            }

            $sandboxAdminSecret = Join-Path $DataRoot "security\admin_secret.txt"
            if (Test-Path -LiteralPath $sandboxAdminSecret -PathType Leaf) {
                $fiSec = New-Object System.IO.FileInfo($sandboxAdminSecret)
                $fsSec = $fiSec.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                $removeArgs = New-Object System.Collections.Generic.List[string]
                $unmappedPurge = New-Object System.Collections.Generic.List[string]
                $removeArgs.Add($sandboxAdminSecret)
                $removeArgs.Add("/inheritance:r")
                foreach ($ace in $fsSec.Access) {
                    if ($ace.IsInherited) { continue }
                    $s = if ($ace.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) { $ace.IdentityReference.Value } else { try { $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "" } }
                    if ($s -and $s -notin @("S-1-5-18", "S-1-5-32-544", $currentSid)) {
                        $canTrans = $false
                        try { $null = (New-Object System.Security.Principal.SecurityIdentifier($s)).Translate([System.Security.Principal.NTAccount]); $canTrans = $true } catch { $canTrans = $false }
                        if ($canTrans) {
                            $removeArgs.Add("/remove")
                            $removeArgs.Add("*$s")
                        }
                        else {
                            $unmappedPurge.Add($s)
                        }
                    }
                }
                $removeArgs.AddRange([string[]]@("/grant:r", "${sidUserSelf}:F", "/grant:r", "${sidSystem}:F", "/grant:r", "${sidAdmin}:F", "/C", "/Q"))
                $null = & icacls.exe ($removeArgs.ToArray()) 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "[ERR_ACL_FAILED] Sandbox admin_secret.txt ACL atamasi basarisiz ($LASTEXITCODE)."
                }
                $fiSec2 = New-Object System.IO.FileInfo($sandboxAdminSecret)
                $fsSec2 = $fiSec2.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
                foreach ($uS in $unmappedPurge) {
                    $fsSec2.PurgeAccessRules((New-Object System.Security.Principal.SecurityIdentifier($uS)))
                }
                $fsSec2.PurgeAccessRules($svcSidObj)
                $fsSec2.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                            $svcSidObj,
                            [System.Security.AccessControl.FileSystemRights]::Read,
                            [System.Security.AccessControl.InheritanceFlags]::None,
                            [System.Security.AccessControl.PropagationFlags]::None,
                            [System.Security.AccessControl.AccessControlType]::Allow
                        )))
                $fiSec2.SetAccessControl($fsSec2)
            }
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($AclScriptPath) -or -not (Test-Path $AclScriptPath)) {
        throw "[ERR_ACL_SCRIPT_MISSING] setup_service_acls.ps1 bulunamadi: $AclScriptPath"
    }
    if ([string]::IsNullOrWhiteSpace($effectiveSvcSid)) {
        throw "[ERR_SERVICE_SID_FAILED] Service SID cozumlenemedi: $ServiceName"
    }
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $AclScriptPath -BaseDir $DataRoot -ServiceName $ServiceName -ServiceSid $effectiveSvcSid
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
                }
                else {
                    Join-Path (Split-Path -Parent $cfgPath) $rawRel
                }
                return (Normalize-InstallerPath $resolved)
            }
        }
        catch {}
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
            verified                = $false
            recovery_key_configured = $false
            status                  = "SKIPPED_NO_LIVE_ENDPOINT"
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
                }
                catch {
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
        }
        elseif ($TestSandboxMode) {
            $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($resp.StatusCode -ne 200) {
                throw "HTTP $($resp.StatusCode)"
            }
            $content = $resp.Content
        }
        else {
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
            verified                = $true
            recovery_key_configured = $recConfigured
            status                  = $json.status
        }
    }
    catch {
        throw "[ERR_HEALTH_CHECK_FAILED] Hub health kontrolu basarisiz ($Url): $($_.Exception.Message)"
    }
}

$script:Tx = @{
    Mode                      = "FreshInstall"
    TxId                      = ([guid]::NewGuid().ToString("N"))
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
    CreatedFirewallRules      = @()
}

function Invoke-MarketMmsRollback {
    param(
        [string]$TargetInstallDir,
        [string]$TargetDataRoot,
        [string]$TargetServiceName,
        [switch]$ForceMarkRolledBack
    )
    Write-Host "[ROLLBACK] Kurulum/guncelleme geri aliniyor (kullanici verileri korunuyor)..." -ForegroundColor Yellow

    $rbSteps = [ordered]@{
        stop_new_service  = "SKIPPED"
        restore_binaries  = "SKIPPED"
        restore_client    = "SKIPPED"
        restore_manifest  = "SKIPPED"
        cleanup_firewall  = "SKIPPED"
        reinstall_service = "SKIPPED"
        reapply_acls      = "SKIPPED"
        start_service     = "SKIPPED"
    }
    $failedSteps = New-Object System.Collections.Generic.List[string]
    $errorDetails = New-Object System.Collections.Generic.List[string]

    $prevInRollback = $script:InRollbackFlow
    $script:InRollbackFlow = $true
    try {
        $binDir = Join-Path $TargetDataRoot "bin"
        $prevBinDir = Join-Path $TargetDataRoot "bin.previous"
        $manifestFile = Join-Path $TargetDataRoot "config\install_manifest.json"
        $prevManifestFile = Join-Path $TargetDataRoot "config\install_manifest.previous.json"
        $expectedWrapperPath = Join-Path $binDir "MarketMMSService.exe"

        $expectedPrevVersion = if (-not [string]::IsNullOrWhiteSpace([string]$script:Tx.PreviousVersion)) {
            [string]$script:Tx.PreviousVersion
        }
        elseif (Test-Path -LiteralPath $prevManifestFile -PathType Leaf) {
            try { [string](Get-Content -LiteralPath $prevManifestFile -Raw | ConvertFrom-Json).app_version } catch { "" }
        }
        elseif (Test-Path -LiteralPath $manifestFile -PathType Leaf) {
            try { [string](Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json).app_version } catch { "" }
        }
        else {
            ""
        }

        $expectedPrevXmlPath = if (Test-Path -LiteralPath (Join-Path $prevBinDir "MarketMMSService.xml") -PathType Leaf) {
            Join-Path $prevBinDir "MarketMMSService.xml"
        }
        elseif (-not $script:Tx.CopiedBin -and (Test-Path -LiteralPath (Join-Path $binDir "MarketMMSService.xml") -PathType Leaf)) {
            Join-Path $binDir "MarketMMSService.xml"
        }
        else {
            Join-Path $prevBinDir "MarketMMSService.xml"
        }

        $scmDisp = Resolve-DeterministicScmDisposition `
            -DataRoot $TargetDataRoot `
            -TargetServiceName $TargetServiceName `
            -ExpectedWrapperPath $expectedWrapperPath `
            -HadExistingService ([bool]$script:Tx.HadExistingService) `
            -ExpectedPreviousVersion $expectedPrevVersion `
            -ExpectedPrevXmlPath $expectedPrevXmlPath `
            -KnownTxServiceModified ([bool]$script:Tx.ServiceModified) `
            -KnownTxId ([string]$script:Tx.TxId)

        $isScmFailClosed = ($scmDisp.Disposition -eq "FAIL_CLOSED")

        # Step 1: Deterministic SCM service cleanup/preservation
        try {
            switch ($scmDisp.Disposition) {
                "FAIL_CLOSED" {
                    throw $scmDisp.Reason
                }
                "ABSENT_CLEAN" {
                    $rbSteps.stop_new_service = "OK"
                }
                "ABSENT_NEEDS_INSTALL" {
                    $rbSteps.stop_new_service = "OK"
                }
                "PRESERVE_UNMODIFIED_PREVIOUS" {
                    if ($scmDisp.Snapshot.Status -ne "Stopped") {
                        Invoke-VerifiedServiceStop -DataRoot $TargetDataRoot -TargetServiceName $TargetServiceName -ExpectedWrapperPath $expectedWrapperPath
                    }
                    $rbSteps.stop_new_service = "OK"
                }
                "REMOVE_NEW_ONLY" {
                    Invoke-VerifiedServiceUninstall -DataRoot $TargetDataRoot -TargetServiceName $TargetServiceName -ExpectedWrapperPath $expectedWrapperPath
                    $rbSteps.stop_new_service = "OK"
                }
                "REMOVE_NEW_AND_REINSTALL_PREVIOUS" {
                    Invoke-VerifiedServiceUninstall -DataRoot $TargetDataRoot -TargetServiceName $TargetServiceName -ExpectedWrapperPath $expectedWrapperPath
                    $rbSteps.stop_new_service = "OK"
                }
                default {
                    throw "[ERR_SCM_STATE_UNKNOWN] Bilinmeyen SCM durumu: $($scmDisp.Disposition)"
                }
            }
        }
        catch {
            $rbSteps.stop_new_service = "FAILED"
            $failedSteps.Add("stop_new_service")
            $errorDetails.Add("stop_new_service: $($_.Exception.Message)")
        }

        # Step 2: Restore binaries (skip destructive cleanup if SCM failed closed)
        try {
            if ($isScmFailClosed) {
                $rbSteps.restore_binaries = "SKIPPED_SCM_FAIL_CLOSED"
            }
            elseif ($FaultInjectionStage -eq "RollbackBinary") {
                throw "[ERR_ROLLBACK_BINARY_FAILED] Simule edilmis binary geri yukleme hatasi."
            }
            elseif (Test-Path -LiteralPath $prevBinDir) {
                $expectedBackend = Test-Path -LiteralPath (Join-Path $prevBinDir "mms_backend.exe")
                if (Test-Path -LiteralPath $binDir) {
                    Remove-Item -LiteralPath $binDir -Recurse -Force -ErrorAction Stop
                }
                New-Item -ItemType Directory -Path $binDir -Force -ErrorAction Stop | Out-Null
                Copy-Item -Path (Join-Path $prevBinDir "*") -Destination $binDir -Recurse -Force -ErrorAction Stop
                if ($expectedBackend -and -not (Test-Path -LiteralPath (Join-Path $binDir "mms_backend.exe"))) {
                    throw "Geri yuklenen mms_backend.exe dogrulanamadi."
                }
                $restoredSqlite = Join-Path $binDir "sqlite3.dll"
                if (Test-Path -LiteralPath $restoredSqlite) {
                    $binLibDir = Join-Path $binDir "lib"
                    $rootLibDir = Join-Path $TargetDataRoot "lib"
                    if (-not (Test-Path -LiteralPath $binLibDir)) { New-Item -ItemType Directory -Path $binLibDir -Force | Out-Null }
                    if (-not (Test-Path -LiteralPath $rootLibDir)) { New-Item -ItemType Directory -Path $rootLibDir -Force | Out-Null }
                    Copy-Item -LiteralPath $restoredSqlite -Destination (Join-Path $binLibDir "sqlite3.dll") -Force -ErrorAction Stop
                    Copy-Item -LiteralPath $restoredSqlite -Destination (Join-Path $rootLibDir "sqlite3.dll") -Force -ErrorAction Stop
                }
                Remove-Item -LiteralPath $prevBinDir -Recurse -Force -ErrorAction Stop
                $rbSteps.restore_binaries = "OK"
            }
            elseif (-not $script:Tx.HadExistingService -and $script:Tx.CopiedBin) {
                if (Test-Path -LiteralPath $binDir) {
                    Remove-Item -LiteralPath $binDir -Recurse -Force -ErrorAction Stop
                }
                $freshRootSqlite = Join-Path $TargetDataRoot "lib\sqlite3.dll"
                if (Test-Path -LiteralPath $freshRootSqlite) {
                    Remove-Item -LiteralPath $freshRootSqlite -Force -ErrorAction Stop
                }
                $rbSteps.restore_binaries = "OK"
            }
        }
        catch {
            $rbSteps.restore_binaries = "FAILED"
            $failedSteps.Add("restore_binaries")
            $errorDetails.Add("restore_binaries: $($_.Exception.Message)")
        }

        # Step 3: Restore desktop client binaries
        $clientDir = Join-Path $TargetInstallDir "client"
        $prevClientDir = Join-Path $TargetInstallDir "client.previous"
        try {
            if ($isScmFailClosed) {
                $rbSteps.restore_client = "SKIPPED_SCM_FAIL_CLOSED"
            }
            elseif (Test-Path -LiteralPath $prevClientDir) {
                $expectedClientExe = Test-Path -LiteralPath (Join-Path $prevClientDir "market_pos.exe")
                if (Test-Path -LiteralPath $clientDir) {
                    Remove-Item -LiteralPath $clientDir -Recurse -Force -ErrorAction Stop
                }
                New-Item -ItemType Directory -Path $clientDir -Force -ErrorAction Stop | Out-Null
                Copy-Item -Path (Join-Path $prevClientDir "*") -Destination $clientDir -Recurse -Force -ErrorAction Stop
                if ($expectedClientExe -and -not (Test-Path -LiteralPath (Join-Path $clientDir "market_pos.exe"))) {
                    throw "Geri yuklenen market_pos.exe dogrulanamadi."
                }
                Remove-Item -LiteralPath $prevClientDir -Recurse -Force -ErrorAction Stop
                $rbSteps.restore_client = "OK"
            }
            elseif (-not $script:Tx.HadExistingService -and $script:Tx.CopiedClient -and (Test-Path -LiteralPath $clientDir)) {
                Remove-Item -LiteralPath $clientDir -Recurse -Force -ErrorAction Stop
                $rbSteps.restore_client = "OK"
            }
        }
        catch {
            $rbSteps.restore_client = "FAILED"
            $failedSteps.Add("restore_client")
            $errorDetails.Add("restore_client: $($_.Exception.Message)")
        }

        # Step 4: Restore install manifest (preserve install_manifest.previous.json unless validated & copied)
        try {
            if ($isScmFailClosed) {
                $rbSteps.restore_manifest = "SKIPPED_SCM_FAIL_CLOSED"
            }
            elseif ($FaultInjectionStage -eq "RollbackManifest") {
                throw "[ERR_ROLLBACK_MANIFEST_FAILED] Simule edilmis manifest geri yukleme hatasi."
            }
            elseif (Test-Path -LiteralPath $prevManifestFile) {
                $prevManifestRaw = Get-Content -LiteralPath $prevManifestFile -Raw -ErrorAction Stop
                $null = $prevManifestRaw | ConvertFrom-Json -ErrorAction Stop
                Copy-Item -LiteralPath $prevManifestFile -Destination $manifestFile -Force -ErrorAction Stop
                $null = (Get-Content -LiteralPath $manifestFile -Raw -ErrorAction Stop) | ConvertFrom-Json -ErrorAction Stop
                Remove-Item -LiteralPath $prevManifestFile -Force -ErrorAction Stop
                $rbSteps.restore_manifest = "OK"
            }
            elseif (-not $script:Tx.HadExistingService -and $script:Tx.ManifestWritten -and (Test-Path -LiteralPath $manifestFile)) {
                Remove-Item -LiteralPath $manifestFile -Force -ErrorAction Stop
                $rbSteps.restore_manifest = "OK"
            }
        }
        catch {
            $rbSteps.restore_manifest = "FAILED"
            $failedSteps.Add("restore_manifest")
            $errorDetails.Add("restore_manifest: $($_.Exception.Message)")
        }

        # Step 5 (M-1): Cleanup ONLY firewall rules created during this installer transaction
        $txCreatedFwRules = @()
        if ($null -ne $script:Tx.CreatedFirewallRules) {
            $txCreatedFwRules = @($script:Tx.CreatedFirewallRules | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        try {
            if ($txCreatedFwRules.Count -gt 0) {
                if ($FaultInjectionStage -eq "RollbackFirewall") {
                    throw "[ERR_ROLLBACK_FIREWALL_FAILED] Simule edilmis firewall rollback temizleme hatasi."
                }
                $ciOpts = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                $validatedRules = New-Object System.Collections.Generic.List[string]
                foreach ($rn in $txCreatedFwRules) {
                    if (-not [regex]::IsMatch($rn, '^MarketMMS-Hub-(?:API-TCP|Discovery-UDP)-\d{1,5}$', $ciOpts)) {
                        throw "Gecersiz MarketMMS firewall kural adi (silme engellendi): $rn"
                    }
                    $validatedRules.Add($rn)
                }
                if ($TestSandboxMode) {
                    $curFw = Read-SandboxFirewallRules -DataRoot $TargetDataRoot
                    $remainingFw = @($curFw | Where-Object { $validatedRules -notcontains $_ })
                    Write-SandboxFirewallRules -DataRoot $TargetDataRoot -Rules $remainingFw
                }
                else {
                    foreach ($rn in $validatedRules) {
                        $existingRule = Get-NetFirewallRule -DisplayName $rn -ErrorAction SilentlyContinue
                        if ($existingRule) {
                            Remove-NetFirewallRule -DisplayName $rn -ErrorAction Stop
                        }
                    }
                }
                $script:Tx.CreatedFirewallRules = @()
                $rbSteps.cleanup_firewall = "OK"
            }
        }
        catch {
            $rbSteps.cleanup_firewall = "FAILED"
            $failedSteps.Add("cleanup_firewall")
            $errorDetails.Add("cleanup_firewall: $($_.Exception.Message)")
        }

        # Step 6, 7 & 8 (H-1 + M-2 + B-1): Verify/Restore Old Service + Registry Identity Stamp -> ACL -> Start
        if ($script:Tx.HadExistingService) {
            $restoredWrapper = Join-Path $binDir "MarketMMSService.exe"
            $restoredXml = Join-Path $binDir "MarketMMSService.xml"

            if ($isScmFailClosed) {
                $rbSteps.reinstall_service = "FAILED"
                $failedSteps.Add("reinstall_service")
                $errorDetails.Add("reinstall_service: [ERR_ROLLBACK_SERVICE_CONFLICT] $($scmDisp.Reason)")
            }
            elseif ($rbSteps.restore_binaries -eq "FAILED") {
                $rbSteps.reinstall_service = "SKIPPED_BINARY_FAILED"
                $failedSteps.Add("reinstall_service")
                $errorDetails.Add("reinstall_service: binary restore basarisiz oldugu icin atlandi.")
            }
            elseif ($rbSteps.stop_new_service -eq "FAILED") {
                $rbSteps.reinstall_service = "SKIPPED_STOP_FAILED"
                $failedSteps.Add("reinstall_service")
                $errorDetails.Add("reinstall_service: mevcut yeni servis kaldirilamadigi/durmadigi icin atlandi.")
            }
            else {
                try {
                    if ($FaultInjectionStage -eq "RollbackService") {
                        throw "[ERR_ROLLBACK_SERVICE_FAILED] Simule edilmis eski servis yeniden kurulum hatasi."
                    }

                    $restoredVer = if (-not [string]::IsNullOrWhiteSpace($expectedPrevVersion)) { $expectedPrevVersion } else { "previous" }
                    if (Test-Path -LiteralPath $manifestFile) {
                        try {
                            $m = Get-Content -LiteralPath $manifestFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                            if ($m.app_version) { $restoredVer = [string]$m.app_version }
                        }
                        catch {}
                    }
                    $restoredXmlSha = Get-FileSha256Upper -FilePath $restoredXml

                    if ($scmDisp.Disposition -eq "PRESERVE_UNMODIFIED_PREVIOUS") {
                        $postSnap = Read-ScmServiceIdentitySnapshot -DataRoot $TargetDataRoot -TargetServiceName $TargetServiceName
                        if (-not $postSnap.Exists) {
                            throw "[ERR_ROLLBACK_SERVICE_CONFLICT] Korunmasi gereken eski servis kaydi artik mevcut degil."
                        }
                        if ($postSnap.DeletePending) {
                            throw "[ERR_SCM_DELETE_PENDING] Eski servis kaydi DELETE_PENDING durumunda: $TargetServiceName"
                        }
                        $normPostImg = Normalize-InstallerPath $postSnap.ImageExecutable
                        $normRestored = Normalize-InstallerPath $restoredWrapper
                        if (-not [string]::Equals($normPostImg, $normRestored, [System.StringComparison]::OrdinalIgnoreCase) -or
                            -not (Test-IsExpectedLocalServiceAccount -AccountName $postSnap.ObjectName) -or
                            ($postSnap.ServiceSidType -ne "UNRESTRICTED") -or
                            -not [string]::Equals($postSnap.StampedVersion, $restoredVer.Trim(), [System.StringComparison]::OrdinalIgnoreCase) -or
                            -not [string]::Equals($postSnap.StampedXmlSha256, $restoredXmlSha, [System.StringComparison]::OrdinalIgnoreCase)) {
                            throw "[ERR_ROLLBACK_SERVICE_CONFLICT] Mevcut servis kaydi beklenen eski surum kimlik damgasiyla eslesmiyor."
                        }
                        if ($TestSandboxMode) {
                            Add-SandboxScmOp -DataRoot $TargetDataRoot -Operation "verify_existing:$($postSnap.StampedVersion)"
                        }
                        else {
                            $sidOut = & sc.exe sidtype $TargetServiceName unrestricted 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                throw "sc.exe sidtype basarisiz oldu ($LASTEXITCODE): $sidOut"
                            }
                        }
                        $rbSteps.reinstall_service = "OK"
                    }
                    else {
                        $postStep1Snap = Read-ScmServiceIdentitySnapshot -DataRoot $TargetDataRoot -TargetServiceName $TargetServiceName
                        if ($postStep1Snap.Exists) {
                            if ($postStep1Snap.DeletePending) {
                                throw "[ERR_SCM_DELETE_PENDING] Eski servis kurulmadan once SCM DELETE_PENDING tespit edildi ($TargetServiceName)."
                            }
                            throw "[ERR_ROLLBACK_SERVICE_CONFLICT] Eski servis kurulmadan once mevcut servis kaydi kaldirilamadi ($TargetServiceName)."
                        }
                        if ($TestSandboxMode) {
                            Add-SandboxScmOp -DataRoot $TargetDataRoot -Operation "install:$restoredVer"
                            Add-SandboxScmOp -DataRoot $TargetDataRoot -Operation "sidtype:unrestricted"
                            Write-SandboxService -DataRoot $TargetDataRoot -Name $TargetServiceName -Status "Stopped" -Version $restoredVer -BinPath $restoredWrapper -ClearStamp
                        }
                        else {
                            if (-not (Test-Path -LiteralPath $restoredWrapper)) {
                                throw "Geri yuklenen servis sarmalayici bulunamadi: $restoredWrapper"
                            }
                            $instOut = & $restoredWrapper install 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                throw "Eski servis kurulamadi ($LASTEXITCODE): $instOut"
                            }
                            $sidOut = & sc.exe sidtype $TargetServiceName unrestricted 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                throw "sc.exe sidtype basarisiz oldu ($LASTEXITCODE): $sidOut"
                            }
                        }
                        Write-ScmServiceIdentityStamp `
                            -DataRoot $TargetDataRoot `
                            -TargetServiceName $TargetServiceName `
                            -StampVersion $restoredVer `
                            -XmlSha256 $restoredXmlSha `
                            -PreviousVersion "" `
                            -TxId ([string]$script:Tx.TxId) `
                            -WrapperPath $restoredWrapper
                        $rbSteps.reinstall_service = "OK"
                    }
                }
                catch {
                    $rbSteps.reinstall_service = "FAILED"
                    $failedSteps.Add("reinstall_service")
                    $errorDetails.Add("reinstall_service: $($_.Exception.Message)")
                }
            }

            # 7 (H-1): Resolve Service SID & re-apply directory + admin_secret.txt ACLs before starting service
            if (($rbSteps.restore_binaries -eq "FAILED") -or ($rbSteps.reinstall_service -ne "OK")) {
                $rbSteps.reapply_acls = "SKIPPED_PREREQ_FAILED"
                $failedSteps.Add("reapply_acls")
                $errorDetails.Add("reapply_acls: binary/servis on kosulu basarisiz oldugu icin atlandi.")
            }
            else {
                try {
                    if ($FaultInjectionStage -eq "RollbackAcl") {
                        throw "[ERR_ROLLBACK_ACL_FAILED] Simule edilmis rollback NTFS ACL yenileme hatasi."
                    }
                    $rbSvcSid = Resolve-WindowsServiceSid -TargetServiceName $TargetServiceName
                    if ([string]::IsNullOrWhiteSpace($rbSvcSid)) {
                        throw "[ERR_SERVICE_SID_FAILED] Rollback Service SID cozumlenemedi: $TargetServiceName"
                    }
                    Apply-DirectoryAcls -DataRoot $TargetDataRoot -ServiceSid $rbSvcSid -IgnoreInstallAclFault
                    $rbAdminSecret = Join-Path $TargetDataRoot "security\admin_secret.txt"
                    if (-not $TestSandboxMode -and (Test-Path -LiteralPath $rbAdminSecret -PathType Leaf)) {
                        & icacls.exe $rbAdminSecret /inheritance:r /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" /grant:r "*${rbSvcSid}:R" /C /Q | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "[ERR_ADMIN_SECRET_ACL_FAILED] Rollback admin_secret.txt ACL atamasi basarisiz ($LASTEXITCODE)."
                        }
                    }
                    if (-not (Test-AdminSecretReadOnlyAcl -FilePath $rbAdminSecret -ExpectedServiceSid $rbSvcSid -SandboxMode:([bool]$TestSandboxMode))) {
                        throw "[ERR_ROLLBACK_ADMIN_SECRET_ACL_INVALID] Rollback sonrasi admin_secret.txt uzerinde guvenli Read-only ServiceSID ACL dogrulanamadi."
                    }
                    $rbSteps.reapply_acls = "OK"
                }
                catch {
                    $rbSteps.reapply_acls = "FAILED"
                    $failedSteps.Add("reapply_acls")
                    $errorDetails.Add("reapply_acls: $($_.Exception.Message)")
                }
            }

            # 8: Start previous service ONLY if stop/binary/service/stamp/ACL gates all succeeded
            if ($script:Tx.HadPreviousServiceRunning) {
                if (($rbSteps.stop_new_service -ne "OK") -or ($rbSteps.restore_binaries -eq "FAILED") -or ($rbSteps.reinstall_service -ne "OK") -or ($rbSteps.reapply_acls -ne "OK")) {
                    $rbSteps.start_service = "SKIPPED_GATE_FAILED"
                    $failedSteps.Add("start_service")
                    $errorDetails.Add("start_service: ACL veya geri yukleme basarisiz oldugu icin servis guvenlik geregi baslatilmadi.")
                }
                else {
                    try {
                        if ($TestSandboxMode) {
                            $restoredVerStart = if (-not [string]::IsNullOrWhiteSpace($expectedPrevVersion)) { $expectedPrevVersion } else { "previous" }
                            if (Test-Path -LiteralPath $manifestFile) {
                                try {
                                    $mStart = Get-Content -LiteralPath $manifestFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                                    if ($mStart.app_version) { $restoredVerStart = [string]$mStart.app_version }
                                }
                                catch {}
                            }
                            Add-SandboxScmOp -DataRoot $TargetDataRoot -Operation "start:$restoredVerStart"
                            Write-SandboxService -DataRoot $TargetDataRoot -Name $TargetServiceName -Status "Running" -Version $restoredVerStart -BinPath $restoredWrapper
                            $rbSteps.start_service = "OK"
                        }
                        else {
                            $startOut = & $restoredWrapper start 2>&1
                            if ($LASTEXITCODE -ne 0) {
                                throw "Eski servis baslatilamadi ($LASTEXITCODE): $startOut"
                            }
                            Start-Sleep -Seconds 2
                            $svcVerify = Get-Service -Name $TargetServiceName -ErrorAction Stop
                            if ($svcVerify.Status -ne "Running") {
                                throw "Geri yuklenen servis Running durumuna gecemedi: $($svcVerify.Status)"
                            }
                            $rbSteps.start_service = "OK"
                        }
                    }
                    catch {
                        $rbSteps.start_service = "FAILED"
                        $failedSteps.Add("start_service")
                        $errorDetails.Add("start_service: $($_.Exception.Message)")
                    }
                }
            }
        }
    }
    finally {
        $script:InRollbackFlow = $prevInRollback
    }

    $overallStatus = if ($failedSteps.Count -eq 0) { "ROLLED_BACK" } else { "PARTIAL_ROLLBACK_FAILED" }
    $txExtra = @{
        rollback_steps  = $rbSteps
        failed_steps    = @($failedSteps.ToArray())
        rollback_errors = @($errorDetails.ToArray())
        scm_disposition = $scmDisp.Disposition
    }

    if ($ForceMarkRolledBack -or (Test-Path -LiteralPath (Get-InstallerTxStateFile $TargetDataRoot))) {
        try {
            Write-InstallerTxState -DataRoot $TargetDataRoot -Status $overallStatus -ExtraFields $txExtra
        }
        catch {
            if ($overallStatus -eq "ROLLED_BACK") {
                $overallStatus = "PARTIAL_ROLLBACK_FAILED"
            }
            $failedSteps.Add("write_tx_state")
            $errorDetails.Add("write_tx_state: $($_.Exception.Message)")
        }
    }

    if ($overallStatus -ne "ROLLED_BACK") {
        $diagSummary = "Kismi rollback hatasi: status=$overallStatus failed_steps=$($failedSteps -join ',') details=$($errorDetails -join ' | ')"
        Write-InstallerDiagnosticLog -DataRoot $TargetDataRoot -ExitCode 74 -Code "ERR_PARTIAL_ROLLBACK_FAILED" -Message $diagSummary -Stage "Rollback"
        Write-Host "[ROLLBACK][PARTIAL_FAILURE] $diagSummary" -ForegroundColor Red
    }
    else {
        Write-Host "[ROLLBACK] Tamamlandi; data/, backups/, security/, certs/ ve config/ korundu." -ForegroundColor Green
    }

    return [ordered]@{
        overall_status = $overallStatus
        steps          = $rbSteps
        failed_steps   = @($failedSteps.ToArray())
        errors         = @($errorDetails.ToArray())
    }
}

# ==============================================================================
# ANA AKIS
# ==============================================================================
$script:CurrentInstallerStage = "ServiceProtection"
Assert-ServiceProtection

$script:CurrentInstallerStage = "AdminCheck"
if (-not $TestSandboxMode -and -not (Test-IsAdministrator)) {
    Fail-Installer -ExitCode 5 -Code "ERR_ADMIN_REQUIRED" `
        -Message "Bu kurulum islemi yerel Yonetici (Administrator) yetkisi gerektirir."
}

if ($Action -eq "VerifyPrerequisites") {
    $script:CurrentInstallerStage = "VerifyPrerequisites"
    try {
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
    catch {
        $caughtErr = $_
        $errMsg = if ($null -ne $caughtErr -and $null -ne $caughtErr.Exception) { $caughtErr.Exception.Message } else { "$caughtErr" }
        Fail-Installer -ExitCode 71 -Code "ERR_PREREQUISITES_FAILED" -Message $errMsg -ErrorRecord $caughtErr -Stage $script:CurrentInstallerStage
    }
}

if ($Action -eq "Commit") {
    $script:CurrentInstallerStage = "Commit"
    try {
        Remove-InstallerTxArtifacts -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot
        $out = [ordered]@{
            status      = "COMMITTED"
            app_version = $AppVersion
            msi_managed = [bool]$MsiManaged
        }
        Write-Output ($out | ConvertTo-Json -Compress)
        exit 0
    }
    catch {
        $caughtErr = $_
        $errMsg = if ($null -ne $caughtErr -and $null -ne $caughtErr.Exception) { $caughtErr.Exception.Message } else { "$caughtErr" }
        Fail-Installer -ExitCode 74 -Code "ERR_COMMIT_FAILED" -Message $errMsg -ErrorRecord $caughtErr -Stage $script:CurrentInstallerStage
    }
}

if ($Action -eq "Rollback") {
    $script:CurrentInstallerStage = "Rollback"
    try {
        $txLookup = Read-InstallerTxStateSafe -DataRoot $ProgramDataRoot
        $manifestPrev = Join-Path $ProgramDataRoot "config\install_manifest.previous.json"
        $binPrev = Join-Path $ProgramDataRoot "bin.previous"

        if ($txLookup.Source -eq "PRIMARY" -or $txLookup.Source -eq "PREVIOUS") {
            if ($txLookup.Source -eq "PREVIOUS") {
                Write-InstallerDiagnosticLog -DataRoot $ProgramDataRoot -ExitCode 0 -Code "INFO_TX_STATE_RECOVERED_FROM_PREVIOUS" `
                    -Message "installer_tx_state.json bozuk veya eksik oldugu icin installer_tx_state.previous.json uzerinden kurtarildi ($($txLookup.ErrorDetail))." -Stage "Rollback"
            }
            $txState = $txLookup.State
            if ($txState.status -eq "ROLLED_BACK") {
                Write-Host "[ROLLBACK] Geri alma zaten uygulanmis (idempotent no-op)." -ForegroundColor Gray
                exit 0
            }
            $script:Tx.Mode = [string]$txState.mode
            if ($null -ne $txState.PSObject.Properties["tx_id"] -and -not [string]::IsNullOrWhiteSpace([string]$txState.tx_id)) {
                $script:Tx.TxId = [string]$txState.tx_id
            }
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
            $script:Tx.CreatedFirewallRules = @()
            if ($null -ne $txState.created_firewall_rules) {
                $script:Tx.CreatedFirewallRules = @($txState.created_firewall_rules | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            $rbReport = Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
            if ($rbReport.overall_status -ne "ROLLED_BACK") {
                Fail-Installer -ExitCode 74 -Code "ERR_PARTIAL_ROLLBACK_FAILED" `
                    -Message ("Rollback tum adimlari tamamlayamadi: $($rbReport.failed_steps -join ', ')") -Stage "Rollback" -SkipDiagnosticLog
            }
            exit 0
        }

        if ($txLookup.PrimaryCorrupt) {
            if ($txLookup.PreviousExists -and $txLookup.PreviousCorrupt) {
                Fail-Installer -ExitCode 74 -Code "ERR_TX_STATE_CORRUPT" `
                    -Message "Hem installer_tx_state.json hem installer_tx_state.previous.json bozuk; tahminle geri alma yapilmadi, tum dosya ve veriler korundu." -Stage "Rollback"
            }

            $mfFallback = Resolve-ValidatedManifestFallback -DataRoot $ProgramDataRoot -ExpectedServiceName $ServiceName
            if ($mfFallback.IsValid) {
                $fbScm = Resolve-ManifestFallbackServiceModified -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName -PreviousVersion $mfFallback.PreviousVersion
                $script:Tx.Mode = "Upgrade"
                $script:Tx.PreviousVersion = $mfFallback.PreviousVersion
                $script:Tx.HadExistingService = $true
                $script:Tx.HadPreviousServiceRunning = [bool]$mfFallback.HadPreviousServiceRunning
                $script:Tx.BackedUpBin = $true
                $script:Tx.BackedUpManifest = $true
                $script:Tx.ServiceModified = [bool]$fbScm.ServiceModified
                $script:Tx.CreatedFirewallRules = @()
                Write-InstallerDiagnosticLog -DataRoot $ProgramDataRoot -ExitCode 0 -Code "INFO_TX_STATE_RECOVERED_FROM_MANIFEST_PREVIOUS" `
                    -Message "installer_tx_state.json bozuktu ve previous tx state yoktu; dogrulanmis install_manifest.previous.json uzerinden kurtarma baslatildi (version=$($mfFallback.PreviousVersion), service_state=$($mfFallback.ServiceState), had_running=$($mfFallback.HadPreviousServiceRunning), service_modified=$($script:Tx.ServiceModified), scm_disposition=$($fbScm.Disposition))." -Stage "Rollback"
                $rbReport = Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
                if ($rbReport.overall_status -ne "ROLLED_BACK") {
                    Fail-Installer -ExitCode 74 -Code "ERR_PARTIAL_ROLLBACK_FAILED" `
                        -Message ("Rollback tum adimlari tamamlayamadi: $($rbReport.failed_steps -join ', ')") -Stage "Rollback" -SkipDiagnosticLog
                }
                exit 0
            }

            Fail-Installer -ExitCode 74 -Code "ERR_TX_STATE_CORRUPT" `
                -Message "installer_tx_state.json bozuk ve manifest fallback dogrulanamadi ($($mfFallback.Reason)); tahminle geri alma yapilmadi, tum veriler korundu." -Stage "Rollback"
        }

        if ((Test-Path -LiteralPath $binPrev) -or (Test-Path -LiteralPath $manifestPrev)) {
            $mfFallback = Resolve-ValidatedManifestFallback -DataRoot $ProgramDataRoot -ExpectedServiceName $ServiceName
            if (-not $mfFallback.IsValid) {
                Fail-Installer -ExitCode 74 -Code "ERR_TX_STATE_CORRUPT" `
                    -Message "Transaction state yok ve .previous kurtarma dogrulanamadi ($($mfFallback.Reason)); tahminle geri alma yapilmadi, tum veriler korundu." -Stage "Rollback"
            }
            $fbScm = Resolve-ManifestFallbackServiceModified -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName -PreviousVersion $mfFallback.PreviousVersion
            $script:Tx.Mode = "Upgrade"
            $script:Tx.PreviousVersion = $mfFallback.PreviousVersion
            $script:Tx.HadExistingService = $true
            $script:Tx.HadPreviousServiceRunning = [bool]$mfFallback.HadPreviousServiceRunning
            $script:Tx.BackedUpBin = $true
            $script:Tx.BackedUpManifest = $true
            $script:Tx.ServiceModified = [bool]$fbScm.ServiceModified
            $script:Tx.CreatedFirewallRules = @()
            Write-InstallerDiagnosticLog -DataRoot $ProgramDataRoot -ExitCode 0 -Code "INFO_TX_STATE_RECOVERED_FROM_MANIFEST_PREVIOUS" `
                -Message "Transaction state dosyasi yoktu; dogrulanmis install_manifest.previous.json uzerinden kurtarma baslatildi (version=$($mfFallback.PreviousVersion), service_state=$($mfFallback.ServiceState), had_running=$($mfFallback.HadPreviousServiceRunning), service_modified=$($script:Tx.ServiceModified), scm_disposition=$($fbScm.Disposition))." -Stage "Rollback"
            $rbReport = Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
            if ($rbReport.overall_status -ne "ROLLED_BACK") {
                Fail-Installer -ExitCode 74 -Code "ERR_PARTIAL_ROLLBACK_FAILED" `
                    -Message ("Rollback tum adimlari tamamlayamadi: $($rbReport.failed_steps -join ', ')") -Stage "Rollback" -SkipDiagnosticLog
            }
        }
        else {
            Write-Host "[ROLLBACK] Aktif islem gunlugu veya .previous yedegi yok; idempotent no-op." -ForegroundColor Gray
        }
        exit 0
    }
    catch {
        $caughtErr = $_
        $errMsg = if ($null -ne $caughtErr -and $null -ne $caughtErr.Exception) { $caughtErr.Exception.Message } else { "$caughtErr" }
        Fail-Installer -ExitCode 74 -Code "ERR_ROLLBACK_FAILED" -Message $errMsg -ErrorRecord $caughtErr -Stage $script:CurrentInstallerStage
    }
}

if ($Action -eq "Uninstall") {
    $script:CurrentInstallerStage = "Uninstall"
    try {
        if ($FaultInjectionStage -eq "UninstallService") {
            Fail-Installer -ExitCode 75 -Code "ERR_UNINSTALL_SERVICE_FAILED" `
                -Message "Simule edilmis uninstall servis durdurma/kaldirma hatasi; kullanici verileri korundu."
        }

        $uninstWrapper = Join-Path $ProgramDataRoot "bin\MarketMMSService.exe"
        if ($TestSandboxMode) {
            $svc = Read-SandboxService $ProgramDataRoot
            if ($svc) {
                Remove-SandboxService $ProgramDataRoot
            }
        }
        else {
            $uninstSnap = Read-ScmServiceIdentitySnapshot -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName
            if ($uninstSnap.Exists) {
                Invoke-VerifiedServiceUninstall -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ExpectedWrapperPath $uninstWrapper
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

        if (-not $TestSandboxMode) {
            $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
            if (Test-Path $runKeyPath) {
                Remove-ItemProperty -Path $runKeyPath -Name "MarketMMSClient" -ErrorAction SilentlyContinue
            }
            Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction SilentlyContinue | ForEach-Object {
                $userRunPath = Join-Path $_.PSPath "Software\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path $userRunPath) {
                    Remove-ItemProperty -Path $userRunPath -Name "MarketMMSClient" -ErrorAction SilentlyContinue
                }
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
                (Get-InstallerTxStateFile $ProgramDataRoot),
                (Get-InstallerTxPrevStateFile $ProgramDataRoot)
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
    catch {
        $caughtErr = $_
        $errMsg = if ($null -ne $caughtErr -and $null -ne $caughtErr.Exception) { $caughtErr.Exception.Message } else { "$caughtErr" }
        Fail-Installer -ExitCode 75 -Code "ERR_UNINSTALL_FAILED" -Message $errMsg -ErrorRecord $caughtErr -Stage $script:CurrentInstallerStage
    }
}

# Install / Upgrade / Repair ortak is akisi
try {
    $script:CurrentInstallerStage = "StagingPrerequisites"
    Assert-StagingPrerequisites -RootStaging $StagingDir

    $script:CurrentInstallerStage = "ProgramDataSafety"
    Assert-ProgramDataSafety -DataRoot $ProgramDataRoot

    $script:CurrentInstallerStage = "VersionCheck"
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
            }
            elseif ($cmp -eq 0) {
                $script:Tx.Mode = "Repair"
            }
            else {
                $script:Tx.Mode = "Upgrade"
            }
        }
    }
}
catch {
    $caughtErr = $_
    $errMsg = if ($null -ne $caughtErr -and $null -ne $caughtErr.Exception) { $caughtErr.Exception.Message } else { "$caughtErr" }
    Fail-Installer -ExitCode 74 -Code "ERR_INSTALLER_PRECHECK_FAILED" -Message $errMsg -ErrorRecord $caughtErr -Stage $script:CurrentInstallerStage
}

$script:CurrentInstallerStage = "Init"

try {
    $script:CurrentInstallerStage = "ProgramDataDirs"
    if ($FaultInjectionStage -eq "ProgramData") {
        if ($TestSandboxMode) {
            Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
        }
        throw "[ERR_PROGRAMDATA_FAILED] Simule edilmis ProgramData dizin olusturma hatasi."
    }

    # 0. Transaction durumunu kayda al
    if (-not (Test-Path $ProgramDataRoot)) {
        [MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity($ProgramDataRoot, [bool]$TestSandboxMode)
    }
    foreach ($sub in $StandardProgramDataSubdirs) {
        $subDir = Join-Path $ProgramDataRoot $sub
        if (-not (Test-Path $subDir)) {
            if ($sub -eq "logs") {
                [MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity($subDir, [bool]$TestSandboxMode)
            }
            else {
                New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            }
        }
    }
    if ($TestSandboxMode) {
        $existingSvcCheck = Read-SandboxService $ProgramDataRoot
        if ($existingSvcCheck) {
            $script:Tx.HadExistingService = $true
            $script:Tx.HadPreviousServiceRunning = ($existingSvcCheck.status -eq "Running")
        }
    }
    else {
        $existingSvcCheck = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($existingSvcCheck) {
            $script:Tx.HadExistingService = $true
            $script:Tx.HadPreviousServiceRunning = ($existingSvcCheck.Status -eq "Running")
        }
    }
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    # 1. Mevcut servisi yalnizca durdur (SCM kaydi Step 5'e kadar korunur; gereksiz erken kaldirma yapilmaz)
    $script:CurrentInstallerStage = "StopExistingService"
    $existingWrapperExpected = Join-Path $ProgramDataRoot "bin\MarketMMSService.exe"
    $preStopSnap = Read-ScmServiceIdentitySnapshot -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName
    if ($preStopSnap.Exists) {
        Invoke-VerifiedServiceStop -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ExpectedWrapperPath $existingWrapperExpected
    }

    if ($FaultInjectionStage -eq "PrePreviousBackup") {
        throw "[ERR_PRE_BACKUP_FAILED] Simule edilmis .previous yedekleme oncesi kesinti."
    }

    # 2. Upgrade/Repair oncesi mevcut ikililer ve DB (+ WAL/SHM VACUUM INTO) yedeklemesi
    $script:CurrentInstallerStage = "PreUpgradeBackup"
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

    $script:CurrentInstallerStage = "BackupExistingBinaries"
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

    # 3. Config ve Admin Secret (mevcutsa ASLA ezilmez; Recovery Key DPAPI olusturulmaz/dokunulmaz)
    $script:CurrentInstallerStage = "ConfigAndAdminSecret"
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
        }
        else {
            $defaultCfg = [ordered]@{
                schema_version               = 1
                environment                  = "production"
                port                         = $Port
                discovery_port               = $DiscoveryPort
                enable_discovery             = $true
                db_path                      = "../data/market_master.db"
                backup_dir                   = "../backups"
                pepper_file                  = "../security/pepper.dpapi"
                admin_secret_file            = "../security/admin_secret.txt"
                tls                          = [ordered]@{
                    enabled = $true
                    cert    = "../certs/server.crt"
                    key     = "../certs/server.key"
                    ca_cert = "../certs/ca.crt"
                }
                tenant_id                    = "tenant-default"
                store_id                     = "store-main-01"
                hub_id                       = "MMS-HUB-01"
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
            # Servis kaydindan once yalnizca SYSTEM + Administrators kilidi uygulanir; ServiceSID Step 6'da eklenir.
            & icacls.exe $adminSecretFile /inheritance:r /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_ADMIN_SECRET_ACL_FAILED] admin_secret.txt on-kilit ACL atamasi basarisiz oldu ($LASTEXITCODE)."
            }
        }
    }

    # 4. Istemci ve Hub ikililerinin kopyalanmasi
    $script:CurrentInstallerStage = "CopyBinaries"
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

    $script:CurrentInstallerStage = "MigrationCheck"
    if ($FaultInjectionStage -eq "Migration") {
        throw "[ERR_MIGRATION_FAILED] Simule edilmis veritabani migration hatasi."
    }

    # 5. Servis SCM kaydi, SID Tipi ve Deterministik Registry Kimlik Damgasi
    $script:CurrentInstallerStage = "ServiceInstallAndFirewall"
    if ($FaultInjectionStage -eq "ServiceInstall") {
        throw "[ERR_SERVICE_INSTALL_FAILED] Simule edilmis servis kayit hatasi."
    }

    $deployedWrapper = Join-Path $binDir "MarketMMSService.exe"
    $deployedXmlSha = Get-FileSha256Upper -FilePath (Join-Path $binDir "MarketMMSService.xml")

    $script:Tx.ServiceModified = $true
    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    $preStep5Snap = Read-ScmServiceIdentitySnapshot -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName
    if ($preStep5Snap.Exists) {
        Invoke-VerifiedServiceUninstall -DataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ExpectedWrapperPath $existingWrapperExpected
    }

    if ($TestSandboxMode) {
        Add-SandboxInstallScmOp -DataRoot $ProgramDataRoot -Operation "install:$AppVersion"
        Add-SandboxInstallScmOp -DataRoot $ProgramDataRoot -Operation "sidtype:unrestricted"
        Write-SandboxService -DataRoot $ProgramDataRoot -Name $ServiceName -Status "Stopped" -Version $AppVersion -BinPath $deployedWrapper -ClearStamp
    }
    else {
        $instOut = & $deployedWrapper install 2>&1
        if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_INSTALL_FAILED] WinSW install basarisiz: $instOut" }
        $sidOut = sc.exe sidtype $ServiceName unrestricted 2>&1
        if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_SID_FAILED] sc.exe sidtype basarisiz: $sidOut" }
    }

    Write-ScmServiceIdentityStamp `
        -DataRoot $ProgramDataRoot `
        -TargetServiceName $ServiceName `
        -StampVersion $AppVersion `
        -XmlSha256 $deployedXmlSha `
        -PreviousVersion ([string]$existingVersion) `
        -TxId ([string]$script:Tx.TxId) `
        -WrapperPath $deployedWrapper

    Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"

    # 6. NTFS ACL yapilandirmasi & admin_secret.txt Service SID izni (Servis kayitli, henuz baslatilmadi)
    $script:CurrentInstallerStage = "ApplyAcls"
    $resolvedSvcSid = Resolve-WindowsServiceSid -TargetServiceName $ServiceName
    if (-not $TestSandboxMode -and [string]::IsNullOrWhiteSpace($resolvedSvcSid)) {
        throw "[ERR_SERVICE_SID_FAILED] Service SID cozumlenemedi: $ServiceName"
    }
    Apply-DirectoryAcls -DataRoot $ProgramDataRoot -ServiceSid $resolvedSvcSid
    if (-not $TestSandboxMode -and (Test-Path -LiteralPath $adminSecretFile)) {
        & icacls.exe $adminSecretFile /inheritance:r /grant:r "*S-1-5-18:F" /grant:r "*S-1-5-32-544:F" /grant:r "*${resolvedSvcSid}:R" /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "[ERR_ADMIN_SECRET_ACL_FAILED] admin_secret.txt ACL atamasi basarisiz oldu ($LASTEXITCODE)."
        }
    }

    # 6b. Firewall kurulumu ve TLS hazirlik kontrolu (yalnizca bu islemde olusturulan kurallar izlenir)
    $script:CurrentInstallerStage = "ServiceInstallAndFirewall"
    $txFwTcpRule = "MarketMMS-Hub-API-TCP-$Port"
    $txFwUdpRule = "MarketMMS-Hub-Discovery-UDP-$DiscoveryPort"
    if ($TestSandboxMode) {
        $curSandboxFw = Read-SandboxFirewallRules -DataRoot $ProgramDataRoot
        $newlyAddedFw = New-Object System.Collections.Generic.List[string]
        foreach ($rName in @($txFwTcpRule, $txFwUdpRule)) {
            if ($curSandboxFw -notcontains $rName) {
                $curSandboxFw += $rName
                $newlyAddedFw.Add($rName)
            }
        }
        if ($newlyAddedFw.Count -gt 0) {
            Write-SandboxFirewallRules -DataRoot $ProgramDataRoot -Rules $curSandboxFw
            $script:Tx.CreatedFirewallRules = @($newlyAddedFw.ToArray())
            Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
        }
    }
    else {
        $preMissingFw = New-Object System.Collections.Generic.List[string]
        foreach ($rName in @($txFwTcpRule, $txFwUdpRule)) {
            if (-not (Get-NetFirewallRule -DisplayName $rName -ErrorAction SilentlyContinue)) {
                $preMissingFw.Add($rName)
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($FirewallScriptPath) -and (Test-Path $FirewallScriptPath)) {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FirewallScriptPath -TcpPort $Port -UdpPort $DiscoveryPort -ConfigPath $configFile | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "[ERR_FIREWALL_FAILED] configure_hub_firewall.ps1 basarisiz oldu ($LASTEXITCODE)."
            }
            $createdNowFw = New-Object System.Collections.Generic.List[string]
            foreach ($rName in $preMissingFw) {
                if (Get-NetFirewallRule -DisplayName $rName -ErrorAction SilentlyContinue) {
                    $createdNowFw.Add($rName)
                }
            }
            if ($createdNowFw.Count -gt 0) {
                $script:Tx.CreatedFirewallRules = @($createdNowFw.ToArray())
                Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
            }
        }
    }

    $hasTlsCerts = (Test-Path (Join-Path $ProgramDataRoot "certs\ca.crt")) -and `
    (Test-Path (Join-Path $ProgramDataRoot "certs\server.crt")) -and `
    (Test-Path (Join-Path $ProgramDataRoot "certs\server.key"))

    $serviceState = "PENDING_TLS_PROVISIONING"
    $healthResult = @{ verified = $false; recovery_key_configured = (Test-Path (Join-Path $ProgramDataRoot "security\backup_recovery_key.dpapi")); status = "DEFERRED_NO_CERTS" }

    $script:CurrentInstallerStage = "ServiceStart"
    if ($FaultInjectionStage -eq "ServiceStart") {
        throw "[ERR_SERVICE_START_FAILED] Simule edilmis servis baslatma hatasi."
    }

    if ($hasTlsCerts) {
        if ($TestSandboxMode) {
            Write-SandboxService -DataRoot $ProgramDataRoot -Name $ServiceName -Status "Running" -Version $AppVersion -BinPath $deployedWrapper
            $serviceState = "RUNNING"
        }
        else {
            $startOut = & $deployedWrapper start 2>&1
            if ($LASTEXITCODE -ne 0) { throw "[ERR_SERVICE_START_FAILED] Servis baslatilamadi: $startOut" }
            Start-Sleep -Seconds 3
            $svcCheck = Get-Service -Name $ServiceName -ErrorAction Stop
            if ($svcCheck.Status -ne "Running") {
                throw "[ERR_SERVICE_START_FAILED] Servis calisma durumuna gecemedi: $($svcCheck.Status)"
            }
            $serviceState = "RUNNING"
        }

        $script:CurrentInstallerStage = "HealthCheck"
        if (-not [string]::IsNullOrWhiteSpace($HealthCheckUrl)) {
            $healthResult = Invoke-HealthVerification -Url $HealthCheckUrl -DataRoot $ProgramDataRoot
        }
        elseif (-not $TestSandboxMode) {
            $healthPort = $Port
            if (Test-Path $configFile) {
                try { $healthPort = [int](Get-Content $configFile -Raw | ConvertFrom-Json).port } catch {}
            }
            $healthResult = Invoke-HealthVerification -Url ("https://127.0.0.1:{0}/health" -f $healthPort) -DataRoot $ProgramDataRoot
        }
        elseif ($FaultInjectionStage -eq "HealthCheck") {
            $healthResult = Invoke-HealthVerification -Url "" -DataRoot $ProgramDataRoot
        }
    }
    else {
        if (-not $AllowDeferredTlsStartBool) {
            throw "[ERR_TLS_CERTS_MISSING] TLS sertifikalari (ca.crt, server.crt, server.key) eksik ve ertelenmis baslangic kapali."
        }
        $script:CurrentInstallerStage = "HealthCheck"
        if ($FaultInjectionStage -eq "HealthCheck") {
            $null = Invoke-HealthVerification -Url $HealthCheckUrl -DataRoot $ProgramDataRoot
        }
    }

    # 7. Kurulum manifestini kaydet (Yalnizca TUM adimlar basariliysa!)
    $script:CurrentInstallerStage = "WriteManifest"
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
    }
    else {
        Remove-InstallerTxArtifacts -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot
    }

    Write-Output ($manifest | ConvertTo-Json -Compress)
    exit 0
}
catch {
    $caughtError = $_
    $errMsg = if ($null -ne $caughtError -and $null -ne $caughtError.Exception) {
        $caughtError.Exception.Message
    }
    else {
        "$caughtError"
    }
    $failCode = if ($MsiManaged) { "ERR_INSTALLER_STEP_FAILED" } else { "ERR_INSTALLER_ROLLED_BACK" }
    Write-InstallerDiagnosticLog -DataRoot $ProgramDataRoot -ExitCode 74 -Code $failCode -Message $errMsg -ErrorRecord $caughtError -Stage $script:CurrentInstallerStage

    if ($MsiManaged) {
        try {
            Write-InstallerTxState -DataRoot $ProgramDataRoot -Status "IN_PROGRESS"
        }
        catch {
            # State yazilamasa bile asil kurulum hatasi gizlenmez
        }
        Fail-Installer -ExitCode 74 -Code $failCode -Message $errMsg -ErrorRecord $caughtError -Stage $script:CurrentInstallerStage -SkipDiagnosticLog
    }
    else {
        $rbCatchReport = $null
        try {
            $rbCatchReport = Invoke-MarketMmsRollback -TargetInstallDir $InstallDir -TargetDataRoot $ProgramDataRoot -TargetServiceName $ServiceName -ForceMarkRolledBack
        }
        catch {
            # Rollback hata verse bile asil kurulum hatasi gizlenmez
        }
        if ($null -ne $rbCatchReport -and $rbCatchReport.overall_status -ne "ROLLED_BACK") {
            $errMsg = "$errMsg [PARTIAL_ROLLBACK_FAILED: $($rbCatchReport.failed_steps -join ', ')]"
        }
        Fail-Installer -ExitCode 74 -Code $failCode -Message $errMsg -ErrorRecord $caughtError -Stage $script:CurrentInstallerStage -SkipDiagnosticLog
    }
}
