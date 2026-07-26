#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 日志清理（logclean）
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: logclean
# 脚本版本: 1.0
# 功能说明:
#   清理 Linux 系统日志与缓存以释放磁盘空间，包括：journald 旧日志（按容量
#   裁剪）、/var/log 下早于 N 天的轮转日志文件、apt/dnf/yum 包管理器缓存，
#   以及可选的旧内核包清理（保留当前运行的内核）。清理范围经过严格限定，
#   不会删除 /var/log 下的当前活动日志和关键系统日志。
# 使用方式:
#   bash logclean.sh                          # 查看日志占用情况（默认）
#   bash logclean.sh status                   # 同上，查看占用
#   bash logclean.sh clean                    # 执行清理
#   bash logclean.sh clean --days 14          # 保留 14 天内的日志
#   bash logclean.sh clean --journal 500M     # journald 保留 500MB
#   bash logclean.sh clean --old-kernels -y   # 同时清理旧内核
#   bash logclean.sh clean --plan             # 仅预览清理计划
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="logclean"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
DRY_RUN=0
YES=0
KEEP_DAYS=7
KEEP_JOURNAL_SIZE="100M"
PURGE_OLD_KERNELS=0


# ----------------------------------------------------------------------
# 函数:require_root
# 功能:校验当前是否以 root 运行，否则终止脚本
# 参数:无
# 返回值:0 表示是 root；非 0 表示非 root 并终止
# ----------------------------------------------------------------------
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "日志清理需要 root 权限。"
}

# ----------------------------------------------------------------------
# 函数:usage
# 功能:输出脚本帮助说明（操作、选项、说明）到标准输出
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 日志清理 v${SCRIPT_VERSION}

用法：
  logclean [操作] [选项]

操作：
  status       查看日志占用情况（默认）
  clean        执行清理

选项：
  --days N           保留最近 N 天的日志文件，默认 ${KEEP_DAYS}
  --journal SIZE     journald 保留容量，默认 ${KEEP_JOURNAL_SIZE}（如 100M、500M、1G）
  --old-kernels      同时清理旧内核（仅 Debian/RHEL 系，保留当前内核）
  --plan, --dry-run  只显示计划，不执行清理
  -y, --yes          跳过确认
  -h, --help         显示帮助
  --version          显示版本

说明：
  清理范围：journald 旧日志、/var/log 下早于 N 天的 *.log[N] 轮转文件、
  apt/dnf/yum 缓存。--old-kernels 时附带清理多余内核（保留当前）。
  不会删除 /var/log 下的当前活动日志和关键系统日志。
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
  printf "netool懒人工具箱 | 日志清理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ----------------------------------------------------------------------
# 函数:confirm
# 功能:交互式确认提示，YES 模式下直接通过；否则读取用户输入判断是否同意
# 参数:$1 - 提示文本
# 返回值:0 表示确认；1 表示拒绝或读取失败
# ----------------------------------------------------------------------
confirm() {
  local prompt="$1"
  if (( YES )); then return 0; fi
  local answer=""
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ----------------------------------------------------------------------
# 函数:human_size
# 功能:将字节数转换为人类可读的单位（B/KB/MB/GB）输出
# 参数:$1 - 字节数
# 返回值:始终 0，转换结果输出到 stdout
# ----------------------------------------------------------------------
human_size() {
  local bytes="$1"
  if (( bytes >= 1073741824 )); then
    awk -v b="$bytes" 'BEGIN{printf "%.2fGB", b/1073741824}'
  elif (( bytes >= 1048576 )); then
    awk -v b="$bytes" 'BEGIN{printf "%.2fMB", b/1048576}'
  elif (( bytes >= 1024 )); then
    awk -v b="$bytes" 'BEGIN{printf "%.2fKB", b/1024}'
  else
    printf "%dB\n" "$bytes"
  fi
}

# ----------------------------------------------------------------------
# 函数:dir_size_bytes
# 功能:返回指定目录的总字节数；目录不存在或失败时返回 0
# 参数:$1 - 目录路径
# 返回值:始终 0，字节数输出到 stdout
# ----------------------------------------------------------------------
dir_size_bytes() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    printf "0"
    return 0
  fi
  du -sb "$dir" 2>/dev/null | awk '{print $1}' || printf "0"
}

# ----------------------------------------------------------------------
# 函数:detect_package_manager
# 功能:检测系统使用的包管理器，依次识别 apt/dnf/yum，未识别返回 unknown
# 参数:无
# 返回值:始终 0，结果输出到 stdout
# ----------------------------------------------------------------------
detect_package_manager() {
  if command_exists apt || command_exists apt-get; then
    printf "apt"
  elif command_exists dnf; then
    printf "dnf"
  elif command_exists yum; then
    printf "yum"
  else
    printf "unknown"
  fi
}

