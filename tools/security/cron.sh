#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 定时任务管理
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: cron-tools
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Linux 系统的 crontab 任务，支持列出、备份、恢复、导出当前用户或
#   指定用户的 crontab；可扫描所有用户的 crontab 及 /etc/cron.d、/etc/crontab
#   和 /etc/cron.{hourly,daily,weekly,monthly}；同时支持列出 systemd timer。
#
# 使用方式:
#   bash cron.sh list                            # 列出当前用户的 crontab
#   bash cron.sh list-all                        # 列出所有用户的 crontab（需 root）
#   bash cron.sh backup --user <用户>            # 备份指定用户的 crontab
#   bash cron.sh restore --file <备份文件>       # 从备份文件恢复 crontab
#   bash cron.sh timers                          # 列出 systemd timer
#   bash cron.sh export [--user <用户>]          # 导出 crontab 到 stdout
#   bash cron.sh backups                         # 列出可用备份
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="cron-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh cron
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) cron
#   直接：bash tools/security/cron.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

BACKUP_ROOT="/var/backups/netool-cron-tools"
TARGET_USER=""
RESTORE_FILE=""
LIST_TIMERS=0
YES=0
DRY_RUN=0


# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助说明（操作、选项、说明）到标准输出
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 定时任务管理 v${SCRIPT_VERSION}

用法:
  cron [操作] [选项]

操作:
  list                           列出当前用户的 crontab（默认）
  list-all                       列出所有用户的 crontab（需 root）
  backup [--user <用户>]         备份 crontab 到 ${BACKUP_ROOT}
  restore --file <备份文件> [--user <用户>]  从备份恢复 crontab
  timers                         列出 systemd timer
  export [--user <用户>]         导出 crontab 到 stdout

选项:
  --user <用户>           指定用户（默认当前用户）
  --file <备份文件>       恢复时指定的备份文件路径
  --plan, --dry-run       仅预览备份/恢复操作，不执行
  -y, --yes               跳过确认
  -h, --help              显示帮助
  --version               显示版本

说明:
  backup 会把指定用户的 crontab 保存到 ${BACKUP_ROOT}/<用户>-<时间戳>.cron
  list-all 会扫描 /var/spool/cron/ 和 /etc/cron.d/，需 root
  --plan 模式下会显示将要执行的操作，但不会修改系统
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅信息；NETOOL 子工具调用时静默不输出
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 定时任务管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}


