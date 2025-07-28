@echo off
echo =========================================
echo  Building countdown.exe (i18n enabled)
echo =========================================

REM Check if GCC is available
where gcc >nul 2>&1
if %errorlevel% neq 0 (
    echo Error: GCC not found. Please install MinGW-w64 or similar.
    echo You can download it from: https://www.mingw-w64.org/
    pause
    exit /b 1
)

echo Building countdown.exe with internationalization support...

REM Compile with i18n support
gcc -o countdown.exe countdown.c -lwinmm
if %errorlevel% neq 0 (
    echo Build failed!
    pause
    exit /b 1
)

echo Build successful!
echo.

echo Testing with default language (auto-detect):
countdown.exe 3
echo.

echo Testing with English:
countdown.exe --lang=en 3
echo.

echo Testing with Japanese:
countdown.exe --lang=ja 3
echo.

echo Available language options:
echo   --lang=en or --english    : English
echo   --lang=ja or --japanese   : Japanese
echo   -l en                     : English (short form)
echo   -l ja                     : Japanese (short form)
echo   (no option)               : Auto-detect from system

pause
