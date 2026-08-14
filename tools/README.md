# Dolet Host Toolchains

`tools/` contains setup and maintenance scripts only. Executables that run on
the compiler host live in the versioned `toolchains/` store:

```text
toolchains/<id>/<version>/
|-- toolchain.toml
`-- hosts/<host-id>/
    |-- host.toml
    `-- bin/
```

Target runtimes, ABI data, CRT objects, SDK libraries, and linker policy do
not belong here. They live under `library/platform/<os>/targets/<target>/`.

## Windows LLVM bundle

Install the current Windows host bundle from an existing LLVM/MLIR directory:

```batch
tools\setup_tools.bat C:\llvm\bin
```

Required source files:

- `clang.exe`
- `lld-link.exe`
- `ld.lld.exe`
- `mlir-translate.exe`

The script installs them under
`toolchains/llvm/1/hosts/windows-x86_64/bin/`. The checked-in manifests map
logical compiler roles to these host executables; platform manifests never
contain executable names or host paths.

## Linux LLVM bundle

The thin Linux SDK normally discovers one complete native LLVM/MLIR directory
automatically. Search order is the bundled host slot, `DOLET_TOOLCHAIN_PATH`,
`PATH`, then the standard roots declared in `hosts/linux-x86_64/host.toml`.
For a custom install you can launch directly with, for example:

```sh
DOLET_TOOLCHAIN_PATH=/custom/llvm/bin ./bin/doletc app.dlt -o app
```

The setup script is optional and pins the SDK to a chosen installation.

On an x86_64 Linux host, install the native Linux executables with:

```sh
./tools/setup_tools.sh
# or explicitly:
./tools/setup_tools.sh /opt/llvm/bin
```

With no argument, the script discovers versioned installations such as
`/usr/lib/llvm-20/bin`. It verifies every tool after linking it into
`toolchains/llvm/1/hosts/linux-x86_64/bin/`. Never copy
Windows executables into the Linux host pack: host packs describe the machine
running `doletc`, independently from the target selected by `--target`.