# ------------------------------------------------------------------------------
# 函数: effective_user
# 功能: 返回当前操作的有效用户名（优先 TARGET_USER，否则取当前用户）
# 参数: 无
# 返回值: 0，标准输出为用户名字符串
# ------------------------------------------------------------------------------
effective_user() {
  if [[ -n "$TARGET_USER" ]]; then
    printf "%s" "$TARGET_USER"
  else
    printf "%s" "${USER:-$(whoami 2>/dev/null || echo root)}"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_list
# 功能: 列出当前用户（或 --user 指定用户）的 crontab 内容
# 参数: 无
# 返回值: 始终 0（无 crontab 时仅打印提示）
# ------------------------------------------------------------------------------
do_list() {
  local user=""
  user="$(effective_user)"
  printf "\n用户 %s 的 crontab:\n" "$user"
  if ! command_exists crontab; then
    log_warn "未安装 crontab 命令。"
    return 0
  fi
  if ! crontab -u "$user" -l 2>/dev/null; then
    printf "  （无 crontab 或用户不存在）\n"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_list_all
# 功能: 列出系统所有用户的 crontab，并扫描 /etc/cron.d、/etc/crontab 及
#       /etc/cron.{hourly,daily,weekly,monthly} 周期任务目录
# 参数: 无
# 返回值: 始终 0（需 root 权限，未授权时由 require_root 终止）
# ------------------------------------------------------------------------------
do_list_all() {
  require_root
  printf "\n所有用户的 crontab:\n"

  if ! command_exists crontab; then
    log_warn "未安装 crontab 命令，尝试扫描文件。"
  fi

  # /var/spool/cron 下的用户 crontab
  local spool_dir=""
  for d in /var/spool/cron /var/spool/cron/crontabs; do
    if [[ -d "$d" ]]; then
      spool_dir="$d"
      break
    fi
  done

  if [[ -n "$spool_dir" ]]; then
    while IFS= read -r -d '' f; do
      local u=""
      u="$(basename "$f")"
      printf "\n== 用户 %s ==\n" "$u"
      sed 's/^/  /' "$f" 2>/dev/null || true
    done < <(find "$spool_dir" -maxdepth 1 -type f -print0 2>/dev/null)
  fi

  # /etc/cron.d
  if [[ -d /etc/cron.d ]]; then
    printf "\n== /etc/cron.d ==\n"
    while IFS= read -r -d '' f; do
      printf "\n-- %s --\n" "$(basename "$f")"
      sed 's/^/  /' "$f" 2>/dev/null || true
    done < <(find /etc/cron.d -maxdepth 1 -type f -print0 2>/dev/null)
  fi

  # /etc/crontab
  if [[ -f /etc/crontab ]]; then
    printf "\n== /etc/crontab ==\n"
    sed 's/^/  /' /etc/crontab 2>/dev/null || true
  fi

  # /etc/cron.{hourly,daily,weekly,monthly}
  local period=""
  for period in hourly daily weekly monthly; do
    if [[ -d "/etc/cron.${period}" ]]; then
      printf "\n== /etc/cron.%s ==\n" "$period"
      ls -1 "/etc/cron.${period}" 2>/dev/null | sed 's/^/  /' || true
    fi
  done
}

# ------------------------------------------------------------------------------
# 函数: do_backup
# 功能: 将指定用户的 crontab 内容写入 ${BACKUP_ROOT}/<用户>-<时间戳>.cron
#       使用 mktemp 创建权限 600 的临时文件，写入成功后再原子重命名为备份文件，
#       避免在备份目录下产生半成品或权限过宽的中间文件。
# 参数: 无（依赖 TARGET_USER / DRY_RUN 等全局变量）
# 返回值: 0 表示成功或用户无 crontab；非 0 表示命令缺失等致命错误
# ------------------------------------------------------------------------------
do_backup() {
  local user=""
  user="$(effective_user)"

  if ! command_exists crontab; then
    die "未安装 crontab 命令。"
  fi

  mkdir -p "$BACKUP_ROOT" 2>/dev/null || true
  chmod 700 "$BACKUP_ROOT" 2>/dev/null || true

  local ts=""
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup_file="${BACKUP_ROOT}/${user}-${ts}.cron"

  if (( DRY_RUN )); then
    printf "\n备份计划（预览）:\n"
    printf "  目标用户: %s\n" "$user"
    printf "  备份路径: %s\n" "$backup_file"
    printf "  备份来源: crontab -u %s -l\n" "$user"
    log_info "预览模式，不会写入备份文件。"
    return 0
  fi

  # 通过 mktemp 创建临时文件并 chmod 600 限制权限，再写入 crontab 内容
  local tmp_file
  tmp_file="$(mktemp)" || die "无法创建临时文件。"
  chmod 600 "$tmp_file" 2>/dev/null || true

  if ! crontab -u "$user" -l >"$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    log_warn "用户 ${user} 没有 crontab 或读取失败。"
    return 0
  fi

  # 写入成功后原子重命名为最终备份文件，并确保权限为 600
  mv -f "$tmp_file" "$backup_file"
  chmod 600 "$backup_file" 2>/dev/null || true
  log_success "已备份用户 ${user} 的 crontab 到: ${backup_file}"
}

# ------------------------------------------------------------------------------
# 函数: do_restore
# 功能: 从 --file 指定的备份文件恢复 crontab 到指定用户
# 参数: 无（依赖 RESTORE_FILE / TARGET_USER / DRY_RUN / YES 等全局变量）
# 返回值: 0 表示已恢复或用户取消；非 0 表示参数错误或恢复失败
# ------------------------------------------------------------------------------
do_restore() {
  [[ -n "$RESTORE_FILE" ]] || die "请用 --file 指定备份文件路径。"
  [[ -f "$RESTORE_FILE" ]] || die "备份文件不存在: $RESTORE_FILE"

  local user=""
  user="$(effective_user)"

  if ! command_exists crontab; then
    die "未安装 crontab 命令。"
  fi

  printf "\n恢复计划:\n"
  printf "  备份文件: %s\n" "$RESTORE_FILE"
  printf "  目标用户: %s\n" "$user"
  printf "  文件大小: %s 字节\n" "$(wc -c <"$RESTORE_FILE" | awk '{print $1}')"

  if (( DRY_RUN )); then
    printf "  执行命令: crontab -u %s %s\n" "$user" "$RESTORE_FILE"
    log_info "预览模式，不会恢复 crontab。"
    return 0
  fi

  if (( YES != 1 )); then
    local answer=""
    read_prompt "确认恢复? [y/N]: " answer || return 1
    [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]] || { log_info "已取消。"; return 0; }
  fi

  if ! crontab -u "$user" "$RESTORE_FILE" 2>/dev/null; then
    die "恢复失败，请检查权限或文件格式。"
  fi

  log_success "已恢复用户 ${user} 的 crontab。"
}

# ------------------------------------------------------------------------------
# 函数: do_timers
# 功能: 通过 systemctl list-timers 列出所有 systemd timer
# 参数: 无
# 返回值: 始终 0（无 systemctl 时仅警告）
# ------------------------------------------------------------------------------
do_timers() {
  if ! command_exists systemctl; then
    log_warn "未安装 systemctl，无法列出 systemd timer。"
    return 0
  fi
  printf "\nsystemd timer 列表:\n"
  systemctl list-timers --all --no-pager 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 函数: do_export
# 功能: 将指定用户的 crontab 内容输出到 stdout，便于重定向或管道处理
# 参数: 无（依赖 TARGET_USER 全局变量）
# 返回值: 0 表示成功；非 0 表示命令缺失
# ------------------------------------------------------------------------------
do_export() {
  local user=""
  user="$(effective_user)"
  if ! command_exists crontab; then
    die "未安装 crontab 命令。"
  fi
  crontab -u "$user" -l 2>/dev/null || log_warn "用户 ${user} 没有 crontab。"
}

# ------------------------------------------------------------------------------
# 函数: list_backups
# 功能: 列出 ${BACKUP_ROOT} 目录下所有 *.cron 备份文件
# 参数: 无
# 返回值: 始终 0（无备份或目录不存在时仅打印 "无"）
# ------------------------------------------------------------------------------
list_backups() {
  printf "\n可用备份（%s）:\n" "$BACKUP_ROOT"
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    printf "  无\n"
    return 0
  fi
  local count=0
  while IFS= read -r -d '' f; do
    printf "  %s\n" "$f"
    count=$((count + 1))
  done < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name '*.cron' -print0 2>/dev/null | sort -z)
  (( count == 0 )) && printf "  无\n"
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口。加载 common.sh、获取进程锁、解析命令行参数并分发到对应操作
# 参数: $@ - 命令行参数（操作名与选项）
# 返回值: 0 表示正常结束；非 0 表示获取锁失败或参数错误
# ------------------------------------------------------------------------------
main() {
  netool_acquire_lock "cron-tools" "另一个 cron 实例正在运行，请等待其完成后再试。" || return 1

  local action="list"

  while (($# > 0)); do
    case "$1" in
      list|ls) action="list" ;;
      list-all|ls-all) action="list-all" ;;
      backup) action="backup" ;;
      restore) action="restore" ;;
      timers) action="timers" ;;
      export) action="export" ;;
      backups) action="backups" ;;
      --user)
        [[ $# -gt 1 ]] || die "--user 需要指定用户名。"
        TARGET_USER="$2"
        shift
        ;;
      --file)
        [[ $# -gt 1 ]] || die "--file 需要指定备份文件。"
        RESTORE_FILE="$2"
        shift
        ;;
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数: $1" ;;
    esac
    shift
  done

  print_banner

  case "$action" in
    list) do_list ;;
    list-all) do_list_all ;;
    backup) do_backup ;;
    restore) do_restore ;;
    timers) do_timers ;;
    export) do_export ;;
    backups) list_backups ;;
  esac
}

main "$@" || exit $?
