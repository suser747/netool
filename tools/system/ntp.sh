#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 时间同步管理（ntp-tools）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: ntp-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Linux 系统的时间与 NTP 同步服务，支持查看当前时间/时区/同步状态、
#   立即同步一次时间、自动配置 chrony/systemd-timesyncd/ntpdate 之一并设置
#   时区，以及关闭本工具配置的同步服务。修改 /etc/localtime 与 chrony.conf
#   前会自动带时间戳备份。
# 使用方式:
#   bash ntp.sh status                  # 查看时间、时区与同步状态（默认）
#   bash ntp.sh sync                     # 立即同步一次时间
#   bash ntp.sh setup                     # 配置 chrony 等服务并设置时区
#   bash ntp.sh disable                   # 关闭本工具配置的同步服务
#   bash ntp.sh setup --servers "a b" --timezone Asia/Shanghai -y
# 退出码:
#   0 - 成功或用户取消
#   1 - 一般错误（安装/写入失败等）
#   2 - 用法错误
#   3 - 权限错误（非 root）
#   4 - 依赖缺失（无可用 NTP 服务且无包管理器）
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="ntp-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh ntp
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) ntp
#   直接：bash tools/system/ntp.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

NTP_SERVERS="ntp.aliyun.com ntp.tencent.com cn.pool.ntp.org"
TIMEZONE="Asia/Shanghai"
DRY_RUN=0
YES=0



# ----------------------------------------------------------------------
# 函数:usage
# 功能:输出脚本帮助说明（操作、选项、说明）到标准输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 时间同步管理 v${SCRIPT_VERSION}

用法：
  ntp [操作] [选项]

操作：
  status              查看当前时间、时区和同步状态（默认）
  sync                立即同步一次时间
  setup               配置时间同步服务（chrony/systemd-timesyncd）并设置时区
  disable             关闭本工具配置的同步服务

选项：
  --servers <列表>    自定义 NTP 服务器，空格分隔，默认：${NTP_SERVERS}
  --timezone <时区>   设置时区，默认：${TIMEZONE}
  --plan, --dry-run   只显示计划
  -y, --yes           跳过确认
  -h, --help          显示帮助
  --version           显示版本

说明：
  setup 会按以下顺序选择服务：chrony > systemd-timesyncd > ntpdate
  会同时设置时区（通过 timedatectl 或软链 /etc/localtime）。
EOF
}

# ----------------------------------------------------------------------
# 函数:print_banner
# 功能:打印脚本横幅信息；NETOOL 子工具调用时静默不输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 时间同步管理 v%s\n" "$SCRIPT_VERSION"
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
  if (( YES )); then return 0; fi
  local answer=""
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ----------------------------------------------------------------------
# 函数:detect_ntp_service
# 功能:检测当前可用的 NTP 服务类型，按 chrony > systemd-timesyncd > ntpdate 顺序
# 参数:无
# 返回值:始终 0，标准输出为服务名（chrony/systemd-timesyncd/ntpdate）或空串
# ----------------------------------------------------------------------
detect_ntp_service() {
  if command_exists chronyc && command_exists chronyd; then
    printf "chrony"
  elif command_exists timedatectl && systemctl cat systemd-timesyncd >/dev/null 2>&1; then
    printf "systemd-timesyncd"
  elif command_exists ntpdate; then
    printf "ntpdate"
  else
    printf ""
  fi
}

# ----------------------------------------------------------------------
# 函数:do_status
# 功能:打印当前系统时间、时区与 NTP 服务运行状态
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_status() {
  printf "\n时间信息：\n"
  printf "  当前时间：%s\n" "$(date 2>/dev/null || echo '-')"

  if command_exists timedatectl; then
    printf "\ntimedatectl：\n"
    timedatectl 2>/dev/null | sed 's/^/  /' || true
  else
    if [[ -L /etc/localtime ]]; then
      local tz_path=""
      tz_path="$(readlink /etc/localtime 2>/dev/null || true)"
      printf "  时区（软链）：%s\n" "$tz_path"
    fi
  fi

  printf "\nNTP 服务状态：\n"
  local svc=""
  svc="$(detect_ntp_service)"
  if [[ -n "$svc" ]]; then
    printf "  检测到：%s\n" "$svc"
    case "$svc" in
      chrony)
        if command_exists chronyc; then
          chronyc tracking 2>/dev/null | sed 's/^/  /' || true
        fi
        ;;
      systemd-timesyncd)
        systemctl status systemd-timesyncd --no-pager 2>/dev/null | head -n 8 | sed 's/^/  /' || true
        ;;
      ntpdate)
        log_warn "ntpdate 仅支持手动同步，无守护进程状态。"
        ;;
    esac
  else
    printf "  未检测到可用的 NTP 服务（chrony/systemd-timesyncd/ntpdate）。\n"
  fi
}

