"""Verified, deterministic self-hosting pipeline for the Dolet compiler.

The checked-in compiler is a seed, not an independent language implementation.
It is trusted only when its SHA-256 matches bootstrap.seed.toml. The seed builds
the current compiler twice and promotion requires a byte-identical fixed point.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
from pathlib import Path
import shutil
import subprocess
import sys

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.8-3.10: parse the deliberately small schema below.
    tomllib = None


ROOT = Path(__file__).resolve().parent.parent
LOCK_PATH = ROOT / "bootstrap.seed.toml"
PIPELINE_PATH = ROOT / "build" / "pipeline_build.dlt"
VERSION_PATH = ROOT / "VERSION"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_lock_fallback(text: str) -> dict[str, object]:
    """Parse exactly the bootstrap seed-lock schema without a TOML dependency."""
    values: dict[str, object] = {}
    current: dict[str, object] = values
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            prefix = "seeds."
            if not section.startswith(prefix) or len(section) == len(prefix):
                raise RuntimeError(f"unsupported seed lock section: {line}")
            seeds = values.setdefault("seeds", {})
            if not isinstance(seeds, dict):
                raise RuntimeError("invalid seeds table in seed lock")
            name = section[len(prefix):]
            if name in seeds:
                raise RuntimeError(f"duplicate seed lock section: {section}")
            record: dict[str, object] = {}
            seeds[name] = record
            current = record
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise RuntimeError(f"invalid seed lock line: {raw_line}")
        key = key.strip()
        if not key or key in current:
            raise RuntimeError(f"invalid or duplicate seed lock key: {key}")
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            parsed: object = value[1:-1]
        else:
            try:
                parsed = int(value)
            except ValueError as error:
                raise RuntimeError(f"unsupported seed lock value: {value}") from error
        current[key] = parsed
    return values


def read_lock() -> dict[str, object]:
    text = LOCK_PATH.read_text(encoding="utf-8")
    if tomllib is not None:
        return tomllib.loads(text)
    return parse_lock_fallback(text)


def checked_source_version() -> str:
    version = VERSION_PATH.read_text(encoding="utf-8").strip()
    if not version:
        raise RuntimeError("compiler source version is missing from VERSION")
    return version


def host_id() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64"}:
        machine = "x86_64"
    return f"{system}-{machine}"


def seed_record(lock: dict[str, object]) -> tuple[str, dict[str, object]]:
    if lock.get("schema") != 3:
        raise RuntimeError("unsupported bootstrap.seed.toml schema")
    selected_host = host_id()
    seeds = lock.get("seeds")
    if not isinstance(seeds, dict) or selected_host not in seeds:
        available = ", ".join(sorted(seeds)) if isinstance(seeds, dict) else "none"
        raise RuntimeError(
            f"no trusted seed for host {selected_host}; available seeds: {available}"
        )
    record = seeds[selected_host]
    if not isinstance(record, dict):
        raise RuntimeError(f"invalid seed record for host {selected_host}")
    return selected_host, record


def checked_seed(record: dict[str, object]) -> Path:
    seed = (ROOT / str(record.get("path", ""))).resolve()
    try:
        seed.relative_to(ROOT.resolve())
    except ValueError as error:
        raise RuntimeError("seed path escapes the compiler repository") from error
    if not seed.is_file():
        raise RuntimeError(f"seed compiler is missing: {seed}")
    actual = sha256(seed)
    expected = str(record.get("sha256", "")).lower()
    if actual != expected:
        raise RuntimeError(
            "seed compiler integrity failure\n"
            f"  expected: {expected}\n"
            f"  actual:   {actual}\n"
            "Restore the tracked seed and lock from source control before building."
        )
    expected_version = str(record.get("compiler_version", "")).strip()
    if not expected_version:
        raise RuntimeError("trusted seed compiler_version is missing")
    completed = subprocess.run(
        [str(seed), "--version"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    reported = (completed.stdout + completed.stderr).strip()
    if completed.returncode != 0 or not reported.endswith(expected_version):
        raise RuntimeError(
            "seed compiler version failure\n"
            f"  expected: {expected_version}\n"
            f"  reported: {reported or 'missing'}"
        )
    return seed


def run(command: list[str], label: str) -> None:
    print(f"[{label}] {' '.join(command)}", flush=True)
    completed = subprocess.run(command, cwd=ROOT, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}")


def update_lock(
    lock: dict[str, object], selected_host: str, promoted: Path, version: str
) -> None:
    seeds = lock["seeds"]
    assert isinstance(seeds, dict)
    selected = seeds[selected_host]
    assert isinstance(selected, dict)
    selected["sha256"] = sha256(promoted)
    lines = ["schema = 3", ""]
    for name in sorted(seeds):
        record = seeds[name]
        if not isinstance(record, dict):
            raise RuntimeError(f"invalid seed record for host {name}")
        lines.extend(
            [
                f"[seeds.{name}]",
                f"target = \"{record.get('target', '')}\"",
                f"path = \"{record.get('path', '')}\"",
                f"compiler_version = \"{version if name == selected_host else record.get('compiler_version', '')}\"",
                f"sha256 = \"{record.get('sha256', '')}\"",
                "",
            ]
        )
    content = "\n".join(lines)
    temporary = LOCK_PATH.with_suffix(".toml.tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as destination:
        destination.write(content)
    os.replace(temporary, LOCK_PATH)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-promote",
        action="store_true",
        help="verify the fixed point but leave the checked-in seed unchanged",
    )
    parser.add_argument(
        "--verify-seed",
        action="store_true",
        help="verify the selected host seed and exit without requiring a backend toolchain",
    )
    args = parser.parse_args()
    lock = read_lock()
    version = checked_source_version()
    selected_host, record = seed_record(lock)
    seed = checked_seed(record)
    if args.verify_seed:
        print(f"[seed] {selected_host}: {seed.relative_to(ROOT)} ({sha256(seed)})")
        return 0
    run([sys.executable, str(ROOT / "scripts" / "generate_pipeline.py")], "source")
    if not PIPELINE_PATH.is_file():
        raise RuntimeError(f"generated compiler source is missing: {PIPELINE_PATH}")

    extension = seed.suffix
    stage1 = ROOT / "bin" / f"doletc.stage1{extension}"
    stage2 = ROOT / "bin" / f"doletc.stage2{extension}"
    for stale in (stage1, stage2):
        stale.unlink(missing_ok=True)
    try:
        run([str(seed), str(PIPELINE_PATH), "-o", str(stage1)], "stage-1")
        run([str(stage1), str(PIPELINE_PATH), "-o", str(stage2)], "stage-2")
        stage1_hash = sha256(stage1)
        stage2_hash = sha256(stage2)
        if stage1_hash != stage2_hash:
            raise RuntimeError(
                "self-hosting fixed-point failure: stage 1 and stage 2 differ\n"
                f"  stage 1: {stage1_hash}\n"
                f"  stage 2: {stage2_hash}"
            )
        print(f"[fixed-point] byte-identical SHA-256 {stage2_hash}")
        if not args.no_promote:
            replacement = seed.with_name(seed.name + ".new")
            shutil.copy2(stage2, replacement)
            os.replace(replacement, seed)
            update_lock(lock, selected_host, seed, version)
            print(f"[promote] {seed.relative_to(ROOT)}")
            run([str(seed), "--version"], "verify")
    finally:
        stage1.unlink(missing_ok=True)
        stage2.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"bootstrap: {error}", file=sys.stderr)
        raise SystemExit(1)
