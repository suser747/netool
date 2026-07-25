#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 主机名与时区管理（host-tools）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: host-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   查看/修改 Linux 系统的主机名与时区。查看类操作不修改系统；修改主机名
#   时优先调用 hostnamectl，缺失则回退 hostname + /etc/hostname 写入；
#   修改时区统一通过 timedatectl set-timezone 完成。所有修改类操作均要求
#   root 权限并支持 --dry-run 预览与 -y 跳过确认。
# 使用方式:
#   bash host.sh                                  # 进入交互式菜单（默认）
#   bash host.sh status                           # 查看主机名、时间、时区
#   bash host.sh set-hostname web-01              # 修改主机名
#   bash host.sh set-timezone Asia/Shanghai       # 修改时区
#   bash host.sh list-timezones Shanghai          # 按关键字过滤时区列表
#   bash host.sh set-hostname web-01 --plan -y    # 预览修改计划
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="host-tools"
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
netool懒人工具箱 | 主机名/时区管理 v${SCRIPT_VERSION}

用法：
  host [操作] [参数]

操作：
  status                  查看主机名、时间、时区（默认）
  set-hostname NAME       修改主机名
  set-timezone TZ         修改时区，例如 Asia/Shanghai
  list-timezones [关键字] 列出可用时区，可按关键字过滤

  选项：
  --plan, --dry-run       只显示修改计划，不写入系统
  -y, --yes               不再询问
  -h, --help              显示帮助
  --version               显示版本

说明：
  查看类操作不改系统；修改主机名或时区需要 root，并会二次确认。
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
  printf "netool懒人工具箱 | 主机名/时区管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ----------------------------------------------------------------------
# 函数:show_status
# 功能:打印当前主机名、hostnamectl 状态、系统时间与 timedatectl 时区信息
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
show_status() {
  printf "\n主机信息：\n"
  printf "  当前主机名：%s\n" "$(hostname 2>/dev/null || echo "-")"
  if command_exists hostnamectl; then
    hostnamectl status 2>/dev/null | sed 's/^/  /' || true
  fi

  printf "\n时间信息：\n"
  date 2>/dev/null | sed 's/^/  /' || true
  if command_exists timedatectl; then
    timedatectl 2>/dev/null | sed 's/^/  /' || true
  else
    log_warn "未检测到 timedatectl，无法直接管理 systemd 时区。"
  fi
}

