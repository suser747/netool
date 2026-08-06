#!/usr/bin/env bash
# netool - 应用配置文件扫描
set -Eeuo pipefail

SCRIPT_NAME="app-config"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

SCAN_ROOT="${SCAN_ROOT:-/opt}"

usage() {
  cat <<EOF
netool | 应用配置扫描 v${SCRIPT_VERSION}

用法:
  app-config scan [--path DIR]     扫描 Compose/.env/Supervisor/systemd
  app-config secrets-audit         检查 .env 等文件权限过宽

环境变量: SCAN_ROOT 默认 /opt
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | 应用配置 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

do_scan() {
  local root="${1:-$SCAN_ROOT}"
  printf "\n%s扫描路径: %s%s\n" "$COLOR_BOLD" "$root" "$COLOR_RESET"

  printf "\nDocker Compose:\n"
  find "$root" /srv /home -maxdepth 4 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' \) 2>/dev/null \
    | head -n 30 | sed 's/^/  /' || printf "  (未找到)\n"

  printf "\n.env 文件 (仅路径):\n"
  find "$root" /srv /home -maxdepth 5 -name '.env' 2>/dev/null | head -n 20 | sed 's/^/  /' || printf "  (未找到)\n"

  printf "\nSupervisor:\n"
  if [[ -d /etc/supervisor/conf.d ]]; then
    ls -1 /etc/supervisor/conf.d 2>/dev/null | sed 's/^/  /' || true
  else
    printf "  未安装 supervisor\n"
  fi

  printf "\n自定义 systemd ( /etc/systemd/system/*.service 非软链):\n"
  find /etc/systemd/system -maxdepth 1 -name '*.service' ! -type l 2>/dev/null | head -n 15 | sed 's/^/  /' || true
}

_env_keys_only() {
  local f="$1"
  [[ -r "$f" ]] || return 0
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$f" 2>/dev/null | cut -d= -f1 | head -n 15 | tr '\n' ' '
  printf "\n"
}

do_secrets_audit() {
  printf "\n%s敏感文件权限审计:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local f mode
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    mode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%OLp' "$f" 2>/dev/null || echo ?)"
    if [[ "$mode" =~ ^(666|664|646|776|766|667)$ ]] || [[ "$mode" == 644 && "$f" == *".env"* ]]; then
      printf "  %s[过宽]%s %s (%s)\n" "$COLOR_YELLOW" "$COLOR_RESET" "$f" "$mode"
    fi
  done < <(find "$SCAN_ROOT" /srv /home /etc -maxdepth 5 \( -name '.env' -o -name '*.pem' -o -name 'id_rsa' \) 2>/dev/null | head -n 50)
  log_info "仅标记权限风险，不读取文件内容。"
}

run_action() {
  case "${1:-scan}" in
    scan)
      local p="$SCAN_ROOT"
      [[ "${2:-}" == --path && -n "${3:-}" ]] && p="$3"
      do_scan "$p"
      ;;
    secrets-audit|audit) do_secrets_audit ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer="" path=""
  while true; do
    printf "\n应用配置:\n  1. 扫描 (默认 %s)\n  2. 指定路径扫描\n  3. 权限审计\n  b. 返回\n" "$SCAN_ROOT"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || return 1
    case "$answer" in
      1) do_scan "$SCAN_ROOT" ;;
      2) read_prompt "路径: " path || true; do_scan "${path:-$SCAN_ROOT}" ;;
      3) do_secrets_audit ;;
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
