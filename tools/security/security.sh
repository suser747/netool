#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - Fail2ban SSH 防护
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: security-tools
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Fail2ban 服务及其 SSH 防护配置，支持查看状态、安装与启用 SSH 防护。
#   启用 SSH 防护时会写入 /etc/fail2ban/jail.d/netool-sshd.conf，
#   若该文件已存在则先按时间戳备份（jail.d/netool-sshd.conf.bak.<时间戳>），
#   确保后续可手动回滚。
#   默认规则: maxretry=5，findtime=10m，bantime=1h，仅保护 sshd jail。
#   该工具不修改 SSH 端口，不删除已有 Fail2ban 配置。
#
# 使用方式:
#   bash security.sh status        # 查看 Fail2ban 状态（默认）
#   bash security.sh install       # 安装 Fail2ban（支持 --plan 预览）
#   bash security.sh enable-ssh    # 写入保守 SSH 防护配置并启用服务
#   bash security.sh --plan        # 预览模式，不执行安装或配置
#   bash security.sh -y            # 跳过确认
#   bash security.sh -h            # 显示帮助
#   bash security.sh --version     # 显示版本
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="security-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh security
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) security
#   直接：bash tools/security/security.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

YES=0
DRY_RUN=0
# 本工具写入的 sshd jail 配置路径
JAIL_FILE="/etc/fail2ban/jail.d/netool-sshd.conf"



# ------------------------------------------------------------------------------
# 函数: confirm
# 功能: 询问用户是否确认执行；YES=1 时跳过交互
# 参数: $1 - 提示文本
# 返回值: 0 表示确认；非 0 表示取消或读取失败
# ------------------------------------------------------------------------------
confirm() {
  local prompt="$1"
  local answer=""
  if ((YES)); then return 0; fi
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息到标准输出
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | Fail2ban SSH 防护 v${SCRIPT_VERSION}

用法:
  security [操作] [选项]

操作:
  status       查看 Fail2ban 状态（默认）
  install      安装 Fail2ban，支持 --plan 预览
  enable-ssh   写入保守 SSH 防护配置并启用服务

选项:
  --plan        只显示计划，不执行安装或配置
  -y, --yes     不再询问
  -h, --help    显示帮助
  --version     显示版本

说明:
  enable-ssh 默认规则: maxretry=5，findtime=10m，bantime=1h，只保护 sshd jail。
  该工具不修改 SSH 端口，不删除已有 Fail2ban 配置。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅；被 NETOOL 主入口调用时不打印，便于工具箱统一收口
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | Fail2ban SSH 防护 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: detect_manager
# 功能: 检测当前系统可用的包管理器名称
# 参数: 无
# 返回值: 通过 stdout 输出 apt/dnf/yum/apk/pacman/zypper 之一；无法识别时输出 unknown
# ------------------------------------------------------------------------------
detect_manager() {
  if command_exists apt-get; then
    printf "apt"
  elif command_exists dnf; then
    printf "dnf"
  elif command_exists yum; then
    printf "yum"
  elif command_exists apk; then
    printf "apk"
  elif command_exists pacman; then
    printf "pacman"
  elif command_exists zypper; then
    printf "zypper"
  else
    printf "unknown"
  fi
}

# ------------------------------------------------------------------------------
# 函数: install_plan
# 功能: 打印 Fail2ban 安装计划（按包管理器给出建议命令），主要用于 --plan 预览
# 参数: $1 - 包管理器名称
# 返回值: 始终 0
# ------------------------------------------------------------------------------
install_plan() {
  local manager="$1"
  printf "\nFail2ban 安装计划:\n"
  printf "  包管理器: %s\n" "$manager"
  printf "\n建议命令:\n"
  case "$manager" in
    apt) printf "  apt-get update && apt-get install -y fail2ban\n" ;;
    dnf) printf "  dnf install -y fail2ban\n" ;;
    yum) printf "  yum install -y fail2ban\n" ;;
    apk) printf "  apk add fail2ban\n" ;;
    pacman) printf "  pacman -Sy --needed fail2ban\n" ;;
    zypper) printf "  zypper install -y fail2ban\n" ;;
    *) log_warn "未识别包管理器，无法生成安装命令。" ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: do_status
