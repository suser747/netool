#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 系统信息查看工具（system-tools）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: system-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   以低风险方式查看 Linux 系统运行信息，包括系统/内核/架构/主机名、运行时长、
#   CPU、内存、磁盘占用，以及当前时间、时区、登录用户和运行中的 systemd 服务。
#   同时提供系统更新与清理的命令提示（仅打印命令，不自动执行），避免误操作系统。
# 使用方式:
#   bash system.sh                       # 进入交互式菜单（默认）
#   bash system.sh info                  # 查看系统信息
#   bash system.sh update                # 打印系统更新命令
#   bash system.sh clean                 # 打印系统清理命令
#   bash system.sh time                  # 查看时间和时区
#   bash system.sh users                 # 查看登录用户
#   bash system.sh time-users            # 查看时间和登录用户
#   bash system.sh services              # 查看运行中的 systemd 服务
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="system-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR


# ----------------------------------------------------------------------
# 函数:usage
# 功能:输出脚本帮助说明（操作、说明）到标准输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 系统工具 v${SCRIPT_VERSION}

用法：
  system [操作]

操作：
  info       查看系统信息（默认）
  update     打印系统更新命令，不自动执行
  clean      打印清理命令，不自动执行
  time       查看时间和时区
  users      查看登录用户
  time-users 查看时间和登录用户
  services   查看运行中的 systemd 服务

说明：
  当前模块只做低风险信息查看和命令提示，不自动修改系统。
EOF
}

# ----------------------------------------------------------------------
# 函数:print_banner
# 功能:打印脚本横幅信息；NETOOL 子工具调用时静默不输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 系统工具 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ----------------------------------------------------------------------
# 函数:os_name
# 功能:获取当前操作系统名称，优先读取 /etc/os-release 的 PRETTY_NAME
# 参数:无
# 返回值:0 表示成功；非 0 表示回退到 uname
# ----------------------------------------------------------------------
os_name() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf "%s\n" "${PRETTY_NAME:-${NAME:-未知系统}}"
  else
    uname -s
  fi
}

# ----------------------------------------------------------------------
# 函数:do_info
# 功能:打印系统概览信息，包括系统/内核/架构/主机名/运行时长/CPU/内存/磁盘
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_info() {
  printf "\n系统信息：\n"
  printf "  系统：%s\n" "$(os_name)"
  printf "  内核：%s\n" "$(uname -r 2>/dev/null || echo "-")"
  printf "  架构：%s\n" "$(uname -m 2>/dev/null || echo "-")"
  printf "  主机：%s\n" "$(hostname 2>/dev/null || echo "-")"
  printf "  运行：%s\n" "$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "-")"
  printf "\nCPU：\n"
  if command_exists lscpu; then
    # 优先使用 lscpu 抽取关键字段:型号、核数、架构
    lscpu | awk -F: '/Model name|CPU\(s\)|Architecture/{gsub(/^[ \t]+/,"",$2); printf "  %-12s %s\n", $1":", $2}'
  else
    grep -m1 'model name' /proc/cpuinfo 2>/dev/null | sed 's/^/  /' || true
  fi
  printf "\n内存：\n"
  free -h 2>/dev/null | sed 's/^/  /' || true
  printf "\n磁盘：\n"
  # 过滤 tmpfs/devtmpfs 等伪文件系统，只展示真实磁盘
  df -hT -x tmpfs -x devtmpfs 2>/dev/null | sed 's/^/  /' || true
}

# ----------------------------------------------------------------------
# 函数:do_update_hint
# 功能:根据系统已安装的包管理器打印对应的系统更新命令（仅展示，不执行）
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_update_hint() {
  printf "\n系统更新命令（仅展示，不执行）：\n"
  if command_exists apt; then
    printf "  apt update && apt upgrade -y\n"
  elif command_exists dnf; then
    printf "  dnf upgrade --refresh -y\n"
  elif command_exists yum; then
    printf "  yum update -y\n"
  elif command_exists apk; then
    printf "  apk update && apk upgrade\n"
  elif command_exists pacman; then
    printf "  pacman -Syu\n"
  elif command_exists zypper; then
    printf "  zypper refresh && zypper update -y\n"
  else
    printf "  未识别包管理器。\n"
  fi
}

