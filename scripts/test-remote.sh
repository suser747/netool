#!/usr/bin/env bash
# 模拟 curl|bash 远程模式：仅保留 main.sh，无本地 tools/ 目录
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/netool-remote-test.XXXXXX")"
export NETOOL_SKIP_LICENSE=1

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

cp "${ROOT}/main.sh" "${WORKDIR}/main.sh"
cp "${ROOT}/VERSION" "${WORKDIR}/VERSION"
mkdir -p "${WORKDIR}/tools"
cp "${ROOT}/tools/common.sh" "${WORKDIR}/tools/common.sh"
cp "${ROOT}/tools/load_common.sh" "${WORKDIR}/tools/load_common.sh"
cp "${ROOT}/tools/version.sh" "${WORKDIR}/tools/version.sh"
cp "${ROOT}/tools/versions.env" "${WORKDIR}/tools/versions.env"
cd "$WORKDIR"

echo "==> 远程模式模拟目录: ${WORKDIR}"
echo "    （保留 main.sh + common.sh，子工具从 Gitee 在线下载）"
echo "==> 测试 status / versions（内置）"
bash main.sh status >/dev/null || { echo "FAIL: status"; exit 1; }
bash main.sh versions >/dev/null || { echo "FAIL: versions"; exit 1; }

echo "==> 测试 check（内置，无需下载子脚本）"
bash main.sh check >/dev/null || { echo "FAIL: check"; exit 1; }

echo "==> 测试 mirror --version（需下载子脚本 + common.sh）"
ver="$(bash main.sh mirror --version 2>/dev/null | tail -1)"
[[ -n "$ver" ]] || { echo "FAIL: mirror --version 无输出"; exit 1; }
echo "    mirror 版本: ${ver}"

echo "==> 测试 network ip（远程下载 network.sh）"
bash main.sh network ip >/dev/null || { echo "FAIL: network ip"; exit 1; }

echo "==> 测试 user list"
bash main.sh user list >/dev/null || { echo "FAIL: user list"; exit 1; }

echo "==> 全部远程模式测试通过"