# 功能: 查看 Fail2ban 服务状态、sshd jail 状态，并打印本工具写入的配置文件内容
# 参数: 无
# 返回值: 始终 0；fail2ban-client 不存在时仅给出提示
# ------------------------------------------------------------------------------
do_status() {
  local jail_output=""

  printf "\nFail2ban 状态:\n"
  if ! command_exists fail2ban-client; then
    log_warn "未安装 fail2ban-client。可执行: security install --plan"
    return 0
  fi

  fail2ban-client version 2>/dev/null | sed 's/^/  version: /' || true
  fail2ban-client status 2>/dev/null | sed 's/^/  /' || true

  printf "\nSSHD Jail:\n"
  if jail_output="$(fail2ban-client status sshd 2>&1)"; then
    printf "%s\n" "$jail_output" | sed 's/^/  /'
  else
    printf "%s\n" "$jail_output" | sed 's/^/  /'
    log_warn "未检测到 sshd jail 正在运行。"
  fi

  if [[ -f "$JAIL_FILE" ]]; then
    printf "\nnetool配置: %s\n" "$JAIL_FILE"
    sed -n '1,80p' "$JAIL_FILE" | sed 's/^/  /'
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_install
# 功能: 安装 Fail2ban: 调用包管理器安装后尝试 enable + start
# 参数: 无
# 返回值: 始终 0（用户取消或服务异常时仅打印警告）
# ------------------------------------------------------------------------------
do_install() {
  local manager=""
  manager="$(detect_manager)"
  install_plan "$manager"

  if ((DRY_RUN)); then
    return 0
  fi

  [[ "$manager" != "unknown" ]] || die "未识别包管理器。"
  require_root
  if ! confirm "确认安装 Fail2ban?"; then
    log_warn "已取消。"
    return 0
  fi

  case "$manager" in
    apt) apt-get update && apt-get install -y fail2ban ;;
    dnf) dnf install -y fail2ban ;;
    yum) yum install -y fail2ban ;;
    apk) apk add fail2ban ;;
    pacman) pacman -Sy --needed fail2ban ;;
    zypper) zypper install -y fail2ban ;;
  esac

  # 优先使用 systemd；缺失时回退到 SysV service
  if command_exists systemctl; then
    if ! systemctl enable --now fail2ban 2>/dev/null; then
      log_warn "systemctl enable --now fail2ban 失败，请手动检查服务状态。"
    fi
  elif command_exists service; then
    if ! service fail2ban start 2>/dev/null; then
      log_warn "service fail2ban start 失败，请手动检查服务状态。"
    fi
  fi
  log_success "Fail2ban 安装流程完成。"
}

# ------------------------------------------------------------------------------
# 函数: print_ssh_jail_config
# 功能: 输出 sshd jail 的保守配置内容到 stdout
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
print_ssh_jail_config() {
  cat <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
}