# ----------------------------------------------------------------------
# 函数:current_kernel
# 功能:获取当前正在运行的内核版本号
# 参数:无
# 返回值:始终 0，内核版本输出到 stdout
# ----------------------------------------------------------------------
current_kernel() {
  uname -r 2>/dev/null || printf ""
}

# ----------------------------------------------------------------------
# 函数:do_status
# 功能:展示当前日志占用情况，包括 journald、/var/log、包管理器缓存以及
#       可清理的轮转日志（最多 20 条），并提示旧内核清理开关状态
# 参数:无
# 返回值:始终 0
# ----------------------------------------------------------------------
do_status() {
  printf "\n日志占用情况：\n"

  if command_exists journalctl; then
    local journal_size=""
    journal_size="$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMG]?' | head -n1 || true)"
    printf "  journald 占用：%s\n" "${journal_size:-未知}"
  else
    printf "  journald：未安装 journalctl\n"
  fi

  local var_log_size=""
  var_log_size="$(dir_size_bytes /var/log)"
  printf "  /var/log 占用：%s\n" "$(human_size "$var_log_size")"

  # 按包管理器分别展示对应缓存目录占用
  local pkg_mgr=""
  pkg_mgr="$(detect_package_manager)"
  case "$pkg_mgr" in
    apt)
      local apt_cache_size=""
      apt_cache_size="$(dir_size_bytes /var/cache/apt/archives 2>/dev/null || printf 0)"
      printf "  apt 缓存占用：%s\n" "$(human_size "$apt_cache_size")"
      ;;
    dnf|yum)
      local yum_cache_dir=""
      if [[ "$pkg_mgr" == "dnf" ]]; then
        yum_cache_dir="/var/cache/dnf"
      else
        yum_cache_dir="/var/cache/yum"
      fi
      local yum_cache_size=""
      yum_cache_size="$(dir_size_bytes "$yum_cache_dir" 2>/dev/null || printf 0)"
      printf "  %s 缓存占用：%s\n" "$pkg_mgr" "$(human_size "$yum_cache_size")"
      ;;
  esac

  # 列出最多 20 个早于 KEEP_DAYS 天的轮转日志文件作为清理预览
  printf "\n可清理的轮转日志（早于 %s 天）：\n" "$KEEP_DAYS"
  if [[ -d /var/log ]]; then
    local count=0
    while IFS= read -r -d '' f; do
      printf "  %s\n" "$f"
      count=$((count + 1))
      (( count >= 20 )) && break
    done < <(find /var/log -type f \( -name '*.log.[0-9]*' -o -name '*.log-*' -o -name '*.[0-9]' -o -name '*.gz' \) -mtime +"$KEEP_DAYS" -print0 2>/dev/null)
    if (( count == 0 )); then
      printf "  无\n"
    fi
  fi

  printf "\n当前内核：%s\n" "$(current_kernel)"
  if [[ "$PURGE_OLD_KERNELS" -eq 1 ]]; then
    printf "  旧内核清理：已启用\n"
  else
    printf "  旧内核清理：未启用（用 --old-kernels 开启）\n"
  fi
}

# ----------------------------------------------------------------------
# 函数:list_old_kernel_pkgs
# 功能:列出可清理的旧内核相关包，apt 系用 dpkg 列出，dnf/yum 系用 rpm 列出；
#       始终排除当前运行的内核版本
# 参数:无
# 返回值:0 表示成功，包名列表输出到 stdout（可能为空）
# ----------------------------------------------------------------------
list_old_kernel_pkgs() {
  local current=""
  current="$(current_kernel)"
  [[ -n "$current" ]] || return 0

  local pkg_mgr=""
  pkg_mgr="$(detect_package_manager)"

  case "$pkg_mgr" in
    apt)
      # 过滤 linux-image/headers/modules 包，剔除当前内核版本
      dpkg -l 2>/dev/null | awk -v cur="$current" '
        $1=="ii" && ($2 ~ /^linux-image-[0-9]/ || $2 ~ /^linux-headers-[0-9]/ || $2 ~ /^linux-modules-[0-9]/) {
          ver=$2
          gsub(/^linux-(image|headers|modules)-/, "", ver)
          if (ver != cur) print $2
        }
      '
      ;;
    dnf|yum)
      rpm -qa 2>/dev/null | grep -E '^(kernel-|kernel-core-|kernel-modules-|kernel-devel-)' | grep -vF "$current" || true
      ;;
  esac
}

