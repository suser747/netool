#!/usr/bin/env bash
# 本地验证脚本：语法检查 + 冒烟测试
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

echo "==> bash -n 语法检查"
while IFS= read -r -d '' f; do
  if ! bash -n "$f"; then
    echo "FAIL: $f"
    fail=1
  fi
done < <(find . -name '*.sh' -not -path './.git/*' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> shellcheck"
  if ! find . -name '*.sh' -not -path './.git/*' -print0 | \
    xargs -0 shellcheck -x -e SC1091,SC2034,SC2086,SC2155,SC2162; then
    fail=1
  fi
else
  echo "==> shellcheck 未安装，跳过"
fi

echo "==> 冒烟测试"
export NETOOL_SKIP_LICENSE=1
bash main.sh --version >/dev/null || fail=1
bash main.sh check >/dev/null || fail=1
bash main.sh mirror --version >/dev/null || fail=1
bash main.sh user list >/dev/null || fail=1

echo "==> 远程模式模拟"
bash scripts/test-remote.sh >/dev/null || fail=1

if (( fail == 0 )); then
  echo "全部通过"
else
  echo "存在失败项"
  exit 1
fi
