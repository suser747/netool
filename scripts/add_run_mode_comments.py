#!/usr/bin/env python3
"""为 tools 下子脚本注入统一的「运行方式」说明注释块（若尚未存在）。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
SKIP = {"common.sh", "load_common.sh", "version.sh"}

BLOCK = """
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh {tool}
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) {tool}
#   直接：bash {relpath} [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------
"""

# main.sh 路由名 -> 相对路径映射（用于注释中的直接运行路径）
ROUTE_HINT = {
    "system/system.sh": "system",
    "network/network.sh": "network",
    "docker/docker.sh": "docker",
}


def tool_route(rel: str) -> str:
    name = rel.replace("tools/", "").replace(".sh", "")
    parts = name.split("/")
    if len(parts) == 2:
        return parts[1] if parts[0] != "utility" else parts[1].replace("_", "")
    return name


def inject(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if "运行方式" in text and "curl -fsSL" in text and "本地：" in text:
        return False
    rel = str(path.relative_to(ROOT)).replace("\\", "/")
    route = tool_route(rel)
    block = BLOCK.format(tool=route, relpath=rel)
    marker = "trap on_error ERR"
    if marker not in text:
        return False
    text = text.replace(marker, marker + block, 1)
    path.write_text(text, encoding="utf-8")
    return True


def main() -> None:
    changed = []
    for path in sorted(TOOLS.rglob("*.sh")):
        if path.name in SKIP:
            continue
        if inject(path):
            changed.append(path.relative_to(ROOT))
    print(f"annotated {len(changed)} files")
    for p in changed:
        print(f"  {p}")


if __name__ == "__main__":
    main()
