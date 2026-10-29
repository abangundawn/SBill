@echo off
setlocal
title Perbaiki File Sistem Windows 11 (x86 / SysWOW64)
cd /d "%~dp0"

rem ============================================================
rem  Cek hak Administrator, kalau belum -> minta elevasi (UAC)
rem ============================================================
net session >nul 2>&1
if errorlevel 1 (
    echo Meminta hak Administrator...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs" >nul 2>&1
    exit /b
)

if not exist "%~dp0Repair-SystemFiles.ps1" (
    echo [ERROR] Repair-SystemFiles.ps1 tidak ditemukan di folder ini.
    pause
    exit /b 1
)

if not exist "%~dp0good\manifest.csv" (
    echo [ERROR] Folder good atau manifest.csv tidak ditemukan.
    echo         Taruh file bagus di folder "good" lalu jalankan lagi.
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo    PERBAIKI FILE SISTEM - Windows 11 x86 (SysWOW64)
echo ============================================================
echo    Folder tool : %~dp0
echo.
echo    File yang bisa diganti (isi folder good):
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "(Import-Csv '%~dp0good\manifest.csv' | ForEach-Object { $_.Name }) -join ', '"`) do echo      %%A
echo.
echo    1. Cek kondisi file         (tidak mengubah apa pun)
echo    2. Perbaiki file hilang / rusak
echo    3. Paksa ganti semua file dari folder good
echo    4. Restore dari backup terakhir
echo    5. Tampilkan daftar file bagus
echo    6. Scan file sistem versi lama / tidak bertanda tangan
echo    0. Keluar
echo.
set "pilihan="
set /p "pilihan=Pilih [0-6]: "

if "%pilihan%"=="1" goto scan
if "%pilihan%"=="2" goto repair
if "%pilihan%"=="3" goto force
if "%pilihan%"=="4" goto restore
if "%pilihan%"=="5" goto list
if "%pilihan%"=="6" goto legacy
if "%pilihan%"=="0" goto end
goto menu

:scan
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode Scan
echo.
pause
goto menu

:repair
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode Repair
echo.
pause
goto menu

:force
cls
echo PERINGATAN: semua file akan diganti walau versi terpasang lebih baru.
set "y="
set /p "y=Lanjutkan? [y/N]: "
if /i not "%y%"=="y" goto menu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode Repair -Force
echo.
pause
goto menu

:restore
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode Restore
echo.
pause
goto menu

:list
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode List
echo.
pause
goto menu

:legacy
cls
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-SystemFiles.ps1" -Mode ScanLegacy
echo.
pause
goto menu

:end
endlocal
exit /b 0
