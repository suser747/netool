#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 主入口脚本
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: main
# 脚本版本: 2.1
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   命令行懒人向 Linux 运维脚本，菜单式 + 参数式双入口。
#   支持 curl|bash 远程运行与本地部署两种模式。
#   通过统一入口分发到 tools/ 下的子脚本执行具体功能。
#
# 使用方式:
#   交互式菜单:  bash main.sh
#   参数式调用:  bash main.sh <工具名> [参数...]
#   远程执行:    bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) <工具名>
#
# 标准参数:
#   --help       显示帮助信息
#   --version    显示版本信息
#   --check      检查环境和依赖
#   -y/--yes     非交互模式（跳过确认提示）
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================

set -Eeuo pipefail

SCRIPT_NAME="netool"
SCRIPT_VERSION="2.1"
REPO_URL="https://gitee.com/suser747/netool"
SCRIPT_URL="https://gitee.com/suser747/netool/raw/master/main.sh"
SHORT_SCRIPT_URL="https://gitee.com/suser747/netool/raw/master/main.sh"
RAW_BASE_URL="https://gitee.com/suser747/netool/raw/master"
AGREEMENT_URL="https://gitee.com/suser747/netool/blob/master/USER_AGREEMENT.md"
LICENSE_VERSION="1"
LOG_DIR="/var/log/netool"
EXIT_OK=0
EXIT_ERROR=1
EXIT_USAGE=2
EXIT_PERMISSION=3
EXIT_DEPENDENCY=4
QUIET=0
SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "bash" && "$SCRIPT_SOURCE" != "-bash" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

NETOOL_BOOTSTRAP_DIR=""
if [[ -f "${SCRIPT_DIR}/tools/common.sh" ]]; then
  # shellcheck source=tools/common.sh
  source "${SCRIPT_DIR}/tools/common.sh"
elif command -v curl >/dev/null 2>&1; then
  NETOOL_BOOTSTRAP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/netool-bootstrap.XXXXXX" 2>/dev/null || mktemp -d)"
  mkdir -p "${NETOOL_BOOTSTRAP_DIR}/tools"
  if curl -fsSL "${RAW_BASE_URL:-https://gitee.com/suser747/netool/raw/master}/tools/common.sh" \
    -o "${NETOOL_BOOTSTRAP_DIR}/tools/common.sh" 2>/dev/null \
    && bash -n "${NETOOL_BOOTSTRAP_DIR}/tools/common.sh" 2>/dev/null; then
    # shellcheck source=/dev/null
    source "${NETOOL_BOOTSTRAP_DIR}/tools/common.sh"
  else
    rm -rf "$NETOOL_BOOTSTRAP_DIR"
    NETOOL_BOOTSTRAP_DIR=""
    printf '[错误] 无法加载 tools/common.sh，且远程下载失败。请检查网络或改用本地部署。\n' >&2
    exit 1
  fi
else
  printf '[错误] 缺少 tools/common.sh，且未安装 curl 无法远程下载。\n' >&2
  exit 1
fi
trap on_error ERR

TOOL_EXIT_CODE=0
SELECTED_ACTION=""
SELECTED_TOOL=""
SELECTED_ARGS=()

setup_locale() {
  if [[ -z "${LANG:-}" ]] || [[ "${LANG:-}" != *UTF-8* && "${LANG:-}" != *utf-8* ]]; then
    if command -v locale >/dev/null 2>&1; then
      local zh_locale
      zh_locale=$(locale -a 2>/dev/null | grep -iE 'zh_CN.*utf8|zh_CN.*utf-8' | head -n1 || true)
      if [[ -n "$zh_locale" ]]; then
        export LANG="$zh_locale"
        export LC_ALL="$zh_locale"
      elif locale -a 2>/dev/null | grep -q 'C.UTF-8'; then
        export LANG="C.UTF-8"
        export LC_ALL="C.UTF-8"
      fi
    fi
  fi
}

ORIG_LANG="${LANG:-}"
ORIG_LC_ALL="${LC_ALL:-}"
ORIG_LC_CTYPE="${LC_CTYPE:-}"

setup_locale

