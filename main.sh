#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 主入口脚本
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: main
# 脚本版本: 2.2
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

# Bash 3.2+（macOS 自带 / CentOS 7 等旧环境）
if [[ "${BASH_VERSINFO[0]:-0}" -lt 3 ]] || { [[ "${BASH_VERSINFO[0]:-0}" -eq 3 ]] && [[ "${BASH_VERSINFO[1]:-0}" -lt 2 ]]; }; then
  printf '[错误] 需要 Bash 3.2 或更高版本（当前: %s）。\n' "${BASH_VERSION:-未知}" >&2
  exit 1
fi

SCRIPT_NAME="netool"
REPO_URL="${NETOOL_REPO_URL:-https://gitee.com/suser747/netool}"
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

SCRIPT_VERSION="$(head -n1 "${SCRIPT_DIR}/VERSION" 2>/dev/null | tr -d '[:space:]')"
SCRIPT_VERSION="${SCRIPT_VERSION:-2.3}"

# =============================================================================
# 公共库 bootstrap：本地 tools/common.sh 优先；纯 curl 模式则临时下载
# =============================================================================
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
trap '[[ -n "${NETOOL_BOOTSTRAP_DIR:-}" ]] && rm -rf "$NETOOL_BOOTSTRAP_DIR"' EXIT

# 与 common.sh / README 统一的在线入口（短链用于用户复制，raw/master 用于子脚本下载）
SHORT_SCRIPT_URL="${NETOOL_SHORT_ENTRY_URL}"
RAW_BASE_URL="${NETOOL_RAW_BASE}"
SCRIPT_URL="${NETOOL_ENTRY_URL}"
AGREEMENT_URL="${NETOOL_REPO_URL}/blob/${NETOOL_RAW_BRANCH}/USER_AGREEMENT.md"

if [[ -f "${SCRIPT_DIR}/tools/version.sh" ]]; then
  # shellcheck source=tools/version.sh
  source "${SCRIPT_DIR}/tools/version.sh"
fi
if ! declare -F netool_print_all_versions >/dev/null 2>&1; then
  netool_print_all_versions() {
    printf "netool 懒人工具箱 v%s\n" "$SCRIPT_VERSION"
  }
fi

TOOL_EXIT_CODE=0
SELECTED_ACTION=""
SELECTED_TOOL=""
SELECTED_ARGS=()

# 尝试设置 UTF-8 / 中文 locale，避免菜单与日志乱码
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

# =============================================================================
# 操作系统识别与中文显示环境提示
# =============================================================================
# 解析 /etc/os-release 等，填充 OS_ID / OS_FAMILY / OS_PACKAGE_MANAGER
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

