#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - Docker 管理工具
# =============================================================================
# 脚本名称：docker.sh
# 版本：1.0
# 功能说明：
#   提供 Docker 日常运维的懒人化封装，覆盖状态查看、容器/镜像/数据卷/网络
#   列举、日志查看，以及 Docker 软件包的安装、卸载与国内镜像加速器配置。
#   安装/卸载自动识别 APT / DNF / YUM / APK / Pacman / Zypper 包管理器，
#   并在安装失败时进行回滚清理，降低残留风险。
# 使用方式：
#   bash docker.sh [操作] [选项]
#   curl -fsSL <SCRIPT_URL> | bash -s -- [操作] [选项]
# 操作（详见 usage）：
#   status     查看 Docker 状态（默认）
#   ps/images/volumes/networks  查看对应资源
#   logs NAME  查看容器最近日志
#   install    安装 Docker（支持 --plan 预览、--mirror 配置加速器）
#   uninstall  卸载 Docker 软件包，保留 /var/lib/docker
#   -h/--help  显示帮助
# =============================================================================

set -Eeuo pipefail

SCRIPT_NAME="docker-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# 交互/批量模式标志：1 表示跳过所有二次确认（-y / --yes 触发）
YES=0
# 安装时是否配置国内镜像加速器：1 表示配置（--mirror 触发）
CONFIGURE_MIRROR=0


## 校验 Docker 已安装，未安装时给出明确的安装引导并终止
## 用于 ps/images/volumes/networks/logs 等需要 docker 命令的操作
require_docker() {
  command_exists docker || die "未安装 Docker，请使用 install 子命令安装：bash docker.sh install"
}

## 输出脚本帮助信息
usage() {
  cat <<EOF
netool懒人工具箱 | Docker 工具 v${SCRIPT_VERSION}

用法：
  docker [操作]

操作：
  status     查看 Docker 状态（默认）
  ps         查看容器
  images     查看镜像
  volumes    查看数据卷
  networks   查看网络
  logs NAME  查看容器最近日志
  install    安装 Docker（支持 --plan 预览、--mirror 配置加速器）
  uninstall  卸载 Docker 软件包，不删除 /var/lib/docker

选项：
  -y, --yes  跳过二次确认
  --plan     仅打印安装计划，不实际执行
  --mirror   安装完成后配置国内镜像加速器

说明：
  查看类操作低风险；安装/卸载需要 root，并会二次确认。
EOF
}

## 输出脚本启动横幅（被外层工具箱调用时跳过）
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | Docker 工具 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

## 查看 Docker 综合状态：版本信息 + 磁盘占用
## 未安装 Docker 时仅提示，不报错（便于用户先了解安装建议）
do_status() {
  if ! command_exists docker; then
    log_warn "未安装 Docker。可执行：docker.sh install --plan 查看安装建议。"
    return 0
  fi
  printf "\nDocker 版本：\n"
  docker version 2>/dev/null | sed -n '1,30p' || true
  printf "\nDocker 占用：\n"
  docker system df 2>/dev/null || true
}

## 列出正在运行的容器（表格形式展示名称/镜像/状态/端口）
do_ps() {
  require_docker
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

## 列出本地所有镜像
do_images() {
  require_docker
  docker images
}

## 列出所有数据卷
do_volumes() {
  require_docker
  docker volume ls
}

## 列出所有网络
do_networks() {
  require_docker
  docker network ls
}

## 查看指定容器的最近 120 行日志
## 参数1: 容器名或 ID（必填）
do_logs() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "请指定容器名：docker.sh logs <name>"
  require_docker
  docker logs --tail 120 "$name"
}

## 检测当前系统使用的包管理器
## 返回值: apt / dnf / yum / apk / pacman / zypper / unknown
## 通过检查各包管理器命令是否存在来判断，优先级从前到后
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

## 二次确认提示（默认否）
## 参数1: 提示文本  返回值: 0 用户确认；1 用户取消或读取失败
## 当全局 YES=1（-y / --yes 触发）时直接返回 0，跳过询问
confirm() {
  local prompt="$1"
  local answer=""
  if (( YES )); then return 0; fi
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

## 校验当前用户为 root，否则终止脚本
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "该操作需要 root 权限。"
}

## 打印 Docker 安装计划（仅展示，不执行）
## 参数1: 包管理器名称（apt/dnf/yum/apk/pacman/zypper）
docker_install_plan() {
  local manager="$1"
  printf "\nDocker 安装计划：\n"
  printf "  包管理器：%s\n" "$manager"
  printf "  说明：优先使用发行版仓库中的 docker/docker.io 软件包。\n"
  printf "\n建议命令：\n"
  case "$manager" in
    apt) printf "  apt-get update && apt-get install -y docker.io docker-compose-plugin\n" ;;
    dnf) printf "  dnf install -y docker docker-compose-plugin\n" ;;
    yum) printf "  yum install -y docker docker-compose-plugin\n" ;;
    apk) printf "  apk add docker docker-cli-compose\n" ;;
    pacman) printf "  pacman -Sy --needed docker docker-compose\n" ;;
    zypper) printf "  zypper install -y docker docker-compose\n" ;;
    *) log_warn "未识别包管理器，无法生成安装命令。" ;;
  esac
}

