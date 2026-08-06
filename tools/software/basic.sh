#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 基础工具批量安装
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: basic.sh
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   一键安装 Linux 服务器常用基础工具包，覆盖 curl/wget/git/vim/
#   nano/unzip/tar/gzip/ca-certificates/net-tools/dnsutils/lsof/
#   htop/iotop/iftop 等常用软件。脚本会自动识别系统包管理器
#   (apt/dnf/yum/apk/pacman/zypper) 并完成依赖映射与安装。
#
# 使用方式:
#   1) 直接执行: ./basic.sh
#   2) 预览命令: ./basic.sh --plan
#   3) 免确认执行: ./basic.sh -y
#   4) 查看帮助: ./basic.sh -h
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="basic-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh basic
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) basic
#   直接：bash tools/software/basic.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


# 需要安装的基础软件包列表（统一名称，由 mapped_packages 做发行版映射）
PACKAGES=(curl wget git vim nano unzip tar gzip ca-certificates net-tools dnsutils lsof htop iotop iftop)
# 是否仅打印安装计划（不实际执行）
DRY_RUN=0
# 是否跳过确认提示直接执行
YES=0


# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 打印脚本帮助信息到标准输出
# 参数: 无
# 返回值: 始终 0
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 基础工具安装 v${SCRIPT_VERSION}

用法：
  basic [选项]

选项：
  --plan        只显示将执行的安装命令
  -y, --yes     直接执行，不再询问
  -h, --help    显示帮助
  --version     显示版本

说明：
  安装 curl/wget/git/vim/unzip/net-tools/dnsutils/lsof/htop 等常用工具。
  会根据 apt/dnf/yum/apk/pacman/zypper 自动选择包管理器。
EOF
}

# -----------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本启动横幅（被 netool 主入口调用时跳过）
# 参数: 无
# 返回值: 始终 0
# -----------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 基础工具安装 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# -----------------------------------------------------------------------------
# 函数: detect_manager
# 功能: 检测当前系统可用的包管理器，按 apt > dnf > yum > apk > pacman > zypper 顺序探测
# 参数: 无
# 返回值: 始终 0（结果通过标准输出返回: apt/dnf/yum/apk/pacman/zypper/unknown）
# -----------------------------------------------------------------------------
detect_manager() {
  if command_exists apt-get; then
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

# -----------------------------------------------------------------------------
# 函数: mapped_packages
# 功能: 将 PACKAGES 中的统一包名映射为目标包管理器下的实际包名
#       （主要处理 dnsutils 在不同发行版下的命名差异）
# 参数: $1 - 包管理器名称（apt/dnf/yum/apk/pacman/zypper）
# 返回值: 始终 0（映射结果通过标准输出返回，以空格分隔）
# -----------------------------------------------------------------------------
mapped_packages() {
  local manager="$1"
  local pkg
  for pkg in "${PACKAGES[@]}"; do
    case "$manager:$pkg" in
      apt:dnsutils) printf "dnsutils " ;;
      dnf:dnsutils|yum:dnsutils) printf "bind-utils " ;;
      apk:dnsutils) printf "bind-tools " ;;
      pacman:dnsutils) printf "bind " ;;
      zypper:dnsutils) printf "bind-utils " ;;
      apt:net-tools|dnf:net-tools|yum:net-tools|apk:net-tools|pacman:net-tools|zypper:net-tools) printf "net-tools " ;;
      *) printf "%s " "$pkg" ;;
    esac
  done
  printf "\n"
}

# -----------------------------------------------------------------------------
# 函数: print_plan
# 功能: 打印即将执行的安装计划（包管理器、软件包列表、建议命令）
# 参数: $1 - 包管理器名称
# 返回值: 始终 0
# -----------------------------------------------------------------------------
print_plan() {
  local manager="$1"
  local packages
  packages="$(mapped_packages "$manager")"

  printf "\n将使用包管理器：%s\n" "$manager"
  printf "将安装软件包：%s\n" "$packages"
  printf "\n建议命令：\n"
  case "$manager" in
    apt) printf "  apt-get update && apt-get install -y %s\n" "$packages" ;;
    dnf) printf "  dnf install -y %s\n" "$packages" ;;
    yum) printf "  yum install -y %s\n" "$packages" ;;
    apk) printf "  apk update && apk add %s\n" "$packages" ;;
    pacman) printf "  pacman -Sy --needed %s\n" "$packages" ;;
    zypper) printf "  zypper refresh && zypper install -y %s\n" "$packages" ;;
    *)
      log_warn "未识别包管理器。支持 apt/dnf/yum/apk/pacman/zypper。"
      return 0
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 函数: confirm
# 功能: 向用户询问是否继续安装，YES 模式下直接通过
# 参数: 无（使用全局变量 YES）
# 返回值: 0 - 用户确认, 1 - 用户取消
# -----------------------------------------------------------------------------
confirm() {
  local answer=""
  if (( YES )); then return 0; fi
  read_prompt "确认安装这些基础工具？[y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# -----------------------------------------------------------------------------
# 函数: run_install
# 功能: 执行实际的安装流程: 打印计划 -> 校验权限 -> 用户确认 -> 调用包管理器
# 参数: $1 - 包管理器名称
# 返回值: 0 - 安装成功, 非 0 - 失败（die 会终止脚本）
# -----------------------------------------------------------------------------
run_install() {
  local manager="$1"
  local packages
  packages="$(mapped_packages "$manager")"

  print_plan "$manager"
  # DRY_RUN 模式仅展示计划，不真正执行
  if (( DRY_RUN )); then
    return 0
  fi

  # 校验 root 权限，包安装必需
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "安装软件需要 root 权限，请用 root 或 sudo。"
  fi

  if ! confirm; then
    log_info "已取消。"
    return 0
  fi

  # 实际调用包管理器安装；此处 $packages 需做单词拆分，故不加引号
  # shellcheck disable=SC2086
  case "$manager" in
    apt) apt-get update && apt-get install -y $packages ;;
    dnf) dnf install -y $packages ;;
    yum) yum install -y $packages ;;
    apk) apk update && apk add $packages ;;
    pacman) pacman -Sy --needed $packages ;;
    zypper) zypper refresh && zypper install -y $packages ;;
    *) die "未识别包管理器。" ;;
  esac

  log_success "基础工具安装完成。"
}

# -----------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口，解析命令行参数并触发安装流程
# 参数: $1..$N - 命令行参数
# 返回值: 0 - 成功, 非 0 - 失败
# -----------------------------------------------------------------------------
main() {
  print_banner

  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done

  run_install "$(detect_manager)"
}

main "$@" || exit $?
