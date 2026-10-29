$ErrorActionPreference = 'Stop'
$src = "$env:TEMP\win11-x86-dlls"
$bk  = "C:\Users\Owner\rea-backup\xp-dlls-20261028-2121"
$log = "$bk\apply-log.txt"
$names = @('wininet.dll','mswsock.dll','IPHLPAPI.DLL','olepro32.dll','activeds.dll')

function Log($m) {
  $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  $line | Tee-Object -FilePath $log -Append
}

Log "=== mulai penggantian DLL ==="
$acls = Get-Content "$bk\original-acls.json" -Raw | ConvertFrom-Json

foreach ($n in $names) {
  $dst = "$env:WINDIR\SysWOW64\$n"
  $s = Join-Path $src $n
  Log "--- $n"
  Log ("  src  : {0} ({1} bytes) ver={2}" -f $s, (Get-Item $s).Length, (Get-Item $s).VersionInfo.FileVersion)
  Log ("  dst  : {0} ({1} bytes) ver={2}" -f $dst, (Get-Item $dst).Length, (Get-Item $dst).VersionInfo.FileVersion)

  # 1. ambil alih kepemilikan & akses
  & takeown.exe /f $dst /a | Out-Null
  & icacls.exe $dst /grant "*S-1-5-32-544:(F)" | Out-Null

  # 2. ganti file
  Copy-Item -LiteralPath $s -Destination $dst -Force
  $newLen = (Get-Item $dst).Length
  Log ("  replaced -> {0} bytes ver={1}" -f $newLen, (Get-Item $dst).VersionInfo.FileVersion)

  # 3. pulihkan kepemilikan TrustedInstaller
  & icacls.exe $dst /setowner "NT SERVICE\TrustedInstaller" | Out-Null

  # 4. pulihkan DACL asli (hanya bagian akses)
  $orig = New-Object System.Security.AccessControl.FileSecurity
  $orig.SetSecurityDescriptorSddlForm($acls.$n.Sddl)
  $daclSddl = $orig.GetSecurityDescriptorSddlForm([System.Security.AccessControl.AccessControlSections]::Access)
  $final = New-Object System.Security.AccessControl.FileSecurity
  $final.SetSecurityDescriptorSddlForm($daclSddl)
  Set-Acl -LiteralPath $dst -AclObject $final

  $now = Get-Acl -LiteralPath $dst
  Log ("  owner now = {0}" -f $now.Owner)
  Log ("  sddl same = {0}" -f ($now.Sddl -eq $acls.$n.Sddl))
  Log ("  signature = {0}" -f (Get-AuthenticodeSignature $dst).Status)
}
Log "=== selesai ==="
