# =====================================================================
#  Repair-SystemFiles.ps1
#  Mengganti file sistem Windows (x86 / SysWOW64) yang hilang atau rusak
#  dengan salinan "bagus" di folder .\good
#
#  Dipanggil oleh PerbaikiFileSistem.bat (menu), tapi bisa juga manual:
#     powershell -ExecutionPolicy Bypass -File Repair-SystemFiles.ps1 -Mode Scan
#
#  Mode:
#     Scan        - cek saja, tidak mengubah apa pun
#     Repair      - ganti file yang hilang / beda / rusak
#     Restore     - kembalikan file dari backup terakhir
#     List        - tampilkan isi folder good + manifest
#     ScanLegacy  - cari file sistem versi lama / tidak bertanda tangan
#
#  Param tambahan:
#     -Force          paksa ganti walaupun versi terpasang lebih baru
#     -WindowsRoot X  pakai root Windows lain (untuk uji coba)
# =====================================================================

[CmdletBinding()]
param(
    [ValidateSet('Scan', 'Repair', 'Restore', 'List', 'ScanLegacy')]
    [string]$Mode = 'Scan',

    [string]$WindowsRoot = $env:WINDIR,

    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------
#  Konfigurasi
# ---------------------------------------------------------------------
$ToolRoot   = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$GoodDir    = Join-Path $ToolRoot 'good'
$Manifest   = Join-Path $GoodDir 'manifest.csv'
$BackupRoot = Join-Path $ToolRoot 'backup'
$LogDir     = Join-Path $ToolRoot 'logs'
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = Join-Path $LogDir "repair-$Stamp.log"

New-Item -ItemType Directory -Force -Path $BackupRoot, $LogDir | Out-Null

# ---------------------------------------------------------------------
#  Helper
# ---------------------------------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0}  [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'GANTI' { Write-Host $line -ForegroundColor Cyan }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-Header {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host "  $Text" -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkGray
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Sha256 {
    param([string]$Path)
    try { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash }
    catch { $null }
}

function Get-FileVersionSafe {
    param([string]$Path)
    try {
        $raw = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.FileVersion
        if ($raw -and $raw -match '^\d+(\.\d+){1,3}') { [version]$Matches[0] } else { $null }
    } catch { $null }
}

function Get-FileVersionText {
    param([string]$Path)
    try {
        $v = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.FileVersion
        if ($v) { ($v -replace '\s*\(.*$', '') } else { '-' }
    } catch { '-' }
}

# SDDL ACL standar file sistem (semua file di SysWOW64 memakai ACL yang sama).
# Diambil dari file sistem lain yang masih ada, dipakai kalau file target hilang.
function Get-ReferenceSddl {
    param([string]$Root)
    $candidates = @(
        (Join-Path $Root 'SysWOW64\kernel32.dll'),
        (Join-Path $Root 'SysWOW64\ntdll.dll'),
        (Join-Path $Root 'System32\kernel32.dll')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            try { return (Get-Acl -LiteralPath $c).Sddl } catch { }
        }
    }
    return $null
}

function Set-SystemAcl {
    param(
        [string]$Path,
        [string]$Sddl,
        [string]$Owner = 'NT SERVICE\TrustedInstaller'
    )
    if (-not $Sddl) { Write-Log "  (ACL referensi tidak ditemukan, ACL dibiarkan apa adanya)" 'WARN'; return }
    try {
        $orig = New-Object System.Security.AccessControl.FileSecurity
        $orig.SetSecurityDescriptorSddlForm($Sddl)
        $daclSddl = $orig.GetSecurityDescriptorSddlForm(
            [System.Security.AccessControl.AccessControlSections]::Access)
        $final = New-Object System.Security.AccessControl.FileSecurity
        $final.SetSecurityDescriptorSddlForm($daclSddl)
        Set-Acl -LiteralPath $Path -AclObject $final -ErrorAction Stop
    } catch {
        Write-Log "  (gagal set ACL: $($_.Exception.Message))" 'WARN'
    }
    try {
        & icacls.exe $Path /setowner $Owner 2>&1 | Out-Null
    } catch { }
}