detect_os() {
  OS_ID="unknown"
  OS_VERSION_ID=""
  OS_VERSION_MAJOR=""
  OS_VERSION_MINOR=""
  OS_NAME="Unknown"
  OS_FAMILY=""
  OS_PACKAGE_MANAGER=""
  
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_NAME="${PRETTY_NAME:-}"
    
    if [[ -n "$OS_VERSION_ID" ]]; then
      OS_VERSION_MAJOR="$(echo "$OS_VERSION_ID" | cut -d. -f1)"
      OS_VERSION_MINOR="$(echo "$OS_VERSION_ID" | cut -d. -f2)"
    fi
  elif [[ -f /etc/redhat-release ]]; then
    OS_ID="rhel"
    OS_NAME="$(cat /etc/redhat-release)"
    if echo "$OS_NAME" | grep -qi 'centos'; then
      OS_ID="centos"
    elif echo "$OS_NAME" | grep -qi 'fedora'; then
      OS_ID="fedora"
    fi
    OS_VERSION_MAJOR="$(echo "$OS_NAME" | grep -oE '[0-9]+' | head -n1)"
  elif [[ -f /etc/debian_version ]]; then
    OS_ID="debian"
    OS_NAME="Debian"
    OS_VERSION_ID="$(cat /etc/debian_version)"
    OS_VERSION_MAJOR="$(echo "$OS_VERSION_ID" | cut -d. -f1)"
  else
    OS_ID="unknown"
    OS_NAME="Unknown"
  fi
  
  case "$OS_ID" in
    debian|ubuntu|linuxmint|pop|kali|deepin|zorin)
      OS_FAMILY="debian"
      OS_PACKAGE_MANAGER="apt"
      ;;
    fedora)
      OS_FAMILY="rhel"
      OS_PACKAGE_MANAGER="dnf"
      ;;
    centos)
      OS_FAMILY="rhel"
      if [[ -n "$OS_VERSION_MAJOR" && "$OS_VERSION_MAJOR" =~ ^[0-9]+$ && "$OS_VERSION_MAJOR" -ge 8 ]]; then
        OS_PACKAGE_MANAGER="dnf"
      else
        OS_PACKAGE_MANAGER="yum"
      fi
      ;;
    rhel|ol|almalinux|rocky)
      OS_FAMILY="rhel"
      if [[ -n "$OS_VERSION_MAJOR" && "$OS_VERSION_MAJOR" =~ ^[0-9]+$ && "$OS_VERSION_MAJOR" -ge 8 ]]; then
        OS_PACKAGE_MANAGER="dnf"
      else
        OS_PACKAGE_MANAGER="yum"
      fi
      ;;
    opensuse-leap|opensuse-tumbleweed)
      OS_FAMILY="rhel"
      OS_PACKAGE_MANAGER="zypper"
      ;;
    arch|manjaro|artix)
      OS_FAMILY="arch"
      OS_PACKAGE_MANAGER="pacman"
      ;;
    alpine)
      OS_FAMILY="alpine"
      OS_PACKAGE_MANAGER="apk"
      ;;
    *)
      OS_FAMILY="unknown"
      OS_PACKAGE_MANAGER="unknown"
      ;;
  esac
}

check_display_env() {
  detect_os

  local encoding_ok=0 has_zh_locale=0 need_tip=0

  if [[ "${LANG:-}" == *UTF-8* || "${LANG:-}" == *utf-8* || "${LC_ALL:-}" == *UTF-8* || "${LC_ALL:-}" == *utf-8* || "${LC_CTYPE:-}" == *UTF-8* || "${LC_CTYPE:-}" == *utf-8* ]]; then
    encoding_ok=1
  fi

  if [[ "${LANG:-}" == zh_* || "${LC_ALL:-}" == zh_* || "${LC_CTYPE:-}" == zh_* ]]; then
    has_zh_locale=1
  fi

  if (( encoding_ok == 0 || has_zh_locale == 0 )); then
    need_tip=1
  fi

  (( need_tip == 0 )) && return 0

  printf "%s%s[Tip]%s 中文显示修复建议：\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET" >&2

  if (( encoding_ok == 0 )); then
    printf "       [编码] 当前非 UTF-8，原始 LANG=%s\n" "$ORIG_LANG" >&2
  fi

  if (( has_zh_locale == 0 )); then
    local locale_available=0
    if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qiE 'zh_CN.*utf-?8'; then
      locale_available=1
    fi
    printf "       [区域] " >&2
    if (( locale_available == 1 )); then
      printf "export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8\n" >&2
    else
      printf "请先安装 zh_CN.UTF-8 locale\n" >&2
    fi
  fi

  printf "       [字体] 可安装中文字体：fonts-wqy-zenhei 或 fonts-noto-cjk\n" >&2
  printf "       安装后重连 SSH，或执行 export LANG=zh_CN.UTF-8\n\n" >&2
}

check_display_env

print_banner() {
  printf "%s" "$COLOR_CYAN"
  cat <<'EOF'
 _____   _  _     _____
  ___   _   _   ___    ___   _ __  |___  | | || |   |___  |
 / __| | | | | / __|  / _ \ | '__|    / /  | || |_     / /
 \__ \ | |_| | \__ \ |  __/ | |      / /   |__   _|   / /
 |___/  \__,_| |___/  \___| |_|     /_/       |_|    /_/
EOF
  printf "%s" "$COLOR_RESET"
  printf "%snetool懒人工具箱 v%s%s\n" "$COLOR_BOLD" "$SCRIPT_VERSION" "$COLOR_RESET"
  printf "%s命令行懒人向 Linux 运维脚本%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  print_divider
}

print_section() {
  printf "%s%s----------------------%s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET"
}

