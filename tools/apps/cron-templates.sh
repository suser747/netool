#!/usr/bin/env bash
# netool - 常用定时任务模板
set -Eeuo pipefail

SCRIPT_NAME="cron-templates"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

CRON_DIR="/etc/cron.d"

usage() {
  cat <<EOF
netool | 定时任务模板 v${SCRIPT_VERSION}

用法:
  cron-templates list
  cron-templates show <id>
  cron-templates install <id> [--plan]

模板 id: cert-renew | disk-alert | log-truncate

说明: install 默认 --plan 预览；实际写入须 root 且确认。
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | 定时模板 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

template_body() {
  case "$1" in
    cert-renew)
      cat <<'EOF'
# netool: certbot 续期 (每月 1 日 3:00)
0 3 1 * * root certbot renew --quiet --deploy-hook "systemctl reload nginx 2>/dev/null || systemctl reload apache2 2>/dev/null || true"
EOF
      ;;
    disk-alert)
      cat <<'EOF'
# netool: 根分区 >85% 写 syslog
0 * * * * root df / /home 2>/dev/null | awk 'NR>1 {gsub(/%/,"",$5); if($5+0>=85) print "netool-disk-alert "$6" "$5"% used"}' | logger -t netool
EOF
      ;;
    log-truncate)
      cat <<'EOF'
# netool: 压缩 7 天前 nginx 日志 (示例路径)
0 2 * * * root find /var/log/nginx -name '*.log' -mtime +7 -exec gzip {} \; 2>/dev/null
EOF
      ;;
    *) return 1 ;;
  esac
}

template_desc() {
  case "$1" in
    cert-renew) printf "Certbot 证书续期 + reload Web 服务\n" ;;
    disk-alert) printf "磁盘使用率 >=85%% 时写 syslog\n" ;;
    log-truncate) printf "压缩 7 天前 nginx 日志\n" ;;
    *) printf "未知\n" ;;
  esac
}

do_list() {
  printf "\n%s可用模板:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local id
  for id in cert-renew disk-alert log-truncate; do
    printf "  %-14s %s" "$id" "$(template_desc "$id")"
    printf "\n"
  done
}

do_show() {
  local id="${1:-}"
  template_body "$id" >/dev/null || die "未知模板：$id"
  printf "\n%s模板 %s:%s\n" "$COLOR_BOLD" "$id" "$COLOR_RESET"
  template_desc "$id"
  printf "\n--- 内容预览 ---\n"
  template_body "$id"
}

do_install() {
  local id="${1:-}"
  local flag="${2:-}"
  template_body "$id" >/dev/null || die "未知模板：$id"

  local dest="${CRON_DIR}/netool-${id}"
  printf "\n将写入: %s\n\n" "$dest"
  template_body "$id"

  if [[ "$flag" == --plan ]]; then
    log_info "预览模式，未写入。安装: sudo ./main.sh cron-templates install $id"
    return 0
  fi

  require_root
  confirm_default_no "确认安装模板 ${id} 到 ${dest}?" || { log_info "已取消"; return 0; }

  local tmp
  tmp="$(mktemp)"
  template_body "$id" >"$tmp"
  chmod 644 "$tmp"
  cp "$tmp" "$dest"
  rm -f "$tmp"
  log_success "已安装：$dest"
}

run_action() {
  case "${1:-list}" in
    list) do_list ;;
    show) do_show "${2:-}" ;;
    install) do_install "${2:-}" "${3:-}" "${4:-}" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer="" id=""
  while true; do
    printf "\n定时模板:\n  1. 列出模板\n  2. 预览 cert-renew\n  3. 预览 disk-alert\n  4. 预览 log-truncate\n  b. 返回\n"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || return 1
    case "$answer" in
      1) do_list ;;
      2) do_show cert-renew ;;
      3) do_show disk-alert ;;
      4) do_show log-truncate ;;
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