# ----------------------------------------------------------------------
# 函数:do_clean_hint
# 功能:根据系统已安装的包管理器打印对应的清理命令（仅展示，不执行）
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_clean_hint() {
  printf "\n清理命令（仅展示，不执行）：\n"
  if command_exists apt; then
    printf "  apt autoremove -y && apt clean\n"
  elif command_exists dnf; then
    printf "  dnf autoremove -y && dnf clean all\n"
  elif command_exists yum; then
    printf "  yum autoremove -y && yum clean all\n"
  elif command_exists apk; then
    printf "  apk cache clean\n"
  elif command_exists pacman; then
    printf "  pacman -Sc\n"
  elif command_exists zypper; then
    printf "  zypper clean --all\n"
  else
    printf "  未识别包管理器。\n"
  fi
}

# ----------------------------------------------------------------------
# 函数:do_time
# 功能:打印当前系统时间与时区信息（date 与 timedatectl）
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_time() {
  printf "\n时间信息：\n"
  date 2>/dev/null | sed 's/^/  /' || true
  timedatectl 2>/dev/null | sed 's/^/  /' || true
}

# ----------------------------------------------------------------------
# 函数:do_users
# 功能:打印当前登录用户与最近登录记录（最多 8 条）
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_users() {
  printf "\n当前登录用户：\n"
  who 2>/dev/null | sed 's/^/  /' || true
  printf "\n最近登录：\n"
  last -n 8 2>/dev/null | sed 's/^/  /' || true
}

# ----------------------------------------------------------------------
# 函数:do_time_users
# 功能:组合调用 do_time 与 do_users，一次性输出时间与登录用户信息
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_time_users() {
  do_time
  do_users
}

# ----------------------------------------------------------------------
# 函数:do_services
# 功能:列出当前运行中的 systemd 服务（最多 40 行）
# 参数:无
# 返回值:0 表示成功或非 systemd 系统；非 0 由调用方处理
# ----------------------------------------------------------------------
do_services() {
  if ! command_exists systemctl; then
    log_warn "当前系统没有 systemctl，无法列出 systemd 服务。"
    return 0
  fi
  systemctl --type=service --state=running --no-pager 2>/dev/null | sed -n '1,40p'
}

# ----------------------------------------------------------------------
# 函数:run_action
# 功能:根据传入的操作名分派到对应处理函数；支持 -h/--help 与 --version
# 参数:$1 - 操作名（缺省为 info）
# 返回值:0 表示成功；1 表示未知操作（die 退出）
# ----------------------------------------------------------------------
run_action() {
  case "${1:-info}" in
    info|status) do_info ;;
    update) do_update_hint ;;
    clean) do_clean_hint ;;
    time|date) do_time ;;
    users|who) do_users ;;
    time-users|time_users|date-users|date_users) do_time_users ;;
    services|service) do_services ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
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
  while true; do
    printf "\n请选择系统操作：\n"
    printf "  1. 查看系统信息\n"
    printf "  2. 查看更新命令\n"
    printf "  3. 查看清理命令\n"
    printf "  4. 查看时间和时区\n"
    printf "  5. 查看登录用户\n"
    printf "  6. 查看运行服务\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号： " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) do_info ;;
      2) do_update_hint ;;
      3) do_clean_hint ;;
      4) do_time ;;
      5) do_users ;;
      6) do_services ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入，请重新输入。" ;;
      *) log_warn "无效输入，请输入 1-6 或 b 返回。" ;;
    esac
  done
}

# ----------------------------------------------------------------------
# 函数:main
# 功能:脚本入口，根据参数决定直接执行操作或进入交互菜单
# 参数:$@ - 命令行参数
# 返回值:随分派函数返回
# ----------------------------------------------------------------------
main() {
  print_banner
  if (($# > 0)); then
    run_action "$1"
  else
    interactive_loop
  fi
}

main "$@"
