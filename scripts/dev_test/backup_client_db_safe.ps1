# backup_client_db_safe.ps1 - Safe SQLite Online Backup API Utility
# Pure ASCII (PowerShell 5.1+ compatible).
# Opens source SQLite DB in read-only mode (SQLITE_OPEN_READONLY), executes
# sqlite3_backup_init/step/finish into a new snapshot file, verifies PRAGMA integrity_check,
# and writes a .sha256 sidecar without modifying source DB files or WAL/SHM state.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceDbPath,
    [Parameter(Mandatory = $true)][string]$OutputBackupPath,
    [string]$SqliteDllPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceDbPath) -or -not (Test-Path -LiteralPath $SourceDbPath -PathType Leaf)) {
    throw "Source SQLite DB not found: $SourceDbPath"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($SqliteDllPath)) {
    $candidates = @(
        (Join-Path $repoRoot ".dart_tool\lib\sqlite3.dll"),
        (Join-Path $repoRoot "dist\windows_release_v1_0_0_tray\hub_bin\sqlite3.dll"),
        (Join-Path $repoRoot "dist\windows_release\hub_bin\sqlite3.dll"),
        (Join-Path $repoRoot "build\windows\x64\runner\Release\sqlite3.dll")
    )
    $SqliteDllPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($SqliteDllPath) -or -not (Test-Path -LiteralPath $SqliteDllPath -PathType Leaf)) {
    throw "Native sqlite3.dll not found."
}

$outFull = [System.IO.Path]::GetFullPath($OutputBackupPath)
$outDir = Split-Path -Parent $outFull
if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
if (Test-Path -LiteralPath $outFull) {
    throw "Refusing to overwrite existing backup target: $outFull"
}

