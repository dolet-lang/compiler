@echo off
setlocal enabledelayedexpansion

echo ============================================
echo  Dolet Compiler — Full Bootstrap Build
echo ============================================
echo.

set "ROOT=%~dp0"
set "BIN=%ROOT%bin"
set "BUILD=%ROOT%build"
set "SRC=%BUILD%\pipeline_build.dlt"

if not exist "%BIN%" mkdir "%BIN%"

:: Step 0: Concatenate sources into pipeline_build.dlt
echo [0/3] Generating pipeline_build.dlt ...
python "%ROOT%scripts\generate_pipeline.py"
if %errorlevel% neq 0 (
    echo [FAILED] Pipeline generation
    exit /b 1
)
echo.

:: Step 1: doletc.exe -> doletc2.exe
echo [1/3] doletc.exe -^> bin\doletc2.exe
"%BIN%\doletc.exe" "%SRC%" -o "%BIN%\doletc2.exe"
if %errorlevel% neq 0 (
    echo [FAILED] Stage 1 compile
    exit /b 1
)
echo.

:: Step 2: doletc2.exe -> doletc3.exe
echo [2/3] doletc2.exe -^> bin\doletc3.exe
"%BIN%\doletc2.exe" "%SRC%" -o "%BIN%\doletc3.exe"
if %errorlevel% neq 0 (
    echo [FAILED] Stage 2 compile
    exit /b 1
)
echo.

:: A successful compile is not enough for a self-hosted compiler. Refuse to
:: promote unless the two self-compiled stages reached a byte-stable fixed point.
fc /b "%BIN%\doletc2.exe" "%BIN%\doletc3.exe" >nul
if %errorlevel% neq 0 (
    echo [FAILED] Bootstrap is not byte-stable: Stage 2 differs from Stage 3
    echo [FAILED] Refusing to promote a potentially miscompiled compiler
    exit /b 1
)
echo [OK] Stage 2 and Stage 3 are byte-identical
echo.

:: Step 3: Promote doletc3 as the new doletc
echo [3/3] Promoting doletc3.exe -^> doletc.exe
copy /Y "%BIN%\doletc3.exe" "%BIN%\doletc.exe" >nul
echo.

:: Verify
"%BIN%\doletc.exe" --version
echo.

:: Cleanup intermediates
del "%BIN%\doletc2.exe" 2>nul
del "%BIN%\doletc3.exe" 2>nul

echo ============================================
echo  BOOTSTRAP COMPLETE
echo  bin\doletc.exe — fully self-compiled
echo ============================================
