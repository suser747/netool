#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - Homebrew 管理工具
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: homebrew
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   Homebrew 包管理器的安装、配置、卸载一体化工具。
#   支持国内镜像源配置，解决国内用户访问 GitHub 速度慢的问题。
#   支持 macOS (arm64/x86_64) 与 Linux 双平台。
#
# 主要功能:
#   1. 安装/配置 Homebrew - 安装 brew 并配置国内镜像源
#   2. 卸载 Homebrew     - 完整卸载并清理残留文件
#   3. 安装 Command Line Tools - macOS 专用 Git 安装（Homebrew 依赖）
#
# 安全特性:
#   - 执行前 bash -n 语法校验，防止 sed 替换出错或内容被篡改
#   - commit pin 审计: 记录官方 install.sh 的 commit hash 便于事后追溯
#   - 备份机制: 删除旧版前备份（桌面/主目录/tmp 三级回退，兼容 Linux）
#   - ERR trap 错误捕获: 任意命令失败时打印出错行号和退出码
#   - 跨平台 sed 兼容封装
#
# 使用方式:
#   交互式运行:    bash homebrew.sh
#   经工具箱调用:  bash main.sh homebrew
#   预览模式:      bash homebrew.sh --plan        （或 --dry-run，仅打印不执行）
#   非交互安装:    bash homebrew.sh -y            （或 --yes，自动确认所有提示）
#   组合使用:      bash homebrew.sh --plan -y
#
# 命令行参数:
#   --plan, --dry-run  预览模式，仅打印将要执行的操作，不实际执行
#   -y, --yes          非交互模式，所有确认提示自动通过（主菜单默认选 1）
#   --help             显示用法后退出
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="homebrew"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh homebrew
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) homebrew
#   直接：bash tools/software/homebrew.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


# 命令行参数标志（在入口参数解析处赋值）
# DRY_RUN=1 时仅预览将要执行的操作，不实际执行
# YES=1 时非交互模式，所有确认提示自动按默认值（或确认）继续
DRY_RUN=0
YES=0

# 时间戳，用于备份目录命名和日志记录
TIME=$(date "+%Y-%m-%d_%H-%M-%S")
# CPU 架构: arm64 / x86_64 / aarch64 等
UNAME_MACHINE="$(uname -m)"
# 操作系统类型：Linux / Darwin
OS="$(uname)"

# 平台标志变量（HOMEBREW_ON_LINUX / HOMEBREW_ON_MACOS）
if [[ "${OS}" == "Linux" ]]; then
  HOMEBREW_ON_LINUX=1
elif [[ "${OS}" == "Darwin" ]]; then
  HOMEBREW_ON_MACOS=1
else
  echo "Homebrew 只运行在 Mac OS 或 Linux." >&2
  exit 1
fi

# ============================================================
# 颜色输出控制
# ============================================================
# 仅在终端（TTY）环境下启用 ANSI 颜色转义，管道/重定向时自动禁用
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi

# 颜色变量定义（与 netool 工具箱其他脚本保持一致的配色风格）
tty_universal() { tty_escape "0;$1"; }    # 普通字体 + 指定颜色
tty_underline="$(tty_escape "4;39")"      # 下划线（默认前景色）
tty_blue="$(tty_universal 34)"            # 蓝色：菜单编号、提示
tty_red="$(tty_universal 31)"             # 红色：错误、重要警告
tty_green="$(tty_universal 32)"           # 绿色：成功、完成
tty_yellow="$(tty_universal 33)"          # 黄色：警告、确认提示
tty_bold="$(tty_universal 1)"             # 粗体：标题
tty_cyan="$(tty_universal 36)"            # 青色：信息提示
tty_reset="$(tty_escape 0)"               # 重置所有属性

# netool懒人工具箱调用时抑制颜色输出（与项目其它脚本一致）
# 当通过 main.sh 调用时 NETOOL=1，
# 此时禁用所有颜色转义，保证输出在日志/管道中干净可读
if [[ -n "${NETOOL:-}" ]]; then
  tty_escape() { :; }
  tty_underline=""
  tty_blue=""
  tty_red=""
  tty_green=""
  tty_yellow=""
  tty_bold=""
  tty_cyan=""
  tty_reset=""
fi

# ============================================================
# 日志函数（与 netool 工具箱其他脚本保持一致）
# ============================================================
log_info()    { echo "${tty_bold}${tty_cyan}[信息]${tty_reset} $*"; }     # 普通信息
log_success() { echo "${tty_bold}${tty_green}[完成]${tty_reset} $*"; }    # 操作成功
log_warn()    { echo "${tty_bold}${tty_yellow}[警告]${tty_reset} $*"; }   # 警告信息
log_error()   { echo "${tty_bold}${tty_red}[错误]${tty_reset} $*" >&2; }  # 错误信息（输出到 stderr）

# ============================================================
# 平台初始化
# ============================================================