# ----------------------------------------------------------------------
# 函数:do_clean
# 功能:按计划执行清理：journald 裁剪 → /var/log 轮转文件 → 包管理器缓存 →
#       旧内核包（可选）。每一步均有日志输出，并在完成后调用 do_status 复查
# 参数:无
# 返回值:0 表示成功或被取消；1 表示非 root（die 退出）
# ----------------------------------------------------------------------
do_clean() {
  require_root

  printf "\n清理计划：\n"
  printf "  保留日志天数：%s\n" "$KEEP_DAYS"
  printf "  journald 保留容量：%s\n" "$KEEP_JOURNAL_SIZE"
  printf "  清理范围：/var/log 轮转文件、包管理器缓存\n"
  if [[ "$PURGE_OLD_KERNELS" -eq 1 ]]; then
    printf "  旧内核清理：已启用（保留当前内核 %s）\n" "$(current_kernel)"
  fi

  if (( DRY_RUN )); then
    log_info "预览模式，不会执行清理。"
    do_status
    return 0
  fi

  if ! confirm "确认执行清理？"; then
    log_info "已取消。"
    return 0
  fi

  # 1. journald：按容量裁剪旧日志
  if command_exists journalctl; then
    log_info "清理 journald（保留 ${KEEP_JOURNAL_SIZE}）..."
    journalctl --vacuum-size="$KEEP_JOURNAL_SIZE" 2>&1 | sed 's/^/  /' || true
  else
    log_warn "未安装 journalctl，跳过 journald 清理。"
  fi

  # 2. /var/log：删除早于 KEEP_DAYS 天的轮转日志文件
  log_info "清理 /var/log 下早于 ${KEEP_DAYS} 天的轮转文件..."
  local removed=0
  while IFS= read -r -d '' f; do
    rm -f "$f" && removed=$((removed + 1))
  done < <(find /var/log -type f \( -name '*.log.[0-9]*' -o -name '*.log-*' -o -name '*.[0-9]' -o -name '*.gz' \) -mtime +"$KEEP_DAYS" -print0 2>/dev/null)
  log_success "已删除 ${removed} 个轮转日志文件。"

  # 3. 包管理器缓存：按检测到的管理器执行对应 clean 命令
  local pkg_mgr=""
  pkg_mgr="$(detect_package_manager)"
  case "$pkg_mgr" in
    apt)
      log_info "清理 apt 缓存..."
      apt-get clean 2>&1 | sed 's/^/  /' || true
      apt-get autoremove -y 2>&1 | tail -n 5 | sed 's/^/  /' || true
      log_success "apt 缓存已清理。"
      ;;
    dnf)
      log_info "清理 dnf 缓存..."
      dnf clean all 2>&1 | sed 's/^/  /' || true
      log_success "dnf 缓存已清理。"
      ;;
    yum)
      log_info "清理 yum 缓存..."
      yum clean all 2>&1 | sed 's/^/  /' || true
      log_success "yum 缓存已清理。"
      ;;
  esac

  # 4. 旧内核包：仅在 --old-kernels 时执行，保留当前内核
  if [[ "$PURGE_OLD_KERNELS" -eq 1 ]]; then
    local old_pkgs=""
    old_pkgs="$(list_old_kernel_pkgs)"
    if [[ -n "$old_pkgs" ]]; then
      log_info "清理旧内核包..."
      case "$pkg_mgr" in
        apt)
          # shellcheck disable=SC2086
          apt-get purge -y $old_pkgs 2>&1 | tail -n 5 | sed 's/^/  /' || true
          ;;
        dnf)
          # shellcheck disable=SC2086
          dnf remove -y $old_pkgs 2>&1 | tail -n 5 | sed 's/^/  /' || true
          ;;
        yum)
          # shellcheck disable=SC2086
          yum remove -y $old_pkgs 2>&1 | tail -n 5 | sed 's/^/  /' || true
          ;;
      esac
      log_success "旧内核已清理。"
    else
      log_info "未发现可清理的旧内核包。"
    fi
  fi

  log_success "清理完成。"
  do_status
}

# ----------------------------------------------------------------------
# 函数:main
# 功能:脚本入口，加载 common.sh 获取文件锁，解析参数后分派到 status 或 clean
# 参数:$@ - 命令行参数
# 返回值:随分派函数返回；获取锁失败返回 1
# ----------------------------------------------------------------------
main() {
  netool_acquire_lock "logclean" "另一个 logclean 实例正在运行，请等待其完成后再试。" || return 1

  local action="status"
  while (($# > 0)); do
    case "$1" in
      status|info) action="status" ;;
      clean|cleanup) action="clean" ;;
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      --old-kernels) PURGE_OLD_KERNELS=1 ;;
      --days)
        [[ $# -gt 1 ]] || die "--days 需要指定天数。"
        KEEP_DAYS="$2"
        shift
        ;;
      --journal)
        [[ $# -gt 1 ]] || die "--journal 需要指定容量。"
        KEEP_JOURNAL_SIZE="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数:$1" ;;
    esac
    shift
  done

  print_banner

  case "$action" in
    status) do_status ;;
    clean) do_clean ;;
  esac
}

main "$@" || exit $?
