@echo off
setlocal enabledelayedexpansion

REM ============================================
REM Dolet Release Builder
REM Assembles a distribution folder.
REM
REM Usage: build_release.bat [version]
REM   Example: build_release.bat 0.3
REM
REM Before running, make sure you have inside dolet-compiler/:
REM   bin/doletc.exe  - Compiled compiler
REM   tools/          - LLVM tools (clang, lld-link, mlir-translate)
REM   library/        - Standard library + importable libs
REM ============================================

set "SCRIPT_DIR=%~dp0"
set "VER=%~1"
if "%VER%"=="" set "VER=0.3"

set "DIST=%SCRIPT_DIR%dist\dolet-v%VER%-windows-x64"

echo [Dolet Release Builder v%VER%]
echo.

REM --- Verify doletc.exe ---
if not exist "%SCRIPT_DIR%bin\doletc.exe" (
    echo [ERROR] bin\doletc.exe not found!
    echo.
    echo   To compile doletc.exe, clone the bootstrap compiler and run:
    echo     git clone https://github.com/dolet-lang/dolet-bootstrap.git bootstrap
    echo     cd bootstrap
    echo     python build.py compile
    echo.
    exit /b 1
)

REM --- Verify tools/ ---
if not exist "%SCRIPT_DIR%tools\clang.exe" (
    echo [ERROR] tools/ not found!
    echo.
    echo   Clone the LLVM tools into dolet-compiler\tools\:
    echo     git clone https://github.com/dolet-lang/tools.git tools
    echo.
    exit /b 1
)

REM --- Verify library/ ---
if not exist "%SCRIPT_DIR%library\std" (
    echo [ERROR] library/ not found!
    echo.
    echo   Clone the Dolet library into dolet-compiler\library\:
    echo     git clone https://github.com/dolet-lang/library.git library
    echo.
    exit /b 1
)

REM --- Clean previous build ---
if exist "%DIST%" (
    echo Cleaning previous build...
    rmdir /s /q "%DIST%"
)

REM --- Create directory structure ---
mkdir "%DIST%\bin" 2>nul
mkdir "%DIST%\tools" 2>nul

REM --- 1. Copy compiler binary ---
echo [1/4] Copying doletc.exe ...
copy /Y "%SCRIPT_DIR%bin\doletc.exe" "%DIST%\bin\" >nul
echo   bin\doletc.exe [OK]

REM --- 2. Copy LLVM tools ---
echo [2/4] Copying LLVM tools ...
copy /Y "%SCRIPT_DIR%tools\clang.exe" "%DIST%\tools\" >nul
copy /Y "%SCRIPT_DIR%tools\lld-link.exe" "%DIST%\tools\" >nul
copy /Y "%SCRIPT_DIR%tools\mlir-translate.exe" "%DIST%\tools\" >nul
echo   tools\clang.exe [OK]
echo   tools\lld-link.exe [OK]
echo   tools\mlir-translate.exe [OK]

REM --- 3. Copy library ---
echo [3/4] Copying library ...
xcopy /Y /E /I /Q "%SCRIPT_DIR%library" "%DIST%\library" >nul
echo   library\ [OK]

REM --- 4. Copy packages (optional) ---
echo [4/4] Copying packages ...
if exist "%SCRIPT_DIR%packages" (
    xcopy /Y /E /I /Q "%SCRIPT_DIR%packages" "%DIST%\packages" >nul
    echo   packages\ [OK]
) else (
    echo   packages\ [SKIP]
)

REM --- Copy dltc.bat driver ---
copy /Y "%SCRIPT_DIR%dltc.bat" "%DIST%\" >nul 2>nul

echo.
echo ============================================
echo [SUCCESS] Release assembled at:
echo   %DIST%
echo.
echo Layout:
echo   bin\doletc.exe
echo   tools\ (clang, lld-link, mlir-translate)
echo   library\std\ (runtime + std + sys)
echo   library\importable\ (math, net, random)
echo ============================================
echo.

REM --- Create ZIP ---
echo Creating ZIP archive...
set "ZIP_PATH=%SCRIPT_DIR%dist\dolet-v%VER%-windows-x64.zip"
powershell -Command "Compress-Archive -Path '%DIST%' -DestinationPath '%ZIP_PATH%' -Force"
if errorlevel 1 (
    echo [WARN] ZIP creation failed, but release folder is ready.
) else (
    echo [OK] dist\dolet-v%VER%-windows-x64.zip
)

echo.
echo Done! Upload the ZIP to GitHub Releases.
exit /b 0
