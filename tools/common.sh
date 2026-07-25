#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 公共函数库
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: common
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   本文件提供所有子脚本共用的基础函数和变量，是整个工具箱的统一规范基座。
#   子脚本通过 `source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"` 引入。
#   引入后即可使用本文件提供的颜色变量、日志函数、错误捕获、并发锁、
#   工具函数和确认函数，避免每个子脚本重复实现。
#
# 提供的能力:
#   - 颜色控制: COLOR_* 变量，自动检测 TTY 和 AYU_TOOLBOX 环境变量抑制
#   - 日志函数: log_info / log_success / log_warn / log_error / die
#   - 错误捕获: on_error（配合 `trap on_error ERR` 使用）
#   - 并发锁:   ayu_acquire_lock（基于 flock，防止多实例并发冲突）
#   - 输入工具: read_prompt（兼容管道与 TTY 两种输入模式）
#   - 工具函数: command_exists / require_root / is_root_user / timestamp
#               atomic_write / backup_with_timestamp / audit_log / print_divider
#   - 确认函数: confirm_default_no / confirm_default_yes / confirm_phrase
#               （支持 NON_INTERACTIVE 全局变量跳过交互）
# =============================================================================

# -----------------------------------------------------------------------------
# 函数: join_by
# 功能: 使用指定分隔符将多个字符串拼接成一个字符串
# 参数: $1 - 分隔符；$2.. - 待拼接的字符串列表
# 返回值: 通过 stdout 输出拼接结果
# -----------------------------------------------------------------------------
join_by() {
  local separator="$1"
  shift
  local first=1
  local item=""

  for item in "$@"; do
    if (( first )); then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$separator" "$item"
    fi
  done
}

# -----------------------------------------------------------------------------
# 函数: metadata_value
# 功能: 从 key=value 格式的元数据文件中读取指定 key 的值
# 参数: $1 - 元数据文件路径；$2 - 要读取的 key 名称
# 返回值: 文件不存在时返回 0；存在时通过 stdout 输出 value，未匹配则输出空
# -----------------------------------------------------------------------------
metadata_value() {
  local metadata_file="$1"
  local key="$2"

  [[ -f "$metadata_file" ]] || return 0
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$metadata_file"
}

