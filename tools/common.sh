#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 公共函数库
# =============================================================================

# 防止重复 source
[[ -n "${NETOOL_COMMON_SOURCED:-}" ]] && return 0
NETOOL_COMMON_SOURCED=1

# -----------------------------------------------------------------------------
# 路径与品牌常量
# -----------------------------------------------------------------------------
NETOOL_CONFIG_NAME="netool"
NETOOL_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME:-}/.config}/${NETOOL_CONFIG_NAME}"
NETOOL_LOG_DIR="/var/log/${NETOOL_CONFIG_NAME}"
NETOOL_REPO_URL="https://gitee.com/suser747/netool"
NETOOL_RAW_BRANCH="${NETOOL_RAW_BRANCH:-master}"
NETOOL_RAW_BASE="${NETOOL_REPO_URL}/raw/${NETOOL_RAW_BRANCH}"
NETOOL_ENTRY_URL="${NETOOL_RAW_BASE}/main.sh"

# 兼容旧版 ayu-toolbox 路径（读取许可、迁移配置）
NETOOL_LEGACY_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME:-}/.config}/ayu-toolbox"
NETOOL_LEGACY_LOG_DIR="/var/log/netool"

# 工具箱内部调用标记（兼容旧变量 AYU_TOOLBOX）
NETOOL="${NETOOL:-${AYU_TOOLBOX:-}}"
AYU_TOOLBOX="${AYU_TOOLBOX:-$NETOOL}"

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------
join_by() {
  local separator="$1"
  shift
  local first=1 item=""
  for item in "$@"; do
    if (( first )); then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$separator" "$item"
    fi
  done
}

metadata_value() {
  local metadata_file="$1" key="$2"
  [[ -f "$metadata_file" ]] || return 0
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$metadata_file"
}

tolower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

netool_acquire_lock() {
  local lock_name="$1"
  local error_msg="${2:-另一个实例正在运行，请等待其完成后再试。}"
  local lock_dir="${TMPDIR:-/tmp}"
  local lock_file="${lock_dir}/netool-${lock_name}.lock"

  if ! command -v flock >/dev/null 2>&1; then
    log_warn "未找到 flock，跳过并发锁（${lock_name}）。"
    return 0
  fi

  exec 9>"$lock_file"
  if ! flock -n 9; then
    log_error "$error_msg"
    return 1
  fi
  return 0
}

# 兼容旧函数名
ayu_acquire_lock() { netool_acquire_lock "$@"; }

netool_config_dir() {
  if [[ -d "$NETOOL_CONFIG_DIR" || ! -d "$NETOOL_LEGACY_CONFIG_DIR" ]]; then
    printf '%s' "$NETOOL_CONFIG_DIR"
  else
    printf '%s' "$NETOOL_LEGACY_CONFIG_DIR"
  fi
}

netool_license_file() {
  local version="${1:-1}"
  local primary="${NETOOL_CONFIG_DIR}/license-v${version}.accepted"
  local legacy="${NETOOL_LEGACY_CONFIG_DIR}/license-v${version}.accepted"
  if [[ -f "$primary" || ! -f "$legacy" ]]; then
    printf '%s' "$primary"
  else
    printf '%s' "$legacy"
  fi
}

# =============================================================================
# 颜色与日志
# =============================================================================
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_BOLD=""
COLOR_RESET=""

if [[ -t 1 && -z "${NETOOL:-}" && -z "${AYU_TOOLBOX:-}" ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
fi

QUIET="${QUIET:-0}"

log_info()    { (( QUIET == 1 )) || printf "%s%s[信息]%s %s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET" "$*"; }
log_success() { (( QUIET == 1 )) || printf "%s%s[完成]%s %s\n" "$COLOR_BOLD" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
log_warn()    { (( QUIET == 1 )) || printf "%s%s[警告]%s %s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
log_error()   { printf "%s%s[错误]%s %s\n" "$COLOR_BOLD" "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
die()         { log_error "$*"; exit 1; }

on_error() {
  local exit_code=$?
  if [[ -n "${NETOOL:-}" || -n "${AYU_TOOLBOX:-}" ]]; then
    log_error "执行失败，退出码：${exit_code}"
  else
    log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  fi
  exit "$exit_code"
}

read_prompt() {
  local prompt="$1" var_name="$2" value=""
  if [[ ! -t 0 && -t 1 && -r /dev/tty ]]; then
    if { printf "%s" "$prompt" >/dev/tty && IFS= read -r value </dev/tty; } 2>/dev/null; then
      printf -v "$var_name" "%s" "$value"
      return 0
    fi
  fi
  printf "%s" "$prompt"
  IFS= read -r value || [[ -n "$value" ]] || return 1
  printf -v "$var_name" "%s" "$value"
}

print_divider() { printf "%s%s%s\n" "$COLOR_CYAN" "------------------------------------------------------------" "$COLOR_RESET"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_root_user() {
  [[ ${EUID:-$(id -u 2>/dev/null || echo 1)} -eq 0 ]]
}

require_root() {
  is_root_user || die "此操作需要 root 权限，请使用 sudo 或切换到 root 用户"
}

timestamp() { date "+%Y%m%d_%H%M%S"; }

atomic_write() {
  local target="$1" source="$2" tmp
  tmp=$(mktemp)
  cat "$source" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

backup_with_timestamp() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts
  ts=$(timestamp)
  cp -a "$file" "${file}.bak.${ts}"
  printf '%s\n' "${file}.bak.${ts}"
}

audit_log() {
  local action="$1"
  shift || true
  local detail="$*"
  if ! is_root_user; then
    return 0
  fi
  local log_dir="$NETOOL_LOG_DIR"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  chmod 700 "$log_dir" 2>/dev/null || true
  local log_file="${log_dir}/audit.log"
  local ts user
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
  user="${USER:-$(whoami 2>/dev/null || echo unknown)}"
  printf "[%s] user=%s action=%s detail=%s\n" "$ts" "$user" "$action" "$detail" >>"$log_file" 2>/dev/null || true
  chmod 600 "$log_file" 2>/dev/null || true
}

confirm_default_no() {
  local prompt="${1:-确认继续?}" resp
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 1
  fi
  read -r -p "${prompt} (y/N) " resp
  [[ "$resp" =~ ^[Yy]$ ]]
}

confirm_default_yes() {
  local prompt="${1:-确认继续?}" resp
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} (Y/n) " resp
  [[ ! "$resp" =~ ^[Nn]$ ]]
}

confirm_phrase() {
  local prompt="$1" phrase="$2" input
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} (请输入: ${phrase}) " input
  [[ "$input" == "$phrase" ]] || die "确认短语不匹配，已取消"
}

validate_bash_script() {
  local script_file="$1"
  if ! bash -n "$script_file" 2>/dev/null; then
    log_error "脚本语法校验失败：${script_file}"
    return 1
  fi
  return 0
}

source_common() {
  # 供子脚本统一引用 common.sh
  local here="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  # shellcheck disable=SC1091
  source "$(cd "$(dirname "$here")/.." && pwd)/common.sh"
}
