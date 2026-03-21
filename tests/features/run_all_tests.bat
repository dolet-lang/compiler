@echo off
setlocal enabledelayedexpansion

REM ============================================
REM Run all Dolet feature tests with self-hosted compiler
REM ============================================

set "DLTC=%~dp0..\..\dltc.bat"
set "PASS=0"
set "FAIL=0"
set "TOTAL=0"

echo =========================================
echo    Dolet Feature Tests (Self-Hosted)
echo =========================================
echo.

for %%f in (test_*.dlt) do (
    set /a TOTAL+=1
    echo --- Testing: %%~nf ---
    call "%DLTC%" "%%f" -o "%%~nf.exe" --keep-mlir 2>&1
    if errorlevel 1 (
        echo [FAIL] %%~nf - COMPILE ERROR
        set /a FAIL+=1
    ) else (
        echo [COMPILED] Running...
        .\%%~nf.exe
        if errorlevel 1 (
            echo [FAIL] %%~nf - RUNTIME ERROR
            set /a FAIL+=1
        ) else (
            echo [PASS] %%~nf
            set /a PASS+=1
        )
    )
    echo.
)

echo =========================================
echo    Results: !PASS!/!TOTAL! passed, !FAIL! failed
echo =========================================

endlocal