function Unlock-File {
    param([string]$Path)
    & takeown.exe /f $Path /a 2>&1 | Out-Null
    & icacls.exe $Path /grant "*S-1-5-32-544:(F)" 2>&1 | Out-Null
}

function Test-GoodSource {
    param([string]$Path, [string]$ExpectedHash, [string]$ExpectedVersion)
    if (-not (Test-Path -LiteralPath $Path)) { return 'file sumber tidak ada' }
    $h = Get-Sha256 $Path
    if ($ExpectedHash -and $h -ne $ExpectedHash) { return 'hash file sumber tidak cocok dengan manifest' }
    $sig = (Get-AuthenticodeSignature -LiteralPath $Path).Status
    if ($sig -ne 'Valid') { return "signature file sumber tidak valid ($sig)" }
    return $null
}

# ---------------------------------------------------------------------
#  Mulai
# ---------------------------------------------------------------------
Write-Header "PERBAIKAN FILE SISTEM WINDOWS - mode: $Mode"
Write-Log "Windows root : $WindowsRoot"
Write-Log "Folder tool  : $ToolRoot"
Write-Log "Log          : $LogFile"

if (-not (Test-IsAdmin)) {
    Write-Log 'Script ini butuh hak Administrator. Jalankan lewat PerbaikiFileSistem.bat.' 'ERROR'
    exit 1
}

if (-not (Test-Path -LiteralPath $Manifest)) {
    Write-Log "Manifest tidak ditemukan: $Manifest" 'ERROR'
    exit 1
}

$items = Import-Csv -LiteralPath $Manifest

# File yang ditaruh manual di folder good (belum ada di manifest) ikut dipakai
# otomatis, jadi cukup copy file bagus ke folder good tanpa edit CSV.
$knownNames = @{}
foreach ($it in $items) { $knownNames[$it.Name.ToLower()] = $true }

$extra = Get-ChildItem $GoodDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -ne '.csv' -and -not $knownNames.ContainsKey($_.Name.ToLower()) }

if ($extra) {
    Write-Log "Ada $($extra.Count) file di folder good yang belum terdaftar di manifest - dipakai otomatis." 'WARN'
    foreach ($f in $extra) {
        $items += [pscustomobject]@{
            Name    = $f.Name
            Target  = "SysWOW64\$($f.Name)"
            Version = ($f.VersionInfo.FileVersion -replace '\s*\(.*$', '')
            SHA256  = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        }
    }
}

# ---------------------------------------------------------------------
#  Mode: List
# ---------------------------------------------------------------------
if ($Mode -eq 'List') {
    Write-Header 'ISI FOLDER GOOD'
    $items | ForEach-Object {
        $p = Join-Path $GoodDir $_.Name
        $ok = Test-Path -LiteralPath $p
        [pscustomobject]@{
            File    = $_.Name
            Target  = $_.Target
            Versi   = $_.Version
            Ukuran  = if ($ok) { (Get-Item -LiteralPath $p).Length } else { 0 }
            Ada     = if ($ok) { 'ya' } else { 'TIDAK' }
        }
    } | Format-Table -AutoSize
    Write-Log "Total $($items.Count) file dipakai (manifest + file tambahan di folder good)."
    exit 0
}