## 安装 Docker 软件包（按当前包管理器分发对应命令）
## 参数1: 包管理器名称  返回值: 0 成功；1 失败
## 失败时不直接退出，由调用方决定后续清理动作
install_docker_packages() {
  local manager="$1"
  case "$manager" in
    apt) apt-get update && apt-get install -y docker.io docker-compose-plugin ;;
    dnf) dnf install -y docker docker-compose-plugin ;;
    yum) yum install -y docker docker-compose-plugin ;;
    apk) apk add docker docker-cli-compose ;;
    pacman) pacman -Sy --needed docker docker-compose ;;
    zypper) zypper install -y docker docker-compose ;;
    *) return 1 ;;
  esac
}

## 安装失败后的清理：移除可能已部分安装的 Docker 相关软件包
## 参数1: 包管理器名称  返回值: 始终为 0（清理本身不阻断流程）
## 注：清理失败不视为致命错误，仅打印警告供用户人工处理
cleanup_failed_install() {
  local manager="$1"
  log_warn "正在清理部分安装的软件包..."
  case "$manager" in
    apt) apt-get remove -y docker.io docker-compose-plugin docker-ce docker-ce-cli containerd.io 2>/dev/null || true ;;
    dnf) dnf remove -y docker docker-compose-plugin docker-ce docker-ce-cli containerd.io 2>/dev/null || true ;;
    yum) yum remove -y docker docker-compose-plugin docker-ce docker-ce-cli containerd.io 2>/dev/null || true ;;
    apk) apk del docker docker-cli-compose 2>/dev/null || true ;;
    pacman) pacman -Rns --noconfirm docker docker-compose 2>/dev/null || true ;;
    zypper) zypper remove -y docker docker-compose 2>/dev/null || true ;;
    *) log_warn "未识别包管理器，跳过自动清理，请手动检查。" ;;
  esac
  log_warn "清理完成。如需重试，请重新执行 install 子命令。"
}

## 启用并启动 Docker 服务（systemd 优先，回退到 service 命令）
## 返回值: 0 启用成功或无可用服务管理器；非 0 启用失败
enable_docker_service() {
  if command_exists systemctl; then
    systemctl enable --now docker 2>/dev/null || true
  elif command_exists service; then
    service docker start 2>/dev/null || true
  fi
}

## 配置 Docker 国内镜像加速器
## 向 /etc/docker/daemon.json 写入镜像加速器配置并重启 Docker 服务
## 返回值: 0 配置成功；1 配置失败或被取消
## 交互式询问是否配置，--mirror 触发或 -y 模式下默认配置
configure_mirror_acceleration() {
  local configure=0

  # 命令行 --mirror 触发，或 -y 模式下自动配置；否则交互询问
  if (( YES )) || (( CONFIGURE_MIRROR )); then
    configure=1
  else
    if confirm "是否配置国内镜像加速器？（推荐国内网络环境使用）"; then
      configure=1
    fi
  fi

  (( configure )) || return 0

  local daemon_dir="/etc/docker"
  local daemon_json="${daemon_dir}/daemon.json"

  require_root

  # 确保配置目录存在
  if [[ ! -d "$daemon_dir" ]]; then
    mkdir -p "$daemon_dir" || {
      log_error "无法创建配置目录：$daemon_dir"
      return 1
    }
  fi

  # 备份已有 daemon.json
  if [[ -f "$daemon_json" ]]; then
    local backup_file="${daemon_json}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$daemon_json" "$backup_file" || {
      log_warn "备份 daemon.json 失败，跳过镜像加速器配置。"
      return 1
    }
    log_info "已备份原配置到：$backup_file"
  fi

  # 写入镜像加速器配置（覆盖式写入，备份已保留）
  # 加速器来源：主流公共镜像服务，按可用性排序
  cat > "$daemon_json" <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

  # 重启 Docker 服务以加载新配置
  if command_exists systemctl; then
    if ! systemctl restart docker 2>/dev/null; then
      log_error "重启 docker 服务失败，请手动执行：systemctl restart docker"
      return 1
    fi
  elif command_exists service; then
    if ! service docker restart 2>/dev/null; then
      log_error "重启 docker 服务失败，请手动执行：service docker restart"
      return 1
    fi
  else
    log_warn "未找到 systemd 或 service 命令，请手动重启 Docker 服务。"
  fi

  log_success "国内镜像加速器配置完成。"
}