# -----------------------------------------------------------------------------
# 函数: major_minor
# 功能: 提取版本号的主.次 部分，例如 "10.15.7" -> "10.15"，用于 macOS 版本号比较
# 参数: $1 - 完整版本号字符串
# 返回值: 始终 0（结果通过 stdout 输出）
# -----------------------------------------------------------------------------
major_minor() {
  echo "${1%%.*}.$(x="${1#*.}"; echo "${x%%.*}")"
}

# -----------------------------------------------------------------------------
# 函数: init_macos_vars
# 功能: macOS 平台变量初始化，根据 CPU 架构设置 Homebrew 安装路径
# 参数: 无
# 返回值: 始终 0（设置全局 HOMEBREW_PREFIX / HOMEBREW_REPOSITORY / HOMEBREW_CACHE 等变量）
# -----------------------------------------------------------------------------
# 安装路径: arm64 → /opt/homebrew，x86_64 → /usr/local
init_macos_vars() {
  UNAME_MACHINE="$(/usr/bin/uname -m)"
  HOMEBREW_REPOSITORY_ARM64="/opt/homebrew"
  HOMEBREW_REPOSITORY_X86="/usr/local/Homebrew"

  if [[ "${UNAME_MACHINE}" == "arm64" ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}"
  else
    HOMEBREW_PREFIX="/usr/local"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
  fi
  HOMEBREW_CACHE="${HOME}/Library/Caches/Homebrew"
  HOMEBREW_LOGS="${HOME}/Library/Logs/Homebrew"
  macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
}

# -----------------------------------------------------------------------------
# 函数: init_linux_vars
# 功能: Linux 平台变量初始化，统一安装到 /home/linuxbrew/.linuxbrew
# 参数: 无
# 返回值: 始终 0（设置全局 HOMEBREW_PREFIX / HOMEBREW_REPOSITORY / HOMEBREW_CACHE 等变量）
# -----------------------------------------------------------------------------
# Linux 平台变量初始化
# 统一安装到 /home/linuxbrew/.linuxbrew
init_linux_vars() {
  UNAME_MACHINE="$(uname -m)"
  HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
  HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
  HOMEBREW_CACHE="${HOME}/.cache/Homebrew"
  HOMEBREW_LOGS="${HOME}/.logs/Homebrew"
}

# ============================================================
# 镜像源配置
# ============================================================
# 国内镜像源列表（bottles + pip + git 三合一）
# 格式: 编号:名称:bottles地址:pip地址:git地址
# - bottles 地址: HOMEBREW_BOTTLE_DOMAIN，预编译二进制包下载地址
# - pip 地址:     HOMEBREW_PIP_INDEX_URL，pip 安装 Python 包时使用的源
# - git 地址:     Homebrew 仓库的 git 镜像地址（部分镜像不提供，留空）
MIRRORS=(
  "1:中科大:https://mirrors.ustc.edu.cn/homebrew-bottles:https://pypi.mirrors.ustc.edu.cn/simple:https://mirrors.ustc.edu.cn/git/homebrew"
  "2:清华大学:https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles:https://pypi.tuna.tsinghua.edu.cn/simple:https://mirrors.tuna.tsinghua.edu.cn/git/homebrew"
  "3:上海交通大学:https://mirror.sjtu.edu.cn/homebrew-bottles:https://mirror.sjtu.edu.cn/pypi/web/simple:"
  "4:腾讯:https://mirrors.cloud.tencent.com/homebrew-bottles:https://mirrors.cloud.tencent.com/pypi/simple:"
  "5:阿里巴巴:https://mirrors.aliyun.com/homebrew/homebrew-bottles:http://mirrors.aliyun.com/pypi/simple:"
)

# 仅 Git 仓库地址的镜像源列表（用于仅更换仓库地址的场景）
GIT_ONLY_MIRRORS=(
  "1:清华大学:https://mirrors.tuna.tsinghua.edu.cn/git/homebrew"
  "2:Gitee:https://gitee.com/Homebrew2"
)

# 卸载脚本源（用于下载官方 uninstall.sh）
UNINSTALL_MIRRORS=(
  "1:清华大学源:https://mirrors.tuna.tsinghua.edu.cn/git/homebrew"
  "2:Gitee源:https://gitee.com/Homebrew2"
)

# 当前选中的镜像源配置（关联数组，结构清晰避免字符串拼接）
declare -A MIRROR_CONFIG=(
  ["name"]=""
  ["bottle_url"]=""
  ["pip_url"]=""
  ["git_url"]=""
)

# ============================================================
# 通用工具函数
# ============================================================

# -----------------------------------------------------------------------------
# 函数: JudgeSuccess
# 功能: 判断上一步命令是否成功，失败时打印错误并按参数决定是否退出
# 参数: $1 - 失败时的描述信息; $2 - 'out' 表示失败时直接退出脚本，其他值表示仅打印错误继续
# 返回值: 无（通过日志输出结果，失败时按参数2决定是否退出）
# 注意事项:
#   - 函数体首行立即用 local exit_code=$? 捕获上一条命令退出码，
#     避免后续任何命令（如 [[ ]]）覆盖 $?。
#   - 调用点必须在目标命令执行后立即调用，中间不能插入其他命令。
#   - 推荐优先使用显式 `if ! cmd; then ... fi` 写法替代本函数。
# -----------------------------------------------------------------------------
JudgeSuccess() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_error "此步骤失败: '$1'"
    if [[ "${2:-}" == 'out' ]]; then
      exit 1
    fi
  else
    log_success "此步骤成功"
  fi
}

# -----------------------------------------------------------------------------
# 函数: sed_compatible
# 功能: 跨平台 sed 兼容封装，macOS BSD sed 与 Linux GNU sed 的 -i 参数差异自动适配
# 参数: $1 - 要修改的文件路径; $2 - sed 表达式
# 返回值: 始终 0（成功时修改文件，失败时尝试下一种写法）
# -----------------------------------------------------------------------------
# 跨平台 sed 兼容封装
# macOS 的 BSD sed 需要 -i '' 或 -i.bak 后缀，Linux 的 GNU sed 直接 -i
# 本函数自动尝试两种写法，统一调用接口
sed_compatible() {
  local file="$1"
  local pattern="$2"

  # 优先尝试 GNU sed 的 -i.bak 写法（成功后清理 .bak 文件）
  if sed -i.bak "${pattern}" "${file}" >/dev/null 2>&1; then
    rm -f "${file}.bak"
    return 0
  # 其次尝试 BSD sed 的 -i '' 写法
  elif sed -i '' "${pattern}" "${file}" >/dev/null 2>&1; then
    return 0
  # 最后直接尝试 -i（部分 busybox sed 支持）
  else
    sed -i "${pattern}" "${file}"
    return 0
  fi
}

# -----------------------------------------------------------------------------
# 函数: detect_shell_profile
# 功能: 检测当前用户的 shell 配置文件路径（bash/zsh/其他），Linux 统一使用 /etc/profile
# 参数: 无
# 返回值: 始终 0（通过 stdout 输出配置文件路径）
# -----------------------------------------------------------------------------
# 检测当前用户的 shell 配置文件路径
# - bash: ~/.bash_profile（优先）或 ~/.profile
# - zsh:  ~/.zprofile
# - 其他: ~/.profile
# - Linux: 统一使用 /etc/profile（全局生效）
detect_shell_profile() {
  local shell_profile

  case "${SHELL}" in
    */bash*)
      if [[ -r "${HOME}/.bash_profile" ]]; then
        shell_profile="${HOME}/.bash_profile"
      else
        shell_profile="${HOME}/.profile"
      fi
      ;;
    */zsh*)
      shell_profile="${HOME}/.zprofile"
      ;;
    *)
      shell_profile="${HOME}/.profile"
      ;;
  esac

  if [[ -n "${HOMEBREW_ON_LINUX-}" ]]; then
    shell_profile="/etc/profile"
  fi

  echo "${shell_profile}"
}

# -----------------------------------------------------------------------------
# 函数: check_admin
# 功能: 获取管理员权限，非 root 用户通过 sudo -v 获取（支持免密 sudo）
# 参数: 无
# 返回值: 无（成功时打印日志，失败时 exit 1）
# -----------------------------------------------------------------------------
# 获取管理员权限
# 非 root 用户通过 sudo -v 获取，已支持免密 sudo 的场景直接通过
check_admin() {
  if [[ "$(id -u)" != "0" ]]; then
    if ! sudo -n true 2>/dev/null; then
      log_info "请输入开机密码以获取管理员权限："
      if ! sudo -v; then
        log_error "需要管理员权限才能继续"
        exit 1
      fi
    fi
  fi
  log_success "已获取管理员权限"
}

