#!/usr/bin/env python3
"""Enforce the package layering contract described in PACKAGE_ARCHITECTURE.md.

Every package declares `layer` in its `module.meta`.  The layer decides what the
package may depend on and whether it may reach the operating system:

    pure         Dolet only.  No extern lib, no native sources, no link flags,
                 and pure dependencies only.
    os           May call the OS and ship its own native sources.
    binding      Wraps a third-party native library.
    composition  Assembled from the layers below; no extern lib of its own.

A package may also declare `no-bindings = true`, promising that nothing in its
transitive dependency tree wraps a third-party native library.  `eqoi` carries
that promise so an Eqoi application builds with no prerequisite to install.

Exits non-zero on the first violation so the check can gate CI.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


LAYERS = ("pure", "os", "binding", "composition")

# Layers a package of each layer is allowed to depend on.
ALLOWED_DEPENDENCIES = {
    "pure": {"pure"},
    "os": {"pure", "os"},
    "binding": {"pure", "os", "binding"},
    "composition": {"pure", "os", "binding", "composition"},
}

# Manifest sections that declare native linking.  Forbidden for pure packages.
NATIVE_SECTIONS = ("libs", "dlls")

EXTERN_LIB = re.compile(r"^\s*extern\s+lib\b", re.MULTILINE)


class Package:
    def __init__(self, name: str, root: Path):
        self.name = name
        self.root = root
        self.layer: str | None = None
        self.version: str | None = None
        self.no_bindings = False
        self.dependencies: list[str] = []
        self.native_sections: list[str] = []
        self.link_flags: list[str] = []


def parse_manifest(name: str, root: Path, path: Path) -> Package:
    """Read the subset of module.meta the contract depends on.

    The format is INI-like but not INI: values may be bare (`fonts`) as well as
    `key = value`, and Windows paths in `[libs]` contain colons.  A hand parser
    keeps this tolerant of both spellings without rewriting every manifest.
    """
    package = Package(name, root)
    section = ""

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue

        key, _, value = line.partition("=")
        key = key.strip().lower()
        value = value.strip().strip('"')

        if section in ("info", "package"):
            if key == "layer":
                package.layer = value.lower()
            elif key == "version":
                package.version = value
            elif key == "no-bindings":
                package.no_bindings = value.lower() in ("true", "1", "yes")
        elif section == "dependencies":
            # Both `fonts = "*"` and a bare `fonts` are in use.
            dependency = key
            if dependency and dependency not in package.dependencies:
                package.dependencies.append(dependency)
        elif section in NATIVE_SECTIONS:
            if value:
                package.native_sections.append(f"[{section}] {key}")
        elif section.startswith("link."):
            if key in ("system_libs", "flags", "frameworks") and value:
                package.link_flags.append(f"[{section}] {key}")

    return package


def discover(packages_root: Path) -> dict[str, Package]:
    packages: dict[str, Package] = {}
    for child in sorted(packages_root.iterdir()):
        manifest = child / "module.meta"
        if child.is_dir() and manifest.is_file():
            packages[child.name] = parse_manifest(child.name, child, manifest)
    return packages


def sources(root: Path) -> list[Path]:
    return [
        path
        for path in root.rglob("*.dlt")
        if ".git" not in path.parts and "_quarantine" not in path.parts
    ]


def relative(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root)).replace("\\", "/")
    except ValueError:
        return str(path)


def check_package(package: Package, packages: dict[str, Package]) -> list[str]:
    errors: list[str] = []

    if package.layer is None:
        return [
            "no `layer` declared in [info]. "
            f"Add one of {', '.join(LAYERS)} - see PACKAGE_ARCHITECTURE.md"
        ]
    if package.layer not in LAYERS:
        return [f"unknown layer `{package.layer}`; expected one of {', '.join(LAYERS)}"]

    # Dependency layers.
    allowed = ALLOWED_DEPENDENCIES[package.layer]
    for name in package.dependencies:
        dependency = packages.get(name)
        if dependency is None:
            # Not checked out locally; the tree check below reports it too.
            continue
        if dependency.layer is None:
            continue
        if dependency.layer not in allowed:
            errors.append(
                f"`{package.layer}` package depends on `{name}` which is "
                f"`{dependency.layer}`; allowed: {', '.join(sorted(allowed))}"
            )

    # Native declarations.
    if package.layer == "pure":
        for entry in package.native_sections + package.link_flags:
            errors.append(f"`pure` package declares native linking: {entry}")
        native_dir = package.root / "native"
        if native_dir.is_dir():
            errors.append("`pure` package ships native sources under native/")

    # extern lib in sources.
    if package.layer in ("pure", "composition"):
        for source in sources(package.root):
            text = source.read_text(encoding="utf-8", errors="replace")
            if EXTERN_LIB.search(text):
                errors.append(
                    f"`{package.layer}` package declares `extern lib` in "
                    f"{relative(package.root, source)}; that belongs in an `os` package"
                )

    return errors


def check_no_bindings(package: Package, packages: dict[str, Package]) -> list[str]:
    """Walk the transitive tree and report any binding package reached."""
    errors: list[str] = []
    seen: set[str] = set()
    stack: list[tuple[str, list[str]]] = [(package.name, [package.name])]

    while stack:
        name, path = stack.pop()
        if name in seen:
            continue
        seen.add(name)

        current = packages.get(name)
        if current is None:
            if name != package.name:
                errors.append(
                    f"cannot verify `no-bindings`: dependency `{name}` is not "
                    f"checked out (via {' -> '.join(path)})"
                )
            continue

        if current.layer == "binding" and name != package.name:
            errors.append(
                f"`no-bindings` violated: {' -> '.join(path)} reaches binding `{name}`"
            )
            continue

        for dependency in current.dependencies:
            stack.append((dependency, path + [dependency]))

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--packages",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "packages",
        help="directory holding the package checkouts (default: ./packages)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="print violations only",
    )
    args = parser.parse_args()

    if not args.packages.is_dir():
        print(f"error: no package directory at {args.packages}", file=sys.stderr)
        return 2

    packages = discover(args.packages)
    if not packages:
        print(f"error: no packages found under {args.packages}", file=sys.stderr)
        return 2

    failures = 0
    for name in sorted(packages):
        package = packages[name]
        errors = check_package(package, packages)
        if package.no_bindings and not errors:
            errors += check_no_bindings(package, packages)

        if errors:
            failures += 1
            print(f"FAIL {name}")
            for error in errors:
                print(f"       {error}")
        elif not args.quiet:
            layer = package.layer or "?"
            guarantee = "  no-bindings" if package.no_bindings else ""
            print(f"ok   {name:<10} {layer:<12}{guarantee}")

    print()
    if failures:
        print(f"{failures} of {len(packages)} packages violate the layering contract.")
        print("See PACKAGE_ARCHITECTURE.md.")
        return 1

    print(f"All {len(packages)} packages satisfy the layering contract.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
