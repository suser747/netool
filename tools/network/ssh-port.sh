#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - SSH 端口管理
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: ssh-port.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   面向 Linux 服务器的 SSH 端口安全切换脚本。支持 staged(先测试再切换)
#   与 replace(立即切换)两种模式,自动备份配置,失败时回滚。
#   可检测 firewalld/ufw/SELinux 并给出处理或提示,降低改端口时被锁在外面的风险。
#
# 使用方式:
#   bash ssh-port.sh --port 2222 --mode staged -y
#   bash ssh-port.sh --port 2222 --mode replace -y
#   bash ssh-port.sh --restore -y
#   bash ssh-port.sh --restore-from /var/backups/netool-ssh-port/20260414-153000 -y
#   bash ssh-port.sh --list-backups
#   bash ssh-port.sh -h
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="ssh-port-manager"
SCRIPT_VERSION="2.0"
REPO_URL="https://gitee.com/suser747/netool"
SCRIPT_URL="https://gitee.com/suser747/netool/raw/master/tools/network/ssh-port.sh"
BACKUP_ROOT="/var/backups/${SCRIPT_NAME}"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
MANAGED_DROPIN_FILE="${SSHD_DROPIN_DIR}/99-${SCRIPT_NAME}.conf"
MANAGED_BEGIN="# >>> ssh-port-manager managed ports begin >>>"
MANAGED_END="# <<< ssh-port-manager managed ports end <<<"
DISABLED_PREFIX="# ssh-port-manager disabled: "

ACTION="configure"
MODE=""
NEW_PORT=""
RESTORE_FROM=""
NON_INTERACTIVE=0
DRY_RUN=0
SKIP_FIREWALL=0
BACKUP_DIR=""
SERVICE_NAME=""
SSHD_BIN=""
MANAGED_FILE=""
FIREWALL_TOOL=""
SELINUX_MODE="Disabled"
CURRENT_SESSION_PORT=""
PRIMARY_IP=""
CURRENT_STEP=0
TOTAL_STEPS=0

CURRENT_PORTS=()
TARGET_PORTS=()
CONFIG_FILES=()

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh ssh-port
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) ssh-port
#   直接：bash tools/network/ssh-port.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅; 被 NETOOL 主入口调用时不打印
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then
    return 0
  fi

  print_divider
  printf "netool懒人工具箱 | SSH 端口管理 v%s\n" "$SCRIPT_VERSION"
  printf "SSH 端口安全切换,支持先测试后切换、自动备份与失败回滚\n"
  print_divider
}

# ------------------------------------------------------------------------------
# 函数: start_section
# 功能: 打印一个带颜色的章节标题
# 参数: $1 - 章节标题文本
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
start_section() {
  printf "\n%s==>%s %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$1"
}

# ------------------------------------------------------------------------------
# 函数: start_step
# 功能: 打印带步骤编号的步骤标题,自动递增 CURRENT_STEP
# 参数: $1 - 步骤标题文本
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
start_step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "\n%s==>%s [%s/%s] %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

# ------------------------------------------------------------------------------
# 函数: print_kv
# 功能: 以 "键 值" 格式打印一行键值对,键左对齐宽度 16
# 参数: $1 - 键名, $2 - 值
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
print_kv() {
  printf "  %-16s %s\n" "$1" "$2"
}

# ------------------------------------------------------------------------------
# 函数: run_cmd
# 功能: 执行命令; DRY_RUN 模式下只打印不执行
# 参数: $@ - 要执行的命令及其参数
# 返回值: 0 - 成功或预演模式, 非 0 - 命令执行失败
# ------------------------------------------------------------------------------
run_cmd() {
  if (( DRY_RUN )); then
    printf "%s[预演]%s" "$COLOR_YELLOW" "$COLOR_RESET"
    printf " %q" "$@"
    printf "\n"
    return 0
  fi

  "$@"
}

