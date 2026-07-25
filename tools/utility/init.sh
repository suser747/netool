#!/usr/bin/env bash
# ============================================================
# 项目名称：netool懒人工具箱
# 脚本名称：init.sh（服务器初始化向导）
# 版本：1.0
# 功能说明：
#   新服务器一键初始化向导，按步骤引导用户完成常用配置。
#   涵盖：系统信息查看、功能检查、软件源切换、基础工具安装、
#         BBR 网络优化、主机名/时区设置、SSH 端口管理、Docker 安装。
# 使用方式：
#   ./init.sh              启动交互式初始化向导
#   ./init.sh -h|--help    显示帮助信息
#   ./init.sh --version    显示版本号
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="server-init"
SCRIPT_VERSION="1.0"

# 主入口脚本路径，由 main() 在运行时根据脚本位置赋值，供 run_tool 调用子工具
MAIN_SH=""

# ---------- 颜色定义 ----------
# 默认禁用颜色，仅当标准输出为终端时启用，避免日志归档时混入转义序列
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_BOLD=""
COLOR_RESET=""

# 终端环境：启用 ANSI 颜色转义序列
if [[ -t 1 ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
fi

# 作为子工具被主入口调用时（AYU_TOOLBOX 已设置）：禁用颜色，避免嵌套输出混乱
if [[ -n "${AYU_TOOLBOX:-}" ]]; then
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

# ---------- 日志输出函数 ----------
# 统一带颜色前缀的日志输出，便于在终端中区分级别

# log_info：输出普通信息到标准输出
# 参数：$* - 日志内容
# 返回值：无
log_info() { printf "%s%s[信息]%s %s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET" "$*"; }

# log_success：输出成功信息到标准输出
# 参数：$* - 日志内容
# 返回值：无
log_success() { printf "%s%s[完成]%s %s\n" "$COLOR_BOLD" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }

# log_warn：输出警告信息到标准输出
# 参数：$* - 日志内容
# 返回值：无
log_warn() { printf "%s%s[警告]%s %s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }

# log_error：输出错误信息到标准错误
# 参数：$* - 日志内容
# 返回值：无
log_error() { printf "%s%s[错误]%s %s\n" "$COLOR_BOLD" "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }

# die：输出错误信息后以状态码 1 退出脚本
# 参数：$* - 错误信息
# 返回值：无（直接退出脚本）
die() { log_error "$*"; exit 1; }

# ---------- 错误处理 ----------
# on_error：ERR 信号回调，捕获未处理错误并打印出错行号
# 参数：无（通过 $? 获取退出码）
# 返回值：无（直接退出脚本）
on_error() {
  local exit_code=$?
  log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  exit "$exit_code"
}

trap on_error ERR

# ---------- 审计日志 ----------
# audit_log：记录关键操作到审计日志文件（仅 root 用户生效）
# 参数：$1 - 操作类型（如 init_wizard）；$2.. - 操作详情
# 返回值：0 表示成功或非 root 用户跳过；非 0 表示日志目录创建失败
audit_log() {
  local action="$1"
  shift || true
  local detail="$*"

  # 非 root 用户直接跳过，审计日志仅记录特权操作
  if [[ "${EUID:-$(id -u 2>/dev/null || echo 1)}" -ne 0 ]]; then
    return 0
  fi

  local log_dir="/var/log/ayu-toolbox"
  mkdir -p "$log_dir" 2>/dev/null || return 0
  chmod 700 "$log_dir" 2>/dev/null || true

  local log_file="${log_dir}/audit.log"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
  local user="${USER:-$(whoami 2>/dev/null || echo unknown)}"

  # 追加一行审计记录，权限收紧为 600 仅限 root 读写
  printf "[%s] user=%s action=%s detail=%s\n" "$timestamp" "$user" "$action" "$detail" >>"$log_file" 2>/dev/null || true
  chmod 600 "$log_file" 2>/dev/null || true
}

# ---------- 输入工具 ----------
# read_prompt：向用户输出提示并读取一行输入，结果写入指定变量名
# 参数：$1 - 提示文本；$2 - 用于存放输入的变量名
# 返回值：0 读取成功；1 读取失败（如 EOF）
# 说明：当 stdin 被重定向但 stdout 为终端时，自动从 /dev/tty 读取输入
read_prompt() {
  local prompt="$1"
  local var_name="$2"
  local value=""

  # 管道/重定向场景：从 /dev/tty 读取以保证交互可用
  if [[ ! -t 0 && -t 1 && -r /dev/tty ]]; then
    if { printf "%s" "$prompt" >/dev/tty && IFS= read -r value </dev/tty; } 2>/dev/null; then
      printf -v "$var_name" "%s" "$value"
      return 0
    fi
  fi

  # 常规场景：直接从 stdin 读取
  printf "%s" "$prompt"
  IFS= read -r value || [[ -n "$value" ]] || return 1
  printf -v "$var_name" "%s" "$value"
}

# command_exists：判断指定命令是否存在于 PATH 中
# 参数：$1 - 命令名
# 返回值：0 存在；非 0 不存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# confirm_default_no：交互式询问用户是否继续，默认为"否"
# 参数：无
# 返回值：0 用户明确确认继续；1 用户拒绝或采用默认值
# 说明：用于子工具失败后询问是否继续执行，避免静默吞错
confirm_default_no() {
  local reply=""
  if ! read_prompt "(y/n) [默认: n]: " reply; then reply="n"; fi
  reply="${reply:-n}"
  case "${reply,,}" in
    y|yes|是|确认) return 0 ;;
    *) return 1 ;;
  esac
}

# usage：输出脚本帮助信息到标准输出
# 参数：无
# 返回值：无
usage() {
  cat <<EOF
netool懒人工具箱 | 服务器初始化向导 v${SCRIPT_VERSION}

用法：
  init [选项]

选项：
  -h, --help    显示帮助
  --version     显示版本

说明：
  新服务器一键初始化向导，逐步引导配置常用项。
  包括：系统信息查看、功能检查、换源、基础工具、BBR、主机名/时区、SSH端口、Docker。
EOF
}

# print_banner：输出脚本启动横幅
# 参数：无
# 返回值：无
# 说明：作为子工具被调用时（AYU_TOOLBOX 已设置）不输出横幅，避免重复
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 服务器初始化向导 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ---------- 子工具调用 ----------
# run_tool：通过主入口 main.sh 调用指定子工具并透传参数
# 参数：$1 - 子工具名称；$@ - 透传给子工具的参数
# 返回值：0 子工具执行成功（或用户选择继续）；1 子工具失败且用户选择中止
# 说明：
#   1. 若 main.sh 不存在则跳过并告警；
#   2. 子工具执行失败时，非 YES=1 环境下会询问用户是否继续，避免静默吞错。
run_tool() {
  local tool="$1"
  shift || true
  if [[ -f "$MAIN_SH" ]]; then
    if ! bash "$MAIN_SH" "$tool" "$@"; then
      log_warn "子工具 $tool 执行失败"
      if [[ "${YES:-}" != "1" ]]; then
        log_info "是否继续执行下一步？"
        if ! confirm_default_no; then
          log_info "已中止初始化流程"
          return 1
        fi
      fi
    fi
  else
    log_warn "未找到 main.sh，跳过：${tool}"
  fi
}

# ---------- 主流程 ----------
# main：服务器初始化向导主入口
# 参数：$@ - 命令行参数（支持 -h/--help、--version）
# 返回值：无（通过 exit 终止脚本）
# 说明：按 8 个步骤顺序引导用户完成初始化，每一步均可选择跳过
main() {
  case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
  esac

  print_banner
  audit_log "init_wizard" "start"

  printf "\n%s=== 服务器初始化向导 ===%s\n" "$COLOR_GREEN" "$COLOR_RESET"
  printf "将按以下步骤进行，可随时退出：\n"
  printf "  1. 查看系统信息\n"
  printf "  2. 检查功能可用性\n"
  printf "  3. 软件源切换（可选）\n"
  printf "  4. 基础工具安装（可选）\n"
  printf "  5. BBR 网络优化（可选）\n"
  printf "  6. 设置主机名/时区（可选）\n"
  printf "  7. SSH 端口管理（可选）\n"
  printf "  8. Docker 安装（可选）\n"
  printf "\n"

  local go=""
  if ! read_prompt "是否开始初始化向导？(y/n) [默认: n]: " go; then
    exit 1
  fi
  go="${go:-n}"
  case "${go,,}" in
    y|yes|是|确认) ;;
    *) log_info "已取消。"; exit 0 ;;
  esac

  # 计算脚本所在目录与主入口路径，赋值给全局 MAIN_SH 供 run_tool 使用
  # 注意：local 与赋值分开写，避免 local 掩盖命令失败的退出码
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local ROOT_DIR
  ROOT_DIR="$(dirname "$SCRIPT_DIR")"
  MAIN_SH="${ROOT_DIR}/main.sh"

  printf "\n%s--- 第 1/8 步：系统信息 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
  run_tool system info

  printf "\n%s--- 第 2/8 步：功能检查 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
  run_tool check

  local step=""
  printf "\n"
  if ! read_prompt "是否切换软件源？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 3 步：软件源切换 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    log_info "轻量换源（带备份恢复）：mirror"
    log_info "全能换源（更多发行版+Docker）：lmirrors"
    local choice=""
    if ! read_prompt "请选择 (mirror/lmirrors/n) [默认: mirror]: " choice; then choice="mirror"; fi
    choice="${choice:-mirror}"
    case "${choice,,}" in
      lmirrors|全能) run_tool lmirrors ;;
      n|no|否|不) log_info "已跳过。" ;;
      *) run_tool mirror ;;
    esac
  else
    log_info "已跳过：软件源切换"
  fi

  if ! read_prompt "是否安装基础工具？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 4 步：基础工具安装 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool basic --plan
    local inst=""
    if ! read_prompt "确认执行安装？(y/n) [默认: n]: " inst; then inst="n"; fi
    inst="${inst:-n}"
    if [[ "${inst,,}" == "y" || "${inst,,}" == "是" ]]; then
      run_tool basic -y
      audit_log "init_wizard" "basic_install done"
    else
      log_info "已跳过：基础工具安装"
    fi
  else
    log_info "已跳过：基础工具安装"
  fi

  if ! read_prompt "是否启用 BBR？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 5 步：BBR 网络优化 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool bbr status
    local bbr_go=""
    if ! read_prompt "确认启用 BBR？(y/n) [默认: n]: " bbr_go; then bbr_go="n"; fi
    bbr_go="${bbr_go:-n}"
    if [[ "${bbr_go,,}" == "y" || "${bbr_go,,}" == "是" ]]; then
      run_tool bbr enable -y
      audit_log "init_wizard" "bbr_enable done"
    else
      log_info "已跳过：BBR 启用"
    fi
  else
    log_info "已跳过：BBR 网络优化"
  fi

  if ! read_prompt "是否设置主机名/时区？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 6 步：主机名/时区 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool host
    audit_log "init_wizard" "host done"
  else
    log_info "已跳过：主机名/时区设置"
  fi

  if ! read_prompt "是否修改 SSH 端口？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 7 步：SSH 端口管理 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool ssh
    audit_log "init_wizard" "ssh done"
  else
    log_info "已跳过：SSH 端口管理"
  fi

  if ! read_prompt "是否安装 Docker？(y/n) [默认: n]: " step; then step="n"; fi
  step="${step:-n}"
  if [[ "${step,,}" == "y" || "${step,,}" == "是" ]]; then
    printf "\n%s--- 第 8 步：Docker 安装 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool docker install --plan
    local dk=""
    if ! read_prompt "确认安装 Docker？(y/n) [默认: n]: " dk; then dk="n"; fi
    dk="${dk:-n}"
    if [[ "${dk,,}" == "y" || "${dk,,}" == "是" ]]; then
      run_tool docker install -y
      audit_log "init_wizard" "docker_install done"
    else
      log_info "已跳过：Docker 安装"
    fi
  else
    log_info "已跳过：Docker 安装"
  fi

  printf "\n%s=== 初始化向导完成 ===%s\n" "$COLOR_GREEN" "$COLOR_RESET"
  log_success "服务器初始化向导已完成。"
  audit_log "init_wizard" "complete"
}

main "$@"
