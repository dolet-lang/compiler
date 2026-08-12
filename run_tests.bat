@echo off
setlocal enabledelayedexpansion

set "COMPILER=bin\doletc.exe"
set "TESTS_DIR=tests\features"
set "E2E_DIR=tests\e2e"
set "PASS=0"
set "FAIL=0"
set "ERRORS="
set "TEST_RUNNER=powershell -NoProfile -ExecutionPolicy Bypass -File tests\run_with_limits.ps1"

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
    test_43_pure_math_symbols
    test_44_process_large_output
) do (
    echo [TEST] %%f
    if exist "%TESTS_DIR%\%%f.dlt" (
        REM Delete old exe to prevent stale cache
        if exist "%TESTS_DIR%\%%f.exe" del /q "%TESTS_DIR%\%%f.exe"
        %COMPILER% "%TESTS_DIR%\%%f.dlt" -o "%TESTS_DIR%\%%f.exe" 2>&1
        if exist "%TESTS_DIR%\%%f.exe" (
            REM Run in an isolated process with hard time and memory limits.
            %TEST_RUNNER% -Executable "%TESTS_DIR%\%%f.exe"
            if errorlevel 1 (
                echo   [FAIL] Runtime failed or exceeded safety limits
                set /a FAIL+=1
                set "ERRORS=!ERRORS! %%f-runtime"
            ) else (
                echo   [PASS] Compiled and ran OK
                set /a PASS+=1
            )
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
            %TEST_RUNNER% -Executable "%E2E_DIR%\%%f.exe"
            if errorlevel 1 (
                echo   [FAIL] Runtime failed or exceeded safety limits
                set /a FAIL+=1
                set "ERRORS=!ERRORS! e2e/%%f-runtime"
            ) else (
                echo   [PASS] Compiled and ran OK
                set /a PASS+=1
            )
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
    hex_compare
    dir_list
    option_basic
    result_basic
    try_op
    if_else_nested
    match_option
    poly_ctor
    generic_box
    generic_methods
    generic_bounds_ok
    nested_struct_method
    qualified_ctors
    generic_t_body
    generic_function
    closures_basic
    closures_local
    closures_advanced
    closures_escape
    closures_all_forms
    closures_zero_arg
    closures_mut_capture
    closures_compose
    closures_self_workaround
    closures_self_capture
    closures_locals_in_body
    closure_in_loop
    thread_basic
    thread_parallel_sum
    cpu_count_basic
    atomic_counter
    atomic_cas
    parallel_deque_basic
    parallel_init_idempotence
    parallel_shutdown_idempotence
    parallel_exactly_once
    parallel_eq_serial
    parallel_exact_count
    parallel_empty_range
    parallel_explicit_workers
    parallel_no_deadlock
    spawn_task_basic
    spawn_task_exactly_once
    parallel_leak_free
    parallel_perf_smoke
    mutex_basic
    random_basic
    struct_nested_global
    nested_field_assign
    type_alias_methods
    nested_namespace
    trait_impl
    generic_stmt_call
    temp_receiver_chain
    gen_method
    gen_inst
    gen_t_static
    gen_inst_zero
    platform_contract
    package_path
    package_path_transitive
) do (
    echo [TEST] %%f
    set "SKIP_STRESS=0"
    if "%%f"=="parallel_leak_free" if /I not "!DOLET_RUN_STRESS!"=="1" set "SKIP_STRESS=1"
    if "!SKIP_STRESS!"=="1" (
        echo   [SKIP] Stress test disabled by default. Set DOLET_RUN_STRESS=1 to enable.
    ) else if "%%f"=="package_path_transitive" (
        set "TRANSITIVE_DIR=tests\package_path_transitive"
        set "TRANSITIVE_LIB=!TRANSITIVE_DIR!\packages\child\transitive_link_fixture.lib"
        if exist "!TRANSITIVE_LIB!" del /q "!TRANSITIVE_LIB!"
        toolchains\llvm\1\hosts\windows-x86_64\bin\lld-link.exe /lib /machine:x64 /def:"!TRANSITIVE_DIR!\packages\child\transitive_link_fixture.def" /out:"!TRANSITIVE_LIB!" 2>&1
        if errorlevel 1 (
            echo   [FAIL] Could not prepare transitive native-link fixture
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f-fixture"
        ) else (
            if exist "!TRANSITIVE_DIR!\package_path_transitive.exe" del /q "!TRANSITIVE_DIR!\package_path_transitive.exe"
            %COMPILER% "!TRANSITIVE_DIR!\main.dlt" -o "!TRANSITIVE_DIR!\package_path_transitive.exe" --package-path "!TRANSITIVE_DIR!\packages" 2>&1
            if exist "!TRANSITIVE_DIR!\package_path_transitive.exe" (
                %TEST_RUNNER% -Executable "!TRANSITIVE_DIR!\package_path_transitive.exe"
                if errorlevel 1 (
                    echo   [FAIL] Runtime failed or exceeded safety limits
                    set /a FAIL+=1
                    set "ERRORS=!ERRORS! %%f-runtime"
                ) else (
                    echo   [PASS] Transitive native package linked and ran OK
                    set /a PASS+=1
                )
                del /q "!TRANSITIVE_DIR!\package_path_transitive.exe" 2>nul
            ) else (
                echo   [FAIL] Transitive package compilation failed
                set /a FAIL+=1
                set "ERRORS=!ERRORS! %%f"
            )
        )
        if exist "!TRANSITIVE_LIB!" del /q "!TRANSITIVE_LIB!" 2>nul
    ) else if "%%f"=="package_path" (
        if exist "tests\package_path\package_path.exe" del /q "tests\package_path\package_path.exe"
        %COMPILER% "tests\package_path\main.dlt" -o "tests\package_path\package_path.exe" --package-path "tests\package_path\packages" 2>&1
        if exist "tests\package_path\package_path.exe" (
            %TEST_RUNNER% -Executable "tests\package_path\package_path.exe"
            if errorlevel 1 (
                echo   [FAIL] Runtime failed or exceeded safety limits
                set /a FAIL+=1
                set "ERRORS=!ERRORS! %%f-runtime"
            ) else (
                echo   [PASS] Compiled and ran OK
                set /a PASS+=1
            )
            echo.
            del /q "tests\package_path\package_path.exe" 2>nul
        ) else (
            echo   [FAIL] Compilation failed
            set /a FAIL+=1
            set "ERRORS=!ERRORS! %%f"
        )
        if exist "tests\package_path\main.mlir" del /q "tests\package_path\main.mlir" 2>nul
        if exist "tests\package_path\main.ll" del /q "tests\package_path\main.ll" 2>nul
    ) else if exist "tests\%%f.dlt" (
        if exist "tests\%%f.exe" del /q "tests\%%f.exe"
        %COMPILER% "tests\%%f.dlt" -o "tests\%%f.exe" 2>&1
        if exist "tests\%%f.exe" (
            %TEST_RUNNER% -Executable "tests\%%f.exe"
            if errorlevel 1 (
                echo   [FAIL] Runtime failed or exceeded safety limits
                set /a FAIL+=1
                set "ERRORS=!ERRORS! %%f-runtime"
            ) else (
                echo   [PASS] Compiled and ran OK
                set /a PASS+=1
            )
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
    validate_typo_method
    generic_bounds_fail
    closures_escape_fail
    trait_impl_fail
    errors\missing_import
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
if %FAIL% gtr 0 exit /b 1
exit /b 0
