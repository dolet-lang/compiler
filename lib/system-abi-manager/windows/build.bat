@echo off
REM Build Windows Runtime Library for Dolet

echo Building Dolet Windows Runtime...

REM Compile runtime.c to object file
clang -c runtime.c -o runtime.obj -O2 -Wall

REM Create static library
llvm-ar rcs libdolet_windows.a runtime.obj

REM Cleanup
del runtime.obj

echo Done! Created libdolet_windows.a

REM Copy to tools/libs for backward compatibility
if not exist "..\..\..\libs" mkdir "..\..\..\libs"
copy /Y libdolet_windows.a ..\..\..\libs\libdsl.a

echo Copied to tools/libs/libdsl.a (for compatibility)