# ------------------------------------------------------------------------------
# 函数: command_exists
# 功能: 检查指定命令是否在 PATH 中可用
# 参数: $1 - 命令名
# 返回值: 0 - 存在, 非 0 - 不存在
# ------------------------------------------------------------------------------
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# 函数: array_contains
# 功能: 检查数组中是否包含指定元素
# 参数: $1 - 待查找的元素, $@ - 数组元素(从第二个参数起)
# 返回值: 0 - 包含, 1 - 不包含
# ------------------------------------------------------------------------------
array_contains() {
  local needle="$1"
  local item=""
  shift

  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

# ------------------------------------------------------------------------------
# 函数: format_ports
# 功能: 将端口号数组格式化为逗号分隔的字符串; 空数组返回 "无"
# 参数: $@ - 端口号列表
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
format_ports() {
  if (($# == 0)); then
    printf "%s" "无"
    return 0
  fi

  join_by ", " "$@"
}

# ------------------------------------------------------------------------------
# 函数: mode_label
# 功能: 返回模式的中文标签
# 参数: $1 - 模式名(staged 或 replace)
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
mode_label() {
  case "$1" in
    staged)
      printf "%s" "先测试再切换"
      ;;
    replace)
      printf "%s" "立即切换"
      ;;
    *)
      printf "%s" "$1"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: unique_ports
# 功能: 对端口号列表去重并排序
# 参数: $@ - 端口号列表
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
unique_ports() {
  printf "%s\n" "$@" | awk 'NF' | sort -n | awk '!seen[$0]++'
}

# ------------------------------------------------------------------------------
# 函数: confirm_default_no
# 功能: 询问用户确认,默认为否; 非交互或 YES 模式下直接拒绝以保证安全
# 参数: $1 - 提示文本
# 返回值: 0 - 用户确认, 1 - 用户拒绝或非交互模式
# ------------------------------------------------------------------------------
confirm_default_no() {
  local prompt="$1"
  local answer=""

  if [[ "${NON_INTERACTIVE:-0}" == "1" || "${YES:-0}" == "1" ]]; then
    return 1
  fi

  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: confirm_default_yes
# 功能: 询问用户确认,默认为是; 非交互模式下直接确认
# 参数: $1 - 提示文本
# 返回值: 0 - 用户确认或默认, 1 - 用户拒绝
# ------------------------------------------------------------------------------
confirm_default_yes() {
  local prompt="$1"
  local answer=""

  if (( NON_INTERACTIVE )); then
    return 0
  fi

  read_prompt "${prompt} [Y/n]: " answer || return 1
  [[ ! "$answer" =~ ^([nN]|[nN][oO]|否)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | SSH 端口管理 v${SCRIPT_VERSION}
面向 Linux 服务器的 SSH 端口安全切换脚本。
默认采用"先测试新端口,再决定是否正式切换"的方式,尽量降低改端口时把自己锁在服务器外的风险。

用法:
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL ${SCRIPT_URL}) --port 2222 --mode staged -y
  bash <(curl -fsSL ${SCRIPT_URL}) --port 2222 --mode replace -y
  bash <(curl -fsSL ${SCRIPT_URL}) --restore -y
  bash <(curl -fsSL ${SCRIPT_URL}) --restore-from /var/backups/${SCRIPT_NAME}/20260414-153000 -y
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) ssh --port 2222 --mode staged -y

选项:
  --port <n>          指定新端口
  --mode <name>       staged(保留旧端口并新增新端口)或 replace(仅保留新端口)
  --restore           从最近一次备份恢复
  --restore-from <d>  从指定备份目录恢复
  --list-backups      列出可用备份目录
  --skip-firewall     跳过 firewalld / ufw 放行逻辑
  --dry-run           只打印计划执行的动作,不修改系统
  -y, --yes           非交互模式,配置端口时需要同时指定 --port
  -h, --help          显示帮助
  --version           显示脚本版本

说明:
  1. staged 模式更适合首次切换: 旧端口和新端口会同时可用,方便你先测试
  2. replace 模式会只保留新端口,适合确认新端口可用后再正式切换
  3. 所有改动都会先备份到 ${BACKUP_ROOT}
  4. 如检测到 firewalld、ufw 或 SELinux,会在需要时给出处理或提示
EOF
}

# ------------------------------------------------------------------------------
# 函数: require_root
# 功能: 检查当前是否以 root 权限运行,否则报错退出
# 参数: 无
# 返回值: 0 - 是 root, 1 - 非 root 并退出
# ------------------------------------------------------------------------------
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "需要 root 权限运行; 如果当前不是 root,请自行在前面加 sudo。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_sshd_bin
# 功能: 检测 sshd 可执行文件路径,优先使用 PATH 中的 sshd,回退 /usr/sbin/sshd
# 参数: 无
# 返回值: 0 - 找到, 1 - 未找到并退出
# ------------------------------------------------------------------------------
detect_sshd_bin() {
  if command_exists sshd; then
    SSHD_BIN="$(command -v sshd)"
    return 0
  fi

  if [[ -x /usr/sbin/sshd ]]; then
    SSHD_BIN="/usr/sbin/sshd"
    return 0
  fi

  die "未找到 sshd 可执行文件,无法继续。"
}

# ------------------------------------------------------------------------------
# 函数: detect_service_name
# 功能: 检测 SSH 服务名称(sshd 或 ssh),优先使用 systemctl,回退 init.d
# 参数: 无
# 返回值: 0 - 找到, 1 - 未找到并退出
# ------------------------------------------------------------------------------
detect_service_name() {
  if command_exists systemctl; then
    if systemctl cat sshd >/dev/null 2>&1; then
      SERVICE_NAME="sshd"
      return 0
    fi
    if systemctl cat ssh >/dev/null 2>&1; then
      SERVICE_NAME="ssh"
      return 0
    fi
  fi

  if [[ -x /etc/init.d/sshd ]]; then
    SERVICE_NAME="sshd"
    return 0
  fi

  if [[ -x /etc/init.d/ssh ]]; then
    SERVICE_NAME="ssh"
    return 0
  fi

  die "未找到 SSH 服务(sshd 或 ssh)。"
}

# ------------------------------------------------------------------------------
# 函数: detect_primary_ip
# 功能: 检测服务器主 IP 地址,优先使用 ip 命令,回退 hostname -I
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_primary_ip() {
  if command_exists ip; then
    PRIMARY_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
  fi

  if [[ -z "$PRIMARY_IP" ]] && command_exists hostname; then
    PRIMARY_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_session_port
# 功能: 从 SSH_CONNECTION 环境变量中提取当前 SSH 会话的本地端口
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_session_port() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    CURRENT_SESSION_PORT="$(awk '{print $4}' <<<"${SSH_CONNECTION}")"
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_effective_ports
# 功能: 通过 sshd -T 获取当前生效的 SSH 端口列表
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_effective_ports() {
  "$SSHD_BIN" -T 2>/dev/null | awk '/^port / { print $2 }' | sort -n | awk '!seen[$0]++'
}

# ------------------------------------------------------------------------------
# 函数: detect_config_ports
# 功能: 从 sshd_config 文件中解析已配置的 Port 指令
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_config_ports() {
  grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' | sort -n | awk '!seen[$0]++'
}

# ------------------------------------------------------------------------------
# 函数: load_current_ports
# 功能: 加载当前 SSH 端口列表,优先使用生效端口,回退配置端口,最后默认 22
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
load_current_ports() {
  mapfile -t CURRENT_PORTS < <(detect_effective_ports)

  if ((${#CURRENT_PORTS[@]} == 0)); then
    mapfile -t CURRENT_PORTS < <(detect_config_ports)
  fi

  if ((${#CURRENT_PORTS[@]} == 0)); then
    CURRENT_PORTS=("22")
  fi

  if [[ -n "$CURRENT_SESSION_PORT" ]] && ! array_contains "$CURRENT_SESSION_PORT" "${CURRENT_PORTS[@]}"; then
    mapfile -t CURRENT_PORTS < <(unique_ports "$CURRENT_SESSION_PORT" "${CURRENT_PORTS[@]}")
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_managed_file
# 功能: 检测本工具应写入的管理文件位置(drop-in 或主配置)
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_managed_file() {
  if [[ -d "$SSHD_DROPIN_DIR" ]] && grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$SSHD_CONFIG"; then
    MANAGED_FILE="$MANAGED_DROPIN_FILE"
  else
    MANAGED_FILE="$SSHD_CONFIG"
  fi
}

# ------------------------------------------------------------------------------
# 函数: collect_config_files
# 功能: 收集所有需要处理的 SSH 配置文件(主配置与 drop-in 目录下的 .conf)
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
collect_config_files() {
  local file=""

  CONFIG_FILES=("$SSHD_CONFIG")

  if [[ -d "$SSHD_DROPIN_DIR" ]]; then
    while IFS= read -r -d '' file; do
      [[ "$file" == "$MANAGED_DROPIN_FILE" ]] && continue
      CONFIG_FILES+=("$file")
    done < <(find "$SSHD_DROPIN_DIR" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_firewall_tool
# 功能: 检测可用的防火墙工具(firewalld 或 ufw); SKIP_FIREWALL 时跳过
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_firewall_tool() {
  FIREWALL_TOOL=""

  if (( SKIP_FIREWALL )); then
    return 0
  fi

  if command_exists firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    FIREWALL_TOOL="firewalld"
    return 0
  fi

  if command_exists ufw && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    FIREWALL_TOOL="ufw"
    return 0
  fi
}

# ------------------------------------------------------------------------------
# 函数: detect_selinux_mode
# 功能: 检测 SELinux 当前模式,优先使用 getenforce,回退 sestatus
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_selinux_mode() {
  local mode=""
  # 优先使用 getenforce 检测 SELinux 当前模式
  if command_exists getenforce; then
    SELINUX_MODE="$(getenforce 2>/dev/null || printf 'Disabled')"
    return 0
  fi
  # 回退到 sestatus: 解析 "Current mode" 字段
  if command_exists sestatus; then
    mode="$(sestatus 2>/dev/null | awk -F: '/^Current mode:/ {gsub(/^[ \t]+/, "", $2); print $2}')"
    case "$mode" in
      enforcing)   SELINUX_MODE="Enforcing" ;;
      permissive)  SELINUX_MODE="Permissive" ;;
      disabled|"" ) SELINUX_MODE="Disabled" ;;
    esac
    return 0
  fi
  # 既无 getenforce 也无 sestatus,视为未启用 SELinux
  SELINUX_MODE="Disabled"
}

# ------------------------------------------------------------------------------
# 函数: show_detected_state
# 功能: 打印当前检测到的 SSH 与系统状态信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
show_detected_state() {
  start_section "当前状态"
  print_kv "SSH 服务" "$SERVICE_NAME"
  print_kv "配置文件" "$SSHD_CONFIG"
  print_kv "管理文件" "$MANAGED_FILE"
  print_kv "当前会话端口" "${CURRENT_SESSION_PORT:-未检测到 SSH 会话}"
  print_kv "当前生效端口" "$(format_ports "${CURRENT_PORTS[@]}")"
  print_kv "服务器地址" "${PRIMARY_IP:-未检测到}"
  print_kv "SELinux" "$SELINUX_MODE"
  print_kv "防火墙工具" "${FIREWALL_TOOL:-未检测到可自动处理的防火墙}"
  print_kv "脚本入口" "$SCRIPT_URL"
}

# ------------------------------------------------------------------------------
# 函数: validate_port_number
# 功能: 校验端口号是否为 1-65535 范围内的整数
# 参数: $1 - 待校验的端口号字符串
# 返回值: 0 - 合法, 1 - 非法
# ------------------------------------------------------------------------------
validate_port_number() {
  local port="$1"

  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  ((port >= 1 && port <= 65535))
}

# ------------------------------------------------------------------------------
# 函数: ensure_port_available
# 功能: 检查指定端口是否被其他服务占用,占用时报错退出
# 参数: $1 - 端口号
# 返回值: 0 - 端口可用, 1 - 端口被占用并退出
# ------------------------------------------------------------------------------
ensure_port_available() {
  local port="$1"

  if command_exists ss; then
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|[\\]:])${port}$"; then
      die "端口 ${port} 已被其他服务占用,请更换一个端口。"
    fi
    return 0
  fi

  if command_exists netstat; then
    if netstat -ltn 2>/dev/null | awk 'NR > 2 {print $4}' | grep -Eq "(^|[\\]:])${port}$"; then
      die "端口 ${port} 已被其他服务占用,请更换一个端口。"
    fi
  fi
}

# ------------------------------------------------------------------------------
# 函数: prompt_change_if_needed
# 功能: 询问用户是否需要调整 SSH 端口,不需要则返回 1
# 参数: 无
# 返回值: 0 - 需要调整, 1 - 不需要调整
# ------------------------------------------------------------------------------
prompt_change_if_needed() {
  if ! confirm_default_no "是否需要调整 SSH 端口?"; then
    log_info "保持现状,未做任何改动。"
    return 1
  fi
}

# ------------------------------------------------------------------------------
# 函数: prompt_new_port
# 功能: 提示用户输入新 SSH 端口号并校验合法性,支持非交互模式(需预先指定 NEW_PORT)
# 参数: 无
# 返回值: 0 - 获取到合法端口, 1 - 用户取消或端口不合法
# ------------------------------------------------------------------------------
prompt_new_port() {
  local input=""

  if [[ -n "$NEW_PORT" ]]; then
    validate_port_number "$NEW_PORT" || { log_error "端口 ${NEW_PORT} 不合法,请输入 1 到 65535 之间的整数。"; return 1; }

    if array_contains "$NEW_PORT" "${CURRENT_PORTS[@]}"; then
      if [[ "${MODE:-}" == "replace" ]] && ((${#CURRENT_PORTS[@]} > 1)); then
        return 0
      fi
      log_error "端口 ${NEW_PORT} 已经在当前 SSH 配置中启用; 如果你是想删除其他旧端口,请使用 replace 模式。"
      return 1
    fi

    ensure_port_available "$NEW_PORT"
    return 0
  fi

  if (( NON_INTERACTIVE )); then
    die "非交互模式需要通过 --port 指定新 SSH 端口,例如:bash <(curl -fsSL ${SCRIPT_URL}) --port 2222 --mode staged -y"
  fi

  while true; do
    read_prompt "请输入你想使用的新 SSH 端口(输入 b 返回,q 退出): " input || return 1

    case "$input" in
      b|B|back|返回)
        return 1
        ;;
      q|Q|quit|QUIT|exit|EXIT)
        log_info "已取消。"
        return 1
        ;;
    esac

    validate_port_number "$input" || {
      log_warn "端口不合法,请输入 1 到 65535 之间的整数。"
      continue
    }

    if array_contains "$input" "${CURRENT_PORTS[@]}"; then
      log_warn "端口 ${input} 已经在当前 SSH 配置中启用。"

      if ((${#CURRENT_PORTS[@]} > 1)) && confirm_default_no "如果你是想保留端口 ${input} 并删除其他旧端口,是否按 replace 方式继续?"; then
        NEW_PORT="$input"
        MODE="replace"
        return 0
      fi

      log_info "你可以重新输入其他端口,或输入 b 返回、q 退出。"
      continue
    fi

    ensure_port_available "$input"
    NEW_PORT="$input"
    return 0
  done
}

# ------------------------------------------------------------------------------
# 函数: prompt_mode
# 功能: 提示用户选择端口生效方式(staged 或 replace),支持非交互模式
# 参数: 无
# 返回值: 0 - 选择成功, 1 - 用户取消
# ------------------------------------------------------------------------------
prompt_mode() {
  local choice=""

  if [[ -n "$MODE" ]]; then
    case "$MODE" in
      staged|replace) return 0 ;;
      *)
        die "不支持的模式:${MODE},可选 staged 或 replace。"
        ;;
    esac
  fi

  if (( NON_INTERACTIVE )); then
    MODE="staged"
    return 0
  fi

  cat <<'EOF'

请选择端口生效方式:
  1. staged(推荐,先测试再切换)
     保留当前 SSH 端口,同时新增新端口
     适合先从另一台机器验证新端口是否可用

  2. replace(立即切换)
     只保留新端口
     适合你已经确认新端口可以正常连接,准备正式切换

  b. 返回
EOF

  while true; do
    read_prompt "请输入 1 或 2,默认 1: " choice || return 1

    case "${choice:-1}" in
      1)
        MODE="staged"
        return 0
        ;;
      2)
        MODE="replace"
        return 0
        ;;
      b|B|back|返回)
        return 1
        ;;
      q|Q|quit|QUIT|exit|EXIT)
        log_info "已取消。"
        return 1
        ;;
      *)
        log_warn "无效选择:${choice}。请输入 1、2、b,或 q 退出。"
        ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# 函数: prepare_target_ports
# 功能: 根据模式准备目标端口列表,staged 模式合并新旧端口,replace 模式仅保留新端口
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
prepare_target_ports() {
  if [[ "$MODE" == "staged" ]]; then
    mapfile -t TARGET_PORTS < <(unique_ports "${CURRENT_PORTS[@]}" "$NEW_PORT")
  else
    TARGET_PORTS=("$NEW_PORT")
  fi
}

# ------------------------------------------------------------------------------
# 函数: show_plan
# 功能: 打印变更计划,包括执行方式、新增端口和变更后端口列表
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
show_plan() {
  start_section "变更计划"
  print_kv "执行方式" "$(mode_label "$MODE")"
  print_kv "新增端口" "$NEW_PORT"
  print_kv "变更后端口" "$(format_ports "${TARGET_PORTS[@]}")"

  if [[ "$MODE" == "staged" ]]; then
    log_warn "本次会同时保留旧端口和新端口,方便你先验证新端口是否可用。"
  else
    log_warn "本次会直接切换为仅保留新端口。请先不要关闭当前会话,直到你确认新端口连接正常。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: ensure_backup_dir
# 功能: 确保备份目录已创建,未创建时按时间戳生成新目录
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
ensure_backup_dir() {
  if [[ -n "$BACKUP_DIR" ]]; then
    return 0
  fi

  BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  run_cmd mkdir -p "$BACKUP_DIR"
}

# ------------------------------------------------------------------------------
# 函数: backup_target_path
# 功能: 根据原始路径生成备份目录下的对应路径
# 参数: $1 - 原始文件路径
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
backup_target_path() {
  local target="$1"
  printf "%s/%s\n" "$BACKUP_DIR" "${target#/}"
}

# ------------------------------------------------------------------------------
# 函数: backup_file
# 功能: 备份单个文件到备份目录,保留目录结构; 文件不存在时跳过
# 参数: $1 - 待备份文件路径
# 返回值: 0 - 成功或文件不存在
# ------------------------------------------------------------------------------
backup_file() {
  local target="$1"
  local backup_path=""

  [[ -e "$target" ]] || return 0

  ensure_backup_dir
  backup_path="$(backup_target_path "$target")"
  run_cmd mkdir -p "$(dirname "$backup_path")"
  run_cmd cp -a "$target" "$backup_path"
}

# ------------------------------------------------------------------------------
# 函数: write_backup_metadata
# 功能: 将备份元信息(时间、动作、模式、端口等)写入 backup-info.txt
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
write_backup_metadata() {
  local metadata_file=""
  local managed_present=0

  ensure_backup_dir
  metadata_file="${BACKUP_DIR}/backup-info.txt"

  if [[ -e "$MANAGED_FILE" ]]; then
    managed_present=1
  fi

  if (( DRY_RUN )); then
    log_info "预演:将写入备份元信息 ${metadata_file}"
    return 0
  fi

  cat >"$metadata_file" <<EOF
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
action=${ACTION}
mode=${MODE:-restore}
new_port=${NEW_PORT:-}
current_ports=$(format_ports "${CURRENT_PORTS[@]}")
target_ports=$(format_ports "${TARGET_PORTS[@]}")
managed_file=${MANAGED_FILE}
managed_file_present=${managed_present}
EOF
}

# ------------------------------------------------------------------------------
# 函数: backup_all
# 功能: 备份所有 SSH 配置文件(主配置、drop-in 文件、管理文件)并写入元信息
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
backup_all() {
  local file=""

  ensure_backup_dir

  for file in "${CONFIG_FILES[@]}"; do
    backup_file "$file"
  done

  if [[ "$MANAGED_FILE" != "$SSHD_CONFIG" ]]; then
    backup_file "$MANAGED_FILE"
  fi

  write_backup_metadata
}

# ------------------------------------------------------------------------------
# 函数: render_managed_block
# 功能: 生成由 MANAGED_BEGIN/MANAGED_END 包裹的端口配置块文本
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
render_managed_block() {
  local port=""

  printf "%s\n" "$MANAGED_BEGIN"
  for port in "${TARGET_PORTS[@]}"; do
    printf "Port %s\n" "$port"
  done
  printf "%s\n" "$MANAGED_END"
}

# ------------------------------------------------------------------------------
# 函数: rewrite_config_file
# 功能: 重写配置文件: 注释掉原有 Port 指令并追加管理块(仅主配置文件追加)
# 参数: $1 - 待重写的配置文件路径
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
rewrite_config_file() {
  local file="$1"
  local temp_file=""

  temp_file="$(mktemp)"

  awk \
    -v begin="$MANAGED_BEGIN" \
    -v end="$MANAGED_END" \
    -v prefix="$DISABLED_PREFIX" \
    '
      $0 == begin { in_block = 1; next }
      $0 == end { in_block = 0; next }
      in_block { next }
      /^[[:space:]]*Port[[:space:]]+[0-9]+([[:space:]]*(#.*)?)?$/ {
        print prefix $0
        next
      }
      { print }
    ' "$file" >"$temp_file"

  if [[ "$MANAGED_FILE" == "$SSHD_CONFIG" && "$file" == "$SSHD_CONFIG" ]]; then
    {
      cat "$temp_file"
      printf "\n"
      render_managed_block
    } >"${temp_file}.final"
    mv "${temp_file}.final" "$temp_file"
  fi

  if (( DRY_RUN )); then
    log_info "预演:将更新配置文件 ${file}"
  else
    cat "$temp_file" >"$file"
  fi

  rm -f "$temp_file"
}

# ------------------------------------------------------------------------------
# 函数: write_managed_dropin
# 功能: 将管理块写入 drop-in 管理文件; 若管理文件为主配置则跳过
# 参数: 无
# 返回值: 0 - 成功或跳过
# ------------------------------------------------------------------------------
write_managed_dropin() {
  local temp_file=""

  [[ "$MANAGED_FILE" == "$SSHD_CONFIG" ]] && return 0

  temp_file="$(mktemp)"
  render_managed_block >"$temp_file"

  if (( DRY_RUN )); then
    log_info "预演:将写入管理文件 ${MANAGED_FILE}"
    rm -f "$temp_file"
    return 0
  fi

  mkdir -p "$(dirname "$MANAGED_FILE")"
  cat "$temp_file" >"$MANAGED_FILE"
  rm -f "$temp_file"
}

# ------------------------------------------------------------------------------
# 函数: validate_config
# 功能: 使用 sshd -t 校验配置语法; DRY_RUN 模式下跳过
# 参数: 无
# 返回值: 0 - 校验通过, 非 0 - 校验失败
# ------------------------------------------------------------------------------
validate_config() {
  if (( DRY_RUN )); then
    log_info "预演:跳过 sshd 配置语法校验"
    return 0
  fi

  "$SSHD_BIN" -t
}

# ------------------------------------------------------------------------------
# 函数: detect_listening_ports
# 功能: 检测系统当前监听的端口列表,可筛选指定端口
# 参数: $@ - 待筛选的端口号列表(可选)
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
detect_listening_ports() {
  local port=""
  local ports=()
  local matched=()

  if command_exists ss; then
    while IFS= read -r port; do
      [[ -n "$port" ]] && ports+=("$port")
    done < <(ss -ltnH 2>/dev/null | awk '{print $4}' | sed -E 's/.*[:]([0-9]+)$/\1/' | sort -n | awk '!seen[$0]++')
  fi

  if ((${#ports[@]} == 0)) && command_exists netstat; then
    while IFS= read -r port; do
      [[ -n "$port" ]] && ports+=("$port")
    done < <(netstat -ltn 2>/dev/null | awk 'NR > 2 {print $4}' | sed -E 's/.*[:]([0-9]+)$/\1/' | sort -n | awk '!seen[$0]++')
  fi

  if (($# == 0)); then
    printf "%s\n" "${ports[@]}"
    return 0
  fi

  for port in "$@"; do
    if array_contains "$port" "${ports[@]}"; then
      matched+=("$port")
    fi
  done

  printf "%s\n" "${matched[@]}"
}

# ------------------------------------------------------------------------------
# 函数: reload_service
# 功能: 重载或重启 SSH 服务,优先 reload,失败时回退 restart
# 参数: 无
# 返回值: 0 - 重载/重启成功, 1 - 失败
# ------------------------------------------------------------------------------
reload_service() {
  if (( DRY_RUN )); then
    log_info "预演:将重载 SSH 服务 ${SERVICE_NAME}"
    return 0
  fi

  if command_exists systemctl; then
    if systemctl reload "$SERVICE_NAME" >/dev/null 2>&1; then
      return 0
    fi
    if systemctl restart "$SERVICE_NAME" >/dev/null 2>&1; then
      log_warn "reload 不可用,已自动改用 restart。"
      return 0
    fi
  fi

  if command_exists service; then
    if service "$SERVICE_NAME" reload >/dev/null 2>&1; then
      return 0
    fi
    if service "$SERVICE_NAME" restart >/dev/null 2>&1; then
      log_warn "reload 不可用,已自动改用 restart。"
      return 0
    fi
  fi

  return 1
}

# ------------------------------------------------------------------------------
# 函数: ssh_port_labeled_in_selinux
# 功能: 检查指定端口是否已被 SELinux 标记为 ssh_port_t
# 参数: $1 - 端口号
# 返回值: 0 - 已标记, 1 - 未标记或 semanage 不可用
# ------------------------------------------------------------------------------
ssh_port_labeled_in_selinux() {
  local port="$1"

  command_exists semanage || return 1
  semanage port -l 2>/dev/null | awk '$1 == "ssh_port_t" && $2 == "tcp" { for (i = 3; i <= NF; i++) print $i }' | tr ',' '\n' | tr -d ' ' | grep -qx "$port"
}

# ------------------------------------------------------------------------------
# 函数: configure_selinux_port
# 功能: 为新端口添加 SELinux ssh_port_t 标签; Disabled 模式或已标记时跳过
# 参数: 无
# 返回值: 0 - 成功或跳过, 1 - 失败并退出
# ------------------------------------------------------------------------------
configure_selinux_port() {
  [[ "$SELINUX_MODE" == "Disabled" ]] && return 0

  if ssh_port_labeled_in_selinux "$NEW_PORT"; then
    log_info "SELinux 已允许 SSH 使用 ${NEW_PORT}/tcp。"
    return 0
  fi

  if ! command_exists semanage; then
    if [[ "$SELINUX_MODE" == "Enforcing" ]]; then
      die "检测到 SELinux 正在 Enforcing 模式,但系统未安装 semanage,无法为 ${NEW_PORT}/tcp 写入 ssh_port_t 标签。请先安装对应系统的 policycoreutils 工具后重试。"
    fi
    log_warn "检测到 SELinux 处于 ${SELINUX_MODE} 模式,但未找到 semanage。若新端口无法监听,请先安装对应的 policycoreutils 工具。"
    return 0
  fi

  if (( DRY_RUN )); then
    log_info "预演:将为 SELinux 添加 ssh_port_t tcp/${NEW_PORT}"
    return 0
  fi

  if semanage port -a -t ssh_port_t -p tcp "$NEW_PORT" >/dev/null 2>&1; then
    log_success "已为 SELinux 添加 ssh_port_t tcp/${NEW_PORT}"
    return 0
  fi

  if semanage port -m -t ssh_port_t -p tcp "$NEW_PORT" >/dev/null 2>&1; then
    log_success "已为 SELinux 更新 ssh_port_t tcp/${NEW_PORT}"
    return 0
  fi

  die "SELinux 端口标签调整失败,请手动检查 semanage 输出。"
}

# ------------------------------------------------------------------------------
# 函数: configure_firewall_port
# 功能: 为新端口放行防火墙入站规则,支持 firewalld 和 ufw
# 参数: 无
# 返回值: 0 - 成功或跳过
# ------------------------------------------------------------------------------
configure_firewall_port() {
  [[ -z "$FIREWALL_TOOL" ]] && return 0

  if ! confirm_default_yes "检测到 ${FIREWALL_TOOL} 正在运行,是否为新端口 ${NEW_PORT}/tcp 放行入站?"; then
    log_warn "你选择了跳过自动放行防火墙。若新端口无法连接,请手动放行 ${NEW_PORT}/tcp。"
    return 0
  fi

  case "$FIREWALL_TOOL" in
    firewalld)
      run_cmd firewall-cmd --quiet --add-port="${NEW_PORT}/tcp"
      run_cmd firewall-cmd --quiet --permanent --add-port="${NEW_PORT}/tcp"
      log_success "已通过 firewalld 放行 ${NEW_PORT}/tcp"
      ;;
    ufw)
      run_cmd ufw allow "${NEW_PORT}/tcp"
      log_success "已通过 ufw 放行 ${NEW_PORT}/tcp"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: restore_latest_backup_dir
# 功能: 查找最近一次备份目录路径
# 参数: 无
# 返回值: 0 - 成功, 1 - 无备份目录并退出
# ------------------------------------------------------------------------------
restore_latest_backup_dir() {
  local latest_backup=""

  [[ -d "$BACKUP_ROOT" ]] || die "未找到备份目录:${BACKUP_ROOT}"
  latest_backup="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
  [[ -n "$latest_backup" ]] || die "当前没有可恢复的备份。"
  printf "%s\n" "$latest_backup"
}

# ------------------------------------------------------------------------------
# 函数: list_backups
# 功能: 列出所有备份目录及其元信息
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
list_backups() {
  local backup_dir=""
  local metadata_file=""
  local created_at=""
  local mode_name=""
  local target_ports=""

  [[ -d "$BACKUP_ROOT" ]] || {
    log_warn "当前没有备份目录。"
    return 0
  }

  while IFS= read -r backup_dir; do
    [[ -d "$backup_dir" ]] || continue
    metadata_file="${backup_dir}/backup-info.txt"
    created_at="$(metadata_value "$metadata_file" created_at)"
    mode_name="$(metadata_value "$metadata_file" mode)"
    target_ports="$(metadata_value "$metadata_file" target_ports)"
    printf "%s\n" "$backup_dir"
    if [[ -n "$created_at" || -n "$mode_name" || -n "$target_ports" ]]; then
      printf "  created_at=%s mode=%s target_ports=%s\n" \
        "${created_at:-unknown}" \
        "${mode_name:-unknown}" \
        "${target_ports:-unknown}"
    fi
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
}

# ------------------------------------------------------------------------------
# 函数: is_restore_target_allowed
# 功能: 检查目标文件路径是否属于 SSH 配置目录(安全白名单校验)
# 参数: $1 - 目标文件路径
# 返回值: 0 - 允许, 1 - 不允许
# ------------------------------------------------------------------------------
is_restore_target_allowed() {
  local target_file="$1"

  case "$target_file" in
    "$SSHD_CONFIG"|"$SSHD_DROPIN_DIR"/*.conf)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: restore_backup_dir
# 功能: 从指定备份目录恢复 SSH 配置文件,跳过非 SSH 配置目标
# 参数: $1 - 备份目录路径
# 返回值: 0 - 成功, 1 - 无可恢复文件并退出
# ------------------------------------------------------------------------------
restore_backup_dir() {
  local restore_dir="$1"
  local backup_file=""
  local target_file=""
  local restored_count=0
  local skipped_count=0
  local metadata_file=""
  local managed_file_saved=""
  local managed_file_present=""

  [[ -d "$restore_dir" ]] || die "备份目录不存在:${restore_dir}"

  metadata_file="${restore_dir}/backup-info.txt"
  managed_file_saved="$(metadata_value "$metadata_file" managed_file)"
  managed_file_present="$(metadata_value "$metadata_file" managed_file_present)"

  while IFS= read -r backup_file; do
    [[ -f "$backup_file" ]] || continue
    [[ "$backup_file" == "$metadata_file" ]] && continue
    target_file="/${backup_file#${restore_dir}/}"

    if ! is_restore_target_allowed "$target_file"; then
      skipped_count=$((skipped_count + 1))
      log_warn "跳过非 SSH 配置恢复目标:${target_file}"
      continue
    fi

    run_cmd mkdir -p "$(dirname "$target_file")"
    run_cmd cp -a "$backup_file" "$target_file"
    restored_count=$((restored_count + 1))
  done < <(find "$restore_dir" -type f | sort)

  if [[ -n "$managed_file_saved" && "$managed_file_present" == "0" && -e "$managed_file_saved" ]]; then
    if is_restore_target_allowed "$managed_file_saved"; then
      run_cmd rm -f "$managed_file_saved"
    else
      log_warn "跳过非 SSH 配置删除目标:${managed_file_saved}"
    fi
  fi

  (( restored_count > 0 )) || die "备份目录 ${restore_dir} 中没有可恢复的配置文件。"
  log_success "已恢复 ${restored_count} 个配置文件。"

  if (( skipped_count > 0 )); then
    log_warn "已跳过 ${skipped_count} 个不属于 SSH 配置目录的文件。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: show_restore_summary
# 功能: 打印恢复结果摘要
# 参数: $1 - 恢复目录路径
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
show_restore_summary() {
  local restore_dir="$1"

  start_section "恢复结果"
  print_kv "恢复目录" "$restore_dir"
  print_kv "SSH 服务" "$SERVICE_NAME"
  log_info "如果你之前也调整过防火墙或 SELinux 端口标签,这些改动不会自动删除; 它们通常不会影响 SSH 正常使用。"
}

# ------------------------------------------------------------------------------
# 函数: show_apply_summary
# 功能: 打印执行结果摘要,包括端口变更与监听状态
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
show_apply_summary() {
  local live_ports=()
  local port=""
  local attempt=0

  if ! (( DRY_RUN )); then
    while (( attempt < 5 )); do
      live_ports=()
      while IFS= read -r port; do
        [[ -n "$port" ]] && live_ports+=("$port")
      done < <(detect_listening_ports "${TARGET_PORTS[@]}")

      if ((${#live_ports[@]} > 0)); then
        break
      fi

      attempt=$((attempt + 1))
      sleep 1
    done
  fi

  start_section "执行结果"
  print_kv "执行方式" "$(mode_label "$MODE")"
  print_kv "旧端口" "$(format_ports "${CURRENT_PORTS[@]}")"
  print_kv "新端口" "$NEW_PORT"
  print_kv "当前目标端口" "$(format_ports "${TARGET_PORTS[@]}")"
  print_kv "备份目录" "${BACKUP_DIR:-未创建}"

  if ((${#live_ports[@]} > 0)); then
    print_kv "SSH 监听端口" "$(format_ports "${live_ports[@]}")"
  fi

  if [[ "$MODE" == "staged" ]]; then
    log_warn "当前仍保留旧端口。确认新端口可以正常登录后,再执行 replace 模式完成正式切换。"
  else
    log_warn "当前已切换为仅保留新端口。请先不要关闭这个会话,务必从新的终端确认可连接。"
  fi
}

# ------------------------------------------------------------------------------
# 函数: prompt_finalize_replace
# 功能: 在 staged 模式完成后询问用户是否立即切换为 replace 模式
# 参数: 无
# 返回值: 0 - 用户确认切换, 1 - 用户拒绝或非交互模式
# ------------------------------------------------------------------------------
prompt_finalize_replace() {
  if (( DRY_RUN || NON_INTERACTIVE )); then
    return 1
  fi

  printf "\n"
  log_info "现在旧端口和新端口都已保留。"
  log_info "请保持当前会话不要关闭,并先从另一台机器测试新端口是否可以正常登录。"

  confirm_default_no "如果你已经在另一台机器测试确认新端口可用,是否现在删除旧端口,仅保留新端口?"
}

# ------------------------------------------------------------------------------
# 函数: finalize_replace_after_stage
# 功能: 在 staged 完成后执行 replace 模式,删除旧端口仅保留新端口
# 参数: 无
# 返回值: 透传子函数退出码
# ------------------------------------------------------------------------------
finalize_replace_after_stage() {
  local staged_ports=("${TARGET_PORTS[@]}")

  start_section "正式切换"
  log_info "即将删除旧端口,仅保留 ${NEW_PORT}。"

  CURRENT_PORTS=("${staged_ports[@]}")
  TARGET_PORTS=("$NEW_PORT")
  MODE="replace"
  BACKUP_DIR=""

  backup_all
  apply_port_changes
  validate_and_reload_or_rollback

  show_apply_summary
}

# ------------------------------------------------------------------------------
# 函数: show_follow_up
# 功能: 打印后续建议,包括测试命令和备份恢复提示
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
show_follow_up() {
  start_section "后续建议"
  log_info "需要查看备份时,可执行:bash <(curl -fsSL ${SCRIPT_URL}) --list-backups"
  log_info "需要快速回滚时,可执行:bash <(curl -fsSL ${SCRIPT_URL}) --restore -y"

  if [[ "$MODE" == "staged" ]]; then
    log_info "如果新端口测试通过,可执行:bash <(curl -fsSL ${SCRIPT_URL}) --port ${NEW_PORT} --mode replace -y"
  fi

  if [[ -n "$PRIMARY_IP" ]]; then
    log_info "建议从另一台机器测试:ssh -p ${NEW_PORT} <你的用户名>@${PRIMARY_IP}"
  else
    log_info "建议从另一台机器测试:ssh -p ${NEW_PORT} <你的用户名>@<服务器IP>"
  fi

  log_info "如果是云服务器,还需要确认安全组已放行 ${NEW_PORT}/tcp。"
}

# ------------------------------------------------------------------------------
# 函数: apply_port_changes
# 功能: 应用端口变更,重写所有配置文件并写入管理 drop-in
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
apply_port_changes() {
  local file=""

  for file in "${CONFIG_FILES[@]}"; do
    rewrite_config_file "$file"
  done

  write_managed_dropin
}

# ------------------------------------------------------------------------------
# 函数: validate_and_reload_or_rollback
# 功能: 校验配置并重载服务; 失败时从备份回滚后再次校验/重载,仍失败则退出
# 参数: 无
# 返回值: 0 - 成功, 1 - 失败并退出
# ------------------------------------------------------------------------------
validate_and_reload_or_rollback() {
  # 重启前确保有配置备份,否则拒绝继续以免无法回滚
  if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
    log_error "未找到配置备份目录,无法安全重启 sshd。"
    log_error "可通过控制台/VNC 登录并执行:ssh --restore"
    exit 1
  fi

  # 配置语法校验失败: 回滚后再次校验,仍失败则退出
  if ! validate_config; then
    log_warn "sshd 配置校验失败,尝试回滚配置..."
    restore_backup_dir "$BACKUP_DIR"
    if ! validate_config; then
      log_error "sshd 配置校验失败且回滚后仍无法通过,请手动检查"
      log_error "可通过控制台/VNC 登录并执行:ssh --restore"
      exit 1
    fi
    log_warn "已回滚到原配置,sshd 配置校验通过"
    log_error "应用新配置失败,已回滚到备份版本。"
    exit 1
  fi

  # 服务重载/重启失败: 回滚后再次重启,仍失败则退出
  if ! reload_service; then
    log_warn "sshd 重启失败,尝试回滚配置..."
    restore_backup_dir "$BACKUP_DIR"
    if ! reload_service; then
      log_error "sshd 重启失败且回滚后仍无法启动,请手动检查"
      log_error "可通过控制台/VNC 登录并执行:ssh --restore"
      exit 1
    fi
    log_warn "已回滚到原配置,sshd 重启成功"
    log_error "应用新配置失败,已回滚到备份版本。"
    exit 1
  fi
}

# ------------------------------------------------------------------------------
# 函数: parse_args
# 功能: 解析命令行参数,设置对应的变量
# 参数: $@ - 命令行参数
# 返回值: 0 - 成功, 1 - 参数错误并退出
# ------------------------------------------------------------------------------
parse_args() {
  while (($# > 0)); do
    case "$1" in
      --port)
        shift
        [[ $# -gt 0 ]] || die "--port 需要指定一个端口。"
        NEW_PORT="$1"
        ;;
      --mode)
        shift
        [[ $# -gt 0 ]] || die "--mode 需要指定 staged 或 replace。"
        MODE="$1"
        ;;
      --restore)
        ACTION="restore"
        ;;
      --restore-from)
        shift
        [[ $# -gt 0 ]] || die "--restore-from 需要指定一个备份目录。"
        ACTION="restore"
        RESTORE_FROM="$1"
        ;;
      --list-backups)
        ACTION="list-backups"
        ;;
      --skip-firewall)
        SKIP_FIREWALL=1
        ;;
      --dry-run|--plan)
        DRY_RUN=1
        ;;
      status|--status)
        ACTION="status"
        ;;
      -y|--yes)
        NON_INTERACTIVE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --version)
        printf "%s\n" "$SCRIPT_VERSION"
        exit 0
        ;;
      *)
        die "未知参数:$1"
        ;;
    esac
    shift
  done
}

# ------------------------------------------------------------------------------
# 函数: run_restore_flow
# 功能: 执行备份恢复流程: 检测状态、定位备份、恢复、校验重载、输出结果
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
run_restore_flow() {
  local restore_dir=""

  TOTAL_STEPS=4

  start_step "检测 SSH 状态"
  detect_sshd_bin
  detect_service_name
  detect_managed_file
  detect_selinux_mode
  show_detected_state

  start_step "定位并恢复备份"
  if [[ -n "$RESTORE_FROM" ]]; then
    restore_dir="$RESTORE_FROM"
    log_info "将恢复指定备份:${restore_dir}"
  else
    restore_dir="$(restore_latest_backup_dir)"
    log_info "将恢复最近一次备份:${restore_dir}"
  fi

  if ! confirm_default_no "确认恢复这份 SSH 配置备份吗?"; then
    log_info "已取消。"
    return 0
  fi

  restore_backup_dir "$restore_dir"

  start_step "校验并重载 SSH 服务"
  validate_config
  reload_service || die "恢复后的 SSH 服务重载失败,请手动检查。"

  start_step "输出恢复结果"
  show_restore_summary "$restore_dir"
}

# ------------------------------------------------------------------------------
# 函数: run_configure_flow
# 功能: 执行端口配置流程: 检测状态、准备计划、备份写入、处理兼容项、输出结果
# 参数: 无
# 返回值: 0 - 成功
# ------------------------------------------------------------------------------
run_configure_flow() {
  TOTAL_STEPS=5

  start_step "检测 SSH 状态"
  detect_sshd_bin
  detect_service_name
  detect_primary_ip
  detect_session_port
  detect_managed_file
  collect_config_files
  detect_firewall_tool
  detect_selinux_mode
  load_current_ports
  show_detected_state

  start_step "准备变更计划"
  if ! prompt_change_if_needed; then
    return 0
  fi
  if ! prompt_new_port; then
    return 0
  fi
  if ! prompt_mode; then
    return 0
  fi
  prepare_target_ports
  show_plan

  if ! confirm_default_no "确认按上述计划修改 SSH 端口吗?"; then
    log_info "已取消。"
    return 0
  fi

  if (( DRY_RUN )); then
    log_info "预演模式,不会写入 SSH 配置、重载服务或修改防火墙。"
    return 0
  fi

  require_root

  start_step "备份并写入配置"
  backup_all
  apply_port_changes

  start_step "处理兼容项并重载 SSH"
  configure_selinux_port
  configure_firewall_port
  validate_and_reload_or_rollback

  start_step "输出结果与后续建议"
  show_apply_summary

  if [[ "$MODE" == "staged" ]] && prompt_finalize_replace; then
    finalize_replace_after_stage
  fi

  show_follow_up
}

# ------------------------------------------------------------------------------
# 函数: cli_main
# 功能: 命令行模式入口,根据 ACTION 分发到对应流程
# 参数: 无(参数已在 parse_args 中解析)
# 返回值: 透传子流程退出码
# ------------------------------------------------------------------------------
cli_main() {
  parse_args "$@"
  print_banner

  case "$ACTION" in
    restore)
      require_root
      run_restore_flow
      ;;
    list-backups)
      list_backups
      ;;
    status)
      detect_sshd_bin
      detect_service_name
      detect_primary_ip
      detect_session_port
      detect_managed_file
      collect_config_files
      detect_firewall_tool
      detect_selinux_mode
      load_current_ports
      show_detected_state
      ;;
    configure)
      run_configure_flow
      ;;
    *)
      die "未知动作:${ACTION}"
      ;;
  esac
}

# ------------------------------------------------------------------------------
# 函数: interactive_menu
# 功能: 交互式菜单循环,等待用户选择操作直至返回
# 参数: 无
# 返回值: 0 - 用户选择返回
# ------------------------------------------------------------------------------
interactive_menu() {
  local answer=""
  local status=0

  while true; do
    printf "\n请选择操作:\n"
    printf "  1. 修改 SSH 端口\n"
    printf "  2. 从备份恢复\n"
    printf "  3. 查看备份列表\n"
    printf "  4. 查看当前状态\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号: " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1)
        ACTION="configure"
        NEW_PORT=""
        MODE=""
        status=0
        run_configure_flow || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成(退出码:${status}),返回菜单。"
        fi
        ;;
      2)
        ACTION="restore"
        status=0
        run_restore_flow || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成(退出码:${status}),返回菜单。"
        fi
        ;;
      3)
        list_backups
        ;;
      4)
        detect_sshd_bin
        detect_service_name
        detect_primary_ip
        detect_session_port
        detect_managed_file
        collect_config_files
        detect_firewall_tool
        detect_selinux_mode
        load_current_ports
        show_detected_state
        ;;
      b|B|back|返回)
        log_info "已返回。"
        return 0
        ;;
      *)
        log_warn "无效输入,请输入 1-4 或 b 返回。"
        ;;
    esac
  done
}

# ------------------------------------------------------------------------------
# 函数: entry
# 功能: 脚本入口,获取互斥锁后解析参数,选择命令行模式或交互模式
# 参数: $@ - 命令行参数
# 返回值: 透传子流程退出码
# ------------------------------------------------------------------------------
entry() {
  netool_acquire_lock "ssh-port" "另一个 ssh-port 实例正在运行,请等待其完成后再试。" || return 1
  parse_args "$@"

  if [[ -n "$NEW_PORT" || -n "$MODE" || "$ACTION" != "configure" ]] || (( NON_INTERACTIVE )); then
    cli_main
  else
    interactive_menu
  fi
}

entry "$@"
