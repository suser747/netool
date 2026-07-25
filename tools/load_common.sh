#!/usr/bin/env bash
# netool 公共库加载器（本地部署 + curl 远程模式通用）
[[ -n "${NETOOL_COMMON_SOURCED:-}" ]] && return 0 2>/dev/null || exit 0

if [[ -n "${NETOOL_COMMON_FILE:-}" && -f "$NETOOL_COMMON_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$NETOOL_COMMON_FILE"
  return 0 2>/dev/null || exit 0
fi

_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${_common_dir}/common.sh" ]]; then
  # shellcheck source=common.sh
  source "${_common_dir}/common.sh"
fi
