@echo off
setlocal enabledelayedexpansion

REM ============================================
REM Run all Dolet feature tests with self-hosted compiler
REM ============================================

set "DLTC=%~dp0..\..\dltc.bat"
set "PASS=0"
set "FAIL=0"
set "TOTAL=0"
set "ERRORS="

echo =========================================
echo    Dolet Feature Tests (Self-Hosted)
echo =========================================
echo.

for %%f in (test_*.dlt) do (
    set /a TOTAL+=1
    echo --- Testing: %%~nf ---
    REM Delete old exe to prevent stale cache
    if exist "%%~nf.exe" del /q "%%~nf.exe"
    call "%DLTC%" "%%f" -o "%%~nf.exe" --keep-mlir 2>&1
    if exist "%%~nf.exe" (
        echo [COMPILED] Running...
        .\%%~nf.exe
        echo [PASS] %%~nf
        set /a PASS+=1
        REM Cleanup exe after running
        del /q "%%~nf.exe" 2>nul
    ) else (
        echo [FAIL] %%~nf - COMPILE ERROR
        set /a FAIL+=1
        set "ERRORS=!ERRORS! %%~nf"
    )
    REM Cleanup intermediate files
    if exist "%%~nf.mlir" del /q "%%~nf.mlir" 2>nul
    if exist "%%~nf.ll" del /q "%%~nf.ll" 2>nul
    echo.
)

echo =========================================
echo    Results: !PASS!/!TOTAL! passed, !FAIL! failed
echo =========================================
if not "!ERRORS!"=="" (
    echo    Failed: !ERRORS!
)

endlocal
