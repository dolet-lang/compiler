#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: setup_tools.sh <path-to-llvm-tools-dir>" >&2
    echo "Example: setup_tools.sh /opt/llvm/bin" >&2
    exit 1
fi

llvm_dir=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/.." && pwd)
dest="$root/toolchains/llvm/1/hosts/linux-x86_64/bin"

for tool in clang lld-link ld.lld mlir-translate; do
    if [ ! -x "$llvm_dir/$tool" ]; then
        echo "[ERROR] $tool not found or not executable in $llvm_dir" >&2
        exit 1
    fi
done

mkdir -p "$dest"
echo "Linking LLVM host toolchain..."
for tool in clang lld-link ld.lld mlir-translate; do
    # Linux LLVM tools commonly depend on libraries beside their original
    # installation (for example libMLIR.so). Copying only the executable loses
    # that runtime relationship, so a thin SDK links to the native installation.
    ln -sfn "$llvm_dir/$tool" "$dest/$tool"
done

echo "[OK] Linked llvm/1 for linux-x86_64"
