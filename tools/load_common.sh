#!/usr/bin/env bash
# =============================================================================
# netool 公共库加载器 (tools/load_common.sh)
# =============================================================================
# 职责：统一子脚本加载 common.sh 的入口，兼容两种运行模式：
#   1. 本地部署 — 同目录 ../common.sh 存在，直接 source
#   2. curl 远程 — main.sh 设置 NETOOL_COMMON_FILE 指向已下载的 common.sh
# 用法（子脚本头部）：
#   source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
#   trap on_error ERR
# =============================================================================

# 已被 common.sh source 过时直接返回，避免重复初始化
[[ -n "${NETOOL_COMMON_SOURCED:-}" ]] && return 0 2>/dev/null || exit 0

# 远程模式：main.sh 预先下载 common 到临时目录并导出路径
if [[ -n "${NETOOL_COMMON_FILE:-}" && -f "$NETOOL_COMMON_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NETOOL_COMMON_FILE"
  return 0 2>/dev/null || exit 0
fi

# 本地模式：load_common.sh 与 common.sh 同在 tools/ 目录
_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_common_dir}/common.sh" ]]; then
  # shellcheck source=common.sh
  source "${_common_dir}/common.sh"
fi
