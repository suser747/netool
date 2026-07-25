#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 网络信息查看与连通性测试
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: network.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   提供网络信息查看(IP 地址、路由、监听端口)与连通性测试
#   (Ping、DNS 解析)。支持命令行参数与交互式菜单两种使用方式,
#   仅做低风险查看与连通性测试,不修改任何系统配置。
#
# 使用方式:
#   network            直接执行进入交互菜单
#   network ip         查看 IP 地址
#   network ping 8.8.8.8   对指定主机执行 Ping 测试
#   network dns example.com  对指定域名执行 DNS 解析
#   network -h         显示帮助
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="network-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR


# ------------------------------------------------------------------------------
# 函数: check_ip_command
# 功能: 检测 ip 命令是否可用,不可用时给出降级使用 ifconfig/route 的提示
# 参数: 无
# 返回值: 0 - 始终成功(仅提示,不阻断执行)
# ------------------------------------------------------------------------------
check_ip_command() {
  if ! command_exists ip; then
    log_warn "未检测到 ip 命令,将降级使用 ifconfig/route(信息可能不全)。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 网络工具 v${SCRIPT_VERSION}

用法:
  network [操作] [参数]

操作:
  info            查看网络信息(默认)
  ip              查看 IP 地址
  route           查看路由
  ports           查看监听端口
  ping [host]     Ping 连通性测试,默认 223.5.5.5
  dns [domain]    DNS 解析测试,默认 example.com

说明:
  当前模块只做低风险查看和连通性测试。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅; 作为子模块被调用时静默跳过
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 网络工具 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: do_ip
# 功能: 显示本机 IP 地址与公网 IP 地址
# 参数: 无
# 返回值: 0 - 始终成功(查询失败时输出提示但不报错)
# ------------------------------------------------------------------------------
do_ip() {
  printf "\nIP 地址:\n"
  if command_exists ip; then
    ip -brief addr 2>/dev/null | sed 's/^/  /'
  else
    ifconfig 2>/dev/null | sed 's/^/  /' || true
  fi
  printf "\n公网 IP:\n"
  if command_exists curl; then
    curl -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null | sed 's/^/  /' || printf "  查询失败\n"
    printf "\n"
  else
    printf "  缺少 curl\n"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_route
# 功能: 显示系统路由表
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
do_route() {
  printf "\n路由:\n"
  if command_exists ip; then
    ip route 2>/dev/null | sed 's/^/  /'
  else
    route -n 2>/dev/null | sed 's/^/  /' || true
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_ports
# 功能: 显示系统监听端口列表,优先使用 ss,回退 netstat
# 参数: 无
# 返回值: 0 - 始终成功(命令缺失或失败时输出警告)
# ------------------------------------------------------------------------------
do_ports() {
  printf "\n监听端口:\n"
  if command_exists ss; then
    ss -tulpen 2>/dev/null | sed -n '1,60p' || log_warn "ss 执行失败,无法列出监听端口。"
  elif command_exists netstat; then
    netstat -tulpen 2>/dev/null | sed -n '1,60p' || log_warn "netstat 执行失败,无法列出监听端口。"
  else
    log_warn "缺少 ss 或 netstat,无法列出监听端口。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_ping
# 功能: 对指定主机执行 4 次 Ping 连通性测试
# 参数: $1 - 目标主机地址(可选,默认 223.5.5.5)
# 返回值: 0 - 成功, 非 0 - ping 命令返回非零退出码
# ------------------------------------------------------------------------------
do_ping() {
  local host="${1:-223.5.5.5}"
  printf "\nPing: %s\n" "$host"
  ping -c 4 "$host"
}

# ------------------------------------------------------------------------------
# 函数: do_dns
# 功能: 对指定域名执行 DNS 解析,按 dig > nslookup > getent 顺序回退
# 参数: $1 - 待解析域名(可选,默认 example.com)
# 返回值: 0 - 成功, 1 - 缺少所有解析工具
# ------------------------------------------------------------------------------
do_dns() {
  local domain="${1:-example.com}"
  printf "\nDNS: %s\n" "$domain"
  if command_exists dig; then
    dig +short "$domain"
  elif command_exists nslookup; then
    nslookup "$domain"
  elif command_exists getent; then
    getent hosts "$domain"
  else
    die "缺少 dig/nslookup/getent"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_info
# 功能: 依次输出 IP 地址、路由、监听端口等综合网络信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
do_info() {
  do_ip
  do_route
  do_ports
}

# ------------------------------------------------------------------------------
# 函数: run_action
# 功能: 根据传入的操作名分发到对应处理函数
# 参数: $1 - 操作名, $2 - 操作参数
# 返回值: 0 - 成功, 1 - 未知操作
# ------------------------------------------------------------------------------
run_action() {
  local action="${1:-info}"
  shift || true
  case "$action" in
    info|status) do_info ;;
    ip|addr) do_ip ;;
    route|gateway) do_route ;;
    ports|port|listen) do_ports ;;
    ping) do_ping "${1:-223.5.5.5}" ;;
    dns|resolve) do_dns "${1:-example.com}" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作:$action" ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: interactive_loop
# 功能: 交互式菜单循环,等待用户选择网络操作直至返回
# 参数: 无
# 返回值: 0 - 用户选择返回, 1 - 无法读取输入
# ------------------------------------------------------------------------------
interactive_loop() {
  local answer=""
  while true; do
    printf "\n请选择网络操作:\n"
    printf "  1. 查看网络信息\n"
    printf "  2. 查看 IP 地址\n"
    printf "  3. 查看路由\n"
    printf "  4. 查看监听端口\n"
    printf "  5. Ping 测试\n"
    printf "  6. DNS 解析测试\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号: " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) do_info ;;
      2) do_ip ;;
      3) do_route ;;
      4) do_ports ;;
      5) do_ping ;;
      6) do_dns ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入,请重新输入。" ;;
      *) log_warn "无效输入,请输入 1-6 或 b 返回。" ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本入口,打印横幅后根据是否带参数选择命令行模式或交互模式
# 参数: $@ - 全部命令行参数
# 返回值: 0 - 成功, 非 0 - 子函数错误码
# ------------------------------------------------------------------------------
main() {
  print_banner
  check_ip_command
  if (($# > 0)); then
    run_action "$@"
  else
    interactive_loop
  fi
}

main "$@"
