#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/.." && pwd)
dest="$root/toolchains/llvm/1/hosts/linux-x86_64/bin"

if [ "$#" -gt 1 ]; then
    echo "Usage: setup_tools.sh [path-to-llvm-tools-dir]" >&2
    exit 1
fi

find_llvm_dir() {
    if [ "$#" -eq 1 ]; then
        printf '%s\n' "$1"
        return
    fi
    for candidate in /usr/lib/llvm-*/bin /opt/llvm/bin; do
        if [ -x "$candidate/mlir-translate" ] && [ -x "$candidate/clang" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done
    return 1
}

llvm_dir=$(find_llvm_dir "$@") || {
    echo "[ERROR] No complete LLVM/MLIR installation was discovered." >&2
    echo "        Install clang, lld, and mlir tools, or pass their bin directory." >&2
    exit 1
}

for tool in clang lld-link ld.lld mlir-translate; do
    if [ ! -x "$llvm_dir/$tool" ]; then
        echo "[ERROR] $tool not found or not executable in $llvm_dir" >&2
        exit 1
    fi
done

mkdir -p "$dest"
echo "Linking LLVM host toolchain from $llvm_dir..."
for tool in clang lld-link ld.lld mlir-translate; do
    # Linux LLVM tools commonly depend on libraries beside their original
    # installation (for example libMLIR.so). Copying only the executable loses
    # that runtime relationship, so a thin SDK links to the native installation.
    ln -sfn "$llvm_dir/$tool" "$dest/$tool"
done

for tool in clang lld-link ld.lld mlir-translate; do
    if ! "$dest/$tool" --version >/dev/null 2>&1; then
        echo "[ERROR] Linked host tool failed its startup check: $tool" >&2
        exit 1
    fi
done

echo "[OK] Linked and verified llvm/1 for linux-x86_64"
