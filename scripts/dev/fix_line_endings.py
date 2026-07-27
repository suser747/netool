#!/usr/bin/env python3
"""Convert CRLF to LF in repository text files that must run on Linux."""
from __future__ import annotations

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Extensions that should always use LF (shell/scripts/config consumed on Linux)
LF_EXTENSIONS = {
    ".sh",
    ".py",
    ".yml",
    ".yaml",
    ".env",
}

SKIP_DIRS = {".git", "__pycache__", ".venv", "node_modules"}


def should_process(path: str) -> bool:
    _, ext = os.path.splitext(path)
    return ext.lower() in LF_EXTENSIONS


def convert_file(path: str) -> tuple[bool, int]:
    with open(path, "rb") as fh:
        data = fh.read()
    count = data.count(b"\r\n")
    if count == 0:
        return False, 0
    with open(path, "wb") as fh:
        fh.write(data.replace(b"\r\n", b"\n"))
    return True, count


def main() -> int:
    fix = "--fix" in sys.argv
    converted: list[tuple[str, int]] = []
    found: list[tuple[str, int]] = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            full = os.path.join(dirpath, name)
            if not should_process(full):
                continue
            rel = os.path.relpath(full, ROOT)
            with open(full, "rb") as fh:
                count = fh.read().count(b"\r\n")
            if count:
                found.append((rel, count))
                if fix:
                    convert_file(full)
                    converted.append((rel, count))

    if not found:
        print("No CRLF issues found.")
        return 0

    action = "Fixed" if fix else "Found"
    for rel, count in sorted(found):
        print(f"{action}: {rel} ({count} CRLF lines)")

    print(f"\nTotal: {len(found)} file(s)")
    if not fix:
        print("Run with --fix to convert CRLF -> LF")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