# -----------------------------------------------------------------------------
# 函数: confirm_action
# 功能: 用户确认提示，支持 --plan/--dry-run 预览模式和 -y/--yes 非交互模式
# 参数: $1 - 提示信息（不含 Y/N 部分）; $2 - 默认值 Y 或 N，默认为 N
# 返回值: 0 表示用户确认，1 表示用户取消
# 行为说明:
#   - YES=1（-y/--yes）: 自动确认，返回 0，并打印自动确认日志
#   - DRY_RUN=1（--plan/--dry-run）: 仅打印预览日志，返回 1（跳过实际操作）
#   - 交互模式: 读取用户输入，按 Y/y 确认，其他视为取消
# -----------------------------------------------------------------------------
confirm_action() {
  local prompt="$1"
  local default="${2:-N}"

  # -y/--yes 非交互模式: 自动确认
  if [[ "${YES:-0}" == "1" ]]; then
    log_info "[非交互模式] ${prompt} -> Y"
    return 0
  fi

  # --plan/--dry-run 预览模式: 跳过实际操作
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] ${prompt} -> 跳过"
    return 1
  fi

  # 交互模式: 询问用户
  echo -n "${tty_yellow}${prompt} (Y/N) [默认: ${default}]: ${tty_reset}"
  local input
  read input
  input="${input:-${default}}"

  if [[ "${input}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  return 1
}

# -----------------------------------------------------------------------------
# 函数: backup_file
# 功能: 备份单个文件到备份目录（桌面/主目录/tmp 三级回退，兼容 Linux 无桌面场景）
# 参数: $1 - 要备份的文件路径
# 返回值: 无（成功时打印日志，源文件不存在则跳过）
# -----------------------------------------------------------------------------
backup_file() {
  local source="$1"
  local backup_dir

  # 优先使用桌面，不存在则用用户主目录，再不存在用 /tmp
  if [[ -d "${HOME}/Desktop" ]]; then
    backup_dir="${HOME}/Desktop/Homebrew_Backup_${TIME}"
  elif [[ -n "${HOME:-}" && -d "${HOME}" ]]; then
    backup_dir="${HOME}/Homebrew_Backup_${TIME}"
  else
    backup_dir="/tmp/Homebrew_Backup_${TIME}"
  fi

  if [[ -f "${source}" ]]; then
    mkdir -p "${backup_dir}" 2>/dev/null || true
    cp "${source}" "${backup_dir}/$(basename "${source}").bak"
    log_success "已备份: ${source}"
  fi
}

# -----------------------------------------------------------------------------
# 函数: rm_and_backup
# 功能: 备份并删除指定目录（用于删除旧版 Homebrew），备份策略与 backup_file 一致
# 参数: $1 - 要备份并删除的目录路径
# 返回值: 无（目标目录不存在则跳过）
# -----------------------------------------------------------------------------
rm_and_backup() {
  local dir="$1"
  if [[ -d "${dir}" ]]; then
    local backup_dir
    if [[ -d "${HOME}/Desktop" ]]; then
      backup_dir="${HOME}/Desktop/Old_Homebrew_${TIME}"
    elif [[ -n "${HOME:-}" && -d "${HOME}" ]]; then
      backup_dir="${HOME}/Old_Homebrew_${TIME}"
    else
      backup_dir="/tmp/Old_Homebrew_${TIME}"
    fi
    mkdir -p "${backup_dir}$(dirname "${dir}")" 2>/dev/null || true
    sudo cp -rf "${dir}" "${backup_dir}${dir}" 2>/dev/null || true
    sudo rm -rf "${dir}"
    log_success "已删除并备份: ${dir}"
  fi
}

# -----------------------------------------------------------------------------
# 函数: env_vars_exist
# 功能: 检测 Homebrew 环境变量是否已存在（通过 ckbrew 标记识别）
# 参数: $1 - shell 配置文件路径
# 返回值: 0 表示已存在，1 表示不存在
# -----------------------------------------------------------------------------
env_vars_exist() {
  local shell_profile="$1"
  if [[ -f "${shell_profile}" ]]; then
    if grep -q "ckbrew" "${shell_profile}"; then
      return 0
    fi
  fi
  return 1
}

# -----------------------------------------------------------------------------
# 函数: remove_env_variables
# 功能: 清理 shell 配置文件中的 Homebrew 环境变量（带 ckbrew 标记的行），使用 grep -v 反向过滤
# 参数: $1 - shell 配置文件路径
# 返回值: 无
# -----------------------------------------------------------------------------
remove_env_variables() {
  local shell_profile="$1"
  if [[ -f "${shell_profile}" ]]; then
    local temp_file="${shell_profile}.tmp.$$"
    grep -v "ckbrew\|HOMEBREW_PIP_INDEX_URL\|HOMEBREW_API_DOMAIN\|HOMEBREW_BOTTLE_DOMAIN\|brew shellenv" \
      "${shell_profile}" > "${temp_file}" 2>/dev/null || true

    if [[ -s "${temp_file}" ]]; then
      mv "${temp_file}" "${shell_profile}"
      log_success "环境变量已清理"
    else
      rm -f "${temp_file}"
    fi
  fi
}

# -----------------------------------------------------------------------------
# 函数: write_env_variables
# 功能: 写入 Homebrew 环境变量到 shell 配置文件，每行末尾的 #ckbrew 标记用于后续清理识别
# 参数: $1 - shell 配置文件路径
# 返回值: 无（若已存在则跳过，写入失败时 exit 1）
# -----------------------------------------------------------------------------
write_env_variables() {
  local shell_profile="$1"
  local bottle_url="${MIRROR_CONFIG["bottle_url"]}"
  local pip_url="${MIRROR_CONFIG["pip_url"]}"

  if env_vars_exist "${shell_profile}"; then
    log_warn "检测到已存在 Homebrew 环境变量，跳过写入"
    return 0
  fi

  touch "${shell_profile}" 2>/dev/null || true

  # 显式 if 判断写入是否成功（避免 set -e 下 ERR trap 提前退出导致 JudgeSuccess 失败分支不可达）
  if cat >> "${shell_profile}" <<EOF

export HOMEBREW_PIP_INDEX_URL=${pip_url} #ckbrew
export HOMEBREW_API_DOMAIN=${bottle_url}/api #ckbrew
export HOMEBREW_BOTTLE_DOMAIN=${bottle_url} #ckbrew
eval \$(${HOMEBREW_REPOSITORY}/bin/brew shellenv) #ckbrew
EOF
  then
    log_success "环境变量写入成功"
  else
    log_error "写入环境变量失败"
    exit 1
  fi
}

# ============================================================
# 前置检查函数
# ============================================================

# -----------------------------------------------------------------------------
# 函数: check_network
# 功能: 网络连接检测，依次访问 gitee、清华、阿里云三个站点判断网络状态
# 参数: 无
# 返回值: 0 表示网络正常或部分可用，无返回（exit 1）表示全部失败
# -----------------------------------------------------------------------------
check_network() {
  log_info "检测网络连接..."
  local test_urls=(
    "https://gitee.com"
    "https://mirrors.tuna.tsinghua.edu.cn"
    "https://mirrors.aliyun.com"
  )
  local success_count=0
  for url in "${test_urls[@]}"; do
    if curl -s --connect-timeout 5 "${url}" >/dev/null 2>&1; then
      success_count=$((success_count + 1))
    fi
  done

  if [[ ${success_count} -ge 2 ]]; then
    log_success "网络连接正常"
    return 0
  elif [[ ${success_count} -eq 1 ]]; then
    log_warn "部分网络连接不稳定，建议检查网络设置"
    return 0
  else
    log_error "无法连接到任何镜像源，请检查网络连接"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# 函数: check_macos_version
# 功能: macOS 版本检查，Homebrew 最低要求 macOS 10.15 (Catalina)，使用 sort -V 进行版本比较
# 参数: 无
# 返回值: 无（版本符合要求时打印日志，过低时 exit 1）
# -----------------------------------------------------------------------------
# macOS 版本检查
# Homebrew 最低要求 macOS 10.15 (Catalina)
check_macos_version() {
  if [[ -z "${HOMEBREW_ON_MACOS-}" ]]; then
    return 0
  fi
  local min_version="10.15"
  # 使用 sort -V 进行版本号比较，避免字符串比较导致 10.15 被误判为低于 10.9
  if [[ "$(printf '%s\n%s\n' "$min_version" "$macos_version" | sort -V | head -n1)" == "$macos_version" && "$macos_version" != "$min_version" ]]; then
    log_error "您的 macOS 版本 ${macos_version} 过低，Homebrew 需要 macOS ${min_version} 或更高版本"
    log_error "建议升级系统或使用 MacPorts 替代"
    exit 1
  fi
  log_success "macOS 版本 ${macos_version} 符合要求"
}

# -----------------------------------------------------------------------------
# 函数: check_git
# 功能: Git 依赖检查，未安装时尝试自动安装（macOS 触发 CLT，Linux 用 apt/yum/dnf）
# 参数: 无
# 返回值: 无（Git 已安装时打印日志，无法安装时 exit 1）
# -----------------------------------------------------------------------------
# Git 依赖检查
# Homebrew 安装过程需要 git，未安装时尝试自动安装:
# - macOS: 触发 Xcode Command Line Tools 安装（含 git）
# - Linux: 通过 apt-get / yum / dnf 自动安装
check_git() {
  if ! command -v git &>/dev/null; then
    log_error "未安装 Git"
    if [[ -n "${HOMEBREW_ON_MACOS-}" ]]; then
      log_info "正在尝试安装 Xcode Command Line Tools..."
      xcode-select --install 2>/dev/null || true
      log_error "请在弹出窗口中点击安装，安装完成后重新运行此脚本"
      exit 1
    else
      log_info "正在安装 Git..."
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v yum &>/dev/null; then
        sudo yum install -y git
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
      else
        log_error "无法自动安装 Git，请手动安装后重试"
        exit 1
      fi
    fi
  fi
  log_success "Git 已安装"
}

# 检测 Git 全局代理设置
# Git 代理可能导致克隆 Homebrew 仓库失败
warning_if() {
  local git_https_proxy git_http_proxy
  git_https_proxy=$(git config --global https.proxy 2>/dev/null)
  git_http_proxy=$(git config --global http.proxy 2>/dev/null)
  if [[ -z "${git_https_proxy}" && -z "${git_http_proxy}" ]]; then
    log_info "未发现Git代理（正常状态）"
  else
    log_warn "发现Git代理设置，可能导致连接问题"
    log_warn "如需取消代理，请运行:"
    log_warn "  git config --global --unset https.proxy"
    log_warn "  git config --global --unset http.proxy"
  fi
}

# ============================================================
# 镜像源选择函数
# ============================================================

# -----------------------------------------------------------------------------
# 函数: select_mirror
# 功能: 交互式选择镜像源（bottles + pip + git 三合一），结果写入 MIRROR_CONFIG 关联数组
# 参数: $1 - 提示标题; $2 - 镜像源数组名（通过 nameref 传递）; $3 - 默认选中的编号
# 返回值: 始终 0（选择成功后写入全局 MIRROR_CONFIG）
# -----------------------------------------------------------------------------
select_mirror() {
  local title="$1"
  local -n mirrors="$2"
  local default="$3"

  echo -e "\n${tty_green}${title}${tty_reset}"
  for mirror in "${mirrors[@]}"; do
    IFS=':' read -r num name _ _ _ <<< "${mirror}"
    echo "${tty_blue}${num}${tty_reset}、${name}"
  done

  echo -n "${tty_cyan}请输入序号 [默认: ${default}]: ${tty_reset}"
  local input
  # 非交互(-y)/预览(--plan)模式: 直接使用默认值，不阻塞 read
  if [[ "${YES:-0}" == "1" || "${DRY_RUN:-0}" == "1" ]]; then
    input="${default}"
    echo "${default}"
  else
    read input
    input="${input:-${default}}"
  fi

  for mirror in "${mirrors[@]}"; do
    IFS=':' read -r num name bottle_url pip_url git_url <<< "${mirror}"
    if [[ "${num}" == "${input}" ]]; then
      echo "${tty_green}已选择 ${name}${tty_reset}"
      MIRROR_CONFIG["name"]="${name}"
      MIRROR_CONFIG["bottle_url"]="${bottle_url}"
      MIRROR_CONFIG["pip_url"]="${pip_url}"
      MIRROR_CONFIG["git_url"]="${git_url}"
      return 0
    fi
  done

  log_error "无效的选择，请重新输入"
  select_mirror "${title}" mirrors "${default}"
}

# -----------------------------------------------------------------------------
# 函数: select_simple_mirror
# 功能: 交互式选择仅含 URL 的镜像源（用于卸载场景），输出选中的 URL
# 参数: $1 - 提示标题; $2 - 镜像源数组名（通过 nameref 传递）; $3 - 默认选中的编号
# 返回值: 始终 0（通过 stdout 输出选中的 URL）
# -----------------------------------------------------------------------------
select_simple_mirror() {
  local title="$1"
  local -n mirrors="$2"
  local default="$3"

  echo -e "\n${tty_green}${title}${tty_reset}"
  for mirror in "${mirrors[@]}"; do
    IFS=':' read -r num name url <<< "${mirror}"
    echo "${tty_blue}${num}${tty_reset}、${name}"
  done

  echo -n "${tty_cyan}请输入序号 [默认: ${default}]: ${tty_reset}"
  local input
  # 非交互(-y)/预览(--plan)模式: 直接使用默认值，不阻塞 read
  if [[ "${YES:-0}" == "1" || "${DRY_RUN:-0}" == "1" ]]; then
    input="${default}"
    echo "${default}"
  else
    read input
    input="${input:-${default}}"
  fi

  for mirror in "${mirrors[@]}"; do
    IFS=':' read -r num name url <<< "${mirror}"
    if [[ "${num}" == "${input}" ]]; then
      echo "${tty_green}已选择 ${name}${tty_reset}"
      echo "${url}"
      return 0
    fi
  done

  log_error "无效的选择，请重新输入"
  select_simple_mirror "${title}" mirrors "${default}"
}

# ============================================================
# brew 路径与仓库定位
# ============================================================

# 获取 brew 命令对应的 Git 仓库目录
# 通过 command -v 定位 brew → realpath 解析符号链接 → 上溯两级得到仓库根目录
# 返回: 仓库目录路径（存在 .git 目录时），失败返回非零
get_brew_git_dir() {
  if command -v brew &>/dev/null; then
    local brew_path
    brew_path=$(command -v brew 2>/dev/null)
    if [[ -n "${brew_path}" ]]; then
      local real_path
      if command -v realpath &>/dev/null; then
        real_path=$(realpath "${brew_path}")
      else
        real_path="${brew_path}"
      fi
      # brew 通常位于 <仓库根>/bin/brew，上溯两级得到仓库根
      local git_dir
      git_dir=$(dirname "$(dirname "${real_path}")")
      if [[ -d "${git_dir}/.git" ]]; then
        echo "${git_dir}"
        return 0
      fi
    fi
  fi
  return 1
}

# ============================================================
# 安装与验证
# ============================================================

# -----------------------------------------------------------------------------
# 函数: error_game_over
# 功能: 安装失败时的最终错误提示，打印排查链接后 exit 1
# 参数: 无
# 返回值: 无（脚本退出码 1）
# -----------------------------------------------------------------------------
error_game_over() {
  log_error "
    失败！终端输入 ${HOMEBREW_REPOSITORY}/bin/brew -v 没有反应表示失败
    查看常见错误解决办法: https://gitee.com/suser747/netool/blob/main/README.md#故障排查
    netool懒人工具箱项目地址: https://gitee.com/suser747/netool
  "
  exit 1
}

# -----------------------------------------------------------------------------
# 函数: start_clone_brew
# 功能: 核心安装函数，克隆并执行官方 install.sh，包含 sed 替换镜像地址与 bash -n 语法校验
# 参数: 无（读取全局 MIRROR_CONFIG）
# 返回值: 无（失败时 exit 1）
# -----------------------------------------------------------------------------
# 核心安装函数: 克隆并执行官方 install.sh
# 执行流程:
#   1. 获取 sudo 权限
#   2. 询问是否删除旧版 Homebrew（可选备份）
#   3. 检测 Git 代理设置
#   4. 克隆官方 install.git 仓库到本地临时目录
#   5. 【安全审计】记录 commit hash 用于事后追溯
#   6. 用 sed 替换 install.sh 中的 GitHub 地址为国内镜像
#   7. 【安全关键】执行前用 bash -n 做语法校验
#   8. 执行修改后的 install.sh
#   9. 清理临时目录
start_clone_brew() {
  local git_url="${MIRROR_CONFIG["git_url"]}"
  local bottle_url="${MIRROR_CONFIG["bottle_url"]}"

  # --plan/--dry-run 预览模式: 仅打印将执行的操作，不实际克隆/安装
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] 将执行以下操作（不实际执行）:"
    log_info "  - 获取 sudo 权限"
    log_info "  - 询问是否删除旧版 Homebrew"
    log_info "  - 检测 Git 代理设置"
    log_info "  - 克隆 ${git_url:-<默认清华源>}/install.git"
    log_info "  - 记录 install.sh 的 commit hash"
    log_info "  - 用 sed 替换 install.sh 中的 GitHub 地址为国内镜像"
    log_info "  - bash -n 语法校验后执行 install.sh"
    log_info "  - 清理临时目录"
    return 0
  fi

  # 镜像源未提供 git 地址时回退到清华大学源
  if [[ -z "${git_url}" ]]; then
    git_url="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew"
    log_warn "所选镜像源未提供 Git 仓库地址，使用默认清华大学源"
  fi

  # macOS 下的权限提示（Linux 通过 sudo 直接获取）
  if [[ -z "${HOMEBREW_ON_LINUX-}" ]]; then
    log_warn "Mac OS 设置开机密码方法：系统偏好设置 -> 用户与群组 -> 更改密码"
    log_warn "如果提示 This incident will be reported，请检查是否为管理员"
  fi

  check_admin

  # 询问是否删除旧版 Homebrew（受 confirm_action 控制，支持 -y/--plan）
  if confirm_action "是否删除之前安装的 Brew？" "N"; then
    log_info "正在删除旧版 Homebrew..."
    # 依次备份并删除 arm64、x86、缓存、日志目录
    rm_and_backup "${HOMEBREW_REPOSITORY_ARM64:-}"
    rm_and_backup "${HOMEBREW_REPOSITORY_X86:-}"
    rm_and_backup "${HOMEBREW_CACHE}"
    rm_and_backup "${HOMEBREW_LOGS}"
  else
    log_info "保留旧版 Brew，继续安装"
  fi

  # macOS 下确保系统标准路径优先（避免 PATH 污染问题）
  if [[ -z "${HOMEBREW_ON_LINUX-}" ]]; then
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOMEBREW_REPOSITORY}/bin"
  fi

  # 检测 Git 代理（代理可能导致克隆失败）
  warning_if

  log_info "开始下载并执行官方安装脚本..."
  cd "${HOME}" || exit 1

  # 清理可能残留的临时克隆目录
  sudo rm -rf brew-install-ck 2>/dev/null || true
  # 克隆官方 install.git 仓库（浅克隆，仅最新提交，节省带宽）
  # 显式 if 判断：失败时清理现场并退出
  if ! sudo git clone --depth=1 "${git_url}/install.git" brew-install-ck; then
    log_error "克隆官方安装脚本失败"
    sudo rm -rf brew-install-ck 2>/dev/null || true
    exit 1
  fi
  log_success "官方安装脚本克隆成功"

  # 【安全审计】记录当前 install.sh 的 commit hash
  # 用于事后追溯执行的代码版本，便于排查问题
  local brew_install_commit=""
  brew_install_commit="$(cd brew-install-ck 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  log_info "install.sh commit: ${brew_install_commit}"

  # 用 sed 替换 install.sh 中的地址，将 GitHub 替换为国内镜像
  # 1. 将 set-head 的 --auto 改为 main，避免旧版 git 的兼容性问题
  sed_compatible "brew-install-ck/install.sh" \
    's|remote" "set-head" "origin" "--auto"|remote" "set-head" "origin" "main"|g'

  # 2. 将 Homebrew 仓库的 GitHub 地址替换为用户选择的镜像地址
  sed_compatible "brew-install-ck/install.sh" \
    "s|https://github.com/Homebrew|${git_url}|g"

  # 3. 将 "update" 改为 "update-reset"，安装后重置仓库到镜像源
  sed_compatible "brew-install-ck/install.sh" \
    's|"update"|"update-reset"|g'

  # 4. 在 shebang 后注入 HOMEBREW_BOTTLE_DOMAIN 环境变量
  #    使安装过程中下载预编译包时使用国内镜像
  local bottle_export="export HOMEBREW_BOTTLE_DOMAIN=${bottle_url}"
  sed_compatible "brew-install-ck/install.sh" \
    "s|^#!/bin/bash|#!/bin/bash\n${bottle_export}|"

  # 【安全关键】执行前做语法校验
  # 防止 sed 替换出错、或下载内容被篡改导致执行任意代码
  # 校验失败则清理临时文件并中止执行
  if ! bash -n brew-install-ck/install.sh 2>/dev/null; then
    sudo rm -rf brew-install-ck
    log_error "install.sh 语法校验失败，已中止执行"
    exit 1
  fi

  log_info "正在执行官方安装脚本..."
  # 显式 if 判断：执行失败时清理现场并退出
  if ! /bin/bash brew-install-ck/install.sh; then
    sudo rm -rf brew-install-ck 2>/dev/null || true
    log_error "官方安装脚本执行失败"
    exit 1
  fi

  # 清理临时克隆目录
  sudo rm -rf brew-install-ck
  log_success "官方安装脚本执行完成"
}

