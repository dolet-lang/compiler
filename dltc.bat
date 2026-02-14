@echo off
setlocal enabledelayedexpansion

REM ============================================
REM Dolet Compiler Driver
REM Usage: dltc <input.dlt> [-o output.exe] [--keep-mlir] [--keep-llvm] [--no-runtime]
REM ============================================

set "SCRIPT_DIR=%~dp0"
set "TOOLS_DIR=%SCRIPT_DIR%tools"
set "COMPILER=%SCRIPT_DIR%bin\doletc.exe"
set "SYS_LIBS=%SCRIPT_DIR%stdlib\sys\windows"

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

set "EXTRA_FLAGS="
set "SRC="
set "OUT="
set "KEEP_MLIR=0"
set "KEEP_LLVM=0"

REM Parse arguments
:parse_args
if "%~1"=="" goto done_args
if "%~1"=="--no-runtime" (
    set "EXTRA_FLAGS=--no-runtime"
    shift
    goto parse_args
)
if "%~1"=="--keep-mlir" (
    set "KEEP_MLIR=1"
    shift
    goto parse_args
)
if "%~1"=="--keep-llvm" (
    set "KEEP_LLVM=1"
    shift
    goto parse_args
)
if "%~1"=="-o" (
    shift
    set "OUT=%~f1"
    shift
    goto parse_args
)
if "%SRC%"=="" (
    set "SRC=%~f1"
    set "BASE=%~dpn1"
    set "NAME=%~n1"
)
shift
goto parse_args
:done_args

if "%SRC%"=="" (
    echo [ERROR] No input file specified
    exit /b 1
)

if "%OUT%"=="" (
    set "OUT=%BASE%.exe"
)

REM Extract output base name (without extension) for intermediates
for %%i in ("%OUT%") do set "OUT_BASE=%%~dpni"

echo [1/4] Compiling %NAME%.dlt -^> MLIR ...
"%COMPILER%" %EXTRA_FLAGS% "%SRC%"
if errorlevel 1 (
    echo [ERROR] Codegen failed
    exit /b 1
)

echo [2/4] MLIR -^> LLVM IR ...
"%TOOLS_DIR%\mlir-translate.exe" --mlir-to-llvmir "%BASE%.mlir" -o "%BASE%.ll"
if errorlevel 1 (
    echo [ERROR] MLIR translation failed
    exit /b 1
)

echo [3/4] LLVM IR -^> Object ...
"%TOOLS_DIR%\clang.exe" -c "%BASE%.ll" -o "%BASE%.obj" 2>nul
if not exist "%BASE%.obj" (
    echo [ERROR] Compilation failed
    exit /b 1
)

echo [4/4] Linking -^> %OUT% ...
"%TOOLS_DIR%\lld-link.exe" "%BASE%.obj" -out:"%OUT%" -libpath:"%SYS_LIBS%" -defaultlib:kernel32 -subsystem:console -entry:main >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Linking failed
    exit /b 1
)

REM Cleanup intermediate files
del "%BASE%.obj" 2>nul

if "%KEEP_MLIR%"=="0" (
    del "%BASE%.mlir" 2>nul
)
if "%KEEP_LLVM%"=="0" (
    del "%BASE%.ll" 2>nul
)

echo [SUCCESS] %OUT%
