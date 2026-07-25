#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 进程与服务管理（service-tools）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: service-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   查看 Linux 系统进程资源占用与 systemd 服务状态，并对服务执行
#   start/stop/restart/reload 操作。查看类操作（top/list/status/logs）
#   不修改系统；变更类操作要求 root 权限并二次确认，支持 --dry-run 预览。
#   服务名输入会自动补全 .service 后缀并校验合法性。
# 使用方式:
#   bash service.sh                          # 进入交互式菜单（默认）
#   bash service.sh top                      # 查看进程资源占用 TOP
#   bash service.sh list                     # 列出运行中的 systemd 服务
#   bash service.sh status nginx             # 查看服务状态
#   bash service.sh logs nginx               # 查看服务最近日志
#   bash service.sh restart nginx -y         # 重启服务（跳过确认）
#   bash service.sh stop nginx --plan        # 预览停止计划
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="service-tools"
SCRIPT_VERSION="1.0"
YES=0
DRY_RUN=0

COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_BOLD=""
COLOR_RESET=""

# 终端在 stdout 是 tty 时启用 ANSI 颜色，否则保持空白字符串避免乱码
if [[ -t 1 ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
fi

# 作为子模块被主工具箱调用时（AYU_TOOLBOX 已设置），关闭颜色避免日志混乱
if [[ -n "${AYU_TOOLBOX:-}" ]]; then
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

# ----------------------------------------------------------------------
# 函数:log_info / log_success / log_warn / log_error
# 功能:统一日志输出函数，分别用于信息、成功、警告、错误（输出到 stderr）
# 参数:$* - 要输出的文本
# 返回值:始终 0（die 除外）
# ----------------------------------------------------------------------
log_info() { printf "%s%s[信息]%s %s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET" "$*"; }
log_success() { printf "%s%s[完成]%s %s\n" "$COLOR_BOLD" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
log_warn() { printf "%s%s[警告]%s %s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
log_error() { printf "%s%s[错误]%s %s\n" "$COLOR_BOLD" "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }

# ----------------------------------------------------------------------
# 函数:die
# 功能:输出错误信息并以退出码 1 终止脚本
# 参数:$* - 错误信息文本
# 返回值:不返回（直接退出 1）
# ----------------------------------------------------------------------
die() { log_error "$*"; exit 1; }

# ----------------------------------------------------------------------
# 函数:on_error
# 功能:ERR trap 回调，捕获命令执行失败时打印行号与退出码后退出
# 参数:无（通过 $? 获取退出码）
# 返回值:不返回（直接退出原退出码）
# ----------------------------------------------------------------------
on_error() {
  local exit_code=$?
  log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  exit "$exit_code"
}

trap on_error ERR

# ----------------------------------------------------------------------
# 函数:read_prompt
# 功能:读取用户输入并写入指定变量名，兼容交互式与管道输入场景
# 参数:$1 - 提示信息文本；$2 - 接收输入的变量名
# 返回值:0 表示成功读取；1 表示读取失败
# ----------------------------------------------------------------------
read_prompt() {
  local prompt="$1"
  local var_name="$2"
  local value=""

  # 管道调用且 stdout 是 tty 时，从 /dev/tty 读取以保证交互可用
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

# ----------------------------------------------------------------------
# 函数:command_exists
# 功能:判断指定命令是否存在于 PATH 中
# 参数:$1 - 命令名
# 返回值:0 表示存在；非 0 表示不存在
# ----------------------------------------------------------------------
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ----------------------------------------------------------------------
# 函数:require_root
# 功能:校验当前是否以 root 运行，否则终止脚本
# 参数:无
# 返回值:0 表示是 root；非 0 表示非 root 并终止
# ----------------------------------------------------------------------
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "该操作需要 root 权限。"
}

# ----------------------------------------------------------------------
# 函数:require_systemctl
# 功能:要求 systemctl 必须可用，否则终止脚本
# 参数:无
# 返回值:0 表示可用；非 0 表示缺失并终止
# ----------------------------------------------------------------------
require_systemctl() {
  command_exists systemctl || die "当前系统没有 systemctl。"
}

# ----------------------------------------------------------------------
# 函数:confirm
# 功能:交互式确认提示，YES 模式下直接通过；否则读取用户输入判断是否同意
# 参数:$1 - 提示文本
# 返回值:0 表示确认；1 表示拒绝或读取失败
# ----------------------------------------------------------------------
confirm() {
  local prompt="$1"
  local answer=""
  if ((YES)); then return 0; fi
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ----------------------------------------------------------------------
# 函数:usage
# 功能:输出脚本帮助说明（操作、选项、说明）到标准输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 进程与服务管理 v${SCRIPT_VERSION}

用法：
  service [操作] [服务名]

操作：
  top             查看资源占用最高的进程（默认）
  list            查看运行中的 systemd 服务
  status NAME     查看服务状态
  logs NAME       查看服务最近日志
  reload NAME     重载服务
  restart NAME    重启服务
  start NAME      启动服务
  stop NAME       停止服务

选项：
  --plan, --dry-run  只显示 start/stop/restart/reload 计划，不执行
  -y, --yes       不再询问
  -h, --help      显示帮助
  --version       显示版本

说明：
  top/list/status/logs 为查看类操作；start/stop/restart 需要 root，并会二次确认。
EOF
}

# ----------------------------------------------------------------------
# 函数:print_banner
# 功能:打印脚本横幅信息；AYU_TOOLBOX 模式下静默不输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 进程与服务管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ----------------------------------------------------------------------
# 函数:validate_service_name
# 功能:校验服务名格式是否合法，允许字母数字及 _.@:- 并可选 .service 后缀
# 参数:$1 - 待校验的服务名
# 返回值:0 表示合法；1 表示非法或为空
# ----------------------------------------------------------------------
validate_service_name() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9_.@:-]+(\.service)?$ ]]
}

# ----------------------------------------------------------------------
# 函数:normalize_service_name
# 功能:规范化服务名，若未带 .service 后缀则自动补全
# 参数:$1 - 原始服务名
# 返回值:0 表示成功，规范化后的服务名输出到 stdout
# ----------------------------------------------------------------------
normalize_service_name() {
  local name="$1"
  if [[ "$name" == *.service ]]; then
    printf "%s\n" "$name"
  else
    printf "%s.service\n" "$name"
  fi
}

# ----------------------------------------------------------------------
# 函数:do_top
# 功能:按内存占用倒序打印进程 TOP 列表（前 21 行，含表头）
# 参数:无
# 返回值:0 表示成功；1 表示无法读取进程列表（die 退出）
# ----------------------------------------------------------------------
do_top() {
  local output=""

  printf "\n进程资源占用 TOP：\n"
  # 优先使用扩展 ps 字段，回退到通用 ps aux
  if output="$(ps -eo pid,ppid,user,stat,pcpu,pmem,etime,comm,args --sort=-%mem 2>/dev/null)"; then
    printf "%s\n" "$output" | sed -n '1,21p'
  elif output="$(ps aux 2>/dev/null)"; then
    printf "%s\n" "$output" | sed -n '1,21p'
  else
    die "无法读取进程列表。"
  fi
}

# ----------------------------------------------------------------------
# 函数:do_list
# 功能:列出运行中的 systemd 服务（最多 80 行）
# 参数:无
# 返回值:0 表示成功或非 systemd 系统
# ----------------------------------------------------------------------
do_list() {
  if ! command_exists systemctl; then
    log_warn "当前系统没有 systemctl，无法列出 systemd 服务。"
    return 0
  fi
  printf "\n运行中的 systemd 服务：\n"
  systemctl --type=service --state=running --no-pager 2>/dev/null | sed -n '1,80p'
}

# ----------------------------------------------------------------------
# 函数:do_status
# 功能:查看指定服务的 systemd 运行状态
# 参数:$1 - 服务名（可省略 .service 后缀）
# 返回值:0 表示成功；1 表示参数非法或缺 systemctl（die 退出）
# ----------------------------------------------------------------------
do_status() {
  local name="${1:-}"
  validate_service_name "$name" || die "请指定有效服务名，例如：service status nginx"
  require_systemctl
  name="$(normalize_service_name "$name")"
  systemctl status "$name" --no-pager
}

# ----------------------------------------------------------------------
# 函数:do_logs
# 功能:通过 journalctl 查看指定服务最近 120 条日志
# 参数:$1 - 服务名（可省略 .service 后缀）
# 返回值:0 表示成功；1 表示参数非法或缺命令（die 退出）
# ----------------------------------------------------------------------
do_logs() {
  local name="${1:-}"
  validate_service_name "$name" || die "请指定有效服务名，例如：service logs nginx"
  require_systemctl
  command_exists journalctl || die "当前系统没有 journalctl。"
  name="$(normalize_service_name "$name")"
  journalctl -u "$name" -n 120 --no-pager
}

# ----------------------------------------------------------------------
# 函数:change_service
# 功能:对指定服务执行 start/stop/restart/reload 操作，执行前打印计划并确认
# 参数:$1 - 操作动作（start/stop/restart/reload）；$2 - 服务名
# 返回值:0 表示成功或被取消；1 表示参数非法（die 退出）
# ----------------------------------------------------------------------
change_service() {
  local action="$1"
  local name="${2:-}"
  local verb=""
  validate_service_name "$name" || die "请指定有效服务名，例如：service ${action} nginx"
  name="$(normalize_service_name "$name")"

  # 将英文动作映射为中文动词，便于日志展示
  case "$action" in
    start) verb="启动" ;;
    stop) verb="停止" ;;
    reload) verb="重载" ;;
    restart) verb="重启" ;;
    *) die "未知服务操作：$action" ;;
  esac

  printf "\n服务操作计划：\n"
  printf "  操作：%s\n" "$verb"
  printf "  服务：%s\n" "$name"
  if command_exists systemctl; then
    systemctl is-active "$name" 2>/dev/null | sed 's/^/  当前状态：/' || true
  fi
  if (( DRY_RUN )); then
    log_info "预览模式，不会修改服务状态。"
    return 0
  fi
  require_systemctl
  if ! confirm "确认${verb}该服务？"; then
    log_warn "已取消。"
    return 0
  fi

  require_root
  systemctl "$action" "$name"
  log_success "服务操作完成。"
  # 操作完成后展示服务最新状态摘要（前 18 行）
  systemctl status "$name" --no-pager 2>/dev/null | sed -n '1,18p' || true
}