# locale 非 UTF-8 或非中文时给出一次性提示（可用 NETOOL_SKIP_LOCALE_TIP=1 跳过）
check_display_env() {
  [[ "${NETOOL_SKIP_LOCALE_TIP:-0}" == "1" ]] && return 0

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

# 打印 netool 横幅与版本号
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

# 打印带颜色的章节标题
print_section() {
  printf "%s%s----------------------%s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET"
}

# 首次运行展示用户许可，写入 ~/.config/netool/license-v1
confirm_license() {
  if [[ -n "${NETOOL_SKIP_LICENSE:-}" || -n "${AYU_SKIP_LICENSE:-}" || $# -gt 0 ]]; then
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

# check 子项：一组命令中至少一个可用则标记为可用
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

# check 子项：检测当前用户是否具备 root/sudo 能力
check_root_capability() {
  local label="$1"
  if is_root_user; then
    printf "  %-28s %s可用%s（当前 root）\n" "$label" "$COLOR_GREEN" "$COLOR_RESET"
  else
    printf "  %-28s %s需 root%s（请用 root 或 sudo）\n" "$label" "$COLOR_YELLOW" "$COLOR_RESET"
  fi
}

# check 子项：关键路径可读/可写状态
check_file_path() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    printf "  %-28s %s可用%s（%s）\n" "$label" "$COLOR_GREEN" "$COLOR_RESET" "$path"
  else
    printf "  %-28s %s缺失%s（%s）\n" "$label" "$COLOR_YELLOW" "$COLOR_RESET" "$path"
  fi
}

# check 子项：根据 OS 推断包管理器名称
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

# 内置 check：依赖、权限、路径、各工具所需命令的可用性矩阵
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

  printf "\n%s[应用 / 中间件]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "Web 服务器检查" nginx apache2 httpd caddy || true
  check_command_group "数据库客户端" mysql psql redis-cli || true
  check_command_group "应用配置扫描" find docker || true
  check_command_group "权限审计" awk visudo || true
  check_command_group "日志查看" journalctl tail || true

  printf "\n%s[软件源与 Docker]%s\n" "$COLOR_CYAN" "$COLOR_RESET"
  check_command_group "全能换源 (lmirrors)" apt apt-get dnf yum pacman zypper || true
  check_command_group "Homebrew 安装" curl git ruby || true
  check_command_group "Docker 查看" docker || true

  printf "\n%s说明：%s\n" "$COLOR_BOLD" "$COLOR_RESET"
  printf "  %s可用%s / %s缺依赖%s / %s需 root%s 三种状态。\n" "$COLOR_GREEN" "$COLOR_RESET" "$COLOR_YELLOW" "$COLOR_RESET" "$COLOR_YELLOW" "$COLOR_RESET"
  printf "  查看类功能缺少少量命令也能降级显示；改系统类功能请先确认备份和目标。\n"
  printf "  硬盘验盘真正执行会全盘写入，必须先预览并输入 DESTROY-DISK-TEST。\n"
}

# =============================================================================
# 内置：只读状态面板与版本展示（不下载子脚本）
# =============================================================================
# status 子项：格式化输出「标签 值」一行
status_line() {
  printf "  %-12s %s\n" "$1" "$2"
}

# status 子项：打印分节标题
status_section() {
  printf "\n%s[%s]%s\n" "$COLOR_CYAN" "$1" "$COLOR_RESET"
}

# 内置 status：系统/时间/网络/安全/Docker/工具箱部署方式摘要（不下载子脚本）
run_status_panel() {
  detect_os

  printf "\n%s=== netool 状态面板 ===%s\n" "$COLOR_BOLD" "$COLOR_RESET"

  status_section "系统"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    status_line "发行版" "${PRETTY_NAME:-${NAME:-未知}}"
  else
    status_line "发行版" "${OS_NAME:-未知}"
  fi
  status_line "内核" "$(uname -r 2>/dev/null || echo 未知)"
  status_line "架构" "$(uname -m 2>/dev/null || echo 未知)"
  status_line "主机名" "$(hostname 2>/dev/null || echo 未知)"
  if command_exists uptime; then
    status_line "运行时间" "$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up/up/' | sed 's/,.*//')"
  fi
  if command_exists free; then
    status_line "内存" "$(free -h 2>/dev/null | awk '/^Mem:/ {printf "%s 已用 / %s 总量", $3, $2}')"
  fi
  if command_exists df; then
    status_line "根分区" "$(df -h / 2>/dev/null | awk 'NR==2 {printf "%s 已用 %s / %s (%s)", $6, $3, $2, $5}')"
  fi

  status_section "时间"
  status_line "当前时间" "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
  if command_exists timedatectl; then
    status_line "时区" "$(timedatectl show -p Timezone --value 2>/dev/null || timedatectl 2>/dev/null | awk '/Time zone/ {print $3}')"
    status_line "NTP 同步" "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo 未知)"
  elif command_exists chronyc; then
    status_line "chrony" "$(chronyc tracking 2>/dev/null | awk -F: '/Leap status/ {gsub(/^ +/,"",$2); print $2; exit}')"
  fi

  status_section "网络"
  local primary_ip
  primary_ip="$(netool_primary_ip 2>/dev/null || true)"
  status_line "主 IP" "${primary_ip:-未知}"
  if command_exists ss || command_exists netstat; then
    local ssh_listen
    ssh_listen="$(netool_listening_tcp_local_addrs 2>/dev/null | awk -F: '{p=$NF; if(p==22||p==2222){print $0; exit}}')"
    status_line "SSH 监听" "${ssh_listen:-未检测到}"
  fi
  if command_exists sysctl; then
    status_line "TCP 拥塞" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo 未知)"
  fi

  status_section "安全"
  if command_exists ufw && ufw status 2>/dev/null | grep -qi 'Status:'; then
    status_line "防火墙" "$(ufw status 2>/dev/null | head -n1 | sed 's/Status: //')"
  elif command_exists firewall-cmd; then
    status_line "firewalld" "$(firewall-cmd --state 2>/dev/null || echo 未运行)"
  elif command_exists iptables; then
    status_line "iptables" "$([[ $(iptables -L -n 2>/dev/null | wc -l) -gt 8 ]] && echo 有规则 || echo 规则较少/空)"
  else
    status_line "防火墙" "未检测到 ufw/firewalld/iptables"
  fi
  if command_exists fail2ban-client; then
    status_line "Fail2ban" "$(fail2ban-client ping 2>/dev/null && fail2ban-client status 2>/dev/null | awk -F: '/Number of jail/{gsub(/^ +/,"",$2); print "运行中, jail "$2; exit}' || echo 未运行)"
  else
    status_line "Fail2ban" "未安装"
  fi

  status_section "Docker"
  if command_exists docker; then
    if docker info >/dev/null 2>&1; then
      status_line "服务" "运行中"
      status_line "容器" "$(docker ps -q 2>/dev/null | wc -l | tr -d ' ') 运行 / $(docker ps -aq 2>/dev/null | wc -l | tr -d ' ') 总计"
      status_line "镜像" "$(docker images -q 2>/dev/null | sort -u | wc -l | tr -d ' ') 个"
    else
      status_line "服务" "已安装但未运行或无权限"
    fi
  else
    status_line "Docker" "未安装"
  fi

  status_section "工具箱"
  status_line "版本" "v${SCRIPT_VERSION}"
  if is_local_deploy; then
    status_line "部署" "本地 (${SCRIPT_DIR})"
  else
    status_line "部署" "远程/管道模式"
  fi
  status_line "许可" "$([[ -f "$(netool_license_file "${LICENSE_VERSION}")" ]] && echo 已接受 || echo 未确认)"

  printf "\n%s提示:%s 依赖与命令可用性请运行 ${COLOR_BOLD}./main.sh check${COLOR_RESET}\n" "$COLOR_YELLOW" "$COLOR_RESET"
}

# 内置 versions：读取 tools/versions.env 或远程拉取后展示组件版本
run_versions_display() {
  if [[ -f "${SCRIPT_DIR}/tools/versions.env" ]]; then
    netool_print_all_versions "$SCRIPT_DIR"
    return 0
  fi
  if command_exists curl; then
    local tmp_root=""
    tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/netool-ver.XXXXXX" 2>/dev/null || mktemp -d)"
    mkdir -p "${tmp_root}/tools"
    if curl -fsSL "${RAW_BASE_URL}/tools/versions.env" -o "${tmp_root}/tools/versions.env" 2>/dev/null; then
      netool_print_all_versions "$tmp_root"
      rm -rf "$tmp_root"
      return 0
    fi
    rm -rf "$tmp_root"
  fi
  printf "netool 懒人工具箱 v%s\n" "$SCRIPT_VERSION"
  log_info "完整组件版本列表需本地部署或联网读取 tools/versions.env"
}

# 打印 --help 用法与示例
usage() {
  cat <<EOF
netool懒人工具箱 v${SCRIPT_VERSION}
命令行懒人向 Linux 运维脚本。

用法：
  curl -fsSL ${SHORT_SCRIPT_URL}|bash
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) <工具名> [参数...]

可用工具：
  check         检查当前服务器对各项功能的依赖满足情况
  status        一键状态面板（系统/网络/安全/Docker 摘要，只读）
  versions      显示主版本与各组件版本号
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
  update        更新 netool 工具箱（别名 self-update）
  self-update   同 update
  logclean      日志/缓存/旧内核清理，查看 journald、/var/log、包缓存占用
  user          用户与 SSH 密钥管理，增删用户、上传公钥、禁用密码登录
  cron          定时任务管理，crontab 备份恢复、systemd timer 一览
  ssl-check     HTTPS 证书到期检查，支持多域名批量扫描
  ntp           时间同步管理，配置 chrony/时区，立即同步
  du-analyze    磁盘占用分析，找出大目录和大文件
  web           Web 服务器 (Nginx/Apache/Caddy) 配置检查
  db            数据库状态与配置查看 (MySQL/PG/Redis)
  app-config    应用配置扫描 (Compose/.env/Supervisor)
  audit         用户/权限/sudo/SSH 只读审计
  logs          日志占用与监控 agent 查看
  cron-templates 常用 crontab 模板 (cert-renew/disk-alert 等)

示例：
  curl -fsSL ${SHORT_SCRIPT_URL}|bash           # 进入菜单
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) system info   # 指定子命令
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) system        # 进入系统工具子菜单
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) self-update   # 更新工具箱
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) check  # 功能可用性检查
  bash <(curl -fsSL ${SHORT_SCRIPT_URL}) status # 一键状态面板
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
  完整使用说明见 README.md。
  两个换源工具区别：mirror 轻量带备份；lmirrors 功能全支持更多发行版+Docker。