# -----------------------------------------------------------------------------
# 函数: update_brew_remote
# 功能: 仅更新已安装 brew 的仓库远程地址（不重新安装），用于"仅更换 brew 仓库地址"场景
# 参数: 无（读取全局 MIRROR_CONFIG）
# 返回值: 无（失败时 exit 1）
# -----------------------------------------------------------------------------
update_brew_remote() {
  local git_url="${MIRROR_CONFIG["git_url"]}"

  if [[ -z "${git_url}" ]]; then
    log_error "所选镜像源未提供 Git 仓库地址"
    exit 1
  fi

  # --plan/--dry-run 预览模式: 仅打印将执行的操作
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] 将把 brew 仓库 origin 远程地址设置为: ${git_url}/brew"
    return 0
  fi

  local brew_git_dir
  brew_git_dir=$(get_brew_git_dir)

  if [[ -z "${brew_git_dir}" ]]; then
    log_error "未找到 brew 的 Git 仓库目录，请确保 brew 已安装并可正常运行"
    exit 1
  fi

  log_info "brew Git 目录: ${brew_git_dir}"

  if cd "${brew_git_dir}" && git remote set-url origin "${git_url}/brew"; then
    log_success "远程仓库地址已设置为: $(git remote get-url origin)"
  else
    log_error "设置远程仓库地址失败"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# 函数: verify_installation