# ------------------------------------------------------------------------------
# 函数: enable_ssh
# 功能: 写入 sshd jail 配置并启用 Fail2ban SSH 防护
# 参数: 无
# 返回值: 0 表示成功；非 0 表示取消或缺少 fail2ban-client
# 副作用: 若 JAIL_FILE 已存在，先按时间戳备份（jail.d/netool-sshd.conf.bak.<时间戳>）
# ------------------------------------------------------------------------------
enable_ssh() {
  printf "\nFail2ban SSH 防护配置计划:\n"
  printf "  配置文件: %s\n" "$JAIL_FILE"
  printf "  规则: 5 次失败 / 10 分钟，封禁 1 小时\n"
  printf "  范围: 只启用 sshd jail，不修改 SSH 端口\n"
  printf "\n将写入内容:\n"
  print_ssh_jail_config | sed 's/^/  /'

  if ((DRY_RUN)); then
    return 0
  fi

  command_exists fail2ban-client || die "未安装 fail2ban-client。请先执行 security install。"
  require_root
  if ! confirm "确认写入并启用 Fail2ban SSH 防护?"; then
    log_warn "已取消。"
    return 0
  fi

  # 确保父目录存在；若已有 jail 配置则先备份再覆盖，便于手动回滚
  mkdir -p "$(dirname "$JAIL_FILE")"
  if [[ -f "$JAIL_FILE" ]]; then
    # 时间戳格式与 common.sh 的 timestamp() 保持一致: YYYYMMDD_HHMMSS
    # 只取一次时间戳，避免日志与实际文件名在秒切换边界不一致
    local backup_ts
    backup_ts="$(date +%Y%m%d_%H%M%S)"
    cp "$JAIL_FILE" "${JAIL_FILE}.bak.${backup_ts}"
    log_info "已备份原 jail 配置: ${JAIL_FILE}.bak.${backup_ts}"
  fi
  print_ssh_jail_config >"$JAIL_FILE"

  # 启用并重启 Fail2ban 服务，使新规则立即生效
  if command_exists systemctl; then
    if ! systemctl enable --now fail2ban 2>/dev/null; then
      log_warn "systemctl enable --now fail2ban 失败，请手动检查服务状态。"
    fi
    if ! systemctl restart fail2ban 2>/dev/null; then
      log_warn "systemctl restart fail2ban 失败，请手动检查服务状态。"
    fi
  elif command_exists service; then
    if ! service fail2ban restart 2>/dev/null && ! service fail2ban start 2>/dev/null; then
      log_warn "service fail2ban restart/start 失败，请手动检查服务状态。"
    fi
  fi
  if ! fail2ban-client reload 2>/dev/null; then
    log_warn "fail2ban-client reload 失败，规则可能未生效。"
  fi

  log_success "Fail2ban SSH 防护已配置。"
  do_status
}

# ------------------------------------------------------------------------------
# 函数: run_action
# 功能: 根据操作名分发到对应子命令
# 参数: $1 - 操作名；后续参数透传给子命令
# 返回值: 透传子命令的退出码；未知操作 die
# ------------------------------------------------------------------------------
run_action() {
  local action="${1:-status}"
  shift || true

  case "$action" in
    status|info) do_status ;;
    install|setup) do_install ;;
    enable-ssh|ssh|sshd) enable_ssh ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作: $action" ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: interactive_loop
# 功能: 交互式菜单: 循环展示 Fail2ban 状态/预览安装/安装/启用 SSH 防护，直到用户返回
# 参数: 无
# 返回值: 始终 0（用户选择返回时）；无法读取输入时返回 1
# ------------------------------------------------------------------------------
interactive_loop() {
  local answer=""
  while true; do
    printf "\n请选择安全防护操作:\n"
    printf "  1. 查看 Fail2ban 状态\n"
    printf "  2. 预览安装命令\n"
    printf "  3. 安装 Fail2ban\n"
    printf "  4. 启用 SSH 防护\n"
    printf "  b. 返回\n"
    print_menu_nav_hint
    if ! read_prompt "输入编号: " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) do_status ;;
      2) DRY_RUN=1; do_install; DRY_RUN=0 ;;
      3) do_install ;;
      4) enable_ssh ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入，请重新输入。" ;;
      *) log_warn "无效输入，请输入 1-4 或 b 返回。" ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本入口: 加载公共函数库、获取互斥锁、解析参数并分发到对应子命令或交互菜单
# 参数: $@ - 命令行参数
# 返回值: 透传子命令的退出码
# ------------------------------------------------------------------------------
main() {
  netool_acquire_lock "security" "另一个 security 实例正在运行，请等待其完成后再试。" || return 1
  print_banner

  local args=()
  # 先剥离全局选项，剩余位置参数作为操作名/操作参数
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