confirm_license() {
  if [[ -n "${NETOOL_SKIP_LICENSE:-${AYU_SKIP_LICENSE:-}}" || $# -gt 0 ]]; then
    return 0
  fi

  local agreed=""
  local license_file
  license_file="$(netool_license_file "$LICENSE_VERSION")"

  if [[ -n "${HOME:-}" && -f "$license_file" ]]; then
    return 0
  fi

  printf "%s首次使用脚本，请先阅读并同意用户许可协议。%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  printf "用户许可协议: %s%s%s\n" "$COLOR_CYAN" "$AGREEMENT_URL" "$COLOR_RESET"
  print_section
  if ! read_prompt "是否同意以上条款？(y/n): " agreed; then
    die "无法读取许可确认。"
  fi

  case "$(tolower "$agreed")" in
    y|yes|同意|确认)
      if [[ -n "${HOME:-}" ]]; then
        mkdir -p "$NETOOL_CONFIG_DIR" 2>/dev/null || true
        printf "accepted_at=%s\nversion=%s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date 2>/dev/null || echo unknown)" "$LICENSE_VERSION" >"$(netool_license_file "$LICENSE_VERSION")" 2>/dev/null || true
      fi
      return 0
      ;;
    *)
      log_warn "未同意许可协议，已退出。"
      exit 0
      ;;
  esac
}

check_command_group() {
  local label="$1"
  shift

  local cmd=""
  for cmd in "$@"; do
    if command_exists "$cmd"; then
      printf "  %-28s %s可用%s（%s）\n" "$label" "$COLOR_GREEN" "$COLOR_RESET" "$cmd"
      return 0
    fi
  done

  printf "  %-28s %s缺依赖%s（%s）\n" "$label" "$COLOR_YELLOW" "$COLOR_RESET" "$*"
  return 1
}

check_root_capability() {
  local label="$1"
  if is_root_user; then
    printf "  %-28s %s可用%s（当前 root）\n" "$label" "$COLOR_GREEN" "$COLOR_RESET"
  else
    printf "  %-28s %s需 root%s（请用 root 或 sudo）\n" "$label" "$COLOR_YELLOW" "$COLOR_RESET"
  fi
}

check_file_path() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    printf "  %-28s %s可用%s（%s）\n" "$label" "$COLOR_GREEN" "$COLOR_RESET" "$path"
  else
    printf "  %-28s %s缺失%s（%s）\n" "$label" "$COLOR_YELLOW" "$COLOR_RESET" "$path"
  fi
}

detect_package_manager() {
  if command_exists apt || command_exists apt-get; then
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

run_capability_check() {
  local pkg_mgr=""
  pkg_mgr="$(detect_package_manager)"

  printf "\n%s功能可用性检查：%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf "  %-28s %s\n" "系统" "${PRETTY_NAME:-${NAME:-未知}}"
  fi
  printf "  %-28s %s\n" "包管理器" "$pkg_mgr"
  check_root_capability "root 权限功能"

  printf "\n%s[系统查看与维护]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "系统信息" uname df free awk sed || true
  check_command_group "主机名/时区管理" hostname timedatectl date || true
  check_command_group "系统服务查看" systemctl || true
  check_command_group "基础工具安装" apt apt-get dnf yum apk pacman zypper || true
  check_command_group "Swap 管理" swapon swapoff fallocate mkswap || true
  check_command_group "日志清理" journalctl find du || true
  check_command_group "时间同步管理" chronyc timedatectl ntpdate || true

  printf "\n%s[网络工具]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "网络地址/路由" ip ifconfig || true
  check_command_group "网络端口查看" ss netstat || true
  check_command_group "Ping 测试" ping || true
  check_command_group "DNS 解析" dig nslookup getent || true
  check_command_group "轻量性能测试" dd df ping || true
  check_command_group "HTTPS 证书检查" openssl || true

  printf "\n%s[网络与安全配置]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_file_path "SSH 配置" "/etc/ssh/sshd_config"
  check_command_group "SSH 服务校验" sshd || true
  check_command_group "防火墙管理" ufw firewall-cmd iptables nft || true
  check_command_group "Fail2ban 防护" fail2ban-client || true
  check_command_group "BBR 管理" sysctl modprobe || true
  check_command_group "用户与 SSH 密钥管理" useradd usermod chpasswd getent || true
  check_command_group "定时任务管理" crontab || true

  printf "\n%s[磁盘硬件]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "磁盘基础工具" lsblk findmnt blockdev || true
  check_command_group "磁盘分区工具" parted || true
  check_command_group "硬盘 SMART" smartctl || true
  check_command_group "验盘 fio" fio || true
  check_command_group "盘位映射辅助" udevadm readlink find || true
  check_command_group "磁盘占用分析" du find || true

  printf "\n%s[软件源与 Docker]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "LinuxMirrors 换源" apt apt-get dnf yum pacman zypper || true
  check_command_group "Homebrew 安装" curl git ruby || true
  check_command_group "Docker 查看" docker || true

  printf "\n%s说明：%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  printf "  %s可用%s / %s缺依赖%s / %s需 root%s 三种状态。\n" "$COLOR_GREEN" "$COLOR_RESET" "$COLOR_YELLOW" "$COLOR_RESET" "$COLOR_YELLOW" "$COLOR_RESET"
  printf "  查看类功能缺少少量命令也能降级显示；改系统类功能请先确认备份和目标。\n"
  printf "  硬盘验盘真正执行会全盘写入，必须先预览并输入 DESTROY-DISK-TEST。\n"
}

usage() {
  cat <<EOF
netool懒人工具箱 v${SCRIPT_VERSION}
命令行懒人向 Linux 运维脚本。

用法：
  curl -fsSL ${SHORT_SCRIPT_URL}|bash
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) <工具名> [参数...]

可用工具：
  check         检查当前服务器对各项功能的依赖满足情况
  system        系统信息与基础维护，可追加 info/update/clean/time/users/services
  network       网络信息、端口和连通性检查，可追加 ip/route/ports/ping/dns
  docker        Docker 状态、容器和镜像查看，可追加 status/ps/images/volumes/networks/logs
  basic         基础工具安装，安装常用命令行工具
  host          主机名、时区和时间信息管理
  swap          Swap 管理，查看、创建和删除 swapfile
  firewall      防火墙端口管理，支持 ufw/firewalld/iptables/nftables 检查和常用放行
  security      Fail2ban SSH 防护状态、安装提示和基础配置
  service       进程与 systemd 服务查看/重启
  bbr           BBR 状态查看和内核自带 BBR 启用
  bench         轻量性能测试，查看 CPU/内存/磁盘/网络概况
  mirror        轻量换源（带备份恢复）
  ssh           SSH 端口管理
  disk          磁盘管理总菜单，可追加 status/mount/wipe（破坏性，须显式指定 --devices）
  disk-test     硬盘好坏检测/验盘，全盘写入，会清空被测盘
  slot-map      硬盘盘位映射
  smart-long    启动 SMART 长测
  homebrew      Homebrew 管理（安装/卸载/CLT安装）
  lmirrors      全能换源 + Docker 安装（支持更多发行版）
  init          服务器初始化向导（新服务器一键配置）
  uninstall     一键卸载 netool 懒人工具箱
  update        脚本更新说明/本地仓库拉取
  logclean      日志/缓存/旧内核清理，查看 journald、/var/log、包缓存占用
  user          用户与 SSH 密钥管理，增删用户、上传公钥、禁用密码登录
  cron          定时任务管理，crontab 备份恢复、systemd timer 一览
  ssl-check     HTTPS 证书到期检查，支持多域名批量扫描
  ntp           时间同步管理，配置 chrony/时区，立即同步
  du-analyze    磁盘占用分析，找出大目录和大文件

示例：
  curl -fsSL ${SHORT_SCRIPT_URL}|bash           # 进入菜单
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) system # 系统信息
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) check  # 功能可用性检查
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) init   # 服务器初始化向导
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) -q check  # 静默模式，只输出错误

