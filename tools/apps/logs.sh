#!/usr/bin/env bash
# netool - 日志与监控查看
set -Eeuo pipefail

SCRIPT_NAME="logs-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

usage() {
  cat <<EOF
netool | 日志与监控 v${SCRIPT_VERSION}

用法:
  logs usage              journald /var/log / docker 占用概览
  logs tail-errors [源]   最近 ERROR (syslog|nginx|journal，默认 journal)
  logs monitor            检测常见监控 agent
  logs rotate-hint        logrotate 配置提示

说明: 查看与建议，清理请用 logclean 工具。
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | 日志监控 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

do_usage() {
  printf "\n%s日志占用:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  if command_exists journalctl; then
    printf "  journald:\n"
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /' || true
  fi
  if [[ -d /var/log ]]; then
    printf "  /var/log 合计:\n"
    du -sh /var/log 2>/dev/null | sed 's/^/    /' || true
    du -sh /var/log/* 2>/dev/null | sort -hr | head -n 8 | sed 's/^/    /' || true
  fi
  if command_exists docker && docker info &>/dev/null; then
    printf "  Docker 容器日志 (top):\n"
    find /var/lib/docker/containers -name '*-json.log' 2>/dev/null | while read -r f; do
      du -sh "$f" 2>/dev/null
    done | sort -hr | head -n 5 | sed 's/^/    /' || true
  fi
}

do_tail_errors() {
  local src="${1:-journal}"
  printf "\n%s最近 ERROR (%s):%s\n" "$COLOR_BOLD" "$src" "$COLOR_RESET"
  case "$src" in
    journal|journald)
      journalctl -p err -n 20 --no-pager 2>/dev/null | sed 's/^/  /' || log_warn "journalctl 不可用"
      ;;
    nginx)
      local f="/var/log/nginx/error.log"
      [[ -r "$f" ]] && tail -n 20 "$f" | sed 's/^/  /' || log_warn "无法读 $f"
      ;;
    syslog|messages)
      local f="/var/log/syslog"
      [[ -r "$f" ]] || f="/var/log/messages"
      [[ -r "$f" ]] && grep -i error "$f" 2>/dev/null | tail -n 15 | sed 's/^/  /' || log_warn "无法读 syslog"
      ;;
    *) die "未知源：$src (journal|nginx|syslog)" ;;
  esac
}

do_monitor() {
  printf "\n%s监控组件:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  _mon_one() {
    local label="$1"
    shift
    local ok=0 b st
    for b in "$@"; do command_exists "$b" && ok=1; done
    if (( ok )); then st="已安装"; else st="未检测到"; fi
    printf "  %-18s %s\n" "$label" "$st"
  }
  _mon_one node_exporter node_exporter
  _mon_one prometheus prometheus
  _mon_one zabbix_agent zabbix_agentd zabbix_agent2
  _mon_one grafana grafana-server
  _mon_one telegraf telegraf
}

do_rotate_hint() {
  printf "\n%slogrotate:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  [[ -d /etc/logrotate.d ]] && ls -1 /etc/logrotate.d 2>/dev/null | head -n 15 | sed 's/^/  /' || true
  printf "\n建议: 大日志优先 logrotate 配置；Docker 可配置 json-file max-size。\n"
  printf "清理执行请使用: ./main.sh logclean\n"
}

run_action() {
  case "${1:-usage}" in
    usage|disk) do_usage ;;
    tail-errors|errors) do_tail_errors "${2:-journal}" ;;
    monitor|mon) do_monitor ;;
    rotate-hint|rotate) do_rotate_hint ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer=""
  while true; do
    printf "\n日志与监控:\n  1. 占用概览\n  2. 最近 ERROR (journal)\n  3. Nginx 错误\n  4. 监控 agent\n  5. logrotate 提示\n  b. 返回\n"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || return 1
    case "$answer" in
      1) do_usage ;;
      2) do_tail_errors journal ;;
      3) do_tail_errors nginx ;;
      4) do_monitor ;;
      5) do_rotate_hint ;;
      b|B|back|返回) return 0 ;;
      *) log_warn "无效输入" ;;
    esac
  done
}

main() {
  print_banner
  (($# > 0)) && run_action "$@" || interactive_loop
}

main "$@"
