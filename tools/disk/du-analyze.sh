#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 磁盘占用分析工具
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: du-analyze.sh
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   分析指定目录的磁盘占用情况，列出大目录和大文件排行榜。
#   大目录分析使用 du，大文件分析使用 find。
#   不会进入无权限目录，静默跳过。
#
# 使用方式:
#   du-analyze [选项] [目录]
#   du-analyze --top 20 --depth 3 /
#   du-analyze --min 100M /var
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="du-analyze"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh du-analyze
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) du-analyze
#   直接：bash tools/disk/du-analyze.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

TOP=20
DEPTH=3
TARGET="/"
EXCLUDE_FS="tmpfs devtmpfs overlay squashfs"
MIN_SIZE="1M"


# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 显示脚本使用说明
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 磁盘占用分析 v${SCRIPT_VERSION}

用法：
  du-analyze [选项] [目录]

选项：
  --top N            显示前 N 个大目录/文件，默认 ${TOP}
  --depth N          目录递归深度，默认 ${DEPTH}
  --min SIZE         最小显示大小，默认 ${MIN_SIZE}（如 10M、1G）
  --exclude-fs LIST  排除文件系统类型，逗号分隔，默认：${EXCLUDE_FS}
  -h, --help         显示帮助
  --version          显示版本

说明：
  默认分析根文件系统（-x 限制跨文件系统）。
  大文件分析使用 find，大目录分析使用 du。
  不会进入无权限目录，静默跳过。
EOF
}

# -----------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅 (被工具箱调用时跳过)
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 磁盘占用分析 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# -----------------------------------------------------------------------------
# 函数: human_size
# 功能: 将字节数转换为人类可读的大小字符串 (KB/MB/GB)
# 参数: $1 - 字节数
# 返回值: 0 - 始终成功；标准输出格式化后的大小字符串
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# 函数: size_to_bytes
# 功能: 将人类可读的大小字符串 (如 1M、10G) 转为字节数
# 参数: $1 - 大小字符串，支持 K/M/G/T/P 后缀或纯数字
# 返回值: 0 - 成功；1 - 格式无效 (脚本通过 die 退出)
# -----------------------------------------------------------------------------
size_to_bytes() {
  local s="$1"
  if [[ "$s" =~ ^([0-9]+)([KMGTP]?)$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      K) echo $((num * 1024)) ;;
      M) echo $((num * 1024 * 1024)) ;;
      G) echo $((num * 1024 * 1024 * 1024)) ;;
      T) echo $((num * 1024 * 1024 * 1024 * 1024)) ;;
      P) echo $((num * 1024 * 1024 * 1024 * 1024 * 1024)) ;;
      "") echo "$num" ;;
    esac
  else
    die "无效大小：$s（示例：1M、10G、500K）"
  fi
}

# -----------------------------------------------------------------------------
# 函数: show_disk_usage
# 功能: 显示文件系统使用情况 (排除虚拟文件系统)
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
show_disk_usage() {
  printf "\n文件系统使用情况：\n"
  df -hT 2>/dev/null | awk 'NR==1 || $2 !~ /^(tmpfs|devtmpfs|overlay|squashfs)$/' | sed 's/^/  /' || true
}