EOF
}

# 打印 --list 工具分类与别名列表（主菜单：大类 → 子脚本内二级菜单）
list_tools() {
  local b="${COLOR_BOLD}${COLOR_CYAN}"
  local r="${COLOR_RESET}"
  local y="${COLOR_YELLOW}"

  _menu_row() {
    local out="" piece i
    for ((i = 1; i <= 7; i += 2)); do
      if [[ -n "${!i:-}" ]]; then
        local n="${!i}"
        local lbl_idx=$((i + 1))
        local lbl="${!lbl_idx:-}"
        printf -v piece "  ${b}[%2s]${r} %-12s" "$n" "$lbl"
        out+="$piece"
      fi
    done
    printf "%s\n" "$out"
  }

  _menu_section() {
    printf "\n%s── %s %s\n" "$b" "$1" "$r"
  }

  _menu_section "常用"
  _menu_row "01" "功能检查"   "02" "状态面板"   "03" "组件版本"   "" ""

  _menu_section "系统"
  _menu_row "1"  "系统工具"   "2"  "主机/时区"  "3"  "进程/服务"  "4"  "磁盘占用"
  _menu_row "5"  "基础工具"   "6"  "Swap 管理"  "7"  "日志清理"   "8"  "时间同步"

  _menu_section "网络"
  _menu_row "9"  "网络工具"   "10" "性能测试"   "11" "SSH 管理"   "12" "BBR 优化"
  _menu_row "13" "防火墙"     "14" "证书检查"   ""  ""          ""  ""

  _menu_section "Docker / 磁盘"
  _menu_row "15" "Docker"     "16" "磁盘管理"   ""  ""          ""  ""

  _menu_section "安全"
  _menu_row "17" "Fail2ban"   "18" "用户管理"   "19" "定时任务"   ""  ""

  _menu_section "应用 / 中间件"
  _menu_row "20" "Web 服务器" "21" "数据库"     "22" "应用配置"   "23" "日志监控"
  _menu_row "24" "权限审计"   "25" "定时模板"   ""  ""          ""  ""

  _menu_section "软件源"
  _menu_row "26" "轻量换源"   "27" "Homebrew"   "28" "全能换源"   ""  ""

  _menu_section "快捷"
  _menu_row "29" "初始化"     "30" "卸载工具箱" "31" "更新工具箱" ""  ""

  _menu_row "0"  "退出"       ""  ""          ""  ""           ""  ""

  printf "\n"
  printf "%s说明:${r} 选编号进入对应工具的子菜单；不确定可先输入 ${b}01${r} 做功能检查\n" "$y"
  print_main_menu_nav_hint
}

