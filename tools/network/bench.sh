#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 轻量性能测试
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: bench.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   对系统进行轻量性能测试,包含系统概况、磁盘顺序写入轻测、
#   网络连通性轻测三部分。不下载大型测速脚本,不长时间压测。
#   支持 --plan/--dry-run 预览模式,仅展示测试内容不实际执行 I/O。
#
# 使用方式:
#   bench [操作] [选项]
#     操作可为 all/sys/disk/net(默认 all)
#   bench --plan    仅预览测试内容
#   bench -h        显示帮助
#   bench --version 显示版本
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="bench-tools"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
DRY_RUN=0


# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 轻量性能测试 v${SCRIPT_VERSION}

用法:
  bench [操作] [选项]

操作:
  all       全部测试(默认)
  sys       系统概况
  disk      磁盘顺序写入轻测
  net       网络连通性轻测

选项:
  --plan, --dry-run  仅预览测试内容,不执行
  -h, --help         显示帮助
  --version          显示版本

说明:
  这是轻量测试,不下载大型测速脚本,不长时间压测。
  --plan 模式下会显示将要执行的测试项,但不会实际执行 I/O 操作。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅; 作为子模块被调用时静默跳过
# 参数: 无
# 返回值: 0 - 始终成功
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${AYU_TOOLBOX:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 轻量性能测试 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: do_sys
# 功能: 输出系统概况,包括发行版、内核、架构、CPU、内存与磁盘使用情况
# 参数: 无
# 返回值: 0 - 始终成功(子命令失败时静默处理)
# ------------------------------------------------------------------------------
do_sys() {
  printf "\n系统概况:\n"
  printf "  系统:"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf "%s\n" "${PRETTY_NAME:-${NAME:-未知}}"
  else
    uname -s
  fi
  printf "  内核:%s\n" "$(uname -r 2>/dev/null || echo "-")"
  printf "  架构:%s\n" "$(uname -m 2>/dev/null || echo "-")"
  printf "  CPU:%s\n" "$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//' || echo "-")"
  printf "\n内存:\n"
  free -h 2>/dev/null | sed 's/^/  /' || true
  printf "\n磁盘:\n"
  df -hT -x tmpfs -x devtmpfs 2>/dev/null | sed 's/^/  /' || true
}

# ------------------------------------------------------------------------------
# 函数: do_disk
# 功能: 磁盘顺序写入轻测,向临时文件写入 256 MiB 后删除; 预览模式下不实际写入
# 参数: 无
# 返回值: 0 - 成功, 1 - 缺少 dd 命令
# 说明: dd 失败时仍会清理临时文件,避免残留占用磁盘
# ------------------------------------------------------------------------------
do_disk() {
  command_exists dd || die "缺少 dd。"

  if (( DRY_RUN )); then
    printf "\n磁盘轻测(预览):\n"
    printf "  将写入 256 MiB 到临时文件并删除\n"
    printf "  命令:dd if=/dev/zero of=<tmp> bs=1M count=256 conv=fdatasync\n"
    log_info "预览模式,不会执行磁盘写入。"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp -t ayu-bench.XXXXXX 2>/dev/null || mktemp)"
  printf "\n磁盘轻测:\n"
  printf "  写入 256 MiB 到 %s,完成后自动删除。\n" "$tmp_file"
  # 使用 if 捕获 dd 退出码,避免 set -e 在管道失败时提前退出导致临时文件残留
  if ! dd if=/dev/zero of="$tmp_file" bs=1M count=256 conv=fdatasync status=progress 2>&1 | sed 's/^/  /'; then
    log_warn "dd 写入失败,将清理临时文件。"
  fi
  # 无论 dd 成功或失败都清理临时文件
  rm -f "$tmp_file"
}

# ------------------------------------------------------------------------------
# 函数: do_net
# 功能: 网络连通性轻测,查询公网 IP 并对 223.5.5.5 执行 Ping 测试
# 参数: 无
# 返回值: 0 - 始终成功(子命令失败时静默处理)
# ------------------------------------------------------------------------------
do_net() {
  printf "\n网络轻测:\n"
  if command_exists curl; then
    printf "  公网 IP:"
    curl -fsSL --connect-timeout 5 https://api.ipify.org 2>/dev/null || printf "查询失败"
    printf "\n"
  fi
  if command_exists ping; then
    printf "\n  Ping 223.5.5.5:\n"
    ping -c 4 223.5.5.5 2>/dev/null | sed 's/^/    /' || true
  else
    printf "  缺少 ping。\n"
  fi
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本入口,加载公共库获取文件锁后解析参数并分发到对应测试函数
# 参数: $@ - 命令行参数(操作名与选项)
# 返回值: 0 - 成功, 非 0 - 加锁失败或测试错误
# ------------------------------------------------------------------------------
main() {
  ayu_acquire_lock "bench" "另一个 bench 实例正在运行,请等待其完成后再试。" || return 1

  local action="all"

  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      all|sys|system|disk|io|net|network) action="$1" ;;
      *) die "未知操作:$1" ;;
    esac
    shift
  done

  print_banner

  case "$action" in
    all) do_sys; do_disk; do_net ;;
    sys|system) do_sys ;;
    disk|io) do_disk ;;
    net|network) do_net ;;
  esac
}

main "$@" || exit $?