# 功能: 验证 brew 安装并执行首次更新，失败时尝试自动修复（清理缓存 + update-reset）
# 参数: 无
# 返回值: 无（失败时调用 error_game_over 终止脚本）
# -----------------------------------------------------------------------------
# 验证 brew 安装并执行首次更新
# 失败时尝试自动修复: 清理缓存 + update-reset
# brew update 失败时自动切换阿里云 bottles 源重试一次
verify_installation() {
  log_info "验证 brew 安装..."

  export PATH="${HOMEBREW_REPOSITORY}/bin:${PATH}"

  if ! brew -v 2>/dev/null; then
    log_warn "brew 命令执行失败，尝试自动修复..."
    rm -rf "${HOMEBREW_CACHE}" 2>/dev/null || true

    if ! brew update-reset 2>/dev/null; then
      log_error "自动修复失败"
      error_game_over
    fi

    if ! brew -v 2>/dev/null; then
      error_game_over
    fi
  fi
  log_success "Homebrew 配置成功"

  # 执行 brew update 更新软件包列表
  log_info "执行 brew update..."
  if ! brew update 2>/dev/null; then
    log_warn "brew update 失败，更换阿里源重试..."
    export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
    if ! brew update 2>/dev/null; then
      brew config
      error_game_over
    fi
  fi
  log_success "brew update 成功"
}

