#!/usr/bin/env bash
# =============================================================================
# netool 懒人工具箱 - 公共函数库 (tools/common.sh)
# =============================================================================
# 职责：
#   1. 定义品牌路径、远程 raw URL、配置目录等全局常量
#   2. 提供日志、颜色、交互输入、错误处理等统一 API
#   3. 提供并发锁、备份、审计、脚本校验等安全辅助函数
# 加载方式：
#   - main.sh 直接 source
#   - 子脚本通过 load_common.sh 间接 source
# 注意：使用 return 防止重复 source；子工具模式下 NETOOL=1 会简化错误输出
# =============================================================================

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

# 兼容旧版 ayu-toolbox 配置目录（读取许可、迁移时使用）
NETOOL_LEGACY_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME:-}/.config}/ayu-toolbox"
NETOOL_LEGACY_LOG_DIR="/var/log/netool"

# 主入口调用子工具时设置 NETOOL=1；legacy 变量 AYU_TOOLBOX 与之同步
NETOOL="${NETOOL:-${AYU_TOOLBOX:-}}"
AYU_TOOLBOX="${AYU_TOOLBOX:-$NETOOL}"

# -----------------------------------------------------------------------------
# 字符串与元数据工具
# -----------------------------------------------------------------------------

# join_by SEP ARG... — 用 SEP 连接多个字符串，用于拼接命令行等
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

# metadata_value FILE KEY — 从 key=value 元数据文件读取指定键
metadata_value() {
  local metadata_file="$1" key="$2"
  [[ -f "$metadata_file" ]] || return 0
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$metadata_file"
}

# tolower STR — Bash 3.2 兼容的小写转换（替代 ${var,,}）
tolower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# -----------------------------------------------------------------------------
# 并发控制
# -----------------------------------------------------------------------------

# netool_acquire_lock NAME [MSG] — 基于 flock 的进程锁，防止同工具并发执行
# 无 flock 时降级为警告并继续（不阻塞）
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

ayu_acquire_lock() { netool_acquire_lock "$@"; }

# -----------------------------------------------------------------------------
# 配置与许可路径
# -----------------------------------------------------------------------------

# netool_config_dir — 返回当前生效的用户配置目录（新路径优先，否则 legacy）
netool_config_dir() {
  if [[ -d "$NETOOL_CONFIG_DIR" || ! -d "$NETOOL_LEGACY_CONFIG_DIR" ]]; then
    printf '%s' "$NETOOL_CONFIG_DIR"
  else
    printf '%s' "$NETOOL_LEGACY_CONFIG_DIR"
  fi
}

# netool_license_file VERSION — 返回许可确认文件的完整路径
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
# 颜色与日志（QUIET=1 或 NETOOL 子工具模式下行为见各函数）
# =============================================================================
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_BOLD=""
COLOR_RESET=""

# 独立运行子脚本且 stdout 为终端时启用颜色；被 main.sh 调用时不重复着色
if [[ -t 1 && -z "${NETOOL:-}" ]]; then
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

# on_error — ERR trap 回调；NETOOL 模式下省略行号避免嵌套日志冗余
on_error() {
  local exit_code=$?
  if [[ -n "${NETOOL:-}" ]]; then
    log_error "执行失败，退出码：${exit_code}"
  else
    log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  fi
  exit "$exit_code"
}

# normalize_user_input STR — 去除 CR 与首尾空白，避免 Windows 终端或管道输入导致菜单编号不匹配
normalize_user_input() {
  local val="$1"
  val="${val//$'\r'/}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf '%s' "$val"
}

# read_prompt PROMPT VAR — 读用户输入；stdin 非 TTY 时自动转 /dev/tty
read_prompt() {
  local prompt="$1" var_name="$2" value=""
  if [[ ! -t 0 && -r /dev/tty ]]; then
    if { printf "%s" "$prompt" >/dev/tty && IFS= read -r value </dev/tty; } 2>/dev/null; then
      printf -v "$var_name" "%s" "$(normalize_user_input "$value")"
      return 0
    fi
  fi
  printf "%s" "$prompt"
  IFS= read -r value || [[ -n "$value" ]] || return 1
  printf -v "$var_name" "%s" "$(normalize_user_input "$value")"
}

print_divider() { printf "%s%s%s\n" "$COLOR_CYAN" "------------------------------------------------------------" "$COLOR_RESET"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_root_user() { [[ ${EUID:-$(id -u 2>/dev/null || echo 1)} -eq 0 ]]; }

require_root() { is_root_user || die "此操作需要 root 权限，请使用 sudo 或切换到 root 用户"; }

timestamp() { date "+%Y%m%d_%H%M%S"; }

# atomic_write TARGET SOURCE — 先写临时文件再 mv，避免半写状态
atomic_write() {
  local target="$1" source="$2" tmp
  tmp=$(mktemp)
  cat "$source" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

# backup_with_timestamp FILE — 带时间戳的副本备份，返回备份路径
backup_with_timestamp() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts
  ts=$(timestamp)
  cp -a "$file" "${file}.bak.${ts}"
  printf '%s\n' "${file}.bak.${ts}"
}

# audit_log ACTION DETAIL — root 下写入审计日志（不记录敏感内容）
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
  read_prompt "${prompt} (y/N) " resp || return 1
  [[ "$resp" =~ ^[Yy]$ ]]
}

confirm_default_yes() {
  local prompt="${1:-确认继续?}" resp
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read_prompt "${prompt} (Y/n) " resp || return 1
  [[ ! "$resp" =~ ^[Nn]$ ]]
}

confirm_phrase() {
  local prompt="$1" phrase="$2" input
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read_prompt "${prompt} (请输入: ${phrase}) " input || return 1
  [[ "$input" == "$phrase" ]] || die "确认短语不匹配，已取消"
}

# validate_bash_script FILE — 远程下载后执行前的 bash -n 语法校验
validate_bash_script() {
  local script_file="$1"
  if ! bash -n "$script_file" 2>/dev/null; then
    log_error "脚本语法校验失败：${script_file}"
    return 1
  fi
  return 0
}

source_common() {
  local here="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  # shellcheck disable=SC1091
  source "$(cd "$(dirname "$here")/.." && pwd)/common.sh"
}
