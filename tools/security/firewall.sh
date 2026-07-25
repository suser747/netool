#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 防火墙端口管理
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: firewall-tools
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   跨后端（ufw / firewalld / nftables / iptables）查看防火墙状态、放行端口。
#   在放行端口等修改性操作前，会先将当前规则集导出到
#   /var/backups/netool-firewall/ 下命名为 <后端>.rules.<时间戳> 或 <后端>.<时间戳>.txt，
#   便于失败时手动恢复。
#
# 使用方式:
#   bash firewall.sh status                # 查看防火墙状态（默认）
#   bash firewall.sh allow 8080/tcp        # 放行端口
#   bash firewall.sh --plan                # 预览模式，不修改防火墙
#   bash firewall.sh -y                    # 跳过确认
#   bash firewall.sh -h                    # 显示帮助
#   bash firewall.sh --version             # 显示版本
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="firewall-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
YES=0
DRY_RUN=0
# 防火墙规则集备份根目录: 每次修改前在此目录下生成带时间戳的规则快照
BACKUP_DIR="/var/backups/netool-firewall"


# ------------------------------------------------------------------------------
# 函数: require_root
# 功能: 校验当前是否以 root 身份运行；非 root 直接 die
# 参数: 无
# 返回值: root 时返回 0，否则退出 1
# ------------------------------------------------------------------------------
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "防火墙管理需要 root 权限。"
}

# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息到标准输出
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 防火墙端口管理 v${SCRIPT_VERSION}

用法:
  firewall [操作] [参数]

操作:
  status                 查看防火墙状态（默认）
  allow PORT[/tcp|udp]   放行端口，例如 allow 8080/tcp

选项:
  --plan, --dry-run       只显示计划，不修改防火墙
  -y, --yes              不再询问
  -h, --help             显示帮助
  --version              显示版本

说明:
  优先使用 ufw，其次 firewalld；没有这些工具时会给出 iptables/nft 状态提示。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅；被 AYU_TOOLBOX 调用时不打印，便于工具箱统一收口
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 防火墙端口管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: detect_backend
# 功能: 检测当前可用的防火墙后端
# 参数: 无
# 返回值: 通过 stdout 输出 ufw/firewalld/nftables/iptables/none 之一
# ------------------------------------------------------------------------------
detect_backend() {
  if command_exists ufw; then
    printf "ufw"
  elif command_exists firewall-cmd; then
    printf "firewalld"
  elif command_exists nft; then
    printf "nftables"
  elif command_exists iptables; then
    printf "iptables"
  else
    printf "none"
  fi
}

# ------------------------------------------------------------------------------
# 函数: confirm
# 功能: 询问用户是否确认执行；YES=1 时跳过交互
# 参数: $1 - 提示文本
# 返回值: 0 表示确认；非 0 表示取消或读取失败
# ------------------------------------------------------------------------------
confirm() {
  local prompt="$1"
  local answer=""
  if (( YES )); then return 0; fi
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: do_status
# 功能: 打印当前防火墙后端的状态信息
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
do_status() {
  local backend
  backend="$(detect_backend)"
  printf "\n防火墙后端: %s\n" "$backend"
  case "$backend" in
    ufw) ufw status verbose 2>/dev/null | sed 's/^/  /' ;;
    firewalld) firewall-cmd --state 2>/dev/null | sed 's/^/  state: /'; firewall-cmd --list-all 2>/dev/null | sed 's/^/  /' ;;
    nftables) nft list ruleset 2>/dev/null | sed -n '1,80p' | sed 's/^/  /' ;;
    iptables) iptables -S 2>/dev/null | sed -n '1,80p' | sed 's/^/  /' ;;
    none) log_warn "未检测到 ufw/firewalld/nft/iptables。" ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: parse_port_proto
# 功能: 解析形如 PORT[/PROTO] 的输入，分别写入全局 PORT 与 PROTO
# 参数: $1 - 用户输入字符串，例如 8080/tcp
# 返回值: 始终 0；格式非法时 die
# 副作用: 设置全局 PORT / PROTO
# ------------------------------------------------------------------------------
parse_port_proto() {
  local input="$1"
  PORT="${input%/*}"
  PROTO="${input#*/}"
  # 输入未带 / 时上一步 PORT==PROTO，此时按默认 tcp 处理
  [[ "$PORT" == "$PROTO" ]] && PROTO="tcp"
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "端口无效: $input"
  (( PORT >= 1 && PORT <= 65535 )) || die "端口范围应为 1-65535"
  [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]] || die "协议只支持 tcp/udp"
}

