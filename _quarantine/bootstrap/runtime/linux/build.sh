#!/bin/bash
# Build Linux Runtime Library for Dolet

echo "Building Dolet Linux Runtime..."

# Compile runtime.c to object file
clang -c runtime.c -o runtime.o -O2 -Wall -fPIC

# Create static library
ar rcs libdolet_linux.a runtime.o

# Cleanup
rm -f runtime.o

echo "Done! Created libdolet_linux.a"

# Copy to tools/libs for backward compatibility
mkdir -p ../../../libs
cp -f libdolet_linux.a ../../../libs/libdsl.a

echo "Copied to tools/libs/libdsl.a (for compatibility)"
