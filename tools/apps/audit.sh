#!/usr/bin/env bash
# netool - 用户与权限只读审计
set -Eeuo pipefail

SCRIPT_NAME="audit-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

usage() {
  cat <<EOF
netool | 权限审计 v${SCRIPT_VERSION}

用法: audit [操作]

操作:
  users         UID 0 账户、空密码锁定状态
  sudoers       sudoers 语法检查
  ssh-keys      authorized_keys 概览
  permissions   敏感路径 world-writable 检查
  all           运行全部审计

说明: 只读，不修改系统。
EOF
}

print_banner() {
  [[ -n "${NETOOL:-}" ]] && return 0
  print_divider
  printf "netool | 权限审计 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

do_users() {
  printf "\n%s用户审计:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  printf "  UID 0 账户:\n"
  awk -F: '$3==0 {print "    "$1" (uid="$3")"}' /etc/passwd 2>/dev/null || true
  printf "  空密码字段 (!) 锁定检查:\n"
  awk -F: '($2=="" || $2=="!") {print "    "$1" shadow="$2}' /etc/shadow 2>/dev/null | head -n 10 | sed 's/^/  /' \
    || log_info "无法读 /etc/shadow（需 root）"
}

do_sudoers() {
  printf "\n%ssudoers 检查:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  if is_root_user && command_exists visudo; then
    visudo -c 2>&1 | sed 's/^/  /' || true
  elif [[ -r /etc/sudoers ]]; then
    log_warn "非 root：仅检查文件存在"
    printf "  /etc/sudoers 存在\n"
    ls -1 /etc/sudoers.d 2>/dev/null | sed 's/^/    /' || true
  else
    log_warn "无法访问 sudoers"
  fi
}

do_ssh_keys() {
  printf "\n%sSSH 密钥审计:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local cfg="/etc/ssh/sshd_config"
  if [[ -r "$cfg" ]]; then
    grep -Ei '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)' "$cfg" 2>/dev/null | sed 's/^/  /' || true
  fi
  local home u ak count
  while IFS=: read -r u _ _ _ _ home _; do
    [[ -n "$home" && -d "$home" ]] || continue
    ak="${home}/.ssh/authorized_keys"
    [[ -f "$ak" ]] || continue
    count="$(wc -l <"$ak" 2>/dev/null || echo 0)"
    printf "  %s: %s 条 key\n" "$u" "$count"
  done < /etc/passwd 2>/dev/null | head -n 15
}

do_permissions() {
  printf "\n%s敏感路径权限:%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  local p
  for p in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config; do
    [[ -e "$p" ]] || continue
    printf "  %s %s\n" "$(stat -c '%a %U:%G' "$p" 2>/dev/null || stat -f '%OLp %Su:%Sg' "$p" 2>/dev/null)" "$p"
  done
  printf "  world-writable 目录 (sample):\n"
  find /etc /var/www /opt -xdev -type d -perm -0002 2>/dev/null | head -n 10 | sed 's/^/    /' || true
}

do_all() {
  do_users
  do_sudoers
  do_ssh_keys
  do_permissions
}

run_action() {
  case "${1:-all}" in
    users|user) do_users ;;
    sudoers|sudo) do_sudoers ;;
    ssh-keys|sshkeys) do_ssh_keys ;;
    permissions|perm) do_permissions ;;
    all) do_all ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$1" ;;
  esac
}

interactive_loop() {
  local answer=""
  while true; do
    printf "\n权限审计:\n  1. 用户\n  2. sudoers\n  3. SSH 密钥\n  4. 文件权限\n  5. 全部\n  b. 返回\n"
    print_menu_nav_hint
    read_prompt "输入编号: " answer || return 1
    case "$answer" in
      1) do_users ;;
      2) do_sudoers ;;
      3) do_ssh_keys ;;
      4) do_permissions ;;
      5) do_all ;;
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