# ----------------------------------------------------------------------
# 函数:set_timezone
# 功能:设置系统时区。优先使用 timedatectl，回退到 ln -sf 软链 zoneinfo 文件。
#       修改 /etc/localtime 前会带时间戳备份，便于回滚。
# 参数:$1 - 时区名称，例如 Asia/Shanghai
# 返回值:0 表示成功；非 0 表示时区文件不存在或备份失败时终止
# ----------------------------------------------------------------------
set_timezone() {
  local tz="$1"

  # 修改 /etc/localtime 前先备份原文件，保留时间戳便于回滚
  if [[ -e /etc/localtime ]]; then
    cp -a /etc/localtime "/etc/localtime.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  fi

  if command_exists timedatectl; then
    timedatectl set-timezone "$tz"
  else
    local tz_file="/usr/share/zoneinfo/${tz}"
    [[ -f "$tz_file" ]] || die "时区文件不存在：$tz_file"
    ln -sf "$tz_file" /etc/localtime
  fi
}

# ----------------------------------------------------------------------
# 函数:do_sync
# 功能:立即触发一次时间同步，根据检测到的服务调用对应命令
# 参数:无（依赖 DRY_RUN / YES 等全局变量）
# 返回值:0 表示成功或用户取消；1 表示无可用 NTP 服务
# ----------------------------------------------------------------------
do_sync() {
  require_root

  local svc=""
  svc="$(detect_ntp_service)"

  printf "\n立即同步计划：\n"
  if [[ -n "$svc" ]]; then
    printf "  使用：%s\n" "$svc"
  else
    printf "  无可用 NTP 服务，将尝试 ntpdate（若存在）或提示安装。\n"
  fi
  if (( DRY_RUN )); then
    log_info "预览模式，不会执行同步。"
    return 0
  fi

  if ! confirm "确认立即同步时间？"; then
    log_info "已取消。"
    return 0
  fi

  case "$svc" in
    chrony)
      chronyc makestep 2>&1 | sed 's/^/  /' || true
      log_success "已通过 chrony 同步。"
      ;;
    systemd-timesyncd)
      systemctl restart systemd-timesyncd 2>/dev/null || true
      systemctl try-restart systemd-timesyncd 2>/dev/null || true
      log_success "已重启 systemd-timesyncd。"
      ;;
    ntpdate)
      # shellcheck disable=SC2086
      ntpdate $NTP_SERVERS 2>&1 | sed 's/^/  /' || true
      log_success "已通过 ntpdate 同步。"
      ;;
    *)
      log_warn "未检测到 NTP 服务，请先运行 ntp setup。"
      return 1
      ;;
  esac

  do_status
}