## 安装 Docker 主流程
## 参数: --plan 仅预览不执行；-y/--yes 跳过确认；--mirror 同时配置加速器
## 返回值: 0 安装成功；1 安装失败或用户取消
## 流程：识别包管理器 -> 预览计划 -> root 校验 -> 二次确认
##       -> 安装软件包（失败时清理）-> 启用服务 -> 可选配置加速器
do_install() {
  local plan_only=0
  local manager
  while (($# > 0)); do
    case "$1" in
      --plan|--dry-run) plan_only=1 ;;
      -y|--yes) YES=1 ;;
      --mirror) CONFIGURE_MIRROR=1 ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done

  manager="$(detect_manager)"
  docker_install_plan "$manager"
  (( plan_only )) && return 0
  [[ "$manager" != "unknown" ]] || die "未识别包管理器。"
  require_root
  if ! confirm "确认安装 Docker？"; then
    log_warn "已取消。"
    return 0
  fi

  # 执行安装：失败时打印错误、清理残留、返回非 0 退出
  # 注：不使用 set -e 直接退出，以便在失败后执行清理逻辑
  if ! install_docker_packages "$manager"; then
    log_error "Docker 安装失败，正在清理..."
    cleanup_failed_install "$manager"
    return 1
  fi

  # 启用并启动 Docker 服务（失败仅警告，不回滚安装）
  enable_docker_service

  # 校验 docker 命令可用，避免静默失败（如 PATH 未刷新）
  if ! command_exists docker; then
    log_warn "安装已完成但 docker 命令不可用，请重新登录或手动检查 PATH 配置。"
    return 1
  fi

  log_success "Docker 安装流程完成。"

  # 可选：配置国内镜像加速器
  configure_mirror_acceleration
}

## 卸载 Docker 软件包主流程
## 参数: -y/--yes 跳过二次确认
## 返回值: 0 卸载成功或部分失败（不终止）；1 用户取消或未识别包管理器
## 注：仅卸载软件包，保留 /var/lib/docker 数据目录
do_uninstall() {
  local manager
  while (($# > 0)); do
    case "$1" in
      -y|--yes) YES=1 ;;
      *) die "未知参数：$1" ;;
    esac
    shift
  done

  manager="$(detect_manager)"
  printf "\nDocker 卸载计划：\n"
  printf "  包管理器：%s\n" "$manager"
  printf "  保留数据目录：/var/lib/docker\n"
  [[ "$manager" != "unknown" ]] || die "未识别包管理器。"
  require_root
  if ! confirm "确认卸载 Docker 软件包？"; then
    log_warn "已取消。"
    return 0
  fi

  # 卸载失败不直接退出，记录状态后给出明确提示
  local uninstall_failed=0
  case "$manager" in
    apt) apt-get remove -y docker.io docker-compose-plugin docker-ce docker-ce-cli containerd.io || uninstall_failed=1 ;;
    dnf) dnf remove -y docker docker-compose-plugin docker-ce docker-ce-cli containerd.io || uninstall_failed=1 ;;
    yum) yum remove -y docker docker-compose-plugin docker-ce docker-ce-cli containerd.io || uninstall_failed=1 ;;
    apk) apk del docker docker-cli-compose || uninstall_failed=1 ;;
    pacman) pacman -Rns --noconfirm docker docker-compose || uninstall_failed=1 ;;
    zypper) zypper remove -y docker docker-compose || uninstall_failed=1 ;;
  esac
  if (( uninstall_failed )); then
    log_warn "部分软件包卸载失败，请检查上方输出。数据目录未删除。"
  else
    log_success "Docker 软件包卸载流程完成，数据目录未删除。"
  fi
}

## 命令行操作分发器
## 参数1: 操作名（status/ps/images/volumes/networks/logs/install/uninstall/help/version）
## 其余参数透传给具体操作函数
run_action() {
  local action="${1:-status}"
  shift || true
  case "$action" in
    status|info) do_status ;;
    ps|containers|container) do_ps ;;
    images|image) do_images ;;
    volumes|volume) do_volumes ;;
    networks|network) do_networks ;;
    logs|log) do_logs "${1:-}" ;;
    install|setup) do_install "$@" ;;
    uninstall|remove) do_uninstall "$@" ;;
    -h|--help) usage ;;
    --version) printf "%s\n" "$SCRIPT_VERSION" ;;
    *) die "未知操作：$action" ;;
  esac
}

## 交互式菜单循环（无命令行参数时进入）
## 返回值: 0 用户选择返回；1 读取输入失败
interactive_loop() {
  local answer=""
  local name=""
  while true; do
    printf "\n请选择 Docker 操作：\n"
    printf "  1. 查看 Docker 状态\n"
    printf "  2. 查看容器\n"
    printf "  3. 查看镜像\n"
    printf "  4. 查看数据卷\n"
    printf "  5. 查看网络\n"
    printf "  6. 查看容器日志\n"
    printf "  b. 返回\n"
    if ! read_prompt "输入编号： " answer; then
      log_error "无法读取输入。"
      return 1
    fi

    case "$answer" in
      1) do_status ;;
      2) do_ps ;;
      3) do_images ;;
      4) do_volumes ;;
      5) do_networks ;;
      6)
        read_prompt "容器名： " name || return 1
        do_logs "$name"
        ;;
      b|B|back|返回) return 0 ;;
      "") log_warn "未读取到输入，请重新输入。" ;;
      *) log_warn "无效输入，请输入 1-6 或 b 返回。" ;;
    esac
  done
}

## 脚本入口：有命令行参数时按操作分发；无参数时进入交互菜单
main() {
  print_banner
  if (($# > 0)); then
    run_action "$@"
  else
    interactive_loop
  fi
}

main "$@"