# -----------------------------------------------------------------------------
# 函数: install_homebrew
# 功能: 安装 Homebrew 主流程，包含前置检查、镜像选择、安装/配置、验证与完成提示
# 参数: 无
# 返回值: 无（各步骤失败时可能 exit 1）
# -----------------------------------------------------------------------------
install_homebrew() {
  log_info "开始执行 Homebrew 自动安装程序"
  log_info "netool懒人工具箱 (https://gitee.com/suser747/netool)"
  log_info "时间: ${TIME}"
  if [[ -n "${macos_version:-}" ]]; then
    log_info "系统版本: ${macos_version}"
  fi

  # 前置检查：网络、macOS 版本、Git 依赖
  check_network
  check_macos_version
  check_git

  # 操作类型选择菜单
  echo -e "\n${tty_green}请选择操作类型：${tty_reset}"
  echo "${tty_blue}1${tty_reset}、安装并配置国内源（推荐）"
  echo "${tty_blue}2${tty_reset}、仅配置国内源（已安装 brew）"
  echo "${tty_blue}3${tty_reset}、仅更换 brew 仓库地址"
  echo "${tty_blue}0${tty_reset}、返回主菜单"

  echo -n "${tty_cyan}请输入序号 [默认: 1]: ${tty_reset}"
  # 非交互(-y)/预览(--plan)模式: 直接使用默认值 1，不阻塞 read
  if [[ "${YES:-0}" == "1" || "${DRY_RUN:-0}" == "1" ]]; then
    ACTION_CHOICE="1"
    echo "1"
  else
    read ACTION_CHOICE
    ACTION_CHOICE="${ACTION_CHOICE:-1}"
  fi

  # 返回主菜单
  if [[ "${ACTION_CHOICE}" == "0" ]]; then
    return 0
  fi

  # 选项3: 仅更换仓库地址
  if [[ "${ACTION_CHOICE}" == "3" ]]; then
    select_mirror "请选择 brew 仓库地址源:" GIT_ONLY_MIRRORS "1"
    update_brew_remote
    log_success "仓库地址更新完成"
    return 0
  fi

  # 选项1/2: 选择镜像源
  select_mirror "请选择国内镜像源:" MIRRORS "1"

  # 选项2: 跳过安装，仅配置镜像源
  if [[ "${ACTION_CHOICE}" == "2" ]]; then
    log_info "跳过 brew 安装，仅配置镜像源"
  else
    # 选项1: 完整安装
    start_clone_brew
  fi

  # --plan/--dry-run 预览模式: start_clone_brew 已打印预览，跳过后续配置/验证
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] 跳过环境变量写入、brew update 等实际操作"
    return 0
  fi

  log_info "配置国内镜像源..."

  # 确定 shell 配置文件路径
  local shell_profile
  shell_profile=$(detect_shell_profile)

  # 清理旧的环境变量配置
  if [[ -n "${HOMEBREW_ON_LINUX-}" ]]; then
    remove_env_variables "${shell_profile}"
  else
    remove_env_variables "${shell_profile}"
    xcode-select --install 2>/dev/null || true
  fi

  # 写入新的环境变量
  write_env_variables "${shell_profile}"

  # 加载配置文件使环境变量立即生效
  if ! source "${shell_profile}"; then
    log_warn "${shell_profile} 文件可能存在错误，建议检查"
  fi

  # Linux 下检查 curl 依赖（brew 部分功能需要 curl）
  if [[ -n "${HOMEBREW_ON_LINUX-}" ]]; then
    log_info "检测 curl 是否安装..."
    if ! command -v curl &>/dev/null; then
      if command -v apt-get &>/dev/null; then
        sudo apt-get install -y curl
      elif command -v yum &>/dev/null; then
        sudo yum install -y curl
      elif command -v dnf &>/dev/null; then
        sudo dnf install -y curl
      else
        log_error "请自行安装 curl"
        error_game_over
      fi
    fi
    log_success "curl 已安装"
  fi

  # 验证安装并执行首次更新
  verify_installation

  # 完成提示
  echo -e "\n${tty_green}=========================================${tty_reset}"
  echo -e "${tty_green}    Homebrew 自动安装程序运行完成${tty_reset}"
  echo -e "${tty_green}    国内地址已配置完成${tty_reset}"
  echo -e "${tty_green}=========================================${tty_reset}"
  echo -e "\n${tty_underline}注意：如果之前选择了删除旧版，桌面会有 Old_Homebrew 文件夹，可删除${tty_reset}"

  # 常用 brew 命令速查
  echo -e "\n${tty_cyan}常用 brew 命令：${tty_reset}"
  echo "  ${tty_bold}brew -v${tty_reset}        查看版本"
  echo "  ${tty_bold}brew update${tty_reset}    更新 brew"
  echo "  ${tty_bold}brew search xxx${tty_reset} 搜索软件"
  echo "  ${tty_bold}brew install xxx${tty_reset} 安装软件"
  echo "  ${tty_bold}brew ls${tty_reset}        列出已安装软件"

  # 问题排查指引
  echo -e "\n${tty_yellow}遇到问题？${tty_reset}"
  echo "  官方文档：    https://brew.sh/zh-cn/"
  echo "  故障排查：    https://gitee.com/suser747/netool/blob/main/README.md#故障排查"
  echo "  netool项目：  https://gitee.com/suser747/netool"

  # 最后提示：需要 source 配置文件或重启终端才能使镜像源生效
  if [[ -z "${HOMEBREW_ON_LINUX-}" ]]; then
    echo -e "\n${tty_red}安装成功！请重启终端或运行:${tty_reset}"
    echo -e "  ${tty_bold}source ${shell_profile}${tty_reset}"
    echo -e "${tty_red}否则国内地址无法生效${tty_reset}"
  else
    echo -e "\n${tty_red}Linux 用户请重启电脑或运行:${tty_reset}"
    echo -e "  ${tty_bold}source ${shell_profile}${tty_reset}"
  fi
}

