# Laporan Perbaikan — Error MSINET.OCX pada SBill Client

Tanggal: 28 Oktober 2026
Target: `C:\Program Files (x86)\Sombrero Net Bill Client\SBill Client.exe`

## Kesimpulan

Error 339 ("Component 'MSINET.OCX' ... not correctly registered") **bukan** karena
MSINET.OCX tidak cocok dengan Windows 11.

- Windows 11 **tidak** menyertakan MSINET.OCX.
- MSINET.OCX yang terpasang (`C:\Windows\SysWOW64\msinet.ocx`, 6.01.9782) adalah
  file asli Microsoft, signature valid, dan registrasi COM-nya benar.
- Penyebab sebenarnya: **DLL jaringan 32-bit Windows di SysWOW64 sudah diganti
  versi Windows XP**, dan versi XP itu gagal dijalankan di Windows 11.
  MSINET.OCX memakai WININET.dll, jadi ikut gagal saat dimuat.

| File | Sebelum (XP) | Sesudah (Windows 11) |
|---|---|---|
| wininet.dll | 6.00.2900.3698, 662.016 B, unsigned | 11.00.26100.7920, 2.240.680 B, signed |
| mswsock.dll | 5.1.2600.2180, 245.248 B, unsigned | 10.0.26100.7920, 332.704 B, signed |
| IPHLPAPI.DLL | 5.1.2600.2180, 94.720 B, unsigned | 10.0.26100.7920, 150.952 B, signed |
| olepro32.dll | 5.1.2600.2180, 83.456 B, unsigned | 10.0.26100.7920, 120.320 B, signed |
| activeds.dll | 5.1.2600.5512, 193.536 B, unsigned | 10.0.26100.7019, 227.840 B, signed |
| hhctrl.ocx | 5.2.3790.2847 (Server 2003) | 10.0.26100.7705, signed |
| activeds.tlb | 5.1.2600.0 (XP) | 10.0.26100.1, signed |

## Yang sudah dicoba

1. `sfc /scannow` → gagal, "corrupt files but unable to fix some of them"
   (CBS: `STATUS_SXS_COMPONENT_STORE_CORRUPT`).
2. `DISM /Online /Cleanup-Image /RestoreHealth` → gagal `0x800f0915`
   ("repair content could not be found"). Penyebab: WinSxS sudah dipangkas
   hanya 25 komponen (0,08 GB) — ciri Windows modifikasi/"lite".
3. Karena itu file sistem dipulihkan manual dari **image Windows 11 yang ada di
   ISO** `D:\ISO\Win11Pro_25H2.8037_oprekin.com.iso` (`sources\install.esd`),
   diekstrak per file dengan `wimlib-imagex` (bukan apply seluruh image).
   Semua file pengganti diverifikasi: **PE x86 + signature Authenticode valid
   (Microsoft Windows)**.

## Verifikasi

- 32-bit `LoadLibrary`: wininet.dll, mswsock.dll, IPHLPAPI.dll, olepro32.dll,
  activeds.dll, hhctrl.ocx, msinet.ocx → **semua OK** (sebelumnya 0x8007045A / 0x7E).
- 32-bit wininet `InternetOpenUrl("http://www.example.com/")` → **OK**, data terbaca.
- COM `InetCtls.Inet.1` → sekarang `0x80040112` (Class is not licensed),
  artinya DLL berhasil dimuat. Bukan lagi `0x8007045A`.
- `SBill Client.exe` **berjalan normal**: form "Sombrero Net Bill Premium" muncul,
  jendela internal `MSInetHiddenWnd` (milik kontrol Inet) aktif, tanpa error 339.

## Perubahan lain

- `C:\Windows\System32\msinet.ocx` (salinan 32-bit salah tempat, dibuat 28/10 19:08)
  dihapus. Registrasi tetap menunjuk ke `C:\Windows\SysWOW64\msinet.ocx`.
- Kepemilikan file dikembalikan ke `NT SERVICE\TrustedInstaller` dan ACL asli
  disamakan kembali (diverifikasi `sddlSame=True`).

## Backup

`C:\Users\Owner\rea-backup\xp-dlls-20261028-2121\`
- 5 DLL XP asli + `hhctrl.ocx.xp-original`, `activeds.tlb.xp-original`
- `msinet.ocx` (salinan System32 yang dihapus)
- `original-acls.json`, `apply-log.txt`, `apply-win11-dlls.ps1`

## Catatan / risiko yang masih ada

1. **WinSxS rusak/dipangkas** → SFC dan DISM tidak bisa memperbaiki apa pun.
   Windows Update besar (feature update) atau repair lanjutan bisa gagal.
   Solusi tuntas: repair install / install ulang dari ISO resmi Microsoft.
2. **Tidak ada antivirus** terpasang (`Defender` tidak ada, SecurityCenter2 kosong).
   Disarankan pasang AV dan scan penuh.
3. Sisa paket legacy VB6 (tidak dipakai aplikasi ini, tapi unsigned):
   `XPBUTTON.OCX`, `SombreroNetRemote.ocx`, `OLEMSG32.DLL`, `dx7vb.dll`,
   `DATABROWSE.OCX`, `dbgrid32.ocx`, `DirWalk.ocx`, `SYSTRAY.OCX`, dll.
   Tidak ditemukan indikasi malware (hosts bersih, tidak ada LSP hijack,
   tidak ada AppInit_DLLs).
4. Jika ISO yang dipakai bukan sumber resmi, pertimbangkan unduh ISO resmi
   Microsoft untuk keperluan repair di masa depan.
