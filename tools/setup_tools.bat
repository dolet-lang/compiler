@echo off
setlocal

REM Install the LLVM bundle runnable on this Windows x86_64 host.
REM Target SDKs remain independent under library\platform\<os>\targets.

if "%~1"=="" (
    echo Usage: setup_tools.bat ^<path-to-llvm-tools-dir^>
    echo Example: setup_tools.bat C:\llvm\bin
    exit /b 1
)

set "LLVM_DIR=%~f1"
set "ROOT=%~dp0.."
set "DEST=%ROOT%\toolchains\llvm\1\hosts\windows-x86_64\bin"

for %%T in (clang.exe lld-link.exe ld.lld.exe mlir-translate.exe) do (
    if not exist "%LLVM_DIR%\%%T" (
        echo [ERROR] %%T not found in "%LLVM_DIR%"
        exit /b 1
    )
)

if not exist "%DEST%" mkdir "%DEST%"

echo Installing LLVM host toolchain...
for %%T in (clang.exe lld-link.exe ld.lld.exe mlir-translate.exe) do (
    copy /Y "%LLVM_DIR%\%%T" "%DEST%\%%T" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to install %%T
        exit /b 1
    )
)

echo [OK] Installed llvm/1 for windows-x86_64