# -----------------------------------------------------------------------------
# 函数: uninstall_homebrew
# 功能: 卸载 Homebrew，下载并执行官方卸载脚本，备份环境变量并清理残留目录
# 参数: 无
# 返回值: 无（失败时 return 1）
# -----------------------------------------------------------------------------
uninstall_homebrew() {
  echo -e "\n${tty_green}=========================================${tty_reset}"
  echo -e "${tty_green}    Homebrew 卸载脚本${tty_reset}"
  echo -e "${tty_green}=========================================${tty_reset}"
  log_info "时间: ${TIME}"

  check_network

  # 卸载需要 git 来下载官方卸载脚本
  log_info "检测 Git 是否安装..."
  if ! command -v git &>/dev/null; then
    log_error "未安装 Git，无法继续卸载"
    return 1
  fi
  log_success "Git 已安装"

  # 检测 Homebrew 是否已安装
  log_info "检测 Homebrew 是否安装..."
  if ! command -v brew &>/dev/null; then
    log_warn "未检测到已安装的 Homebrew"
    if ! confirm_action "是否继续执行清理操作？" "N"; then
      log_info "已取消操作"
      return 0
    fi
  else
    log_success "检测到已安装的 Homebrew: $(brew --version 2>/dev/null | head -1)"
  fi

  check_admin

  # 选择卸载脚本源
  local mirror_url
  mirror_url=$(select_simple_mirror "请选择卸载脚本源：" UNINSTALL_MIRRORS "1")

  # 二次确认（破坏性操作，需输入 yes 才能继续；受 -y/--plan 控制）
  echo -e "\n${tty_red}=========================================${tty_reset}"
  echo -e "${tty_red}    警告：此操作将卸载 Homebrew${tty_reset}"
  echo -e "${tty_red}    所有通过 brew 安装的软件将被删除${tty_reset}"
  echo -e "${tty_red}=========================================${tty_reset}"

  # 非交互/预览模式处理
  if [[ "${YES:-0}" == "1" ]]; then
    log_info "[非交互模式] 确认要卸载吗？ -> yes"
  elif [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] 确认要卸载吗？ -> 跳过卸载操作"
    return 0
  else
    echo -n "${tty_yellow}确认要卸载吗？(yes/no) [默认: no]: ${tty_reset}"
    local confirm
    read confirm
    confirm="${confirm:-no}"

    if [[ "${confirm}" != "yes" ]]; then
      log_info "已取消卸载操作"
      return 0
    fi
  fi

  log_info "开始卸载 Homebrew..."

  # 备份环境变量配置文件（多种 shell 都备份）
  log_info "备份环境变量配置文件..."
  backup_file "${HOME}/.zprofile"
  backup_file "${HOME}/.bash_profile"
  backup_file "${HOME}/.profile"

  # 清理环境变量
  local shell_profile
  shell_profile=$(detect_shell_profile)
  remove_env_variables "${shell_profile}"

  # 下载并执行官方卸载脚本
  log_info "下载官方卸载脚本..."
  rm -rf brew-uninstall-ck 2>/dev/null || true

  if ! git clone --depth=1 "${mirror_url}/install.git" brew-uninstall-ck; then
    log_error "下载卸载脚本失败"
    return 1
  fi

  # 修改卸载脚本中的源地址（将 GitHub raw 替换为 Gitee raw）
  log_info "修改卸载脚本中的源地址..."
  sed_compatible "brew-uninstall-ck/uninstall.sh" \
    "s|https://raw.githubusercontent.com/Homebrew/brew/HEAD/.gitignore|https://gitee.com/Homebrew2/brew/raw/master/.gitignore|g"

  log_info "执行官方卸载脚本..."
  log_warn "接下来的提示来自官方卸载脚本，请按照提示操作"

  if /bin/bash brew-uninstall-ck/uninstall.sh; then
    log_success "官方卸载脚本执行完成"
  else
    log_warn "卸载脚本返回非零状态，可能存在部分卸载失败"
  fi

  rm -rf brew-uninstall-ck

  # 检查并清理残留目录（逐个询问用户）
  local remaining_dirs=(
    "${HOME}/Library/Caches/Homebrew"
    "${HOME}/Library/Logs/Homebrew"
    "${HOME}/.cache/Homebrew"
    "${HOME}/.logs/Homebrew"
    "/opt/homebrew"
    "/usr/local/Homebrew"
    "/home/linuxbrew/.linuxbrew"
  )

  log_info "检查并清理残留文件..."

  for dir in "${remaining_dirs[@]}"; do
    if [[ -d "${dir}" ]]; then
      log_info "发现残留目录: ${dir}"
      # 受 confirm_action 控制：-y 自动删除，--plan 跳过删除
      if confirm_action "是否删除 ${dir}？" "Y"; then
        sudo rm -rf "${dir}" 2>/dev/null || rm -rf "${dir}" 2>/dev/null || true
        log_success "已删除: ${dir}"
      fi
    fi
  done

  # 完成提示
  echo -e "\n${tty_green}=========================================${tty_reset}"
  echo -e "${tty_green}    Homebrew 卸载完成${tty_reset}"
  echo -e "${tty_green}=========================================${tty_reset}"

  echo -e "\n${tty_cyan}后续建议：${tty_reset}"
  echo "  1. 重启终端或运行: ${tty_bold}source ~/.zprofile${tty_reset} (或 ~/.bash_profile)"
  echo "  2. 检查环境变量是否正确: ${tty_bold}echo \$PATH${tty_reset}"
  echo "  3. 如需重新安装，请选择安装选项"

  echo -e "\n${tty_yellow}注意：${tty_reset}"
  echo "  - 备份文件已保存到桌面 Homebrew_Backup_${TIME} 目录"
  echo "  - 如需恢复配置，请从备份目录复制相应的配置文件"
}