选项：
  --list        显示可用工具
  -h, --help    显示帮助
  --version     显示版本
  -q, --quiet   静默模式，不输出信息/警告/成功，只输出错误

说明：
  直接运行不带工具名时进入菜单选择。
  传入工具名时，后续参数原样转交给对应脚本。
  本地部署时无需 curl，直接运行 main.sh 即可。
  远程 curl 一键运行详见 REMOTE_USAGE.md。
  两个换源工具区别：mirror 轻量带备份；lmirrors 功能全支持更多发行版+Docker。
EOF
}

list_tools() {
  local b="${COLOR_BOLD}${COLOR_CYAN}"
  local r="${COLOR_RESET}"
  local y="${COLOR_YELLOW}"

  _menu_row() {
    if [[ -n "${3:-}" ]]; then
      printf "  ${b}[%2s]${r} %-10s    ${b}[%2s]${r} %s\n" "$1" "$2" "$3" "$4"
    else
      printf "  ${b}[%2s]${r} %s\n" "$1" "$2"
    fi
  }

  _menu_section() {
    printf "\n%s── %s %s\n" "$b" "$1" "$r"
  }

  _menu_section "系统查看"
  _menu_row "1"  "系统信息"   "11" "时间/用户"
  _menu_row "12" "运行服务"   "23" "主机/时区"
  _menu_row "25" "进程/服务"  "35" "磁盘占用"

  _menu_section "系统维护"
  _menu_row "2"  "系统更新*"  "3"  "系统清理*"
  _menu_row "17" "基础工具"   "20" "Swap 管理"
  _menu_row "30" "日志清理"   "33" "时间同步"

  _menu_section "网络"
  _menu_row "6"  "网络端口"   "13" "DNS 测试"
  _menu_row "14" "Ping 测试"  "19" "性能测试"
  _menu_row "4"  "SSH 管理"   "18" "BBR 优化"
  _menu_row "21" "防火墙"     "34" "证书检查"

  _menu_section "Docker"
  _menu_row "5"  "容器状态"   "16" "镜像/卷/网络"
  _menu_row "22" "安装 Docker"

  _menu_section "磁盘硬件"
  _menu_row "7"  "磁盘管理"   "9"  "盘位映射"
  _menu_row "8"  "验盘检测!"  "10" "SMART 长测"

  _menu_section "用户安全"
  _menu_row "24" "Fail2ban"   "31" "用户管理"
  _menu_row "32" "定时任务"

  _menu_section "软件源"
  _menu_row "15" "轻量换源"   "26" "Homebrew"
  _menu_row "27" "全能换源"

  _menu_section "快捷工具"
  _menu_row "28" "初始化向导" "29" "卸载工具箱"

  _menu_section "其他"
  printf "  ${y}[%2s]${r} 功能检查       ${y}[%2s]${r} 更新脚本\n" "01" "00"
  printf "  ${y}[%2s]${r} 退出\n" "0"

  printf "\n"
  printf "%s说明:${r} *仅提示命令  !毁数据  不确定请先输入 ${b}01${r}\n" "$y"
}

