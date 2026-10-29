========================================================================
 TOOL PERBAIKI FILE SISTEM WINDOWS 11 (x86 / SysWOW64)
========================================================================

Dibuat: 28 Oktober 2026
Untuk : mengganti file sistem 32-bit yang hilang / rusak / tertimpa versi
        lama (misalnya setelah kena paket legacy VB6) dengan salinan bagus
        yang sudah diverifikasi.

Kenapa perlu: SFC dan DISM di Windows ini tidak bisa memperbaiki apa pun
(component store / WinSxS rusak, DISM error 0x800f0915). Tool ini bekerja
langsung di level file, tanpa SFC/DISM.


------------------------------------------------------------------------
 CARA PAKAI
------------------------------------------------------------------------
1. Klik dua kali:  PerbaikiFileSistem.bat
   (akan minta izin Administrator lewat UAC - klik Yes)

2. Pilih menu:
   1. Cek kondisi file        -> hanya melihat, TIDAK mengubah apa pun
   2. Perbaiki file hilang / rusak  -> menyalin file yang HILANG atau BEDA
   3. Paksa ganti semua file  -> ganti semua walau versi terpasang lebih baru
   4. Restore dari backup     -> kembalikan file ke kondisi sebelum diperbaiki
   5. Tampilkan daftar file   -> isi folder good
   6. Scan file versi lama    -> cari file XP/2003/7 dan yang tidak bertanda
                                 tangan di SysWOW64

3. Setelah memperbaiki, restart Windows kalau ada file yang sedang dipakai.


------------------------------------------------------------------------
 CARA KERJA (supaya aman)
------------------------------------------------------------------------
- Sebelum menyalin, file di folder good diverifikasi:
  * harus ada
  * SHA-256 harus sama dengan yang tercatat di manifest.csv
  * signature Authenticode harus "Valid" (milik Microsoft)
  Kalau tidak lolos, file DILEWATI (tidak dipakai).

- File sistem yang akan diganti dibandingkan dulu lewat SHA-256:
  * sama          -> status OK, tidak disentuh
  * beda          -> dibackup dulu, lalu diganti
  * tidak ada     -> disalin
  * versi terpasang LEBIH BARU -> dilewati (kecuali menu 3 / -Force)

- Setiap file yang diganti dibackup ke:
     backup\<tanggal-jam>\SysWOW64\<namafile>
  Menu 4 bisa mengembalikannya.

- Kepemilikan file dikembalikan ke NT SERVICE\TrustedInstaller dan ACL
  aslinya dipulihkan, sama seperti file sistem Windows pada umumnya.

- Semua tindakan dicatat di  logs\repair-<tanggal-jam>.log


------------------------------------------------------------------------
 ISI FOLDER GOOD (7 file, semuanya dari image Windows 11 25H2)
------------------------------------------------------------------------
  wininet.dll     11.00.26100.7920   2.240.680 B   (penyebab error MSINET.OCX)
  mswsock.dll     10.0.26100.7920     332.704 B
  IPHLPAPI.DLL    10.0.26100.7920     150.952 B
  olepro32.dll    10.0.26100.7920     120.320 B
  activeds.dll    10.0.26100.7019     227.840 B
  hhctrl.ocx      10.0.26100.7705     619.520 B
  activeds.tlb    10.0.26100.1        112.128 B


------------------------------------------------------------------------
 MENAMBAH FILE BARU KE DAFTAR
------------------------------------------------------------------------
Cukup copy file bagus (dari Windows 11 asli / image ISO) ke folder good\.
Tool akan otomatis memakainya walau tidak ada di manifest.csv, dengan
target C:\Windows\SysWOW64\<namafile>.

Syarat: file tersebut harus ber-signature valid. File unsigned akan
ditolak oleh tool ini (memang disengaja, supaya tidak memasang file
sembarangan ke folder sistem).

Kalau ingin target selain SysWOW64, atau ingin mencatat versi, edit
good\manifest.csv (kolom: Name,Target,Version,SHA256).


------------------------------------------------------------------------
 BATASAN
------------------------------------------------------------------------
- Tool ini memperbaiki FILE, bukan component store. SFC / DISM tetap
  gagal selama WinSxS rusak. Update besar Windows bisa tetap bermasalah.
  Solusi tuntas: repair install / install ulang dari ISO resmi Microsoft.
- Kalau file sedang dipakai proses lain, penggantian bisa gagal.
  Restart lalu jalankan lagi.
- Mode ScanLegacy bisa menampilkan file Windows 11 asli yang memang
  tidak bertanda tangan (contoh: win32calc.exe, poqexec.exe). Lihat
  kolom Versi - kalau versinya 10.0.26xxx biasanya file asli Windows 11.


------------------------------------------------------------------------
 STRUKTUR FOLDER
------------------------------------------------------------------------
  PerbaikiFileSistem.bat     <- dijalankan (klik 2x)
  Repair-SystemFiles.ps1     <- logika (dipanggil oleh .bat)
  good\                      <- file bagus + manifest.csv
  backup\                    <- backup otomatis sebelum penggantian
  logs\                      <- catatan setiap tindakan
  README.txt                 <- file ini

Folder ini bisa dipindah / dicopy ke tempat lain, misalnya ke flashdisk.
========================================================================