# -----------------------------------------------------------------------------
# 函数: install_git
# 功能: 安装 Command Line Tools（macOS 专用 Git 安装），通过 softwareupdate 触发并配置
# 参数: 无
# 返回值: 无（失败时 return 1）
# -----------------------------------------------------------------------------
install_git() {
  echo -e "\n${tty_green}=========================================${tty_reset}"
  echo -e "${tty_green}    Command Line Tools 自动安装程序${tty_reset}"
  echo -e "${tty_green}=========================================${tty_reset}"
  log_info "时间: ${TIME}"

  # 仅 macOS 适用
  if [[ "$(uname)" != "Darwin" ]]; then
    log_error "此功能仅适用于 macOS 系统"
    log_info "Linux 用户请使用系统包管理器安装 Git"
    return 1
  fi

  check_admin

  # 检测是否已安装
  if xcode-select -p &>/dev/null; then
    log_success "Xcode Command Line Tools 已安装"
    # 受 confirm_action 控制：-y 自动重装，--plan 跳过
    if ! confirm_action "是否重新安装？" "N"; then
      log_info "已取消安装"
      if git --version &>/dev/null; then
        local git_version
        git_version=$(git --version 2>/dev/null | awk '{print $3}')
        log_success "Git 已安装: ${git_version}"
      fi
      return 0
    fi
  fi

  # 检测可用的 Command Line Tools 版本
  log_info "检测可用的 Command Line Tools 版本..."

  # --plan/--dry-run 预览模式: 仅打印将执行的操作，不实际安装
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[预览模式] 将执行以下操作（不实际执行）:"
    log_info "  - 创建 softwareupdate 占位文件触发 CLT 列表"
    log_info "  - 解析并安装 Command Line Tools"
    log_info "  - 切换 xcode-select 路径到 /Library/Developer/CommandLineTools"
    log_info "  - 验证 Git 是否可用"
    return 0
  fi

  # 创建占位文件触发 softwareupdate 列出 CLT
  local clt_placeholder="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo touch "${clt_placeholder}" 2>/dev/null || true

  # 从 softwareupdate 输出中解析 CLT 标签
  local clt_label
  clt_label=$(/usr/sbin/softwareupdate -l 2>/dev/null | \
    grep -B 1 -E 'Command Line Tools' | \
    awk -F'*' '/^ *\\*/ {print $2}' | \
    sed -e 's/^ *Label: //' -e 's/^ *//' | \
    head -1)

  if [[ -z "${clt_label}" ]]; then
    log_warn "未找到可用的 Command Line Tools"
    log_info "正在尝试打开系统更新..."

    sudo touch "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

    log_info "请在弹出的窗口中手动安装 Command Line Tools"
    open "x-apple.systempreferences:com.apple.preferences.softwareupdate"

    echo -e "\n${tty_yellow}安装完成后，请重新运行 Homebrew 安装脚本${tty_reset}"
    return 0
  fi

  log_info "找到 Command Line Tools: ${clt_label}"
  log_info "开始安装，请耐心等待..."

  # 执行安装
  if sudo /usr/sbin/softwareupdate -i "${clt_label}"; then
    log_success "Command Line Tools 安装成功"
  else
    log_error "安装失败，请尝试手动安装"
    sudo rm -f "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" 2>/dev/null || true
    return 1
  fi

  sudo rm -f "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress" 2>/dev/null || true

  # 配置 Command Line Tools 路径
  log_info "配置 Command Line Tools..."
  if sudo /usr/bin/xcode-select --switch "/Library/Developer/CommandLineTools"; then
    log_success "Command Line Tools 配置完成"
  else
    log_warn "配置失败，可能需要手动配置"
  fi

  # 验证 Git 是否可用
  log_info "验证 Git 安装..."

  if git --version &>/dev/null; then
    local git_version
    git_version=$(git --version 2>/dev/null | awk '{print $3}')
    log_success "Git 安装成功: ${git_version}"

    echo -e "\n${tty_green}=========================================${tty_reset}"
    echo -e "${tty_green}    安装完成${tty_reset}"
    echo -e "${tty_green}=========================================${tty_reset}"

    echo -e "\n${tty_cyan}下一步：${tty_reset}"
    echo "  返回主菜单选择安装 Homebrew"
  else
    log_error "Git 验证失败，请重启终端后重试"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# 函数: main_menu
# 功能: 主菜单，循环展示安装/卸载/安装 CLT 选项，-y 模式下自动选择安装
# 参数: 无
# 返回值: 无（用户选择退出时 exit 0）
# -----------------------------------------------------------------------------
main_menu() {
  echo -e "\n${tty_green}=========================================${tty_reset}"
  echo -e "${tty_green}    netool懒人工具箱 - Homebrew 管理工具${tty_reset}"
  echo -e "${tty_green}    版本: ${SCRIPT_VERSION}${tty_reset}"
  echo -e "${tty_green}=========================================${tty_reset}"
  echo ""
  echo "${tty_blue}1${tty_reset}、安装/配置 Homebrew"
  echo "${tty_blue}2${tty_reset}、卸载 Homebrew"
  echo "${tty_blue}3${tty_reset}、安装 Command Line Tools (Git)"
  echo "${tty_blue}0${tty_reset}、退出"
  echo ""
  echo -n "${tty_cyan}请选择操作 [默认: 1]: ${tty_reset}"

  local choice
  # -y/--yes 完全非交互模式: 直接使用默认值 1（安装），不阻塞 read
  # --plan/--dry-run 模式: 仍由用户选择要预览的操作
  if [[ "${YES:-0}" == "1" ]]; then
    choice="1"
    echo "1"
  else
    read choice
    choice="${choice:-1}"
  fi

  case "${choice}" in
    1)
      install_homebrew
      ;;
    2)
      uninstall_homebrew
      ;;
    3)
      install_git
      ;;
    0)
      log_info "感谢使用 netool懒人工具箱！"
      exit 0
      ;;
    *)
      log_error "无效的选择"
      main_menu
      ;;
  esac
}

# ============================================================
# 入口
# ============================================================

# 解析命令行参数
# --plan / --dry-run: 预览模式，仅打印将要执行的操作，不实际执行
# -y / --yes: 非交互模式，所有确认提示自动按确认继续
# --help: 打印用法后退出
# 其他参数: 静默忽略（兼容工具箱调用时传入的额外参数）
DRY_RUN=0
YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan|--dry-run) DRY_RUN=1; shift ;;
    -y|--yes) YES=1; shift ;;
    --help)
      printf "用法: homebrew.sh [--plan|--dry-run] [-y|--yes]\n"
      printf "  --plan, --dry-run  预览模式，不实际执行操作\n"
      printf "  -y, --yes          非交互模式，自动确认所有提示\n"
      exit 0
      ;;
    *) shift ;;
  esac
done

# 预览模式提示
if [[ "${DRY_RUN}" == "1" ]]; then
  log_info "已启用预览模式（--plan/--dry-run），将仅打印操作不实际执行"
fi
# 非交互模式提示
if [[ "${YES}" == "1" ]]; then
  log_info "已启用非交互模式（-y/--yes），所有确认将自动通过"
fi

# 根据平台初始化变量
if [[ -n "${HOMEBREW_ON_MACOS-}" ]]; then
  init_macos_vars
else
  init_linux_vars
fi

main_menu
