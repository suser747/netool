#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - Swap 管理（swap-tools）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: swap-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Linux 系统的 swap 文件，支持查看 swap/内存状态、创建指定大小的
#   swapfile 并写入 /etc/fstab 实现开机自动挂载，以及移除本工具管理的 swapfile。
#   创建 swapfile 前会检测文件系统类型，对 btrfs 等不兼容文件系统给出指引。
# 使用方式:
#   bash swap.sh status                          # 查看 swap 与内存状态（默认）
#   bash swap.sh create --size 2G --file /swapfile  # 创建并启用 swap
#   bash swap.sh remove --file /swapfile            # 移除指定 swapfile
#   bash swap.sh --plan                            # 仅预览计划，不修改系统
# 退出码:
#   0 - 成功或用户取消
#   1 - 一般错误（参数错误、写入失败等）
#   2 - 用法错误
#   3 - 权限错误（非 root）
#   4 - 依赖缺失（缺少 mkswap/swapon 等）
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="swap-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
DEFAULT_SWAPFILE="/swapfile"
DEFAULT_SIZE="2G"
YES=0
DRY_RUN=0


# ----------------------------------------------------------------------
# 函数:require_command
# 功能:要求指定命令必须存在，否则终止脚本
# 参数:$1 - 命令名
# 返回值:0 表示存在；非 0 表示缺失并终止
# ----------------------------------------------------------------------
require_command() {
  command_exists "$1" || die "缺少必要命令：$1"
}

# ----------------------------------------------------------------------
# 函数:require_root
# 功能:校验当前是否以 root 运行，否则终止脚本
# 参数:无
# 返回值:0 表示是 root；非 0 表示非 root 并终止
# ----------------------------------------------------------------------
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Swap 管理需要 root 权限。"
}

# ----------------------------------------------------------------------
# 函数:usage
# 功能:输出脚本帮助说明（操作、选项、说明）到标准输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | Swap 管理 v${SCRIPT_VERSION}

用法：
  swap [操作] [选项]

操作：
  status                 查看 Swap 状态（默认）
  create --size 2G       创建 /swapfile 并写入 /etc/fstab
  remove                 删除本工具管理的 /swapfile

  选项：
  --file PATH            指定 swapfile，默认 ${DEFAULT_SWAPFILE}
  --size SIZE            指定大小，默认 ${DEFAULT_SIZE}
  --plan, --dry-run      只显示计划，不创建或删除 swap
  -y, --yes              不再询问
  -h, --help             显示帮助
  --version              显示版本
EOF
}

# ----------------------------------------------------------------------
# 函数:print_banner
# 功能:打印脚本横幅信息；AYU_TOOLBOX 模式下静默不输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | Swap 管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ----------------------------------------------------------------------
# 函数:confirm
# 功能:交互式确认提示，YES 全局变量为 1 时跳过询问直接返回 0
# 参数:$1 - 提示信息文本
# 返回值:0 表示确认；1 表示取消或读取失败
# ----------------------------------------------------------------------
confirm() {
  local prompt="$1"
  local answer=""
  if (( YES )); then return 0; fi
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ----------------------------------------------------------------------
# 函数:do_status
# 功能:打印当前 swap 状态、内存占用以及 /etc/fstab 中的 swap 条目
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_status() {
  printf "\nSwap 状态：\n"
  swapon --show 2>/dev/null | sed 's/^/  /' || true
  printf "\n内存：\n"
  free -h 2>/dev/null | sed 's/^/  /' || true
  printf "\n/etc/fstab 中的 swap：\n"
  grep -nE '[[:space:]]swap[[:space:]]' /etc/fstab 2>/dev/null | sed 's/^/  /' || printf "  无\n"
}

# ----------------------------------------------------------------------
# 函数:validate_size
# 功能:校验大小字符串是否合法（数字 + 可选 K/M/G/T/P 单位）
# 参数:$1 - 待校验的大小字符串，例如 2G、512M
# 返回值:0 表示合法；1 表示非法
# ----------------------------------------------------------------------
validate_size() {
  [[ "$1" =~ ^[0-9]+[KMGTP]?$ ]]
}

# ----------------------------------------------------------------------
# 函数:size_to_bytes
# 功能:将带单位的大小字符串转换为字节数。支持单位 K/M/G/T/P（基数 1024），
#       无单位时按字节处理。供 dd 回退路径使用，弥补 fallocate 缺失场景。
# 参数:$1 - 待转换的大小字符串，例如 2G、512M、1024
# 返回值:0 表示成功，字节数输出到 stdout；1 表示格式非法
# ----------------------------------------------------------------------
size_to_bytes() {
  local size="$1"
  local num unit
  if [[ "$size" =~ ^([0-9]+)([KMGTP]?)$ ]]; then
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "$unit" in
      K) echo $((num * 1024)) ;;
      M) echo $((num * 1024 * 1024)) ;;
      G) echo $((num * 1024 * 1024 * 1024)) ;;
      T) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
      P) echo $((num * 1024 * 1024 * 1024 * 1024 * 1024)) ;;
      "") echo "$num" ;;
    esac
    return 0
  fi
  return 1
}

