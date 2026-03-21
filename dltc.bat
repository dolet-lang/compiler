@echo off
setlocal enabledelayedexpansion

REM ============================================
REM Dolet Compiler Driver
REM Usage: dltc <input.dlt> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
REM ============================================

set "SCRIPT_DIR=%~dp0"
set "COMPILER=%SCRIPT_DIR%bin\doletc.exe"

if "%~1"=="" (
    echo Dolet Compiler v0.3
    echo Usage: dltc ^<input.dlt^> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
    echo.
    echo Options:
    echo   -o ^<path^>       Output executable path ^(default: input name + .exe^)
    echo   --keep-mlir     Keep intermediate .mlir file
    echo   --keep-llvm     Keep intermediate .ll file
    echo   --no-runtime    Don't auto-import runtime libraries
    exit /b 1
)

if not exist "%COMPILER%" (
    echo [ERROR] Compiler not found: %COMPILER%
    echo Run build_release.bat to compile the compiler first.
    exit /b 1
)

REM Pass all arguments through to doletc.exe
"%COMPILER%" %*
exit /b %errorlevel%