# -----------------------------------------------------------------------------
# 函数: ayu_acquire_lock
# 功能: 获取进程级互斥锁，防止多个实例并发修改系统配置
# 参数: $1 - 锁名（用于构造锁文件名）；$2 - 可选的错误提示信息
# 返回值: 成功获取返回 0；已有实例运行或无 flock 命令时返回 1（无 flock 时返回 0）
# 说明:   锁文件位于 ${TMPDIR:-/tmp}/ayu-<锁名>.lock，flock 在脚本退出时自动释放
# -----------------------------------------------------------------------------
ayu_acquire_lock() {
  local lock_name="$1"
  local error_msg="${2:-另一个实例正在运行，请等待其完成后再试。}"
  local lock_dir="${TMPDIR:-/tmp}"
  local lock_file="${lock_dir}/ayu-${lock_name}.lock"

  # 无 flock 命令时跳过（如 Alpine 默认无 flock，busybox 提供）
  if ! command -v flock >/dev/null 2>&1; then
    return 0
  fi

  exec 9>"$lock_file"
  if ! flock -n 9; then
    printf '[错误] %s\n' "$error_msg" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# 颜色控制（仅 TTY 启用，AYU_TOOLBOX 抑制）
# 当 stdout 不是 TTY 或设置了 AYU_TOOLBOX 环境变量时，所有颜色变量置空，
# 避免在管道、日志文件或工具箱内部调用时输出 ANSI 转义序列。
# =============================================================================
if [[ -t 1 && -z "${AYU_TOOLBOX:-}" ]]; then
  COLOR_RED='\033[0;31m'
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[0;33m'
  COLOR_BLUE='\033[0;34m'
  COLOR_CYAN='\033[0;36m'
  COLOR_BOLD='\033[1m'
  COLOR_RESET='\033[0m'
else
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_CYAN=''
  COLOR_BOLD=''
  COLOR_RESET=''
fi

# =============================================================================
# 统一日志函数
# 所有日志函数使用 COLOR_* 变量输出带颜色标签的信息，便于统一风格。
# QUIET 全局变量为 1 时抑制信息/成功/警告输出，仅保留错误输出。
# =============================================================================
QUIET="${QUIET:-0}"

# 输出普通信息到标准输出
log_info()    { (( QUIET == 1 )) || echo -e "${COLOR_BOLD}${COLOR_CYAN}[信息]${COLOR_RESET} $*"; }

# 输出成功信息到标准输出
log_success() { (( QUIET == 1 )) || echo -e "${COLOR_BOLD}${COLOR_GREEN}[完成]${COLOR_RESET} $*"; }

# 输出警告信息到标准输出
log_warn()    { (( QUIET == 1 )) || echo -e "${COLOR_BOLD}${COLOR_YELLOW}[警告]${COLOR_RESET} $*"; }

# 输出错误信息到标准错误
log_error()   { echo -e "${COLOR_BOLD}${COLOR_RED}[错误]${COLOR_RESET} $*" >&2; }

# 输出错误信息并以退出码 1 终止脚本
die()         { log_error "$*"; exit 1; }

# =============================================================================
# 统一错误捕获
# =============================================================================

# 配合 `trap on_error ERR` 使用，捕获错误时输出失败行号与退出码
# 当通过 AYU_TOOLBOX 调用时输出简化信息，避免暴露内部行号
on_error() {
  local exit_code=$?
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then
    log_error "执行失败，退出码：${exit_code}"
  else
    log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  fi
  exit "$exit_code"
}

# =============================================================================
# 输入与显示工具函数
# =============================================================================

# -----------------------------------------------------------------------------
# 函数: read_prompt
# 功能: 兼容管道与 TTY 两种输入模式的读取函数
# 参数: $1 - 提示信息；$2 - 接收输入值的变量名
# 返回值: 读取成功返回 0；EOF 或读取失败返回 1
# 说明:   当 stdin 不是 TTY 但有可读的 /dev/tty 时（如 curl|bash 模式），
#         自动从 /dev/tty 读取输入，确保交互可用。
# -----------------------------------------------------------------------------
read_prompt() {
  local prompt="$1"
  local var_name="$2"
  local value=""

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

# -----------------------------------------------------------------------------
# 函数: print_divider
# 功能: 输出一条青色分隔线，用于视觉分隔不同输出段落
# 参数: 无
# 返回值: 始终返回 0
# -----------------------------------------------------------------------------
print_divider() { printf "%s%s%s\n" "$COLOR_CYAN" "------------------------------------------------------------" "$COLOR_RESET"; }

# =============================================================================
# 权限与命令检测
# =============================================================================

# 检测命令是否存在（存在返回 0，不存在返回非 0）
command_exists() { command -v "$1" >/dev/null 2>&1; }

# 判断当前是否以 root 用户运行（是返回 0，否返回非 0）
is_root_user() {
  [[ ${EUID:-$(id -u 2>/dev/null || echo 1)} -eq 0 ]]
}

# 要求 root 权限，非 root 时终止脚本
require_root() {
  if ! is_root_user; then
    die "此操作需要 root 权限，请使用 sudo 或切换到 root 用户"
  fi
}

# =============================================================================
# 时间与文件操作工具
# =============================================================================

# 生成时间戳（用于备份目录命名），格式 YYYYmmdd_HHMMSS
timestamp() { date "+%Y%m%d_%H%M%S"; }

# -----------------------------------------------------------------------------
# 函数: atomic_write
# 功能: 原子写入文件（先写临时文件再 mv 替换），避免写入中断导致文件损坏
# 参数: $1 - 目标文件路径；$2 - 源文件路径
# 返回值: 成功返回 0；任何一步失败返回 1 并清理临时文件
# -----------------------------------------------------------------------------
atomic_write() {
  local target="$1" source="$2"
  local tmp
  tmp=$(mktemp)
  cat "$source" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

# -----------------------------------------------------------------------------
# 函数: backup_with_timestamp
# 功能: 带时间戳的备份（避免覆盖历史备份）
# 参数: $1 - 要备份的文件路径
# 返回值: 源文件不存在时静默返回 0；存在时备份并经 stdout 输出备份文件路径
# -----------------------------------------------------------------------------
backup_with_timestamp() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts
  ts=$(timestamp)
  cp -a "$file" "${file}.bak.${ts}"
  echo "${file}.bak.${ts}"
}

# -----------------------------------------------------------------------------
# 函数: audit_log
# 功能: 记录操作审计日志到 /var/log/ayu-toolbox/audit.log（仅 root 生效）
# 参数: $1 - 操作类型；$2.. - 操作详情（可选）
# 返回值: 始终返回 0（日志写入失败不影响主流程）
# 说明:   日志文件权限 600，仅记录操作类型与详情，不记录密码/密钥等敏感数据
# -----------------------------------------------------------------------------
audit_log() {
  local action="$1"
  shift || true
  local detail="$*"

  if ! is_root_user; then
    return 0
  fi

  local log_dir="/var/log/ayu-toolbox"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  chmod 700 "$log_dir" 2>/dev/null || true

  local log_file="${log_dir}/audit.log"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
  local user="${USER:-$(whoami 2>/dev/null || echo unknown)}"

  printf "[%s] user=%s action=%s detail=%s\n" "$ts" "$user" "$action" "$detail" >>"$log_file" 2>/dev/null || true
  chmod 600 "$log_file" 2>/dev/null || true
}

# =============================================================================
# 确认函数
# 所有确认函数支持 NON_INTERACTIVE 全局变量：值为 1 时跳过交互直接返回默认结果。
# - confirm_default_no:  默认拒绝，NON_INTERACTIVE=1 时返回 1（拒绝，安全默认）
# - confirm_default_yes: 默认同意，NON_INTERACTIVE=1 时返回 0（同意，符合默认是）
# - confirm_phrase:      要求输入指定短语，NON_INTERACTIVE=1 时返回 0（高破坏性操作不应使用此跳过）
# =============================================================================

# -----------------------------------------------------------------------------
# 函数: confirm_default_no
# 功能: 确认提示（默认否），用于破坏性或可选操作
# 参数: $1 - 提示信息（可选，默认"确认继续?"）
# 返回值: 用户输入 y/Y 时返回 0；其他输入或 NON_INTERACTIVE=1 时返回 1
# -----------------------------------------------------------------------------
confirm_default_no() {
  local prompt="${1:-确认继续?}"
  local resp
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 1
  fi
  read -r -p "${prompt} (y/N) " resp
  [[ "$resp" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# 函数: confirm_default_yes
# 功能: 确认提示（默认是），用于常规或推荐操作
# 参数: $1 - 提示信息（可选，默认"确认继续?"）
# 返回值: 用户输入 n/N 时返回 1；其他输入或 NON_INTERACTIVE=1 时返回 0
# -----------------------------------------------------------------------------
confirm_default_yes() {
  local prompt="${1:-确认继续?}"
  local resp
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} (Y/n) " resp
  [[ ! "$resp" =~ ^[Nn]$ ]]
}

# -----------------------------------------------------------------------------
# 函数: confirm_phrase
# 功能: 要求输入确认短语（用于高破坏性操作，如擦盘、验盘）
# 参数: $1 - 提示信息；$2 - 要求输入的确认短语
# 返回值: 输入匹配时返回 0；不匹配或读取失败时调用 die 终止脚本
# 说明:   NON_INTERACTIVE=1 时直接返回 0（调用方需自行确保仅在明确授权下使用）
# -----------------------------------------------------------------------------
confirm_phrase() {
  local prompt="$1" phrase="$2"
  local input
  if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  read -r -p "${prompt} (请输入: ${phrase}) " input
  [[ "$input" == "$phrase" ]] || die "确认短语不匹配，已取消"
}
