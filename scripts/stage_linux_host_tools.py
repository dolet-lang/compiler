#!/usr/bin/env python3
"""Stage a relocatable Linux LLVM/MLIR host pack for the Dolet SDK.

The compiler executable can be cross-built, but the backend tools it launches
must run on the machine hosting doletc.  This script deliberately copies the
native Linux tools plus their non-glibc shared-library closure.  Tiny wrappers
set an SDK-relative LD_LIBRARY_PATH, so no path from the build machine leaks
into the resulting package.

On Windows the script reinvokes itself inside WSL.  The generated host pack is
then a normal project tree which Obin can stage into the Linux SDK.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


TOOLS = ("mlir-translate", "clang", "ld.lld", "lld-link")
GLIBC_OWNED = {
    "libc.so.6",
    "libm.so.6",
    "libpthread.so.0",
    "libdl.so.2",
    "librt.so.1",
    "libresolv.so.2",
    "libutil.so.1",
}


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, check=True, **kwargs)


def output(command: list[str]) -> str:
    return subprocess.check_output(command, text=True).strip()


def wsl_path(path: Path) -> str:
    return output(["wsl.exe", "wslpath", "-a", str(path.resolve())])


def reinvoke_in_wsl(root: Path, llvm_bin: str | None, distro: str | None) -> int:
    command = ["wsl.exe"]
    if distro:
        command.extend(("--distribution", distro))
    command.extend(
        (
        "--exec",
        "python3",
        wsl_path(Path(__file__)),
        "--native",
        "--root",
        wsl_path(root),
        )
    )
    if llvm_bin:
        command.extend(("--llvm-bin", llvm_bin))
    return subprocess.call(command)


def version_key(path: Path) -> tuple[int, ...]:
    match = re.search(r"llvm-(\d+(?:\.\d+)*)", str(path))
    if not match:
        return (0,)
    return tuple(int(piece) for piece in match.group(1).split("."))


def find_llvm_bin(explicit: str | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    configured = os.environ.get("DOLET_LINUX_LLVM_BIN")
    if configured:
        candidates.append(Path(configured))
    candidates.extend(sorted(Path("/usr/lib").glob("llvm-*/bin"), key=version_key, reverse=True))
    candidates.append(Path("/opt/llvm/bin"))

    for candidate in candidates:
        if all((candidate / tool).exists() for tool in TOOLS):
            return candidate.resolve()
    searched = "\n  ".join(str(path) for path in candidates)
    raise RuntimeError(
        "no complete native Linux LLVM/MLIR tool directory was found; searched:\n  " + searched
    )


def ldd_dependencies(path: Path) -> list[tuple[str, Path]]:
    result = run(["ldd", str(path)], capture_output=True)
    dependencies: list[tuple[str, Path]] = []
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or "not found" in line:
            if "not found" in line:
                raise RuntimeError(f"unresolved dependency for {path}: {line}")
            continue
        if "=>" in line:
            name, remainder = line.split("=>", 1)
            resolved = remainder.strip().split(" ", 1)[0]
            if resolved.startswith("/"):
                dependencies.append((name.strip(), Path(resolved).resolve()))
            continue
        resolved = line.split(" ", 1)[0]
        if resolved.startswith("/"):
            resolved_path = Path(resolved).resolve()
            dependencies.append((resolved_path.name, resolved_path))
    return dependencies


def is_glibc_owned(name: str) -> bool:
    return name in GLIBC_OWNED or name.startswith("ld-linux-")


def copy_executable(source: Path, destination: Path) -> None:
    shutil.copy2(source.resolve(), destination)
    destination.chmod(destination.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def wrapper_text(tool: str) -> str:
    return f'''#!/bin/sh
set -eu
host_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${{LD_LIBRARY_PATH:-}}" ]; then
    export LD_LIBRARY_PATH="$host_root/lib:$LD_LIBRARY_PATH"
else
    export LD_LIBRARY_PATH="$host_root/lib"
fi
exec "$host_root/libexec/{tool}" "$@"
'''


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def version_tuple(value: str) -> tuple[int, ...]:
    try:
        return tuple(int(piece) for piece in value.split("."))
    except ValueError as error:
        raise RuntimeError(f"invalid glibc version: {value}") from error


def required_glibc(files: list[Path]) -> str:
    required = (0, 0)
    pattern = re.compile(rb"GLIBC_(\d+(?:\.\d+)+)")
    for path in files:
        for match in pattern.findall(path.read_bytes()):
            candidate = version_tuple(match.decode("ascii"))
            if candidate > required:
                required = candidate
    return ".".join(str(piece) for piece in required)


def stage(root: Path, llvm_bin: Path) -> None:
    host_root = root / "toolchains" / "llvm" / "1" / "hosts" / "linux-x86_64"
    bin_dir = host_root / "bin"
    libexec_dir = host_root / "libexec"
    lib_dir = host_root / "lib"
    for directory in (bin_dir, libexec_dir, lib_dir):
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)

    native_sources: dict[str, Path] = {}
    for tool in TOOLS:
        source = (llvm_bin / tool).resolve()
        destination = libexec_dir / tool
        copy_executable(source, destination)
        native_sources[tool] = source

        wrapper = bin_dir / tool
        wrapper.write_text(wrapper_text(tool), encoding="utf-8", newline="\n")
        wrapper.chmod(0o755)

    # Follow the complete non-glibc dependency closure.  This includes LLVM,
    # MLIR, Clang, libstdc++, compression, XML and terminal dependencies while
    # retaining only the Linux glibc ABI as a host baseline.
    queue = list(dict.fromkeys(native_sources.values()))
    visited: set[Path] = set()
    copied: dict[str, Path] = {}
    while queue:
        current = queue.pop(0).resolve()
        if current in visited:
            continue
        visited.add(current)
        for name, dependency in ldd_dependencies(current):
            if is_glibc_owned(name):
                continue
            prior = copied.get(name)
            if prior is not None and prior != dependency:
                raise RuntimeError(f"dependency SONAME collision for {name}: {prior} vs {dependency}")
            if prior is None:
                destination = lib_dir / name
                shutil.copy2(dependency, destination)
                copied[name] = dependency
                queue.append(dependency)

    llvm_version = output([str(llvm_bin / "mlir-translate"), "--version"]).splitlines()[0]
    build_glibc = output(["getconf", "GNU_LIBC_VERSION"])
    if build_glibc.startswith("glibc "):
        build_glibc = build_glibc[len("glibc "):]
    packaged_files = sorted(
        [*bin_dir.iterdir(), *libexec_dir.iterdir(), *lib_dir.iterdir()], key=lambda item: str(item)
    )
    glibc_min = required_glibc(packaged_files)
    maximum_glibc = os.environ.get("DOLET_LINUX_MAX_GLIBC", "").strip()
    if maximum_glibc and version_tuple(glibc_min) > version_tuple(maximum_glibc):
        raise RuntimeError(
            f"host pack requires glibc {glibc_min}, exceeding release maximum {maximum_glibc}; "
            "stage from an older Linux build environment"
        )
    manifest_lines = [
        "schema = 1",
        'host = "linux-x86_64"',
        f'llvm = "{llvm_version.replace(chr(34), chr(39))}"',
        f'build_glibc = "{build_glibc}"',
        f'glibc_min = "{glibc_min}"',
        'layout = "sdk-relative-wrapper-v1"',
        "",
        "[sha256]",
    ]
    for packaged in packaged_files:
        relative = packaged.relative_to(host_root).as_posix()
        manifest_lines.append(f'"{relative}" = "{sha256(packaged)}"')
    (host_root / "bundle.toml").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8", newline="\n")

    clean_env = os.environ.copy()
    clean_env["PATH"] = "/usr/bin:/bin"
    clean_env.pop("LD_LIBRARY_PATH", None)
    for tool in TOOLS:
        run([str(bin_dir / tool), "--version"], env=clean_env, stdout=subprocess.DEVNULL)

    total = sum(path.stat().st_size for path in packaged_files)
    print(f"[OK] staged Linux host pack from {llvm_bin}")
    print(f"     {len(packaged_files)} files, {total / (1024 * 1024):.1f} MiB before compression")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--llvm-bin")
    parser.add_argument("--wsl-distro", default=os.environ.get("DOLET_LINUX_WSL_DISTRO"))
    parser.add_argument("--native", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = args.root.resolve()

    if os.name == "nt" and not args.native:
        return reinvoke_in_wsl(root, args.llvm_bin, args.wsl_distro)
    try:
        stage(root, find_llvm_bin(args.llvm_bin))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"[ERROR] unable to stage Linux host tools: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