# -----------------------------------------------------------------------------
# 函数: analyze_dirs
# 功能: 分析大目录并按占用空间排序输出
# 参数: $1 - 目标目录
#       $2 - 最小显示字节数
#       $3 - 递归深度
#       $4 - 显示前 N 个结果
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
analyze_dirs() {
  local target="$1"
  local min_bytes="$2"
  local depth="$3"
  local top="$4"

  printf "\n%s大目录（前 %s，深度 %s，最小 %s）：%s\n" "$COLOR_BOLD" "$top" "$depth" "$(human_size "$min_bytes")" "$COLOR_RESET"
  printf "扫描目录：%s\n\n" "$target"

  if ! command_exists du; then
    log_warn "缺少 du 命令。"
    return 0
  fi

  # 排除模式: 收集 EXCLUDE_FS 中所有虚拟/网络文件系统的挂载点
  local exclude_opts=()
  # 遍历所有要排除的文件系统类型，通过 findmnt 查找其挂载点加入排除列表
  local mp=""
  while IFS= read -r mp; do
    [[ -n "$mp" ]] && exclude_opts+=(--exclude="$mp")
  done < <(findmnt -rn -o TARGET -t "$EXCLUDE_FS" 2>/dev/null || true)
  # 同时排除常见的虚拟文件系统目录（即使未被 findmnt 列出也兜底排除）
  exclude_opts+=(--exclude="/proc" --exclude="/sys" --exclude="/dev" --exclude="/run")

  # du -x 只统计同一文件系统，防止跨文件系统统计虚拟/网络挂载点。
  # 这是有意设计: 若要分析 / 下所有非临时文件系统的挂载点，应改为遍历各挂载点分别执行 du。
  du -x --max-depth="$depth" "${exclude_opts[@]}" "$target" 2>/dev/null \
    | awk -v min="$min_bytes" '$1 * 1024 >= min {print $1*1024"\t"$2}' \
    | sort -rn \
    | head -n "$top" \
    | while IFS=$'\t' read -r bytes path; do
        printf "  %10s  %s\n" "$(human_size "$bytes")" "$path"
      done
}

# -----------------------------------------------------------------------------
# 函数: analyze_files
# 功能: 查找大文件并按大小排序输出
# 参数: $1 - 目标目录
#       $2 - 最小显示字节数
#       $3 - 显示前 N 个结果
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
analyze_files() {
  local target="$1"
  local min_bytes="$2"
  local top="$3"

  printf "\n%s大文件（前 %s，最小 %s）：%s\n" "$COLOR_BOLD" "$top" "$(human_size "$min_bytes")" "$COLOR_RESET"
  printf "扫描目录：%s\n\n" "$target"

  if ! command_exists find; then
    log_warn "缺少 find 命令。"
    return 0
  fi

  # find 查找大文件，按大小排序
  # 使用 GNU find 的 -printf 输出 "大小\t路径"，性能优于 -exec stat。
  # 非 GNU find（如 macOS/BSD）不支持 -printf，可改用: find ... -exec stat --printf '%s\t%n\n' {} \;
  find "$target" -xdev -type f -size "+${MIN_SIZE}" -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn \
    | head -n "$top" \
    | while IFS=$'\t' read -r bytes path; do
        printf "  %10s  %s\n" "$(human_size "$bytes")" "$path"
      done
}

# -----------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口，加载公共函数库、解析参数并调用分析函数
# 参数: $@ - 命令行参数
# 返回值: 0 - 成功；1 - 一般错误
# -----------------------------------------------------------------------------
main() {

  while (($# > 0)); do
    case "$1" in
      --top)
        [[ $# -gt 1 ]] || die "--top 需要指定数量。"
        TOP="$2"
        shift
        ;;
      --depth)
        [[ $# -gt 1 ]] || die "--depth 需要指定深度。"
        DEPTH="$2"
        shift
        ;;
      --min)
        [[ $# -gt 1 ]] || die "--min 需要指定大小。"
        MIN_SIZE="$2"
        shift
        ;;
      --exclude-fs)
        [[ $# -gt 1 ]] || die "--exclude-fs 需要指定列表。"
        EXCLUDE_FS="$2"
        shift
        ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      --*) die "未知选项：$1" ;;
      *)
        TARGET="$1"
        ;;
    esac
    shift
  done

  [[ -d "$TARGET" ]] || die "目标目录不存在：$TARGET"

  # 校验 MIN_SIZE
  local min_bytes=""
  min_bytes="$(size_to_bytes "$MIN_SIZE")"

  print_banner
  show_disk_usage
  analyze_dirs "$TARGET" "$min_bytes" "$DEPTH" "$TOP"
  analyze_files "$TARGET" "$min_bytes" "$TOP"
  log_success "分析完成。"
}

main "$@" || exit $?