# ----------------------------------------------------------------------
# 函数:do_setup
# 功能:配置时间同步服务并设置时区。会安装 chrony（按包管理器），
#       修改 /etc/localtime（已由 set_timezone 备份）和 chrony.conf（修改前备份）。
# 参数:无（依赖 NTP_SERVERS / TIMEZONE / DRY_RUN / YES 等全局变量）
# 返回值:0 表示成功或用户取消；非 0 表示安装或写入失败时终止
# ----------------------------------------------------------------------
do_setup() {
  require_root

  printf "\n时间同步配置计划：\n"
  printf "  NTP 服务器：%s\n" "$NTP_SERVERS"
  printf "  时区：%s\n" "$TIMEZONE"

  local svc=""
  svc="$(detect_ntp_service)"
  if [[ -n "$svc" ]]; then
    printf "  已存在的 NTP 服务：%s（将复用或调整配置）\n" "$svc"
  else
    # 选择要安装的服务
    if command_exists apt || command_exists apt-get; then
      printf "  将安装：chrony\n"
      svc="chrony"
    elif command_exists dnf || command_exists yum; then
      printf "  将安装：chrony\n"
      svc="chrony"
    elif command_exists apk; then
      printf "  将安装：chrony\n"
      svc="chrony"
    elif command_exists pacman; then
      printf "  将安装：chrony\n"
      svc="chrony"
    else
      die "未识别包管理器，无法自动安装 NTP 服务，请手动安装 chrony。"
    fi
  fi

  if (( DRY_RUN )); then
    log_info "预览模式，不会修改系统。"
    return 0
  fi

  if ! confirm "确认配置时间同步？"; then
    log_info "已取消。"
    return 0
  fi

  # 1. 设置时区
  log_info "设置时区 ${TIMEZONE}..."
  set_timezone "$TIMEZONE"
  log_success "时区已设置。"

  # 2. 安装/配置 chrony
  if [[ "$svc" == "chrony" ]]; then
    if ! command_exists chronyd; then
      log_info "安装 chrony..."
      if command_exists apt || command_exists apt-get; then
        apt-get install -y chrony 2>&1 | tail -n 5 | sed 's/^/  /' || true
      elif command_exists dnf; then
        dnf install -y chrony 2>&1 | tail -n 5 | sed 's/^/  /' || true
      elif command_exists yum; then
        yum install -y chrony 2>&1 | tail -n 5 | sed 's/^/  /' || true
      elif command_exists apk; then
        apk add chrony 2>&1 | tail -n 5 | sed 's/^/  /' || true
      elif command_exists pacman; then
        pacman -S --noconfirm chrony 2>&1 | tail -n 5 | sed 's/^/  /' || true
      fi
    fi

    # 写入 chrony.conf
    local chrony_conf="/etc/chrony/chrony.conf"
    if [[ ! -f "$chrony_conf" ]]; then
      chrony_conf="/etc/chrony.conf"
    fi
    # chrony.conf 修改前带时间戳备份，时间戳格式与 /etc/localtime 备份保持一致
    if [[ -f "$chrony_conf" ]]; then
      cp -a "$chrony_conf" "${chrony_conf}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    local first_server=""
    first_server="$(printf "%s" "$NTP_SERVERS" | awk '{print $1}')"
    cat >"$chrony_conf" <<EOF
# 由 netool懒人工具箱 ntp 工具生成
$(printf "server %s iburst\n" $NTP_SERVERS)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow 127.0.0.1
logdir /var/log/chrony
EOF
    log_success "已写入 ${chrony_conf}。"

    if command_exists systemctl; then
      systemctl enable chronyd 2>/dev/null || true
      systemctl restart chronyd 2>/dev/null || true
      # 强制立即同步
      chronyc makestep 2>/dev/null || true
    fi
    log_success "chrony 已启动并同步。"
  fi

  do_status
}

# ----------------------------------------------------------------------
# 函数:do_disable
# 功能:关闭本工具配置的 NTP 同步服务（chronyd、systemd-timesyncd）并禁用 NTP
# 参数:无（依赖 DRY_RUN / YES 等全局变量）
# 返回值:0 表示成功或用户取消
# ----------------------------------------------------------------------
do_disable() {
  require_root

  printf "\n关闭 NTP 服务计划：\n"
  if (( DRY_RUN )); then
    log_info "预览模式，不会执行。"
    return 0
  fi

  if ! confirm "确认关闭时间同步服务？"; then
    log_info "已取消。"
    return 0
  fi

  if command_exists systemctl; then
    systemctl stop chronyd 2>/dev/null || true
    systemctl disable chronyd 2>/dev/null || true
    systemctl stop systemd-timesyncd 2>/dev/null || true
    systemctl disable systemd-timesyncd 2>/dev/null || true
  fi

  if command_exists timedatectl; then
    timedatectl set-ntp false 2>/dev/null || true
  fi

  log_success "时间同步服务已关闭。"
  do_status
}

# ----------------------------------------------------------------------
# 函数:main
# 功能:脚本主入口。加载 common.sh、获取进程锁、解析命令行参数并分发到对应操作
# 参数:$@ - 命令行参数（操作名与选项）
# 返回值:0 表示正常结束；非 0 表示获取锁失败或参数错误
# ----------------------------------------------------------------------
main() {
  netool_acquire_lock "ntp-tools" "另一个 ntp 实例正在运行，请等待其完成后再试。" || return 1

  local action="status"

  while (($# > 0)); do
    case "$1" in
      status|info) action="status" ;;
      sync) action="sync" ;;
      setup|configure) action="setup" ;;
      disable|off) action="disable" ;;
      --servers)
        [[ $# -gt 1 ]] || die "--servers 需要指定服务器列表。"
        NTP_SERVERS="$2"
        shift
        ;;
      --timezone)
        [[ $# -gt 1 ]] || die "--timezone 需要指定时区。"
        TIMEZONE="$2"
        shift
        ;;
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数:$1" ;;
    esac
    shift
  done

  print_banner

  case "$action" in
    status) do_status ;;
    sync) do_sync ;;
    setup) do_setup ;;
    disable) do_disable ;;
  esac
}

main "$@" || exit $?
