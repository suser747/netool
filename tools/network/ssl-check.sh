#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - HTTPS 证书到期检查
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: ssl-check
# 脚本版本: 1.0
# 功能说明: 使用 openssl s_client 获取并检查 HTTPS 证书到期情况，
#           支持多域名/IP 批量检查、从文件读取目标列表。
#           输出域名、颁发者、到期日、剩余天数与状态（正常/即将到期/已过期），
#           即将到期或已过期以警告色显示。无需在本机安装证书。
# 使用方式: 1) ssl-check <域名或IP> [域名或IP...] [选项]；
#           2) ssl-check --file <域名列表文件> [选项]；
#           3) ssl-check -h 显示帮助。
# =============================================================================

set -Eeuo pipefail

SCRIPT_NAME="ssl-check"
SCRIPT_VERSION="1.0"
# 到期告警阈值（天）：剩余天数小于等于该值即标记为"即将到期"
WARN_DAYS=30
# 默认端口
PORT=443
# 待检查目标列表（支持 "domain" 或 "domain:port" 格式）
TARGETS=()

# 颜色控制变量：仅在终端输出时启用颜色，被父工具箱调用时强制关闭颜色
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_BOLD=""
COLOR_RESET=""

# 标准输出连接到终端时初始化 ANSI 颜色转义码
if [[ -t 1 ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
fi

# 作为子模块被父工具箱调用时关闭颜色，避免日志格式混乱
if [[ -n "${AYU_TOOLBOX:-}" ]]; then
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_CYAN=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

# 统一日志输出函数，带颜色与级别前缀
# 参数：$* - 要输出的消息内容
# 返回值：0 - 成功（die 除外）
log_info() { printf "%s%s[信息]%s %s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$COLOR_RESET" "$*"; }
log_success() { printf "%s%s[完成]%s %s\n" "$COLOR_BOLD" "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
log_warn() { printf "%s%s[警告]%s %s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
log_error() { printf "%s%s[错误]%s %s\n" "$COLOR_BOLD" "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }
# 输出错误消息后立即退出，退出码 1
# 参数：$* - 错误消息
# 返回值：1 - 始终退出
die() { log_error "$*"; exit 1; }

# 函数名：on_error
# 功能：ERR 信号回调，在 set -e 触发退出前打印出错行号与退出码
# 参数：由 trap 自动注入
# 返回值：以原退出码退出
on_error() {
  local exit_code=$?
  log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  exit "$exit_code"
}

trap on_error ERR

# 函数名：command_exists
# 功能：检查指定命令是否在 PATH 中可用
# 参数：$1 - 命令名
# 返回值：0 - 存在, 非 0 - 不存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 函数名：usage
# 功能：输出脚本帮助信息
# 参数：无
# 返回值：0 - 始终成功
usage() {
  cat <<EOF
netool懒人工具箱 | HTTPS 证书到期检查 v${SCRIPT_VERSION}

用法：
  ssl-check <域名或IP> [域名或IP...] [选项]
  ssl-check --file <域名列表文件> [选项]

选项：
  --port <端口>        指定端口，默认 ${PORT}
  --warn-days <天数>   到期 N 天内告警，默认 ${WARN_DAYS}
  --file <文件>        从文件读取目标，每行一个 域名[:端口]
  -h, --help           显示帮助
  --version            显示版本

说明：
  使用 openssl s_client 获取证书信息，无需在本机安装证书。
  输出：域名 / 颁发者 / 到期日 / 剩余天数 / 状态（正常/即将到期/已过期）。
  即将到期或已过期会以警告色显示。
EOF
}

# 函数名：print_banner
# 功能：打印脚本横幅；作为子模块被调用时静默跳过
# 参数：无
# 返回值：0 - 始终成功
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | HTTPS 证书到期检查 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# 函数名：require_openssl
# 功能：检查 openssl 命令是否存在，不存在则报错退出
# 参数：无
# 返回值：0 - 存在, 1 - 不存在并退出
require_openssl() {
  command_exists openssl || die "缺少 openssl 命令。"
}

# 函数名：parse_target
# 功能：解析 "domain:port" 或 "domain" 输入，输出 "domain port"
# 参数：$1 - 待解析的目标字符串
# 返回值：0 - 始终成功（通过标准输出返回解析结果）
parse_target() {
  local input="$1"
  local domain=""
  local port="$PORT"

  if [[ "$input" == *:* ]]; then
    domain="${input%:*}"
    port="${input##*:}"
    # IPv6 含多个冒号的情况：如果最后一段不是数字端口，整体当作域名
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
      domain="$input"
      port="$PORT"
    fi
  else
    domain="$input"
  fi

  printf "%s %s\n" "$domain" "$port"
}

# 函数名：check_one
# 功能：检查单个域名的证书到期情况并输出结果
# 参数：$1 - 域名, $2 - 端口
# 返回值：0 - 检查完成（含无法计算天数的情况）, 1 - 连接失败或无法解析证书
check_one() {
  local domain="$1"
  local port="$2"

  local cert_info=""
  # 通过 openssl 获取证书的到期日、颁发者、主题信息，超时 15 秒
  cert_info="$(echo | timeout 15 openssl s_client -servername "$domain" -connect "${domain}:${port}" 2>/dev/null | openssl x509 -noout -enddate -issuer -subject 2>/dev/null || true)"

  if [[ -z "$cert_info" ]]; then
    printf "  %-40s %s连接失败%s\n" "$domain:${port}" "$COLOR_RED" "$COLOR_RESET"
    return 1
  fi

  local end_date=""
  local issuer=""
  local subject=""
  end_date="$(printf "%s\n" "$cert_info" | awk -F= '/notAfter/ {print $2}')"
  issuer="$(printf "%s\n" "$cert_info" | awk -F= '/issuer/ {print $2}')"
  subject="$(printf "%s\n" "$cert_info" | awk -F= '/subject/ {print $2}')"

  if [[ -z "$end_date" ]]; then
    printf "  %-40s %s无法解析证书%s\n" "$domain:${port}" "$COLOR_RED" "$COLOR_RESET"
    return 1
  fi

  # 转换为时间戳（兼容 GNU date 和 BusyBox date）
  local end_ts=""
  local now_ts=""
  if date -d "$end_date" +%s >/dev/null 2>&1; then
    end_ts="$(date -d "$end_date" +%s)"
    now_ts="$(date +%s)"
  elif date -j -f "%b %d %H:%M:%S %Y %Z" "$end_date" +%s >/dev/null 2>&1; then
    # macOS BSD date
    end_ts="$(date -j -f "%b %d %H:%M:%S %Y %Z" "$end_date" +%s)"
    now_ts="$(date +%s)"
  else
    printf "  %-40s %s\n" "$domain:${port}" "到期：${end_date}（无法计算剩余天数）"
    return 0
  fi

  # 计算剩余天数并根据阈值确定状态与显示颜色
  local days_left=$(( (end_ts - now_ts) / 86400 ))
  local color="$COLOR_GREEN"
  local status="正常"

  if (( days_left < 0 )); then
    color="$COLOR_RED"
    status="已过期"
  elif (( days_left <= WARN_DAYS )); then
    color="$COLOR_YELLOW"
    status="即将到期"
  fi

  printf "  %-40s %s%s%s\n" "$domain:${port}" "$color" "状态：${status}  剩余：${days_left} 天  到期：${end_date}" "$COLOR_RESET"
  printf "    颁发者：%s\n" "$issuer"
}

# 函数名：do_check
# 功能：遍历 TARGETS 列表逐个执行证书检查，并汇总失败数量
# 参数：无
# 返回值：0 - 始终成功（通过日志提示失败数量）
do_check() {
  require_openssl

  if ((${#TARGETS[@]} == 0)); then
    die "未指定目标。请传入域名或用 --file 指定列表文件。"
  fi

  printf "\n检查 %d 个目标（端口 %s，告警阈值 %s 天）：\n\n" "${#TARGETS[@]}" "$PORT" "$WARN_DAYS"

  local target=""
  local domain=""
  local port=""
  local failed=0
  # 逐个解析目标并检查，统计连接或解析失败的数量
  for target in "${TARGETS[@]}"; do
    read -r domain port < <(parse_target "$target")
    if ! check_one "$domain" "$port"; then
      failed=$((failed + 1))
    fi
  done

  printf "\n"
  if (( failed > 0 )); then
    log_warn "完成。${failed} 个目标连接或解析失败。"
  else
    log_success "完成。"
  fi
}

# 函数名：load_targets_from_file
# 功能：从文件读取目标列表追加到 TARGETS 数组，支持注释与空白行
# 参数：$1 - 目标列表文件路径
# 返回值：0 - 成功, 1 - 文件不存在
load_targets_from_file() {
  local file="$1"
  [[ -f "$file" ]] || die "文件不存在：$file"
  local line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"  # 去掉行内注释
    line="$(printf "%s" "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"  # 去除首尾空白
    [[ -n "$line" ]] && TARGETS+=("$line")
  done <"$file"
}

# 函数名：main
# 功能：脚本入口，加载公共库获取文件锁后解析参数并执行证书检查
# 参数：$@ - 命令行参数（域名/IP 与选项）
# 返回值：0 - 成功, 非 0 - 加锁失败或检查错误
main() {
  # shellcheck source=../load_common.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
  ayu_acquire_lock "ssl-check" "另一个 ssl-check 实例正在运行，请等待其完成后再试。" || return 1

  local file=""

  while (($# > 0)); do
    case "$1" in
      --port)
        [[ $# -gt 1 ]] || die "--port 需要指定端口号。"
        PORT="$2"
        shift
        ;;
      --warn-days)
        [[ $# -gt 1 ]] || die "--warn-days 需要指定天数。"
        WARN_DAYS="$2"
        shift
        ;;
      --file)
        [[ $# -gt 1 ]] || die "--file 需要指定文件路径。"
        file="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      --*)
        die "未知选项：$1"
        ;;
      *)
        TARGETS+=("$1")
        ;;
    esac
    shift
  done

  if [[ -n "$file" ]]; then
    load_targets_from_file "$file"
  fi

  print_banner
  do_check
}

main "$@" || exit $?
