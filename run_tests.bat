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
    test_17_type_alias
    test_18_nullable
    test_19_collections
    test_20_foreach
    test_21_static
    test_22_access_modifiers
    test_23_fun_pointers
    test_24_variadic
    test_25_context_blocks
    test_26_async
    test_27_stack_alloc
    test_28_nested_access
    test_29_super_method
    test_30_reverse_loop
    test_31_advanced_match
    test_32_list_methods
    test_33_nested_collections
    test_mini_struct
    test_import_helper
    test_35_mut_imm
    test_36_selective_import
    test_37_selective_bracket
    test_38_annotations
    test_39_positional_args
    test_40_new_constructor
    test_41_single_line_if
    test_42_method_chain
) do (
    echo [TEST] %%f
    if exist "%TESTS_DIR%\%%f.dlt" (
        REM Delete old exe to prevent stale cache
        if exist "%TESTS_DIR%\%%f.exe" del /q "%TESTS_DIR%\%%f.exe"
        %COMPILER% "%TESTS_DIR%\%%f.dlt" -o "%TESTS_DIR%\%%f.exe" 2>&1
        if exist "%TESTS_DIR%\%%f.exe" (
            echo   [PASS] Compiled OK
            set /a PASS+=1
            REM Try to run
            "%TESTS_DIR%\%%f.exe" 2>&1
            echo.
            REM Cleanup exe after running
            del /q "%TESTS_DIR%\%%f.exe" 2>nul
        ) else (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f"
        )
        REM Cleanup intermediate files
        if exist "%TESTS_DIR%\%%f.mlir" del /q "%TESTS_DIR%\%%f.mlir" 2>nul
        if exist "%TESTS_DIR%\%%f.ll" del /q "%TESTS_DIR%\%%f.ll" 2>nul
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
        REM Delete old exe to prevent stale cache
        if exist "%E2E_DIR%\%%f.exe" del /q "%E2E_DIR%\%%f.exe"
        %COMPILER% "%E2E_DIR%\%%f.dlt" -o "%E2E_DIR%\%%f.exe" 2>&1
        if exist "%E2E_DIR%\%%f.exe" (
            echo   [PASS] Compiled OK
            set /a PASS+=1
            "%E2E_DIR%\%%f.exe" 2>&1
            echo.
            del /q "%E2E_DIR%\%%f.exe" 2>nul
        ) else (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! e2e/%%f"
        )
        if exist "%E2E_DIR%\%%f.mlir" del /q "%E2E_DIR%\%%f.mlir" 2>nul
        if exist "%E2E_DIR%\%%f.ll" del /q "%E2E_DIR%\%%f.ll" 2>nul
    ) else (
        echo   [SKIP] File not found
    )
)

REM --- Top-level standalone tests ---
for %%f in (
    panic_basic
    visibility_ok
    error_paths
    str_utils
    str_parse
    str_split
    str_literal_method
    str_parse_f64
) do (
    echo [TEST] %%f
    if exist "tests\%%f.dlt" (
        if exist "tests\%%f.exe" del /q "tests\%%f.exe"
        %COMPILER% "tests\%%f.dlt" -o "tests\%%f.exe" 2>&1
        if exist "tests\%%f.exe" (
            echo   [PASS] Compiled OK
            set /a PASS+=1
            "tests\%%f.exe" 2>&1
            echo.
            del /q "tests\%%f.exe" 2>nul
        ) else (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f"
        )
        if exist "tests\%%f.mlir" del /q "tests\%%f.mlir" 2>nul
        if exist "tests\%%f.ll" del /q "tests\%%f.ll" 2>nul
    ) else (
        echo   [SKIP] File not found
    )
)

REM --- Tests that MUST FAIL to compile (visibility violations, validator) ---
for %%f in (
    visibility_fail_field
    visibility_fail_method
    validate_bare_return
) do (
    echo [TEST-MUST-FAIL] %%f
    if exist "tests\%%f.dlt" (
        if exist "tests\%%f.exe" del /q "tests\%%f.exe"
        %COMPILER% "tests\%%f.dlt" -o "tests\%%f.exe" 2>nul
        if exist "tests\%%f.exe" (
            echo   [FAIL] Should have failed compile, but compiled OK
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f-should-fail"
            del /q "tests\%%f.exe" 2>nul
        ) else (
            echo   [PASS] Correctly failed compile
            set /a PASS+=1
        )
        if exist "tests\%%f.mlir" del /q "tests\%%f.mlir" 2>nul
        if exist "tests\%%f.ll" del /q "tests\%%f.ll" 2>nul
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
