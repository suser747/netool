#!/usr/bin/env bash
# netool - Web 服务器配置检查 (Nginx / Apache / Caddy)
set -Eeuo pipefail

SCRIPT_NAME="web-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：./main.sh web
#   远程：bash <(curl -fsSL …/main.sh) web
#   直接：bash tools/apps/web.sh [status|check nginx|…]
# -----------------------------------------------------------------------------

usage() {
  cat <<EOF
netool | Web 服务器工具 v${SCRIPT_VERSION}

用法: web [操作] [参数]

操作:
  status              检测 Nginx/Apache/Caddy 安装与运行状态
  check nginx         Nginx 配置语法与概要
  check apache        Apache 配置语法与 VirtualHost 概要
  check caddy         Caddyfile 路径与概要
  list-sites          列出站点配置目录
  security-scan       只读安全项检查（版本泄露、HTTP 监听等）

说明: 只读检查，不修改配置。
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | Web 服务器 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

_svc_active() {
  local u="$1"
  systemctl is-active "$u" 2>/dev/null || echo unknown
}

do_status() {
  printf "\n%sWeb 服务状态:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local svc
  for svc in nginx apache2 httpd caddy; do
    if command_exists "$svc" || systemctl list-unit-files "${svc}.service" &>/dev/null; then
      printf "  %-10s 命令:%s  服务:%s\n" "$svc" \
        "$(command_exists "$svc" && echo 有 || echo 无)" \
        "$(_svc_active "$svc")"
    fi
  done
  printf "\n常见配置路径:\n"
  local p
  for p in /etc/nginx/nginx.conf /etc/apache2/apache2.conf /etc/httpd/conf/httpd.conf /etc/caddy/Caddyfile; do
    [[ -f "$p" ]] && printf "  [存在] %s\n" "$p" || true
  done
}

do_check_nginx() {
  printf "\n%sNginx 检查:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  command_exists nginx || { log_warn "未安装 nginx"; return 0; }
  if nginx -t 2>&1 | sed 's/^/  /'; then
    log_success "nginx -t 通过"
  else
    log_warn "nginx -t 未通过或无权限"
  fi
  if nginx -T 2>/dev/null | grep -E '^\s*server_name|listen ' | head -n 20 | sed 's/^/  /'; then
    :
  else
    log_info "无法 dump 完整配置（可能需要 root）"
  fi
}

do_check_apache() {
  printf "\n%sApache 检查:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local ctl=""
  for ctl in apache2ctl apachectl httpd; do
    command_exists "$ctl" && break
  done
  [[ -n "$ctl" ]] || { log_warn "未找到 apache2ctl/apachectl/httpd"; return 0; }
  "$ctl" configtest 2>&1 | sed 's/^/  /' || true
  "$ctl" -S 2>/dev/null | head -n 25 | sed 's/^/  /' || log_info "apache -S 需要 root"
}

do_check_caddy() {
  printf "\n%sCaddy 检查:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  command_exists caddy || { log_warn "未安装 caddy"; return 0; }
  local cf="/etc/caddy/Caddyfile"
  [[ -f "$cf" ]] || cf="$(find /etc /opt -maxdepth 3 -name Caddyfile 2>/dev/null | head -n1)"
  if [[ -n "$cf" && -f "$cf" ]]; then
    printf "  Caddyfile: %s\n" "$cf"
    caddy validate --config "$cf" 2>&1 | sed 's/^/  /' || true
    grep -E '^\s*(reverse_proxy|root|file_server|tls)' "$cf" 2>/dev/null | head -n 15 | sed 's/^/  /' || true
  else
    log_warn "未找到 Caddyfile"
  fi
}

do_list_sites() {
  printf "\n%s站点配置:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local d
  for d in /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/apache2/sites-enabled /etc/httpd/conf.d; do
    [[ -d "$d" ]] || continue
    printf "  [%s]\n" "$d"
    ls -1 "$d" 2>/dev/null | sed 's/^/    /' || true
  done
}

do_security_scan() {
  printf "\n%sWeb 安全只读扫描:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  if command_exists nginx && [[ -r /etc/nginx/nginx.conf ]]; then
    grep -q 'server_tokens off' /etc/nginx/nginx.conf 2>/dev/null \
      && printf "  nginx: server_tokens off 已配置\n" \
      || printf "  %snginx: 建议设置 server_tokens off%s\n" "$COLOR_YELLOW" "$COLOR_RESET"
  fi
  if command_exists ss; then
    printf "  监听 80/443:\n"
    ss -tlnp 2>/dev/null | grep -E ':80 |:443 ' | sed 's/^/    /' || printf "    (无或未检测到)\n"
  fi
}

run_action() {
  case "${1:-status}" in
    status) do_status ;;
    check)
      case "${2:-}" in
        nginx) do_check_nginx ;;
        apache|httpd) do_check_apache ;;
        caddy) do_check_caddy ;;
        *) die "用法: web check nginx|apache|caddy" ;;
      esac
      ;;
    list-sites|sites) do_list_sites ;;
    security-scan|security) do_security_scan ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer=""
  while true; do
    printf "\nWeb 服务器:\n"
    printf "  1. 服务状态\n  2. 检查 Nginx\n  3. 检查 Apache\n  4. 检查 Caddy\n"
    printf "  5. 列出站点\n  6. 安全扫描\n  b. 返回\n"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || { log_error "无法读取输入"; return 1; }
    case "$answer" in
      1) do_status ;;
      2) do_check_nginx ;;
      3) do_check_apache ;;
      4) do_check_caddy ;;
      5) do_list_sites ;;
      6) do_security_scan ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未输入" ;;
      *) log_warn "无效输入" ;;
    esac
  done
}

main() {
  print_banner
  (($# > 0)) && run_action "$@" || interactive_loop
}

main "$@"
