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
echo "Installing LLVM host toolchain..."
for tool in clang lld-link ld.lld mlir-translate; do
    cp "$llvm_dir/$tool" "$dest/$tool"
    chmod +x "$dest/$tool"
done

echo "[OK] Installed llvm/1 for linux-x86_64"
