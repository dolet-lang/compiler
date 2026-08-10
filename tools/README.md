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

On an x86_64 Linux host, install the native Linux executables with:

```sh
./tools/setup_tools.sh /opt/llvm/bin
```

They are copied to `toolchains/llvm/1/hosts/linux-x86_64/bin/`. Never copy
Windows executables into the Linux host pack: host packs describe the machine
running `doletc`, independently from the target selected by `--target`.
