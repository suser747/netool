#!/usr/bin/env bash
# netool懒人工具箱 - 服务器初始化向导
set -Eeuo pipefail

SCRIPT_NAME="server-init"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

NETOOL_ENTRY_URL="${NETOOL_ENTRY_URL:-${NETOOL_RAW_BASE}/main.sh}"

confirm_default_no() {
  local reply=""
  if ! read_prompt "(y/n) [默认: n]: " reply; then reply="n"; fi
  reply="${reply:-n}"
  case "$(tolower "$reply")" in
    y|yes|是|确认) return 0 ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<EOF
netool懒人工具箱 | 服务器初始化向导 v${SCRIPT_VERSION}

用法：
  init [选项]

选项：
  -h, --help    显示帮助
  --version     显示版本
EOF
}

print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  print_divider
  printf "netool懒人工具箱 | 服务器初始化向导 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

resolve_main_sh() {
  local here root
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  root="$(cd "${here}/../.." && pwd)"
  if [[ -f "${root}/main.sh" ]]; then
    printf '%s' "${root}/main.sh"
    return 0
  fi
  return 1
}

run_tool() {
  local tool="$1"
  shift || true
  local main_sh="${NETOOL_MAIN_SH:-}"

  if [[ -z "$main_sh" ]]; then
    main_sh="$(resolve_main_sh 2>/dev/null || true)"
  fi

  local rc=0
  if [[ -n "${NETOOL_REMOTE:-}" && -n "${NETOOL_ENTRY_URL:-}" ]] && command_exists curl; then
    bash <(curl -fsSL "${NETOOL_ENTRY_URL}") "$tool" "$@" || rc=$?
  elif [[ -n "$main_sh" && -f "$main_sh" ]]; then
    bash "$main_sh" "$tool" "$@" || rc=$?
  else
    log_warn "未找到 main.sh，跳过：${tool}"
    return 0
  fi

  if (( rc != 0 )); then
    log_warn "子工具 ${tool} 执行失败（退出码 ${rc}）"
    if [[ "${YES:-0}" != "1" ]]; then
      log_info "是否继续执行下一步？"
      confirm_default_no || return 1
    fi
  fi
  return 0
}

yes_answer() {
  case "$(tolower "$1")" in
    y|yes|是|确认) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
  esac

  print_banner
  audit_log "init_wizard" "start"

  printf "\n%s=== 服务器初始化向导 ===%s\n" "$COLOR_GREEN" "$COLOR_RESET"
  printf "将按步骤引导配置，可随时退出。\n\n"

  local go=""
  if ! read_prompt "是否开始初始化向导？(y/n) [默认: n]: " go; then exit 1; fi
  go="${go:-n}"
  yes_answer "$go" || { log_info "已取消。"; exit 0; }

  printf "\n%s--- 第 1/8 步：系统信息 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
  run_tool system info || exit 1

  printf "\n%s--- 第 2/8 步：功能检查 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
  run_tool check || exit 1

  local step="" choice="" inst="" bbr_go="" dk=""
  if ! read_prompt "是否切换软件源？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 3 步：软件源切换 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    if ! read_prompt "请选择 (mirror/lmirrors/n) [默认: mirror]: " choice; then choice="mirror"; fi
    case "$(tolower "${choice:-mirror}")" in
      lmirrors|全能) run_tool lmirrors || exit 1 ;;
      n|no|否|不) log_info "已跳过。" ;;
      *) run_tool mirror || exit 1 ;;
    esac
  fi

  if ! read_prompt "是否安装基础工具？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 4 步：基础工具安装 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool basic --plan || exit 1
    if ! read_prompt "确认执行安装？(y/n) [默认: n]: " inst; then inst="n"; fi
    if yes_answer "${inst:-n}"; then
      run_tool basic -y || exit 1
      audit_log "init_wizard" "basic_install done"
    fi
  fi

  if ! read_prompt "是否启用 BBR？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 5 步：BBR 网络优化 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool bbr status || exit 1
    if ! read_prompt "确认启用 BBR？(y/n) [默认: n]: " bbr_go; then bbr_go="n"; fi
    if yes_answer "${bbr_go:-n}"; then
      run_tool bbr enable -y || exit 1
      audit_log "init_wizard" "bbr_enable done"
    fi
  fi

  if ! read_prompt "是否设置主机名/时区？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 6 步：主机名/时区 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool host || exit 1
    audit_log "init_wizard" "host done"
  fi

  if ! read_prompt "是否修改 SSH 端口？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 7 步：SSH 端口管理 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool ssh || exit 1
    audit_log "init_wizard" "ssh done"
  fi

  if ! read_prompt "是否安装 Docker？(y/n) [默认: n]: " step; then step="n"; fi
  if yes_answer "${step:-n}"; then
    printf "\n%s--- 第 8 步：Docker 安装 ---%s\n" "$COLOR_BLUE" "$COLOR_RESET"
    run_tool docker install --plan || exit 1
    if ! read_prompt "确认安装 Docker？(y/n) [默认: n]: " dk; then dk="n"; fi
    if yes_answer "${dk:-n}"; then
      run_tool docker install -y || exit 1
      audit_log "init_wizard" "docker_install done"
    fi
  fi

  printf "\n%s=== 初始化向导完成 ===%s\n" "$COLOR_GREEN" "$COLOR_RESET"
  log_success "服务器初始化向导已完成。"
  audit_log "init_wizard" "complete"
}

main "$@"