# ---------------------------------------------------------------------
#  Mode: Scan / Repair
# ---------------------------------------------------------------------
if ($Mode -in @('Scan', 'Repair')) {

    $refSddl = Get-ReferenceSddl -Root $WindowsRoot
    $backupDir = Join-Path $BackupRoot "$Stamp"
    $results = @()
    $nOk = 0; $nMissing = 0; $nDiff = 0; $nSkip = 0; $nFail = 0; $nReplaced = 0

    foreach ($it in $items) {
        $name    = $it.Name
        $src     = Join-Path $GoodDir $name
        $target  = Join-Path $WindowsRoot $it.Target
        $goodVer = $it.Version

        # --- validasi file sumber dulu
        $srcProblem = Test-GoodSource -Path $src -ExpectedHash $it.SHA256 -ExpectedVersion $goodVer
        if ($srcProblem) {
            Write-Log "$name : $srcProblem - DILEWATI" 'ERROR'
            $results += [pscustomobject]@{
                File = $name; Status = 'GAGAL'; Terpasang = '-'; Seharusnya = $goodVer; Keterangan = $srcProblem
            }
            $nFail++
            continue
        }

        # --- status file terpasang
        if (-not (Test-Path -LiteralPath $target)) {
            $status = 'HILANG'
            $curVer = '-'
            $curHash = $null
            $nMissing++
        } else {
            $curHash = Get-Sha256 $target
            $curVer  = Get-FileVersionText $target
            if ($curHash -eq $it.SHA256) {
                $status = 'OK'
                $nOk++
            } else {
                $status = 'BEDA'
                $nDiff++
            }
        }

        $ket = ''

        if ($status -eq 'OK') {
            $ket = 'sudah benar'
        }
        elseif ($Mode -eq 'Scan') {
            $ket = if ($status -eq 'HILANG') { 'akan disalin' } else { "terpasang $curVer" }
        }
        else {
            # --- cek jangan sampai menurunkan versi
            $curV = Get-FileVersionSafe $target
            $goodV = $null
            try { if ($goodVer) { $goodV = [version]$goodVer } } catch { }

            if ($status -eq 'BEDA' -and $curV -and $goodV -and $curV -gt $goodV -and -not $Force) {
                $ket = "versi terpasang lebih baru ($curVer) - dilewati"
                $nSkip++
                $status = 'LEBIH BARU'
            }
            else {
                # --- backup
                if (Test-Path -LiteralPath $target) {
                    $bkSub = Join-Path $backupDir (Split-Path $it.Target -Parent)
                    New-Item -ItemType Directory -Force -Path $bkSub | Out-Null
                    try {
                        Copy-Item -LiteralPath $target -Destination (Join-Path $bkSub $name) -Force -ErrorAction Stop
                        Write-Log "$name : backup -> $bkSub\$name"
                    } catch {
                        Write-Log "$name : gagal backup ($($_.Exception.Message)) - DILEWATI" 'WARN'
                        $nFail++
                        $results += [pscustomobject]@{
                            File = $name; Status = 'GAGAL'; Terpasang = $curVer; Seharusnya = $goodVer; Keterangan = 'gagal backup'
                        }
                        continue
                    }
                }

                # --- ambil ACL asli (kalau file ada), kalau tidak pakai referensi
                $sddl = if (Test-Path -LiteralPath $target) {
                    try { (Get-Acl -LiteralPath $target).Sddl } catch { $refSddl }
                } else { $refSddl }

                # --- ganti file
                try {
                    if (Test-Path -LiteralPath $target) { Unlock-File $target }
                    Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
                    Set-SystemAcl -Path $target -Sddl $sddl
                    $ket = "diganti dari $curVer"
                    $nReplaced++
                } catch {
                    $msg = $_.Exception.Message
                    if ($msg -match 'being used by another process|sedang digunakan') {
                        $msg = 'file sedang dipakai proses lain - restart lalu ulangi'
                    }
                    $ket = "GAGAL: $msg"
                    $nFail++
                    Write-Log "$name : $ket" 'ERROR'
                }
            }
        }

        $results += [pscustomobject]@{
            File       = $name
            Status     = $status
            Terpasang  = $curVer
            Seharusnya = $goodVer
            Keterangan = $ket
        }
    }

    Write-Header 'HASIL'
    $results | Format-Table -AutoSize

    Write-Host ''
    Write-Log ("Ringkasan: OK=$nOk  HILANG=$nMissing  BEDA=$nDiff  DIGANTI=$nReplaced  DILEWATI=$nSkip  GAGAL=$nFail")

    if ($Mode -eq 'Repair' -and $nReplaced -gt 0) {
        Write-Log 'File sudah diganti. Kalau ada proses yang memakai file tsb, restart Windows.' 'WARN'
        Write-Log "Backup file lama: $backupDir"
    }
    if ($Mode -eq 'Scan' -and ($nMissing + $nDiff) -gt 0) {
        Write-Log 'Jalankan mode Repair (menu nomor 2) untuk memperbaiki.' 'WARN'
    }

    # --- ringkasan tambahan: file lama / tidak bertanda tangan
    $legacy = Get-ChildItem (Join-Path $WindowsRoot 'SysWOW64') -File -ErrorAction SilentlyContinue |
        Where-Object {
            $v = $_.VersionInfo.FileVersion
            $v -match '^(5\.[012]\.|6\.0\.2900|6\.0\.2600|6\.1\.7600)'
        }
    if ($legacy) {
        Write-Host ''
        Write-Log "Catatan: masih ada $($legacy.Count) file di SysWOW64 dengan versi lama (XP/2003/7)." 'WARN'
        Write-Log 'Lihat detail lewat mode ScanLegacy (menu nomor 6).' 'WARN'
    }

    exit 0
}