resolve_selection() {
  local input="${1:-}"
  local input_lower
  input_lower="$(tolower "$input")"
  SELECTED_ACTION="tool"
  SELECTED_TOOL=""
  SELECTED_ARGS=()

  case "$input_lower" in
    1|system|sys|status|info|系统|系统信息|系统工具)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(info)
      ;;
    2|system-update|sys-update|update-system|升级系统|系统更新)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(update)
      ;;
    3|system-clean|sys-clean|clean|cleanup|系统清理|清理)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(clean)
      ;;
    4|ssh|sshd|ssh-port|ssh_port|ssh端口)
      SELECTED_TOOL="ssh"
      ;;
    5|docker|dock|dk|容器)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(status)
      ;;
    6|network|net|ip|ports|port-check|网络|网络工具|端口|端口管理)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(ports)
      ;;
    7|disk|disks|fdisk|parted|分区|磁盘|挂载|磁盘管理)
      SELECTED_TOOL="disk"
      ;;
    8|disk-test|disk_test|verify-disk|verify_disk|full-rw-test|rw-test|test|验盘|硬盘检测|硬盘好坏检测|全盘测试|读写校验)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(full-rw-test)
      ;;
    9|slot-map|slot|map|disk-slot|disk_slot|盘位|盘位映射|硬盘盘位)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(slot-map)
      ;;
    10|smart|smart-long|disk-smart|disk_smart|smart长测|硬盘长测)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(smart-long)
      ;;
    11|time|date|users|who|时间|用户|登录用户)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(time-users)
      ;;
    12|system-services|running-services|systemd|运行服务)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(services)
      ;;
    13|dns|resolve|解析|dns解析)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(dns)
      ;;
    14|ping|连通性|ping测试)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(ping)
      ;;
    15|mirror|mirrors|source|sources|repo|repos|换源|软件源|镜像源)
      SELECTED_TOOL="mirror"
      ;;
    16|docker-assets|docker-resources|images|volumes|networks|镜像|数据卷|docker资源)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(images)
      ;;
    17|basic|base|tools|install-tools|基础工具|常用工具|工具安装)
      SELECTED_TOOL="basic"
      ;;
    18|bbr|tcp-bbr|bbr管理|网络优化|加速)
      SELECTED_TOOL="bbr"
      ;;
    19|bench|benchmark|test-scripts|性能测试|测试脚本)
      SELECTED_TOOL="bench"
      ;;
    20|swap|swapfile|虚拟内存|交换分区|swap管理)
      SELECTED_TOOL="swap"
      ;;
    21|firewall|fw|port|防火墙|端口放行|防火墙管理)
      SELECTED_TOOL="firewall"
      ;;
    22|docker-install|docker-setup|install-docker|docker安装|安装docker)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(install)
      ;;
    23|host|hostname|timezone|time-zone|主机名|时区|时间管理)
      SELECTED_TOOL="host"
      ;;
    24|security|secure|fail2ban|ssh-guard|安全|ssh防护|防护)
      SELECTED_TOOL="security"
      ;;
    25|service|services|process|processes|top|进程|服务管理|进程管理)
      SELECTED_TOOL="service"
      ;;
    26|homebrew|brew|brew-install|homebrew-install|brew安装|homebrew安装)
      SELECTED_TOOL="homebrew"
      ;;
    27|lmirrors|linux-mirrors|change-mirrors|linuxmirrors|换源工具|docker换源|软件源切换|全能换源)
      SELECTED_TOOL="lmirrors"
      ;;
    28|init|initialize|setup|new-server|初始化|初始化向导|服务器初始化|新服务器)
      SELECTED_ACTION="init"
      ;;
    29|uninstall|remove|uninstall-toolbox|卸载|卸载工具箱|删除工具箱)
      SELECTED_ACTION="uninstall"
      ;;
    30|logclean|log-clean|clean-logs|日志清理|清理日志)
      SELECTED_TOOL="logclean"
      ;;
    31|user|usermgr|user-mgmt|用户|用户管理)
      SELECTED_TOOL="user"
      ;;
    32|cron|crontab|定时|定时任务|计划任务)
      SELECTED_TOOL="cron"
      ;;
    33|ntp|time-sync|timesync|时间同步|对时)
      SELECTED_TOOL="ntp"
      ;;
    34|ssl-check|sslcheck|cert-check|cert|证书|证书检查|https证书)
      SELECTED_TOOL="ssl-check"
      ;;
    35|du-analyze|du|disk-usage|analyze|磁盘占用|占用分析|大文件)
      SELECTED_TOOL="du-analyze"
      ;;
    01|check|checkup|doctor|env|health|功能检查|可用性检查|环境检查)
      SELECTED_ACTION="check"
      ;;
    00|0update|script-update|self-update|update|脚本更新|更新)
      SELECTED_ACTION="update"
      ;;
    0|q|quit|exit|退出)
      SELECTED_ACTION="exit"
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

