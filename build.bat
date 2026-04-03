@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  Dolet Compiler — Full Bootstrap Build
echo ============================================
echo.

set "ROOT=%~dp0"
set "BIN=%ROOT%bin"
set "SRC=%ROOT%build\pipeline_build.dlt"

if not exist "%BIN%" mkdir "%BIN%"

echo [1/3] Python bootstrap -^> init.exe
python "%ROOT%bootstrap\doletc.py" "%SRC%" -o "%BIN%\init.exe"
if %errorlevel% neq 0 (
    echo [FAILED] Stage 1
    exit /b 1
)
echo.

echo [2/3] init.exe -^> compiler.exe  (self-hosting)
"%BIN%\init.exe" "%SRC%" -o "%BIN%\compiler.exe"
if %errorlevel% neq 0 (
    echo [FAILED] Stage 2
    exit /b 1
)
echo.

echo [3/3] compiler.exe -^> doletc.exe  (self-hosting x2)
"%BIN%\compiler.exe" "%SRC%" -o "%BIN%\doletc.exe"
if %errorlevel% neq 0 (
    echo [FAILED] Stage 3
    exit /b 1
)
echo.

echo ============================================
echo  BUILD COMPLETE
echo  bin\init.exe      — stage 1 (bootstrap)
echo  bin\compiler.exe  — stage 2 (self-compiled)
echo  bin\doletc.exe    — stage 3 (final)
echo ============================================
