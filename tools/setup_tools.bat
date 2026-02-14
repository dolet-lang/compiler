@echo off
REM Setup LLVM tools for Dolet compiler
REM Copies required tools from an existing installation

set "SCRIPT_DIR=%~dp0"

if "%~1"=="" (
    echo Usage: setup_tools.bat ^<path-to-llvm-tools-dir^>
    echo Example: setup_tools.bat C:\llvm\bin
    echo.
    echo Required tools: clang.exe, lld-link.exe, mlir-translate.exe
    exit /b 1
)

set "LLVM_DIR=%~1"

if not exist "%LLVM_DIR%\clang.exe" (
    echo [ERROR] clang.exe not found in %LLVM_DIR%
    exit /b 1
)

echo Copying LLVM tools...
copy "%LLVM_DIR%\clang.exe" "%SCRIPT_DIR%" >nul
copy "%LLVM_DIR%\lld-link.exe" "%SCRIPT_DIR%" >nul
copy "%LLVM_DIR%\mlir-translate.exe" "%SCRIPT_DIR%" >nul

echo [OK] Tools copied to %SCRIPT_DIR%