# 主菜单编号解析：只选工具大类，不带默认子命令（一律进子脚本二级菜单）
resolve_menu_selection() {
  local input="${1:-}"
  input="$(normalize_user_input "$input")"
  local key
  key="$(tolower "$input")"

  SELECTED_ACTION="tool"
  SELECTED_TOOL=""
  SELECTED_ARGS=()

  case "$key" in
    01|001|check|功能检查) SELECTED_ACTION="check"; return 0 ;;
    02|002|status|状态|状态面板) SELECTED_ACTION="status"; return 0 ;;
    03|003|versions|版本|组件版本) SELECTED_ACTION="versions"; return 0 ;;
    0|q|quit|exit|退出) SELECTED_ACTION="exit"; return 0 ;;
  esac

  if [[ "$key" =~ ^0*[0-9]+$ ]]; then
    key="$((10#${key}))"
  fi

  case "$key" in
    1)  SELECTED_TOOL="system" ;;
    2)  SELECTED_TOOL="host" ;;
    3)  SELECTED_TOOL="service" ;;
    4)  SELECTED_TOOL="du-analyze" ;;
    5)  SELECTED_TOOL="basic" ;;
    6)  SELECTED_TOOL="swap" ;;
    7)  SELECTED_TOOL="logclean" ;;
    8)  SELECTED_TOOL="ntp" ;;
    9)  SELECTED_TOOL="network" ;;
    10) SELECTED_TOOL="bench" ;;
    11) SELECTED_TOOL="ssh" ;;
    12) SELECTED_TOOL="bbr" ;;
    13) SELECTED_TOOL="firewall" ;;
    14) SELECTED_TOOL="ssl-check" ;;
    15) SELECTED_TOOL="docker" ;;
    16) SELECTED_TOOL="disk" ;;
    17) SELECTED_TOOL="security" ;;
    18) SELECTED_TOOL="user" ;;
    19) SELECTED_TOOL="cron" ;;
    20) SELECTED_TOOL="web" ;;
    21) SELECTED_TOOL="db" ;;
    22) SELECTED_TOOL="app-config" ;;
    23) SELECTED_TOOL="logs" ;;
    24) SELECTED_TOOL="audit" ;;
    25) SELECTED_TOOL="cron-templates" ;;
    26) SELECTED_TOOL="mirror" ;;
    27) SELECTED_TOOL="homebrew" ;;
    28) SELECTED_TOOL="lmirrors" ;;
    29) SELECTED_ACTION="init"; return 0 ;;
    30) SELECTED_ACTION="uninstall"; return 0 ;;
    31) SELECTED_ACTION="update"; return 0 ;;
    *) return 1 ;;
  esac
  return 0
}