tool_rel_path() {
  case "$1" in
    system) printf "tools/system/system.sh" ;;
    network) printf "tools/network/network.sh" ;;
    docker) printf "tools/docker/docker.sh" ;;
    basic) printf "tools/software/basic.sh" ;;
    host) printf "tools/system/host.sh" ;;
    swap) printf "tools/system/swap.sh" ;;
    firewall) printf "tools/security/firewall.sh" ;;
    security) printf "tools/security/security.sh" ;;
    service) printf "tools/system/service.sh" ;;
    bbr) printf "tools/network/bbr.sh" ;;
    bench) printf "tools/network/bench.sh" ;;
    mirror) printf "tools/software/mirror.sh" ;;
    ssh) printf "tools/network/ssh-port.sh" ;;
    disk) printf "tools/disk/disk.sh" ;;
    homebrew) printf "tools/software/homebrew.sh" ;;
    lmirrors) printf "tools/software/lmirrors.sh" ;;
    init) printf "tools/utility/init.sh" ;;
    logclean) printf "tools/system/logclean.sh" ;;
    user) printf "tools/security/user.sh" ;;
    cron) printf "tools/security/cron.sh" ;;
    ssl-check) printf "tools/network/ssl-check.sh" ;;
    ntp) printf "tools/system/ntp.sh" ;;
    du-analyze) printf "tools/disk/du-analyze.sh" ;;
    *) return 1 ;;
  esac
}

tool_script_url() {
  local rel=""
  rel="$(tool_rel_path "$1")" || return 1
  printf "%s/%s" "$RAW_BASE_URL" "$rel"
}

is_local_deploy() {
  [[ -f "${SCRIPT_DIR}/main.sh" && -d "${SCRIPT_DIR}/tools" ]]
}

fetch_remote_file() {
  local rel_path="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if ! curl -fsSL "${RAW_BASE_URL}/${rel_path}" -o "$dest"; then
    log_error "下载失败：${RAW_BASE_URL}/${rel_path}"
    return 1
  fi
  if ! validate_bash_script "$dest"; then
    log_error "远程脚本语法校验失败：${rel_path}"
    return 1
  fi
  chmod 700 "$dest"
  return 0
}

patch_remote_script() {
  local script_file="$1"
  local patched="${script_file}.patched"
  {
    head -1 "$script_file"
    printf '%s\n' ': # netool-remote-bootstrap'
    printf '%s\n' 'if [[ -n "${NETOOL_COMMON_FILE:-}" && -f "$NETOOL_COMMON_FILE" && -z "${NETOOL_COMMON_SOURCED:-}" ]]; then # shellcheck source=/dev/null'
    printf '%s\n' '  source "$NETOOL_COMMON_FILE"'
    printf '%s\n' 'fi'
    tail -n +2 "$script_file" | sed 's/^[[:space:]]*# shellcheck source=.*common.*$/: # legacy/; s/^[[:space:]]*source.*common\.sh.*/: # legacy common source/'
  } > "$patched"
  mv "$patched" "$script_file"
}

ensure_remote_common() {
  local tmp_root="$1"
  local common="${tmp_root}/tools/common.sh"
  local loader="${tmp_root}/tools/load_common.sh"
  [[ -f "$common" ]] || fetch_remote_file "tools/common.sh" "$common" || return 1
  chmod 600 "$common"
  if [[ ! -f "$loader" ]]; then
    curl -fsSL "${RAW_BASE_URL}/tools/load_common.sh" -o "$loader" 2>/dev/null && chmod 700 "$loader" || true
  fi
  return 0
}

tool_display_name() {
  case "$1" in
    system) printf "系统信息与基础维护\n" ;;
    network) printf "网络工具\n" ;;
    docker) printf "Docker 工具\n" ;;
    basic) printf "基础工具安装\n" ;;
    host) printf "主机名/时区管理\n" ;;
    swap) printf "Swap 管理\n" ;;
    firewall) printf "防火墙端口管理\n" ;;
    security) printf "Fail2ban SSH 防护\n" ;;
    service) printf "进程与服务管理\n" ;;
    bbr) printf "BBR 网络优化\n" ;;
    bench) printf "轻量性能测试\n" ;;
    mirror) printf "轻量换源（带备份）\n" ;;
    ssh) printf "SSH 端口管理\n" ;;
    disk) printf "磁盘管理\n" ;;
    homebrew) printf "Homebrew 管理\n" ;;
    lmirrors) printf "全能换源 + Docker\n" ;;
    init) printf "服务器初始化向导\n" ;;
    logclean) printf "日志清理\n" ;;
    user) printf "用户与 SSH 密钥管理\n" ;;
    cron) printf "定时任务管理\n" ;;
    ssl-check) printf "HTTPS 证书检查\n" ;;
    ntp) printf "时间同步管理\n" ;;
    du-analyze) printf "磁盘占用分析\n" ;;
    *) printf "%s\n" "$1" ;;
  esac
}

