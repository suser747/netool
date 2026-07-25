#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - BBR 网络优化脚本
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: bbr.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Linux 内核自带的 BBR 拥塞控制算法,支持查看状态、启用与禁用。
#   仅启用内核自带的 BBR,不安装第三方内核,不涉及 BBRv3。
#   启用时会在 /var/backups/netool-bbr 目录下生成带时间戳的 sysctl 备份,
#   禁用时可据此恢复原始拥塞控制与队列算法。
#
# 使用方式:
#   bbr status            查看当前 TCP 拥塞控制状态(默认操作)
#   bbr enable            启用内核自带 BBR
#   bbr disable           移除本工具写入的 BBR 配置并恢复原始 sysctl 值
#   bbr --plan/--dry-run  只显示计划,不写入 sysctl 配置
#   bbr -y/--yes          跳过确认直接执行
#   bbr -h/--help         显示帮助
#   bbr --version         显示版本
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="bbr-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
CONF_FILE="/etc/sysctl.d/99-netool-bbr.conf"
# 备份根目录: 每次启用 BBR 时在此目录下生成 sysctl.conf.bak.<时间戳> 文件
BACKUP_DIR="/var/backups/netool-bbr"
DRY_RUN=0
YES=0


# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | BBR 网络优化 v${SCRIPT_VERSION}

用法:
  bbr [操作] [选项]

操作:
  status     查看当前 TCP 拥塞控制状态(默认)
  enable     启用内核自带 BBR
  disable    移除本工具写入的 BBR 配置

选项:
  --plan, --dry-run  只显示计划,不写入 sysctl 配置
  -y, --yes          跳过确认,直接执行
  -h, --help         显示帮助
  --version          显示版本

说明:
  当前只启用 Linux 内核自带 BBR,不安装第三方内核,不做 BBRv3。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅; 被 AYU_TOOLBOX 调用时不打印,便于工具箱统一收口
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | BBR 网络优化 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: sysctl_value
# 功能: 读取指定 sysctl 键的当前值,失败时返回 "-" 占位
# 参数: $1 - sysctl 键名
# 返回值: 通过 stdout 输出取值; 命令失败时返回 "-"
# ------------------------------------------------------------------------------
sysctl_value() {
  sysctl -n "$1" 2>/dev/null || printf "-"
}

# ------------------------------------------------------------------------------
# 函数: backup_original_sysctl
# 功能: 备份当前 sysctl 中与拥塞控制相关的键值到带时间戳的备份文件
# 参数: 无
# 返回值: 0 - 成功(写入失败时由 set -e 触发错误处理)
# 副作用: 在 BACKUP_DIR 下创建 sysctl.conf.bak.<时间戳> 文件
# ------------------------------------------------------------------------------
backup_original_sysctl() {
  local tcp_cc=""
  local qdisc=""
  local backup_file=""

  # 读取当前生效的拥塞控制算法与队列算法,未取到时使用 "-" 占位
  tcp_cc="$(sysctl_value net.ipv4.tcp_congestion_control)"
  qdisc="$(sysctl_value net.core.default_qdisc)"

  # 备份目录不存在时创建; 时间戳格式与 common.sh 的 timestamp() 保持一致
  mkdir -p "$BACKUP_DIR"
  backup_file="${BACKUP_DIR}/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"

  # 同一份备份文件以 key=value 形式记录原始值,便于后续恢复时解析
  printf "tcp_congestion_control=%s\n" "$tcp_cc" > "$backup_file"
  printf "default_qdisc=%s\n" "$qdisc" >> "$backup_file"

  log_info "已备份原始 sysctl 配置到 ${backup_file}"
}

# ------------------------------------------------------------------------------
# 函数: restore_original_sysctl
# 功能: 从最新一次的 sysctl 备份恢复原始拥塞控制与队列算法
# 参数: 无
# 返回值: 0 - 成功(包括无备份可恢复的情况)
# 副作用: 恢复成功后会删除该次备份文件,避免重复恢复
# ------------------------------------------------------------------------------
restore_original_sysctl() {
  local backup_file=""
  local tcp_cc=""
  local qdisc=""

  # 在备份目录下查找最新的备份文件(文件名按字典序即时间序排列)
  backup_file="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'sysctl.conf.bak.*' 2>/dev/null | sort | tail -n 1)"

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    log_info "未发现备份文件,跳过恢复。"
    return 0
  fi

  tcp_cc="$(grep '^tcp_congestion_control=' "$backup_file" 2>/dev/null | cut -d= -f2 || true)"
  qdisc="$(grep '^default_qdisc=' "$backup_file" 2>/dev/null | cut -d= -f2 || true)"

  printf "\n原始 sysctl 值恢复计划:\n"
  printf "  备份文件:%s\n" "$backup_file"
  printf "  tcp_congestion_control: %s\n" "${tcp_cc:-无记录}"
  printf "  default_qdisc: %s\n" "${qdisc:-无记录}"

  # 仅在备份中记录到有效值时才执行 sysctl -w,避免被占位符覆盖
  if [[ -n "$tcp_cc" && "$tcp_cc" != "-" ]]; then
    sysctl -w "net.ipv4.tcp_congestion_control=$tcp_cc" >/dev/null || true
  fi

  if [[ -n "$qdisc" && "$qdisc" != "-" ]]; then
    sysctl -w "net.core.default_qdisc=$qdisc" >/dev/null || true
  fi

  # 恢复完成后删除本次备份,避免重复恢复到旧值
  rm -f "$backup_file"
  log_success "已恢复原始 sysctl 配置并删除备份文件 ${backup_file}。"
}