# 执行主菜单选中项并统一反馈 / 暂停
run_menu_action() {
  local label="" detail=""
  TOOL_EXIT_CODE=0

  case "$SELECTED_ACTION" in
    exit)
      log_info "已退出。"
      exit 0
      ;;
    update)
      netool_print_action_start "更新工具箱"
      run_self_update || TOOL_EXIT_CODE=$?
      if (( TOOL_EXIT_CODE == 2 )); then TOOL_EXIT_CODE=0; fi
      ;;
    check)
      netool_print_action_start "功能检查"
      run_capability_check || TOOL_EXIT_CODE=$?
      ;;
    status)
      netool_print_action_start "状态面板"
      run_status_panel || TOOL_EXIT_CODE=$?
      ;;
    versions)
      netool_print_action_start "组件版本"
      run_versions_display || TOOL_EXIT_CODE=$?
      ;;
    init)
      netool_print_action_start "初始化向导"
      run_init_wizard || TOOL_EXIT_CODE=$?
      ;;
    uninstall)
      netool_print_action_start "卸载工具箱"
      run_uninstall || TOOL_EXIT_CODE=$?
      ;;
    tool)
      label="$(tool_display_name "$SELECTED_TOOL")"
      detail="${SELECTED_ARGS[*]:-}"
      netool_print_action_start "$label" "$detail"
      if [[ "$SELECTED_TOOL" == "disk" ]]; then
        log_info "磁盘类操作请在子菜单中选择；破坏性操作须先 --plan。"
      fi
      run_tool "$SELECTED_TOOL" ${SELECTED_ARGS[@]+"${SELECTED_ARGS[@]}"}
      ;;
  esac

  if (( TOOL_EXIT_CODE != 0 )); then
    log_warn "执行失败（退出码：${TOOL_EXIT_CODE}）。可先运行 01 做功能检查。"
  else
    log_success "执行完成。"
  fi
  netool_pause_menu
  TOOL_EXIT_CODE=0
}

# 检测交互菜单是否可用；curl | bash 时若 /dev/tty 仍可用则警告后继续
check_interactive_tty() {
  [[ "${NETOOL_ALLOW_PIPE_MENU:-0}" == "1" ]] && return 0
  if [[ -t 0 ]]; then
    return 0
  fi
  if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
    log_warn "检测到 stdin 非终端（常见于 curl | bash 管道模式）。"
    log_info "若菜单无法输入，请改用: bash <(curl -fsSL ${SHORT_SCRIPT_URL})"
    return 0
  fi
  log_error "当前 stdin 非终端，无法使用交互菜单。"
  log_info "请改用进程替换进入菜单："
  printf "  bash <(curl -fsSL %s)\n" "$SHORT_SCRIPT_URL"
  log_info "或直接带参数执行，例如："
  printf "  bash <(curl -fsSL %s) status\n" "$SHORT_SCRIPT_URL"
  exit "$EXIT_USAGE"
}