run_self_update() {
  local origin_url=""
  local update_output=""

  if [[ -f "${SCRIPT_DIR}/main.sh" && -d "${SCRIPT_DIR}/.git" ]] && command -v git >/dev/null 2>&1; then
    origin_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
  fi

  if [[ "$origin_url" == *"gitee.com/suser747/netool"* ]]; then
    log_info "检测到本地 Git 仓库，准备拉取 origin/master。"
    if ! update_output="$(git -C "$SCRIPT_DIR" pull --ff-only origin master 2>&1)"; then
      [[ -z "$update_output" ]] || printf "%s\n" "$update_output" >&2
      log_warn "自动拉取失败，请在仓库目录手动执行：git pull --ff-only origin master"
      return 1
    fi
    [[ -z "$update_output" ]] || printf "%s\n" "$update_output"
    log_success "本地仓库已更新。"
    return 0
  fi

  printf "\n脚本更新：\n"
  printf "  当前版本：v%s\n" "$SCRIPT_VERSION"
  printf "  在线入口：curl -fsSL %s|bash\n" "$SHORT_SCRIPT_URL"
  printf "\n通过在线入口运行时，每次都会拉取 Gitee 最新短入口，无需手动更新。\n"
  printf "如果你是克隆仓库使用，请在仓库目录执行：\n"
  printf "  git pull --ff-only origin master\n"
  # 非 git 仓库或远程不匹配时，仅展示更新说明，未实际更新
  return 2
}

require_command() {
  command_exists "$1" || die "缺少必要命令：$1"
}