# ------------------------------------------------------------------------------
# 函数: do_status
# 功能: 打印当前 BBR 相关 sysctl 状态与 tcp_bbr 模块加载情况
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
do_status() {
  printf "\nBBR 状态:\n"
  printf "  可用拥塞算法:%s\n" "$(sysctl_value net.ipv4.tcp_available_congestion_control)"
  printf "  当前拥塞算法:%s\n" "$(sysctl_value net.ipv4.tcp_congestion_control)"
  printf "  当前队列算法:%s\n" "$(sysctl_value net.core.default_qdisc)"
  if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
    printf "  tcp_bbr 模块:已加载\n"
  else
    printf "  tcp_bbr 模块:未加载或内建\n"
  fi
}

# ------------------------------------------------------------------------------
# 函数: confirm
# 功能: 询问用户是否确认执行 BBR 启用动作
# 参数: 无
# 返回值: 0 - 确认, 非 0 - 取消或读取失败
# ------------------------------------------------------------------------------
confirm() {
  if (( YES )); then return 0; fi
  local answer=""
  read_prompt "确认写入 BBR sysctl 配置并立即应用?[y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: do_enable
# 功能: 启用内核自带 BBR,流程为备份原始 sysctl 值、写入配置、立即应用
# 参数: 无
# 返回值: 0 - 成功, 非 0 - 用户取消或环境不满足
# 副作用: 在 BACKUP_DIR 下创建时间戳备份文件; 写入 CONF_FILE 并应用 sysctl
# ------------------------------------------------------------------------------
do_enable() {
  if (( DRY_RUN )); then
    printf "\nBBR 启用计划:\n"
    printf "  1. 备份原始 sysctl 值到 %s/sysctl.conf.bak.<时间戳>\n" "$BACKUP_DIR"
    printf "  2. 写入配置:%s\n" "$CONF_FILE"
    printf "     net.core.default_qdisc=fq\n"
    printf "     net.ipv4.tcp_congestion_control=bbr\n"
    printf "  3. 应用 sysctl 配置\n"
    log_info "预览模式,不会写入 sysctl 配置。"
    return 0
  fi

  command_exists sysctl || die "缺少 sysctl。"

  # 若当前可用算法列表中没有 BBR,则尝试加载 tcp_bbr 模块
  if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    if (( ! DRY_RUN )); then
      modprobe tcp_bbr 2>/dev/null || true
    fi
  fi

  # 加载后再次校验,仍未暴露 BBR 说明内核版本不支持
  if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    die "当前内核未暴露 BBR,请先确认内核版本和 tcp_bbr 模块。"
  fi

  do_status
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "启用 BBR 需要 root 权限。"
  fi
  if ! confirm; then
    log_info "已取消。"
    return 0
  fi

  # 先备份再写入,确保失败时可恢复到原始拥塞控制算法
  backup_original_sysctl

  cat >"$CONF_FILE" <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  sysctl --system >/dev/null
  log_success "BBR 已启用。"
  do_status
}

# ------------------------------------------------------------------------------
# 函数: do_disable
# 功能: 禁用 BBR,删除本工具写入的 sysctl 配置并从备份恢复原始值后应用
# 参数: 无
# 返回值: 0 - 始终成功(即使未发现本工具的配置也会以 0 返回)
# ------------------------------------------------------------------------------
do_disable() {
  printf "\nBBR 禁用计划:\n"
  printf "  1. 删除配置:%s\n" "$CONF_FILE"
  printf "  2. 恢复原始 sysctl 值\n"
  printf "  3. 应用 sysctl 配置\n"

  if (( DRY_RUN )); then
    log_info "预览模式,不会删除 sysctl 配置或恢复原始值。"
    return 0
  fi
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "移除 BBR 配置需要 root 权限。"
  fi
  if [[ -f "$CONF_FILE" ]]; then
    rm -f "$CONF_FILE"
    restore_original_sysctl
    sysctl --system >/dev/null || true
    log_success "已移除 ${CONF_FILE} 并恢复原始配置。"
  else
    log_info "未发现本工具写入的 BBR 配置。"
  fi
  do_status
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本入口,加载公共函数库、获取互斥锁、解析参数并分发到对应子命令
# 参数: $@ - 命令行参数
# 返回值: 透传子命令的退出码
# ------------------------------------------------------------------------------
main() {
  ayu_acquire_lock "bbr" "另一个 bbr 实例正在运行,请等待其完成后再试。" || return 1
  print_banner
  local args=()
  # 先剥离全局选项,剩余位置参数作为操作名/操作参数
  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  case "${args[0]:-status}" in
    status|info) do_status ;;
    enable|on) do_enable ;;
    disable|off) do_disable ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作:$1" ;;
  esac
}

main "$@" || exit $?