# CLI / 别名解析：支持子命令参数；纯数字优先走主菜单大类映射
resolve_selection() {
  local input="${1:-}"
  input="$(normalize_user_input "$input")"
  local input_lower
  input_lower="$(tolower "$input")"

  SELECTED_ACTION="tool"
  SELECTED_TOOL=""
  SELECTED_ARGS=()

  # 主菜单编号（01-25、0）与 resolve_menu_selection 一致
  if [[ "$input_lower" =~ ^[0-9]+$ ]]; then
    if resolve_menu_selection "$input_lower"; then
      return 0
    fi
  fi

  # 兼容旧版菜单编号 36-39
  case "$input_lower" in
    36) SELECTED_ACTION="check"; return 0 ;;
    37) SELECTED_ACTION="status"; return 0 ;;
    38) SELECTED_ACTION="versions"; return 0 ;;
    39) SELECTED_ACTION="update"; return 0 ;;
  esac

  case "$input_lower" in
    check|checkup|doctor|env|health|功能检查|可用性检查|环境检查)
      SELECTED_ACTION="check"
      ;;
    status|overview|panel|状态|状态面板|概览)
      SELECTED_ACTION="status"
      ;;
    versions|version-all|组件版本|版本列表)
      SELECTED_ACTION="versions"
      ;;
    update|self-update|selfupdate|script-update|0update|工具箱更新|更新工具箱|脚本更新)
      SELECTED_ACTION="update"
      ;;
    init|initialize|setup|new-server|初始化|初始化向导|服务器初始化|新服务器)
      SELECTED_ACTION="init"
      ;;
    uninstall|remove|uninstall-toolbox|卸载|卸载工具箱|删除工具箱)
      SELECTED_ACTION="uninstall"
      ;;
    0|q|quit|exit|退出)
      SELECTED_ACTION="exit"
      ;;
    system|sys|系统|系统工具)
      SELECTED_TOOL="system"
      ;;
    info|系统信息)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(info)
      ;;
    time|date|users|who|时间|用户|登录用户|time-users|time_users)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(time-users)
      ;;
    system-services|running-services|systemd|运行服务|services)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(services)
      ;;
    system-update|sys-update|update-system|升级系统|系统更新)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(update)
      ;;
    system-clean|sys-clean|cleanup|系统清理)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(clean)
      ;;
    clean)
      SELECTED_TOOL="system"
      SELECTED_ARGS=(clean)
      ;;
    host|hostname|timezone|time-zone|主机名|时区|时间管理)
      SELECTED_TOOL="host"
      ;;
    service|services|process|processes|top|进程|服务管理|进程管理)
      SELECTED_TOOL="service"
      ;;
    du-analyze|du|disk-usage|analyze|磁盘占用|占用分析|大文件)
      SELECTED_TOOL="du-analyze"
      ;;
    basic|base|tools|install-tools|基础工具|常用工具|工具安装)
      SELECTED_TOOL="basic"
      ;;
    swap|swapfile|虚拟内存|交换分区|swap管理)
      SELECTED_TOOL="swap"
      ;;
    logclean|log-clean|clean-logs|日志清理|清理日志)
      SELECTED_TOOL="logclean"
      ;;
    ntp|time-sync|timesync|时间同步|对时)
      SELECTED_TOOL="ntp"
      ;;
    network|net|ip|网络|网络工具)
      SELECTED_TOOL="network"
      ;;
    ports|port-check|端口|端口管理)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(ports)
      ;;
    dns|resolve|解析|dns解析)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(dns)
      ;;
    ping|连通性|ping测试)
      SELECTED_TOOL="network"
      SELECTED_ARGS=(ping)
      ;;
    bench|benchmark|test-scripts|性能测试|测试脚本)
      SELECTED_TOOL="bench"
      ;;
    ssh|sshd|ssh-port|ssh_port|ssh端口)
      SELECTED_TOOL="ssh"
      ;;
    bbr|tcp-bbr|bbr管理|网络优化|加速)
      SELECTED_TOOL="bbr"
      ;;
    firewall|fw|防火墙|端口放行|防火墙管理)
      SELECTED_TOOL="firewall"
      ;;
    ssl-check|sslcheck|cert-check|cert|证书|证书检查|https证书)
      SELECTED_TOOL="ssl-check"
      ;;
    docker|dock|dk|容器)
      SELECTED_TOOL="docker"
      ;;
    docker-status|容器状态)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(status)
      ;;
    docker-assets|docker-resources|images|volumes|networks|镜像|数据卷|docker资源)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(images)
      ;;
    docker-install|docker-setup|install-docker|docker安装|安装docker)
      SELECTED_TOOL="docker"
      SELECTED_ARGS=(install)
      ;;
    disk|disks|fdisk|parted|分区|磁盘|挂载|磁盘管理)
      SELECTED_TOOL="disk"
      ;;
    slot-map|slot|map|disk-slot|disk_slot|盘位|盘位映射|硬盘盘位)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(slot-map)
      ;;
    disk-test|disk_test|verify-disk|verify_disk|full-rw-test|rw-test|test|验盘|硬盘检测|硬盘好坏检测|全盘测试|读写校验)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(full-rw-test)
      ;;
    smart|smart-long|disk-smart|disk_smart|smart长测|硬盘长测)
      SELECTED_TOOL="disk"
      SELECTED_ARGS=(smart-long)
      ;;
    security|secure|fail2ban|ssh-guard|安全|ssh防护|防护)
      SELECTED_TOOL="security"
      ;;
    user|usermgr|user-mgmt|用户|用户管理)
      SELECTED_TOOL="user"
      ;;
    cron|crontab|定时|定时任务|计划任务)
      SELECTED_TOOL="cron"
      ;;
    web|nginx|apache|caddy|web服务器)
      SELECTED_TOOL="web"
      ;;
    db|database|mysql|redis|postgres|数据库)
      SELECTED_TOOL="db"
      ;;
    app-config|appconfig|应用配置)
      SELECTED_TOOL="app-config"
      ;;
    audit|权限审计|安全审计)
      SELECTED_TOOL="audit"
      ;;
    logs|log-monitor|日志监控)
      SELECTED_TOOL="logs"
      ;;
    cron-templates|cron-template|定时模板)
      SELECTED_TOOL="cron-templates"
      ;;
    mirror|mirrors|source|sources|repo|repos|换源|软件源|镜像源|轻量换源)
      SELECTED_TOOL="mirror"
      ;;
    homebrew|brew|brew-install|homebrew-install|brew安装|homebrew安装)
      SELECTED_TOOL="homebrew"
      ;;
    lmirrors|linux-mirrors|change-mirrors|linuxmirrors|换源工具|docker换源|软件源切换|全能换源)
      SELECTED_TOOL="lmirrors"
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