run_tool() {
  local tool="$1"
  shift || true

  local rel="" local_path="" tmp_root="" target=""

  rel="$(tool_rel_path "$tool")" || die "未知工具：${tool}"
  local_path="${SCRIPT_DIR}/${rel}"

  if [[ -f "$local_path" ]]; then
    TOOL_EXIT_CODE=0
    export NETOOL=1
    export AYU_TOOLBOX=1
    if [[ -t 1 && -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
      bash "$local_path" "$@" </dev/tty || TOOL_EXIT_CODE=$?
    else
      bash "$local_path" "$@" || TOOL_EXIT_CODE=$?
    fi
    return 0
  fi

  command_exists curl || die "缺少必要命令：curl（远程模式需从 ${RAW_BASE_URL} 下载工具）"

  tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/netool.XXXXXX" 2>/dev/null || mktemp -d)"
  target="${tmp_root}/${rel}"

  if ! fetch_remote_file "$rel" "$target"; then
    rm -rf "$tmp_root"
    exit "$EXIT_DEPENDENCY"
  fi
  patch_remote_script "$target"
  if ! ensure_remote_common "$tmp_root"; then
    rm -rf "$tmp_root"
    exit "$EXIT_DEPENDENCY"
  fi

  export NETOOL=1
  export AYU_TOOLBOX=1
  export NETOOL_REMOTE=1
  export NETOOL_COMMON_FILE="${tmp_root}/tools/common.sh"

  TOOL_EXIT_CODE=0
  if [[ -t 1 && -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
    bash "$target" "$@" </dev/tty || TOOL_EXIT_CODE=$?
  else
    bash "$target" "$@" || TOOL_EXIT_CODE=$?
  fi

  rm -rf "$tmp_root"
}

run_init_wizard() {
  audit_log "init_wizard" "start"
  run_tool init "$@"
  local rc=$?
  TOOL_EXIT_CODE=$rc
  if (( rc == 0 )); then
    audit_log "init_wizard" "complete"
  else
    audit_log "init_wizard" "failed rc=${rc}"
  fi
  return "$rc"
}

run_uninstall() {
  audit_log "uninstall" "requested"

  printf "\n%s%s=== 卸载 netool 懒人工具箱 ===%s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET"
  printf "将执行以下操作：\n"
  printf "  - 删除用户配置：%s~/.config/netool/%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  printf "  - 删除审计日志：%s%s%s\n" "$COLOR_CYAN" "$NETOOL_LOG_DIR" "$COLOR_RESET"
  printf "  - 删除旧版配置：%s~/.config/ayu-toolbox/%s（如存在）\n" "$COLOR_CYAN" "$COLOR_RESET"
  printf "\n%s注意：%s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET"
  printf "  - 不会删除通过工具箱安装的软件（Docker、基础工具等）\n"
  printf "  - 不会恢复修改过的系统配置（SSH端口、BBR、换源、防火墙等）\n"
  printf "  - 仅删除工具箱自身的配置和日志\n"
  printf "\n"

  local confirm=""
  if ! read_prompt "确认卸载 netool 懒人工具箱？(输入 yes 确认): " confirm; then
    log_info "已取消。"
    return 0
  fi

  if [[ "$(tolower "$confirm")" != "yes" ]]; then
    log_info "未输入 yes，已取消。"
    return 0
  fi

  audit_log "uninstall" "confirmed"

  log_info "正在删除配置文件..."
  rm -rf "$NETOOL_CONFIG_DIR" "$NETOOL_LEGACY_CONFIG_DIR" 2>/dev/null || true
  log_success "配置文件已删除"

  if is_root_user; then
    audit_log "uninstall" "complete"
    log_info "正在删除日志目录..."
    rm -rf "$NETOOL_LOG_DIR" "$NETOOL_LEGACY_LOG_DIR" 2>/dev/null || true
    log_success "日志目录已删除"
  fi

  printf "\n"
  log_success "netool 懒人工具箱已卸载。"
  log_info "如果是本地部署，可手动删除项目目录：%s" "$SCRIPT_DIR"
  return 0
}

interactive_loop() {
  local answer=""

  while true; do
    printf "\n"
    list_tools
    print_section
    if ! read_prompt "请输入你的选择: " answer; then
      log_error "无法读取输入。请改用：bash <(curl -fsSL ${SHORT_SCRIPT_URL}) <工具名>"
      exit 1
    fi

    if resolve_selection "$answer"; then
      case "$SELECTED_ACTION" in
        exit)
          log_info "已退出。"
          exit 0
          ;;
        update)
          run_self_update || TOOL_EXIT_CODE=$?
          # 返回码 2 表示非 git 仓库仅展示更新说明，不算失败
          if (( TOOL_EXIT_CODE == 2 )); then
            TOOL_EXIT_CODE=0
          fi
          ;;
        check)
          run_capability_check || TOOL_EXIT_CODE=$?
          ;;
        init)
          run_init_wizard || TOOL_EXIT_CODE=$?
          ;;
        uninstall)
          run_uninstall || TOOL_EXIT_CODE=$?
          ;;
        tool)
          if [[ "$SELECTED_TOOL" == "disk" && "${SELECTED_ARGS[0]:-}" == "full-rw-test" ]]; then
            log_warn "硬盘验盘会全盘写入并清空被测盘。建议先使用 --plan 预览目标。"
          fi
          run_tool "$SELECTED_TOOL" ${SELECTED_ARGS[@]+"${SELECTED_ARGS[@]}"}
          ;;
      esac

      if (( TOOL_EXIT_CODE != 0 )); then
        log_warn "工具执行失败（退出码：${TOOL_EXIT_CODE}），返回菜单。"
      fi
      TOOL_EXIT_CODE=0
      print_divider
      printf "%snetool 懒人工具箱 v%s%s\n" "$COLOR_BOLD" "$SCRIPT_VERSION" "$COLOR_RESET"
      print_divider
    elif [[ -z "$answer" ]]; then
      log_warn "未读取到输入，请重新输入。"
    else
      log_warn "无效输入：${answer}。请输入 0-35、00、01 或工具名称。"
    fi
  done
}

main() {
  while (($# > 0)); do
    case "${1:-}" in
      -h|--help|help) usage; exit "$EXIT_OK" ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit "$EXIT_OK" ;;
      --license|license) printf "%s\n" "$AGREEMENT_URL"; exit "$EXIT_OK" ;;
      --list|list) list_tools; exit "$EXIT_OK" ;;
      -q|--quiet) QUIET=1; shift ;;
      --) shift; break ;;
      -*) die "未知选项：$1。使用 --help 查看帮助。"; exit "$EXIT_USAGE" ;;
      *) break ;;
    esac
  done

  if ! command_exists mktemp; then
    log_warn "缺少 mktemp，部分功能可能受限。"
  fi

  if (( QUIET != 1 )); then
    print_banner
  fi
  confirm_license "$@"

  if (($# > 0)); then
    if resolve_selection "$1"; then
      shift
      case "$SELECTED_ACTION" in
        update)
          rc=0
          run_self_update || rc=$?
          # 0=已更新，2=非 git 仓库仅展示说明（均视为正常结束），1=拉取失败
          if (( rc == 0 || rc == 2 )); then
            exit "$EXIT_OK"
          fi
          exit "$EXIT_ERROR"
          ;;
        check)
          run_capability_check
          exit "$EXIT_OK"
          ;;
        init)
          run_init_wizard
          exit "$?"
          ;;
        uninstall)
          run_uninstall
          exit "$?"
          ;;
        exit)
          exit "$EXIT_OK"
          ;;
        tool)
          run_tool "$SELECTED_TOOL" ${SELECTED_ARGS[@]+"${SELECTED_ARGS[@]}"} "$@"
          ;;
      esac
      exit "$TOOL_EXIT_CODE"
    else
      die "未知工具：$1。可执行 --list 查看可用工具。"
      exit "$EXIT_USAGE"
    fi
  fi

  interactive_loop
}

main "$@"
