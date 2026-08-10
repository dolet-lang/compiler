"""Generate the deterministic single-file source used to self-host doletc.

This script only assembles source. It never invokes a compiler, which keeps it
safe for Obin's before-build hook and for every bootstrap stage.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "build" / "pipeline_build.dlt"

LEXER_FILES = ["lexer/tokenizer.dlt"]
PARSER_FILES = [
    "parser/ast_nodes.dlt",
    "parser/parser_core.dlt",
    "parser/parser_expr.dlt",
    "parser/parser_stmt.dlt",
    "parser/parser_decl.dlt",
    "parser/parser_main.dlt",
]
CODEGEN_FILES = [
    "codegen/codegen_core.dlt",
    "codegen/codegen_types.dlt",
    "codegen/codegen_expr.dlt",
    "codegen/codegen_stmt.dlt",
    "codegen/codegen_decl.dlt",
    "codegen/codegen_access.dlt",
    "codegen/codegen_treeshake.dlt",
    "codegen/codegen_mono.dlt",
    "codegen/codegen_main.dlt",
]
DRIVER_FILES = ["driver/pipeline_init.dlt", "driver/doletc_driver.dlt"]


def read_source(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"[ERROR] Compiler source not found: {path}")
    lines = path.read_text(encoding="utf-8").split("\n")
    return "\n".join(line for line in lines if not line.strip().startswith("import "))


def clean_parser_duplicates(source: str) -> str:
    """Remove declarations intentionally duplicated for directory isolation."""

    token_constant = re.compile(r"^TK_\w+\s*:\s*i32\s*=\s*\d+")
    duplicate_function = re.compile(r"^fun (str_eq|str_from_range|char_at|panic)\b")
    cleaned: list[str] = []
    skipping_function = False

    for line in source.split("\n"):
        stripped = line.strip()
        if token_constant.match(stripped):
            continue
        if duplicate_function.match(stripped):
            skipping_function = True
            continue
        if skipping_function:
            begins_top_level = bool(stripped) and not line.startswith((" ", "\t"))
            if not stripped or begins_top_level:
                skipping_function = False
                if not duplicate_function.match(stripped):
                    cleaned.append(line)
            continue
        cleaned.append(line)
    return "\n".join(cleaned)


def render() -> str:
    tokenizer = read_source(LEXER_FILES[0])
    parser = clean_parser_duplicates("\n".join(read_source(path) for path in PARSER_FILES))
    codegen = "\n".join(read_source(path) for path in CODEGEN_FILES)
    driver = "\n".join(read_source(path) for path in DRIVER_FILES)
    return (
        "# ===== Tokenizer =====\n"
        + tokenizer
        + "\n# ===== Parser =====\n"
        + parser
        + "\n# ===== Codegen =====\n"
        + codegen
        + "\n# ===== Driver =====\n"
        + driver
    )


def main() -> None:
    generated = render()
    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.is_file() else None
    if current == generated:
        print(f"[OK] {OUTPUT.relative_to(ROOT)} is up to date")
        return
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"[OK] generated {OUTPUT.relative_to(ROOT)} ({generated.count(chr(10)) + 1} lines)")


if __name__ == "__main__":
    main()