# ----------------------------------------------------------------------
# 函数:run_action
# 功能:根据传入的操作名分派到对应处理函数；支持 -h/--help 与 --version
# 参数:$1 - 操作名（缺省为 top）；剩余参数会传递给子函数
# 返回值:0 表示成功；1 表示未知操作（die 退出）
# ----------------------------------------------------------------------
run_action() {
  local action="${1:-top}"
  shift || true

  case "$action" in
    top|process|processes|ps) do_top ;;
    list|services|running) do_list ;;
    status|info) do_status "${1:-}" ;;
    logs|log) do_logs "${1:-}" ;;
    reload) change_service reload "${1:-}" ;;
    restart) change_service restart "${1:-}" ;;
    start) change_service start "${1:-}" ;;
    stop) change_service stop "${1:-}" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$action" ;;
  esac
}

# ----------------------------------------------------------------------
# 函数:interactive_loop
# 功能:交互式菜单循环，等待用户选择操作直至选择返回
# 参数:无
# 返回值:0 表示正常返回；1 表示读取输入失败
# ----------------------------------------------------------------------
interactive_loop() {
  local answer=""
  local name=""
  while true; do
    printf "\n请选择进程/服务操作：\n"
    printf "  1. 查看进程 TOP\n"
    printf "  2. 查看运行服务\n"
    printf "  3. 查看服务状态\n"
    printf "  4. 查看服务日志\n"
    printf "  5. 重启服务\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号： " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) do_top ;;
      2) do_list ;;
      3)
        read_prompt "服务名： " name || return 1
        do_status "$name"
        ;;
      4)
        read_prompt "服务名： " name || return 1
        do_logs "$name"
        ;;
      5)
        read_prompt "服务名： " name || return 1
        change_service restart "$name"
        ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入，请重新输入。" ;;
      *) log_warn "无效输入，请输入 1-5 或 b 返回。" ;;
    esac
  done
}

# ----------------------------------------------------------------------
# 函数:main
# 功能:脚本入口，解析全局选项后分派到具体操作或交互菜单
# 参数:$@ - 命令行参数
# 返回值:随分派函数返回
# ----------------------------------------------------------------------
main() {
  print_banner

  # 解析全局选项，剩余位置参数转入 args 数组交给 run_action
  local args=()
  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  if ((${#args[@]} > 0)); then
    run_action "${args[@]}"
  else
    interactive_loop
  fi
}

main "$@" || exit $?
