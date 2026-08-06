#!/usr/bin/env python3
"""Move load_common to script top and strip duplicate boilerplate."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
SKIP = {"common.sh", "load_common.sh"}

LOAD_BLOCK = (
    "\n# shellcheck source=../load_common.sh\n"
    'source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"\n'
    "trap on_error ERR\n"
)

INDENTED_LOAD = re.compile(
    r"\n  # shellcheck source=\.\./load_common\.sh\n"
    r'  source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./load_common\.sh"\n'
)

HAS_TOP_LOAD = re.compile(
    r'^source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./load_common\.sh"',
    re.M,
)

BOILER_BLOCK = re.compile(
    r"\n(?:#[^\n]*\n|# ={3,}[^\n]*\n)*COLOR_RED=\"\"[\s\S]*?"
    r"command_exists\(\)\s*\{[\s\S]*?\}\n",
)

SSH_COLOR_BLOCK = re.compile(
    r"\nif \[\[ -t 1 \]\]; then\n"
    r"  COLOR_RED=\$'\\033\[31m'[\s\S]*?"
    r"fi\n\n"
    r"if \[\[ -n \"\$\{AYU_TOOLBOX:-\}\" \]\]; then[\s\S]*?"
    r"fi\n\n"
    r"# shellcheck source=\.\./load_common\.sh\n"
    r'source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./load_common\.sh"\n',
)

MIRROR_COLOR_BLOCK = re.compile(
    r"\nif \[\[ -t 1 \]\]; then\n"
    r"  COLOR_RED=\$'\\033\[31m'[\s\S]*?"
    r"fi\n\n"
    r"if \[\[ -n \"\$\{AYU_TOOLBOX:-\}\" \]\]; then[\s\S]*?"
    r"fi\n\n"
    r"# shellcheck source=\.\./load_common\.sh\n"
    r'source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)/\.\./load_common\.sh"\n',
)

LOAD_ONLY = (
    "\n# shellcheck source=../load_common.sh\n"
    'source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"\n'
    "trap on_error ERR\n"
)

COMPAT_LAYER = re.compile(
    r"\n## 项目兼容层：标准日志函数[\s\S]*?trap on_error ERR\n",
)

LOG_OVERRIDE = re.compile(
    r"\n# -+[\s\S]*?\n# 函数: log_info[\s\S]*?"
    r"die\(\) \{ log_error \"\$\*\"; exit 1; \}\n",
)


def strip_boilerplate(text: str) -> str:
    prev = None
    while prev != text:
        prev = text
        text = BOILER_BLOCK.sub("\n", text)
        text = SSH_COLOR_BLOCK.sub(LOAD_ONLY, text)
        text = MIRROR_COLOR_BLOCK.sub(LOAD_ONLY, text)
        text = COMPAT_LAYER.sub("\n", text)
        text = LOG_OVERRIDE.sub("\n", text)
    return text


def insert_load_after_version(text: str) -> str:
    if HAS_TOP_LOAD.search(text):
        return text
    # After last SCRIPT_VERSION= line in header (before boilerplate)
    m = re.search(r'(SCRIPT_VERSION="[^"]+"\n)', text)
    if not m:
        raise ValueError("SCRIPT_VERSION not found")
    pos = m.end()
    # Keep script-specific globals until first boilerplate or function
    return text[:pos] + LOAD_BLOCK + text[pos:]


def migrate_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    text = original
    text = INDENTED_LOAD.sub("\n", text)
    text = strip_boilerplate(text)
    if not HAS_TOP_LOAD.search(text):
        text = insert_load_after_version(text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    changed = []
    for path in sorted(TOOLS.rglob("*.sh")):
        if path.name in SKIP:
            continue
        if migrate_file(path):
            changed.append(path.relative_to(ROOT))
    print(f"Updated {len(changed)} files:")
    for p in changed:
        print(f"  {p}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