# ----------------------------------------------------------------------
# 函数:do_create
# 功能:创建指定大小的 swapfile 并启用，写入 /etc/fstab 实现开机自动挂载。
#       创建前会检测目标路径所在文件系统类型，对 btrfs 给出特殊指引；
#       使用 dd 写零失败时会清理残留文件，避免占用磁盘空间。
# 参数:$1 - swapfile 绝对路径；$2 - 大小（如 2G、512M）
# 返回值:0 表示创建成功或用户取消；非 0 表示参数/权限/写入失败时终止
# ----------------------------------------------------------------------
do_create() {
  local file="$1"
  local size="$2"
  validate_size "$size" || die "无效大小：${size}，示例 2G。"
  [[ "$file" == /* ]] || die "swapfile 必须是绝对路径。"
  [[ ! -e "$file" ]] || die "${file} 已存在，请先检查或换路径。"

  printf "\n计划创建 Swap：\n"
  printf "  文件：%s\n" "$file"
  printf "  大小：%s\n" "$size"
  printf "  持久化：写入 /etc/fstab\n"
  if (( DRY_RUN )); then
    log_info "预览模式，不会创建 swap。"
    return 0
  fi
  require_root
  require_command mkswap
  require_command swapon
  require_command chmod
  require_command cp
  require_command sed
  require_command grep
  if ! command_exists fallocate && ! command_exists dd; then
    die "缺少 fallocate 或 dd，无法创建 swapfile。"
  fi

  # 创建 swapfile 前检测目标路径所在文件系统类型，btrfs 不支持普通 swapfile
  local fstype=""
  fstype="$(findmnt -no FSTYPE "$(dirname "$file")" 2>/dev/null || true)"
  if [[ "$fstype" == "btrfs" ]]; then
    log_warn "检测到 btrfs 文件系统，swapfile 需要特殊处理"
    log_warn "btrfs 不支持直接的 swapfile，请使用 swap 子卷或传统的 swap 分区"
    return 1
  fi

  if ! confirm "确认创建并启用 Swap？"; then
    log_info "已取消。"
    return 0
  fi

  if command_exists fallocate; then
    fallocate -l "$size" "$file"
  else
    # fallocate 缺失时回退到 dd 写零。通过 size_to_bytes 把任意单位
    # (K/M/G/T/P) 统一换算为字节数，再用 1M 块大小分批写入，避免
    # 此前仅支持 G 单位导致其他合法大小被拒的问题。
    local total_bytes
    if ! total_bytes="$(size_to_bytes "$size")"; then
      die "无法解析大小：${size}。"
    fi
    local bs=$((1024 * 1024))   # 1M 块大小，平衡速度与内存占用
    local count=$(( total_bytes / bs ))
    # 不足 1M 的余数按 1 块补齐，确保最终文件不小于目标大小
    (( total_bytes % bs > 0 )) && count=$((count + 1))
    # dd 写零失败时清理残留文件，避免占用磁盘空间
    dd if=/dev/zero of="$file" bs="$bs" count="$count" status=progress || {
      rm -f "$file"
      die "dd 写入失败，已清理残留文件：$file"
    }
    # 截断至精确字节数，消除余数块带来的多写部分
    truncate -s "$total_bytes" "$file" 2>/dev/null || true
  fi

  chmod 600 "$file"
  mkswap "$file"
  swapon "$file"
  cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  if ! awk -v f="$file" '$1 == f {found=1; exit} END {exit !found}' /etc/fstab; then
    printf "%s none swap sw 0 0\n" "$file" >> /etc/fstab
  fi
  log_success "Swap 已创建并启用。"
  do_status
}

# ----------------------------------------------------------------------
# 函数:do_remove
# 功能:移除指定 swapfile:先 swapoff，从 /etc/fstab 中删除对应条目，再删除文件
# 参数:$1 - swapfile 绝对路径
# 返回值:0 表示移除成功或用户取消；非 0 表示参数错误或权限不足时终止
# ----------------------------------------------------------------------
do_remove() {
  local file="$1"
  [[ "$file" == /* ]] || die "swapfile 必须是绝对路径。"

  printf "\n计划删除 Swap：%s\n" "$file"
  if (( DRY_RUN )); then
    log_info "预览模式，不会删除 swap。"
    return 0
  fi
  require_root
  require_command swapoff
  require_command cp
  require_command sed
  require_command rm
  if ! confirm "确认关闭并删除该 Swap？"; then
    log_info "已取消。"
    return 0
  fi

  swapoff "$file" 2>/dev/null || true
  cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
  awk -v f="$file" '$1 != f' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
  rm -f "$file"
  log_success "Swap 已删除。"
  do_status
}

# ----------------------------------------------------------------------
# 函数:main
# 功能:脚本主入口。加载 common.sh、获取进程锁、解析命令行参数并分发到对应操作
# 参数:$@ - 命令行参数（操作名与选项）
# 返回值:0 表示正常结束；非 0 表示获取锁失败或参数错误
# ----------------------------------------------------------------------
main() {
  ayu_acquire_lock "swap" "另一个 swap 实例正在运行，请等待其完成后再试。" || return 1
  local action="${1:-status}"
  local file="$DEFAULT_SWAPFILE"
  local size="$DEFAULT_SIZE"
  [[ $# -gt 0 ]] && shift || true

  if [[ "$action" =~ ^[0-9]+[KMGTP]?$ ]]; then
    size="$action"
    action="create"
  fi

  print_banner

  while (($# > 0)); do
    case "$1" in
      --file)
        [[ $# -ge 2 ]] || die "--file 需要指定路径。"
        file="$2"; shift
        ;;
      --size)
        [[ $# -ge 2 ]] || die "--size 需要指定大小。"
        size="$2"; shift
        ;;
      [0-9]*[KMGTP]|[0-9]*) size="$1" ;;
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数:$1" ;;
    esac
    shift
  done

  case "$action" in
    status|info) do_status ;;
    create|add) do_create "$file" "$size" ;;
    remove|delete|del) do_remove "$file" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$action" ;;
  esac
}

main "$@" || exit $?