# ---------------------------------------------------------------------
#  Mode: ScanLegacy
# ---------------------------------------------------------------------
if ($Mode -eq 'ScanLegacy') {
    Write-Header 'FILE SISTEM VERSI LAMA / TIDAK BERTANDA TANGAN (SysWOW64)'

    $known = @{}
    foreach ($it in $items) { $known[$it.Name.ToLower()] = $true }

    $found = Get-ChildItem (Join-Path $WindowsRoot 'SysWOW64') -File -ErrorAction SilentlyContinue | ForEach-Object {
        $v = $_.VersionInfo.FileVersion
        $old = $v -match '^(5\.[012]\.|6\.0\.2900|6\.0\.2600|6\.1\.7600)'
        $msUnsigned = ($_.VersionInfo.CompanyName -eq 'Microsoft Corporation') -and
                      ((Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid')
        if ($old -or $msUnsigned) {
            [pscustomobject]@{
                File      = $_.Name
                Versi     = if ($v) { ($v -replace '\s*\(.*$', '') } else { '-' }
                Ukuran    = $_.Length
                Tanggal   = $_.LastWriteTime.ToString('yyyy-MM-dd')
                TandaTgn  = (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status
                DiGood    = if ($known.ContainsKey($_.Name.ToLower())) { 'ya' } else { '-' }
            }
        }
    }

    if (-not $found) {
        Write-Log 'Tidak ada file versi lama yang mencurigakan.' 'OK'
    } else {
        $found | Sort-Object File | Format-Table -AutoSize
        Write-Log "Ditemukan $($found.Count) file. Yang bertanda 'DiGood = -' belum punya salinan bagus." 'WARN'
        Write-Log 'Kalau file tsb bermasalah, taruh salinan bagusnya di folder good lalu tambahkan ke manifest.csv.' 'WARN'
    }
    exit 0
}

# ---------------------------------------------------------------------
#  Mode: Restore
# ---------------------------------------------------------------------
if ($Mode -eq 'Restore') {
    $backups = Get-ChildItem $BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if (-not $backups) {
        Write-Log "Tidak ada backup di $BackupRoot" 'ERROR'
        exit 1
    }

    $pick = $backups[0]
    Write-Header "RESTORE DARI BACKUP: $($pick.Name)"

    $files = Get-ChildItem $pick.FullName -Recurse -File
    if (-not $files) {
        Write-Log 'Folder backup kosong.' 'ERROR'
        exit 1
    }

    $refSddl = Get-ReferenceSddl -Root $WindowsRoot
    $n = 0
    foreach ($f in $files) {
        # struktur backup: <stamp>\SysWOW64\namafile
        $rel = $f.FullName.Substring($pick.FullName.Length).TrimStart('\')
        $target = Join-Path $WindowsRoot $rel
        try {
            $sddl = if (Test-Path -LiteralPath $target) { (Get-Acl -LiteralPath $target).Sddl } else { $refSddl }
            if (Test-Path -LiteralPath $target) { Unlock-File $target }
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force -ErrorAction Stop
            Set-SystemAcl -Path $target -Sddl $sddl
            Write-Log "restore: $rel" 'OK'
            $n++
        } catch {
            Write-Log "gagal restore $rel : $($_.Exception.Message)" 'ERROR'
        }
    }
    Write-Log "Selesai. $n file dikembalikan. Restart Windows bila perlu." 'WARN'
    exit 0
}