# =============================================================================
# 工具路由：菜单别名 → tools/ 下相对路径
# =============================================================================
# 工具别名 → tools/ 下相对路径（未知别名返回 1）
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
    web) printf "tools/apps/web.sh" ;;
    db) printf "tools/apps/db.sh" ;;
    app-config) printf "tools/apps/app-config.sh" ;;
    audit) printf "tools/apps/audit.sh" ;;
    logs) printf "tools/apps/logs.sh" ;;
    cron-templates) printf "tools/apps/cron-templates.sh" ;;
    *) return 1 ;;
  esac
}

# 构造子脚本 Gitee raw URL
tool_script_url() {
  local rel=""
  rel="$(tool_rel_path "$1")" || return 1
  printf "%s/%s" "$RAW_BASE_URL" "$rel"
}

# 是否存在本地 main.sh + tools/ 目录（决定走本地还是远程下载）
is_local_deploy() {
  [[ -f "${SCRIPT_DIR}/main.sh" && -d "${SCRIPT_DIR}/tools" ]]
}

# =============================================================================
# 远程模式：从 Gitee raw 下载子脚本，校验后执行
# =============================================================================
# 从 RAW_BASE_URL 下载相对路径文件，bash -n 校验后 chmod 700
fetch_remote_file() {
  local rel_path="$1"
  local dest="$2"
  local cached=""
  mkdir -p "$(dirname "$dest")"

  if [[ "${NETOOL_NO_CACHE:-0}" != "1" ]]; then
    cached="$(netool_cache_path "$rel_path")"
    if netool_cache_fresh "$cached" && validate_bash_script "$cached"; then
      cp "$cached" "$dest"
      chmod 700 "$dest"
      return 0
    fi
  fi

  if ! curl -fsSL "${RAW_BASE_URL}/${rel_path}" -o "$dest"; then
    log_error "下载失败：${RAW_BASE_URL}/${rel_path}"
    return 1
  fi
  if ! validate_bash_script "$dest"; then
    log_error "远程脚本语法校验失败：${rel_path}"
    return 1
  fi
  chmod 700 "$dest"

  if [[ "${NETOOL_NO_CACHE:-0}" != "1" && -n "$cached" ]]; then
    mkdir -p "$(dirname "$cached")"
    cp "$dest" "$cached" 2>/dev/null || true
  fi
  return 0
}