# ------------------------------------------------------------------------------
# 函数: backup_firewall_rules
# 功能: 在修改防火墙规则前，将当前规则集按后端导出到 BACKUP_DIR 下，便于失败时恢复
# 参数: $1 - 防火墙后端名称（ufw/firewalld/nftables/iptables/none）
# 返回值: 始终 0；后端无对应工具或导出失败时静默跳过
# 副作用: 在 BACKUP_DIR 下创建 <后端>.rules.<时间戳> 或 <后端>.<时间戳>.txt 文件
# ------------------------------------------------------------------------------
backup_firewall_rules() {
  local backend="$1"
  local backup_file=""
  local timestamp=""

  # 仅对会触发实际修改的后端进行备份；none 等无操作场景直接跳过
  case "$backend" in
    ufw|firewalld|nftables|iptables) ;;
    *) return 0 ;;
  esac

  mkdir -p "$BACKUP_DIR"
  # 时间戳格式与 common.sh 的 timestamp() 保持一致: YYYYMMDD_HHMMSS
  timestamp="$(date +%Y%m%d_%H%M%S)"

  case "$backend" in
    ufw)
      # ufw 没有直接导出命令；优先使用 iptables-save 抓取底层规则，否则退回状态输出
      backup_file="${BACKUP_DIR}/ufw.rules.${timestamp}"
      if command_exists iptables-save; then
        iptables-save >"$backup_file" 2>/dev/null || true
      elif command_exists ufw; then
        ufw status verbose >"$backup_file" 2>/dev/null || true
      fi
      ;;
    firewalld)
      backup_file="${BACKUP_DIR}/firewalld.${timestamp}.txt"
      firewall-cmd --list-all >"$backup_file" 2>/dev/null || true
      ;;
    nftables)
      backup_file="${BACKUP_DIR}/nftables.rules.${timestamp}"
      nft list ruleset >"$backup_file" 2>/dev/null || true
      ;;
    iptables)
      backup_file="${BACKUP_DIR}/iptables.rules.${timestamp}"
      iptables-save >"$backup_file" 2>/dev/null || true
      ;;
  esac

  if [[ -f "$backup_file" ]]; then
    log_info "已备份当前防火墙规则到 ${backup_file}"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_allow
# 功能: 放行指定端口的入口: 解析端口 → 询问确认 → 备份规则 → 调用后端放行
# 参数: $1 - PORT[/PROTO] 字符串
# 返回值: 0 表示放行成功；非 0 表示取消或不支持自动持久化
# ------------------------------------------------------------------------------
do_allow() {
  local target="${1:-}"
  local backend
  [[ -n "$target" ]] || die "请指定端口，例如: firewall allow 8080/tcp"
  parse_port_proto "$target"
  backend="$(detect_backend)"

  printf "\n计划放行端口: %s/%s\n" "$PORT" "$PROTO"
  printf "防火墙后端: %s\n" "$backend"
  if (( DRY_RUN )); then
    log_info "预览模式，不会修改防火墙。"
    return 0
  fi
  if ! confirm "确认放行该端口?"; then
    log_info "已取消。"
    return 0
  fi

  require_root

  # 修改前先快照当前规则集，避免规则异常时无法回滚
  backup_firewall_rules "$backend"

  case "$backend" in
    ufw)
      ufw allow "${PORT}/${PROTO}"
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${PORT}/${PROTO}"
      firewall-cmd --reload
      ;;
    nftables|iptables|none)
      log_warn "当前后端未提供安全的自动持久化策略，未修改规则。"
      log_info "可手动评估命令: iptables -I INPUT -p ${PROTO} --dport ${PORT} -j ACCEPT"
      return 1
      ;;
  esac
  log_success "端口已放行。"
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本入口: 加载公共函数库、获取互斥锁、解析参数并分发到对应子命令
# 参数: $@ - 命令行参数
# 返回值: 透传子命令的退出码
# ------------------------------------------------------------------------------
main() {
  ayu_acquire_lock "firewall" "另一个 firewall 实例正在运行，请等待其完成后再试。" || return 1
  local action="${1:-status}"
  [[ $# -gt 0 ]] && shift || true
  print_banner

  # 顶层快捷选项优先处理: 帮助与版本直接退出
  case "$action" in
    -h|--help) usage; exit 0 ;;
    --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
  esac

  local args=()
  # 先剥离全局选项，剩余位置参数作为操作参数透传给子命令
  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  case "$action" in
    status|info) do_status ;;
    allow|open) do_allow "${args[0]:-}" ;;
    *) die "未知操作: $action" ;;
  esac
}

main "$@" || exit $?
