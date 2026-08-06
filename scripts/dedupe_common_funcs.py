#!/usr/bin/env python3
"""Remove duplicate helpers that exist in tools/common.sh from subscripts."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"

# function_name -> must not remove if file contains this marker (custom impl)
SKIP_IF_CUSTOM = {
    "require_root": [],
}

REMOVE_FUNCS = (
    "require_root",
    "confirm_default_no",
    "confirm_default_yes",
    "on_error",
)

FUNC_BLOCK = re.compile(
    r"(?ms)^(?:#[^\n]*\n)*^({name})\(\)\s*\{{\n.*?\n\}}\n?",
    re.MULTILINE,
)


def strip_functions(text: str, names: tuple[str, ...]) -> str:
    for name in names:
        pat = re.compile(
            r"(?ms)^(?:#[^\n]*\n)*^" + re.escape(name) + r"\(\)\s*\{\n.*?\n\}\n?",
        )
        while True:
            m = pat.search(text)
            if not m:
                break
            text = text[: m.start()] + text[m.end() :]
    return text


def ensure_nav_hint(text: str) -> str:
    if "print_menu_nav_hint" in text:
        return text
    marker = "print_menu_nav_hint"
    # After menu option lists, before read_prompt in interactive-style loops
    pat = re.compile(
        r"(printf[^\n]*返回[^\n]*\n)(\s*if ! read_prompt)",
        re.MULTILINE,
    )
    if pat.search(text):
        return pat.sub(
            r"\1    print_menu_nav_hint\n\2",
            text,
            count=1,
        )
    pat2 = re.compile(
        r"(printf[^\n]*\n)(\s*if ! read_prompt \"输入)",
        re.MULTILINE,
    )
    if pat2.search(text):
        return pat2.sub(r"\1    print_menu_nav_hint\n\2", text, count=1)
    return text


def main() -> int:
    changed = 0
    for path in sorted(TOOLS.rglob("*.sh")):
        if path.name in ("common.sh", "load_common.sh", "version.sh"):
            continue
        original = path.read_text(encoding="utf-8")
        updated = strip_functions(original, REMOVE_FUNCS)
        updated = ensure_nav_hint(updated)
        # Remove duplicate trap on_error after removing on_error if trap follows empty line only once
        updated = re.sub(
            r"\n?trap on_error ERR\n(?=trap on_error ERR)",
            "\n",
            updated,
        )
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed += 1
            print(f"updated: {path.relative_to(ROOT)}")
    print(f"done, {changed} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
