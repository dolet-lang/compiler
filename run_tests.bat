@echo off
setlocal enabledelayedexpansion

set "COMPILER=bin\doletc.exe"
set "TESTS_DIR=tests\features"
set "E2E_DIR=tests\e2e"
set "PASS=0"
set "FAIL=0"
set "ERRORS="

echo ==========================================
echo  Dolet Feature Test Runner
echo ==========================================
echo.

REM --- Feature Tests ---
for %%f in (
    test_01_data_types
    test_02_variables
    test_03_operators
    test_04_control_flow
    test_05_loops
    test_06_functions
    test_07_structs
    test_08_enums
    test_09_strings
    test_10_ffi
    test_11_memory
    test_11_mini
    test_11_tiny
    test_11_tiny2
    test_12_extend
    test_13_traits
    test_14_silicon
    test_15_inheritance
    test_16_import
    test_mini_struct
) do (
    echo [TEST] %%f
    if exist "%TESTS_DIR%\%%f.dlt" (
        %COMPILER% "%TESTS_DIR%\%%f.dlt" -o "%TESTS_DIR%\%%f.exe" 2>&1
        if errorlevel 1 (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f"
        ) else (
            echo   [PASS] Compiled OK
            set /a PASS+=1
            REM Try to run
            "%TESTS_DIR%\%%f.exe" 2>&1
            echo.
        )
    ) else (
        echo   [SKIP] File not found
    )
)

REM --- E2E Tests ---
for %%f in (
    test_hello
    test_memory
) do (
    echo [TEST] e2e/%%f
    if exist "%E2E_DIR%\%%f.dlt" (
        %COMPILER% "%E2E_DIR%\%%f.dlt" -o "%E2E_DIR%\%%f.exe" 2>&1
        if errorlevel 1 (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! e2e/%%f"
        ) else (
            echo   [PASS] Compiled OK
            set /a PASS+=1
            "%E2E_DIR%\%%f.exe" 2>&1
            echo.
        )
    ) else (
        echo   [SKIP] File not found
    )
)

echo.
echo ==========================================
echo  Results: %PASS% PASS / %FAIL% FAIL
echo ==========================================
if not "!ERRORS!"=="" (
    echo  Failed: !ERRORS!
)