# 远程脚本注入 NETOOL_COMMON_FILE bootstrap，避免重复 source common
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

# 远程临时目录确保 common.sh / load_common.sh 可用
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

# 工具别名 → 中文显示名（菜单用）
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
    web) printf "Web 服务器 (Nginx/Apache/Caddy)\n" ;;
    db) printf "数据库 (MySQL/PG/Redis)\n" ;;
    app-config) printf "应用配置扫描\n" ;;
    audit) printf "权限与安全审计\n" ;;
    logs) printf "日志与监控查看\n" ;;
    cron-templates) printf "定时任务模板\n" ;;
    *) printf "%s\n" "$1" ;;
  esac
}

# update 命令：本地 git pull 或提示 curl 在线入口已是最新
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

# 缺少命令时 die 退出
require_command() {
  command_exists "$1" || die "缺少必要命令：$1"
}

# =============================================================================
# run_tool — 统一子工具调度：本地直跑 / 远程下载临时脚本
# =============================================================================
run_tool() {
  local tool="$1"
  shift || true

  local rel="" local_path="" tmp_root="" target=""

  rel="$(tool_rel_path "$tool")" || die "未知工具：${tool}"
  local_path="${SCRIPT_DIR}/${rel}"

  if [[ -f "$local_path" ]]; then
    TOOL_EXIT_CODE=0
    export NETOOL=1
    export QUIET="${QUIET:-0}"
    export NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
    export NETOOL_ENTRY_URL="${SHORT_SCRIPT_URL}"
    export NETOOL_MAIN_SH="${SCRIPT_DIR}/main.sh"
    if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
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
  export NETOOL_REMOTE=1
  export QUIET="${QUIET:-0}"
  export NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
  export NETOOL_ENTRY_URL="${SHORT_SCRIPT_URL}"
  export NETOOL_COMMON_FILE="${tmp_root}/tools/common.sh"

  TOOL_EXIT_CODE=0
  if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then
    bash "$target" "$@" </dev/tty || TOOL_EXIT_CODE=$?
  else
    bash "$target" "$@" || TOOL_EXIT_CODE=$?
  fi

  rm -rf "$tmp_root"
}

# init 向导包装：审计日志 + 委托 run_tool init
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

# uninstall：删除 ~/.config/netool 与 /var/log/netool（不卸载已装软件）
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

# 交互式菜单主循环
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

    if resolve_menu_selection "$answer"; then
      run_menu_action
      print_divider
      printf "%snetool 懒人工具箱 v%s%s\n" "$COLOR_BOLD" "$SCRIPT_VERSION" "$COLOR_RESET"
      print_divider
    elif [[ -z "$answer" ]]; then
      log_warn "未读取到输入，请重新输入。"
    else
      log_warn "无效输入：${answer}。请输入 01-25、0 或工具名称。"
    fi
  done
}

# 入口：解析全局选项 → 许可确认 → 参数模式或 interactive_loop
main() {
  NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
  while (($# > 0)); do
    case "${1:-}" in
      -h|--help|help) usage; exit "$EXIT_OK" ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit "$EXIT_OK" ;;
      --license|license) printf "%s\n" "$AGREEMENT_URL"; exit "$EXIT_OK" ;;
      --list|list) list_tools; exit "$EXIT_OK" ;;
      -q|--quiet) QUIET=1; shift ;;
      -y|--yes) NON_INTERACTIVE=1; shift ;;
      --) shift; break ;;
      -*) die "未知选项：$1。使用 --help 查看帮助。"; exit "$EXIT_USAGE" ;;
      *) break ;;
    esac
  done

  export QUIET="${QUIET:-0}"
  export NON_INTERACTIVE="${NON_INTERACTIVE:-0}"

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
        status)
          run_status_panel
          exit "$EXIT_OK"
          ;;
        versions)
          run_versions_display
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

  check_interactive_tty
  interactive_loop
}

main "$@"
