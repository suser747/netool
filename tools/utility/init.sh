#!/usr/bin/env bash
# =============================================================================
# netool 懒人工具箱 - 服务器初始化向导 (tools/utility/init.sh)
# =============================================================================
# 功能：新服务器分步引导（系统检查 → 换源 → 基础工具 → BBR → 主机名 → SSH → Docker）
# 调用：
#   本地：./main.sh init
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) init
# 说明：各步骤通过 run_tool 回调 main.sh；远程模式下用 NETOOL_ENTRY_URL 重新拉取 main
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="server-init"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh init
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) init
#   直接：bash tools/utility/init.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


# 远程 init 链式调用子工具时使用的 main.sh 地址（由 main.sh 注入或默认 Gitee raw）
NETOOL_ENTRY_URL="${NETOOL_ENTRY_URL:-${NETOOL_RAW_BASE}/main.sh}"

# confirm_default_no — 交互确认，默认否
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

# print_banner — 独立运行时显示横幅；由 main.sh 调用时跳过
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  print_divider
  printf "netool懒人工具箱 | 服务器初始化向导 v%s\n" "$SCRIPT_VERSION"
  print_divider
}

# resolve_main_sh — 本地部署时解析仓库根目录下的 main.sh 路径
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

# run_tool — 通过 main.sh 调用子工具；远程模式用 curl 进程替换重新执行 main
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