if (-not ("MmsClientDbSafeBackup" -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class MmsClientDbSafeBackup
{
    private const int SQLITE_OK = 0;
    private const int SQLITE_DONE = 101;
    private const int SQLITE_OPEN_READONLY = 0x00000001;
    private const int SQLITE_OPEN_READWRITE = 0x00000002;
    private const int SQLITE_OPEN_CREATE = 0x00000004;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string lpLibFileName);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteOpenV2Delegate(IntPtr filename, out IntPtr ppDb, int flags, IntPtr zVfs);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteCloseV2Delegate(IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr SqliteErrmsgDelegate(IntPtr db);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void SqliteFreeDelegate(IntPtr ptr);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteExecCallback(IntPtr arg, int colCount, IntPtr colValues, IntPtr colNames);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteExecDelegate(IntPtr db, IntPtr sql, SqliteExecCallback cb, IntPtr arg, out IntPtr errmsg);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr SqliteBackupInitDelegate(IntPtr pDest, IntPtr zDestName, IntPtr pSource, IntPtr zSourceName);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteBackupStepDelegate(IntPtr pBackup, int nPage);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SqliteBackupFinishDelegate(IntPtr pBackup);

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

    private static T GetDelegate<T>(IntPtr hMod, string name) where T : class
    {
        IntPtr p = GetProcAddress(hMod, name);
        if (p == IntPtr.Zero) throw new InvalidOperationException("Missing sqlite3 export: " + name);
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    private static void ExecSql(SqliteExecDelegate execFn, SqliteFreeDelegate freeFn, IntPtr db, string sql, List<string> firstCol)
    {
        IntPtr sqlPtr = AllocUtf8(sql);
        IntPtr errPtr = IntPtr.Zero;
        SqliteExecCallback cb = null;
        if (firstCol != null)
        {
            cb = delegate(IntPtr arg, int colCount, IntPtr colValues, IntPtr colNames)
            {
                if (colCount > 0 && colValues != IntPtr.Zero)
                {
                    firstCol.Add(PtrToUtf8(Marshal.ReadIntPtr(colValues, 0)));
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
                throw new InvalidOperationException("SQLite error (" + rc + "): " + PtrToUtf8(errPtr));
            }
        }
        finally
        {
            Marshal.FreeHGlobal(sqlPtr);
            if (errPtr != IntPtr.Zero) freeFn(errPtr);
        }
    }

    public static void BackupReadOnlyAndVerify(string dllPath, string srcPath, string dstPath)
    {
        IntPtr hMod = LoadLibraryW(dllPath);
        if (hMod == IntPtr.Zero)
        {
            throw new InvalidOperationException("LoadLibraryW failed for sqlite3.dll: " + Marshal.GetLastWin32Error());
        }
        try
        {
            var openFn = GetDelegate<SqliteOpenV2Delegate>(hMod, "sqlite3_open_v2");
            var closeFn = GetDelegate<SqliteCloseV2Delegate>(hMod, "sqlite3_close_v2");
            var errFn = GetDelegate<SqliteErrmsgDelegate>(hMod, "sqlite3_errmsg");
            var freeFn = GetDelegate<SqliteFreeDelegate>(hMod, "sqlite3_free");
            var execFn = GetDelegate<SqliteExecDelegate>(hMod, "sqlite3_exec");
            var bInitFn = GetDelegate<SqliteBackupInitDelegate>(hMod, "sqlite3_backup_init");
            var bStepFn = GetDelegate<SqliteBackupStepDelegate>(hMod, "sqlite3_backup_step");
            var bFinFn = GetDelegate<SqliteBackupFinishDelegate>(hMod, "sqlite3_backup_finish");

            string tmpDst = dstPath + ".tmp";
            if (File.Exists(tmpDst)) File.Delete(tmpDst);

            IntPtr srcDb = IntPtr.Zero;
            IntPtr dstDb = IntPtr.Zero;
            IntPtr srcPtr = AllocUtf8(srcPath);
            IntPtr dstPtr = AllocUtf8(tmpDst);
            IntPtr mainPtr = AllocUtf8("main");

            try
            {
                int rcSrc = openFn(srcPtr, out srcDb, SQLITE_OPEN_READONLY, IntPtr.Zero);
                if (rcSrc != SQLITE_OK || srcDb == IntPtr.Zero)
                {
                    throw new InvalidOperationException("Source DB open failed: " + (srcDb != IntPtr.Zero ? PtrToUtf8(errFn(srcDb)) : rcSrc.ToString()));
                }
                ExecSql(execFn, freeFn, srcDb, "PRAGMA busy_timeout = 5000;", null);

                int rcDst = openFn(dstPtr, out dstDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, IntPtr.Zero);
                if (rcDst != SQLITE_OK || dstDb == IntPtr.Zero)
                {
                    throw new InvalidOperationException("Backup DB create failed: " + (dstDb != IntPtr.Zero ? PtrToUtf8(errFn(dstDb)) : rcDst.ToString()));
                }

                IntPtr pBackup = bInitFn(dstDb, mainPtr, srcDb, mainPtr);
                if (pBackup == IntPtr.Zero)
                {
                    throw new InvalidOperationException("sqlite3_backup_init failed: " + PtrToUtf8(errFn(dstDb)));
                }
                int stepRc = bStepFn(pBackup, -1);
                int finRc = bFinFn(pBackup);
                if (stepRc != SQLITE_DONE)
                {
                    throw new InvalidOperationException("sqlite3_backup_step failed (" + stepRc + "): " + PtrToUtf8(errFn(dstDb)));
                }
                if (finRc != SQLITE_OK)
                {
                    throw new InvalidOperationException("sqlite3_backup_finish failed (" + finRc + ")");
                }

                var icRows = new List<string>();
                ExecSql(execFn, freeFn, dstDb, "PRAGMA integrity_check;", icRows);
                if (icRows.Count != 1 || !string.Equals(icRows[0], "ok", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Backup PRAGMA integrity_check failed.");
                }
            }
            catch
            {
                if (dstDb != IntPtr.Zero) { closeFn(dstDb); dstDb = IntPtr.Zero; }
                if (File.Exists(tmpDst)) { try { File.Delete(tmpDst); } catch {} }
                throw;
            }
            finally
            {
                Marshal.FreeHGlobal(srcPtr);
                Marshal.FreeHGlobal(dstPtr);
                Marshal.FreeHGlobal(mainPtr);
                if (srcDb != IntPtr.Zero) closeFn(srcDb);
                if (dstDb != IntPtr.Zero) closeFn(dstDb);
            }

            File.Move(tmpDst, dstPath);
        }
        finally
        {
            FreeLibrary(hMod);
        }
    }

    public static void CreateTestWalSeedAndVerify(string dllPath, string dbPath, string backupPath)
    {
        IntPtr hMod = LoadLibraryW(dllPath);
        if (hMod == IntPtr.Zero) throw new InvalidOperationException("LoadLibraryW failed.");
        try
        {
            var openFn = GetDelegate<SqliteOpenV2Delegate>(hMod, "sqlite3_open_v2");
            var closeFn = GetDelegate<SqliteCloseV2Delegate>(hMod, "sqlite3_close_v2");
            var freeFn = GetDelegate<SqliteFreeDelegate>(hMod, "sqlite3_free");
            var execFn = GetDelegate<SqliteExecDelegate>(hMod, "sqlite3_exec");
            IntPtr db = IntPtr.Zero;
            IntPtr pPath = AllocUtf8(dbPath);
            try
            {
                if (openFn(pPath, out db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, IntPtr.Zero) != SQLITE_OK)
                    throw new InvalidOperationException("Cannot create test WAL DB.");
                ExecSql(execFn, freeFn, db, "PRAGMA journal_mode=WAL;", null);
                ExecSql(execFn, freeFn, db, "CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, val TEXT);", null);
                ExecSql(execFn, freeFn, db, "INSERT INTO items(val) VALUES('row_in_db_and_wal');", null);
                // Leave connection open while running online backup so WAL/SHM are active!
                BackupReadOnlyAndVerify(dllPath, dbPath, backupPath);
            }
            finally
            {
                Marshal.FreeHGlobal(pPath);
                if (db != IntPtr.Zero) closeFn(db);
            }

            // Now inspect standalone backup DB and verify the WAL row arrived!
            IntPtr bDb = IntPtr.Zero;
            IntPtr bPtr = AllocUtf8(backupPath);
            try
            {
                if (openFn(bPtr, out bDb, SQLITE_OPEN_READONLY, IntPtr.Zero) != SQLITE_OK)
                    throw new InvalidOperationException("Cannot open verified backup.");
                var rows = new List<string>();
                ExecSql(execFn, freeFn, bDb, "SELECT val FROM items;", rows);
                if (rows.Count != 1 || rows[0] != "row_in_db_and_wal")
                    throw new InvalidOperationException("WAL row missing from backup snapshot.");
            }
            finally
            {
                Marshal.FreeHGlobal(bPtr);
                if (bDb != IntPtr.Zero) closeFn(bDb);
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

$srcFull = [System.IO.Path]::GetFullPath($SourceDbPath)
$srcHashBefore = (Get-FileHash -LiteralPath $srcFull -Algorithm SHA256).Hash

[MmsClientDbSafeBackup]::BackupReadOnlyAndVerify($SqliteDllPath, $srcFull, $outFull)

$srcHashAfter = (Get-FileHash -LiteralPath $srcFull -Algorithm SHA256).Hash
if ($srcHashBefore -ne $srcHashAfter) {
    throw "SAFETY VIOLATION: Source DB hash changed during read-only backup!"
}

$outItem = Get-Item -LiteralPath $outFull
$outHash = (Get-FileHash -LiteralPath $outFull -Algorithm SHA256).Hash
$shaFile = $outFull + ".sha256"
Set-Content -LiteralPath $shaFile -Value ("{0}  {1}" -f $outHash, $outItem.Name) -Encoding ASCII

$result = [ordered]@{
    status                = "BACKUP_VERIFIED_OK"
    source_db_path        = $srcFull
    source_sha256         = $srcHashAfter
    backup_path           = $outFull
    backup_size_bytes     = $outItem.Length
    backup_sha256         = $outHash
    sha256_file           = $shaFile
    integrity_check       = "ok"
    source_untouched      = ($srcHashBefore -eq $srcHashAfter)
    created_at_utc        = (Get-Date).ToUniversalTime().ToString("o")
}
Write-Output ($result | ConvertTo-Json -Compress)
