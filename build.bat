@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  Dolet Compiler — Bootstrap Build
echo ============================================
echo.

set "ROOT=%~dp0"
set "BIN=%ROOT%bin"
set "SRC=%ROOT%build\pipeline_build.dlt"

if not exist "%BIN%" mkdir "%BIN%"

echo [1/1] Python bootstrap -^> doletc.exe
python "%ROOT%bootstrap\doletc.py" "%SRC%" -o "%BIN%\doletc.exe" --platform windows
if %errorlevel% neq 0 (
    echo [FAILED] Build
    exit /b 1
)
echo.

echo ============================================
echo  BUILD COMPLETE
echo  bin\doletc.exe  — compiled via bootstrap
echo ============================================