# ----------------------------------------------------------------------
# 函数:validate_hostname
# 功能:校验主机名合法性，遵循 RFC 长度与字符规则（总长 ≤253，每段 ≤63）
# 参数:$1 - 待校验的主机名
# 返回值:0 表示合法；1 表示非法
# ----------------------------------------------------------------------
validate_hostname() {
  local name="$1"
  local label=""
  [[ -n "$name" && ${#name} -le 253 ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
  [[ "$name" != *..* ]] || return 1

  # 按 '.' 拆分为多个 label，逐段校验长度与字符规则
  IFS='.' read -r -a labels <<<"$name"
  for label in "${labels[@]}"; do
    [[ -n "$label" && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

# ----------------------------------------------------------------------
# 函数:set_hostname
# 功能:修改系统主机名，优先使用 hostnamectl；缺失时回退 hostname + /etc/hostname
# 参数:$1 - 新主机名
# 返回值:0 表示成功或被取消；1 表示参数非法（die 退出）
# ----------------------------------------------------------------------
set_hostname() {
  local name="$1"
  [[ -n "$name" ]] || die "请指定新主机名，例如：host set-hostname web-01"
  validate_hostname "$name" || die "主机名不合法。只能使用字母、数字、短横线和点，不能以短横线开头或结尾。"

  printf "\n主机名修改计划：\n"
  printf "  当前：%s\n" "$(hostname 2>/dev/null || echo "-")"
  printf "  目标：%s\n" "$name"
  if (( DRY_RUN )); then
    log_info "预览模式，不会修改主机名。"
    return 0
  fi
  if ! confirm "确认修改主机名？"; then
    log_warn "已取消。"
    return 0
  fi

  require_root
  if command_exists hostnamectl; then
    # systemd 系统:hostnamectl 会同时持久化主机名
    hostnamectl set-hostname "$name"
  else
    # 非 systemd 系统:手动调用 hostname 并尝试写入 /etc/hostname
    hostname "$name"
    if [[ -w /etc/hostname || ! -e /etc/hostname ]]; then
      printf "%s\n" "$name" >/etc/hostname
    else
      log_warn "无法写入 /etc/hostname，请手动持久化主机名。"
    fi
  fi

  log_success "主机名已修改。"
  show_status
}

# ----------------------------------------------------------------------
# 函数:list_timezones
# 功能:列出可用时区，可通过关键字过滤；无关键字时打印前 120 行并给出提示
# 参数:$1 - 过滤关键字（可选）
# 返回值:0 表示成功；1 表示缺少 timedatectl（die 退出）
# ----------------------------------------------------------------------
list_timezones() {
  local pattern="${1:-}"
  command_exists timedatectl || die "当前系统没有 timedatectl，无法列出时区。"
  if [[ -n "$pattern" ]]; then
    timedatectl list-timezones | grep -i -- "$pattern" | sed -n '1,80p'
  else
    timedatectl list-timezones | sed -n '1,120p'
    printf "\n提示：可用 host list-timezones Shanghai 过滤结果。\n"
  fi
}

# ----------------------------------------------------------------------
# 函数:timezone_exists
# 功能:判断指定时区是否存在，优先用 timedatectl 列表，回退 zoneinfo 文件
# 参数:$1 - 时区名（如 Asia/Shanghai）
# 返回值:0 表示存在；非 0 表示不存在
# ----------------------------------------------------------------------
timezone_exists() {
  local zone="$1"
  if command_exists timedatectl; then
    timedatectl list-timezones 2>/dev/null | grep -Fxq -- "$zone"
  else
    [[ -f "/usr/share/zoneinfo/$zone" ]]
  fi
}

# ----------------------------------------------------------------------
# 函数:set_timezone
# 功能:通过 timedatectl set-timezone 修改系统时区，写入前校验时区是否存在
# 参数:$1 - 新时区名（如 Asia/Shanghai）
# 返回值:0 表示成功或被取消；1 表示参数/环境非法（die 退出）
# ----------------------------------------------------------------------
set_timezone() {
  local zone="$1"
  [[ -n "$zone" ]] || die "请指定时区，例如：host set-timezone Asia/Shanghai"

  printf "\n时区修改计划：\n"
  printf "  当前：%s\n" "$(timedatectl show -p Timezone --value 2>/dev/null || echo "-")"
  printf "  目标：%s\n" "$zone"
  if (( DRY_RUN )); then
    log_info "预览模式，不会修改时区。"
    return 0
  fi
  command_exists timedatectl || die "当前系统没有 timedatectl，无法自动修改时区。"
  timezone_exists "$zone" || die "未找到时区：$zone。可执行 host list-timezones Shanghai 查询。"
  if ! confirm "确认修改系统时区？"; then
    log_warn "已取消。"
    return 0
  fi

  require_root
  timedatectl set-timezone "$zone"
  log_success "时区已修改。"
  show_status
}

# ----------------------------------------------------------------------
# 函数:run_action
# 功能:根据传入的操作名分派到对应处理函数；支持 -h/--help 与 --version
# 参数:$1 - 操作名（缺省为 status）；剩余参数会传递给子函数
# 返回值:0 表示成功；1 表示未知操作（die 退出）
# ----------------------------------------------------------------------
run_action() {
  local action="${1:-status}"
  shift || true

  case "$action" in
    status|info) show_status ;;
    set) set_hostname "${1:-}" ;;
    set-hostname|hostname) set_hostname "${1:-}" ;;
    set-timezone|timezone|tz) set_timezone "${1:-}" ;;
    list-timezones|timezones|zones) list_timezones "${1:-}" ;;
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
  local value=""
  while true; do
    printf "\n请选择主机管理操作：\n"
    printf "  1. 查看主机名和时间\n"
    printf "  2. 修改主机名\n"
    printf "  3. 修改时区\n"
    printf "  4. 查询时区列表\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号： " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) show_status ;;
      2)
        read_prompt "新主机名： " value || return 1
        set_hostname "$value"
        ;;
      3)
        read_prompt "时区，例如 Asia/Shanghai： " value || return 1
        set_timezone "$value"
        ;;
      4)
        read_prompt "过滤关键字，可留空： " value || true
        list_timezones "$value"
        ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入，请重新输入。" ;;
      *) log_warn "无效输入，请输入 1-4 或 b 返回。" ;;
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
