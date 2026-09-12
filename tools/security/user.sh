#!/usr/bin/env bash
# ============================================================
# netool懒人工具箱 - 用户与 SSH 密钥管理
# ============================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: user-tools
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   管理 Linux 系统用户与 SSH 登录配置，支持列出可登录用户、创建用户并设置
#   密码、删除用户（可选保留家目录）、为用户追加 SSH 公钥、禁用/恢复 SSH 密码
#   登录、查看 SSH 登录相关配置。禁用密码登录通过 sshd_config.d drop-in 实现，
#   原配置不动；可用 enable-password 还原。
#
# 使用方式:
#   bash user.sh list                                   # 列出可登录用户（默认）
#   bash user.sh add --name <用户> [--sudo]             # 创建用户并设密码
#   bash user.sh del --name <用户>                      # 删除用户（保留家目录）
#   bash user.sh del-full --name <用户>                 # 删除用户和家目录
#   bash user.sh key --name <用户> --key <公钥或文件>   # 为用户追加 SSH 公钥
#   bash user.sh disable-password                       # 禁用 SSH 密码登录
#   bash user.sh enable-password                        # 恢复 SSH 密码登录
#   bash user.sh status                                 # 查看 SSH 登录相关配置
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="user-tools"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh user
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) user
#   直接：bash tools/security/user.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
MANAGED_DROPIN_FILE="${SSHD_DROPIN_DIR}/99-netool-user-tools.conf"
BACKUP_ROOT="/var/backups/netool-user-tools"
DRY_RUN=0
YES=0



# ------------------------------------------------------------------------------
# 函数: usage
# 功能: 输出脚本帮助信息到标准输出
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 用户与 SSH 密钥管理 v${SCRIPT_VERSION}

用法:
  user [操作] [选项]

操作:
  list                          列出可登录用户（默认）
  add --name <用户> [--sudo]    创建用户并设密码
  del --name <用户>             删除用户（保留家目录）
  del-full --name <用户>        删除用户和家目录
  key --name <用户> --key <公钥或文件>  为用户追加 SSH 公钥
  disable-password              禁用 SSH 密码登录（仅允许密钥）
  enable-password               恢复 SSH 密码登录
  status                        查看 SSH 登录相关配置

选项:
  --name <用户>          指定用户名
  --sudo                 创建用户时加入 sudo/wheel 组
  --key <公钥|文件>      SSH 公钥字符串或公钥文件路径
  --plan, --dry-run      只显示计划
  -y, --yes              跳过确认
  -h, --help             显示帮助
  --version              显示版本

说明:
  公钥会写入目标用户 ~/.ssh/authorized_keys，自动修正属主和权限（700/600）。
  禁用密码登录通过 sshd_config.d drop-in 实现，原配置不动；可用 enable-password 还原。
EOF
}

# ------------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅；被 NETOOL 主入口调用时不打印，便于工具箱统一收口
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  printf "%s\n" "------------------------------------------------------------"
  printf "netool懒人工具箱 | 用户与 SSH 密钥管理 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "------------------------------------------------------------"
}

# ------------------------------------------------------------------------------
# 函数: confirm
# 功能: 询问用户是否确认执行；YES=1 时跳过交互
# 参数: $1 - 提示文本
# 返回值: 0 表示确认；非 0 表示取消或读取失败
# ------------------------------------------------------------------------------
confirm() {
  local prompt="$1"
  if (( YES )); then return 0; fi
  local answer=""
  read_prompt "${prompt} [y/N]: " answer || return 1
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# ------------------------------------------------------------------------------
# 函数: validate_username
# 功能: 校验用户名是否合法（长度、字符集）且非系统保留用户名
# 参数: $1 - 待校验的用户名
# 返回值: 0 表示合法；非 0 表示不合法或为系统保留用户名
# ------------------------------------------------------------------------------
validate_username() {
  local username="$1"
  # 长度和字符校验: 小写字母或下划线开头，仅含 a-z 0-9 _ -，长度 1-32
  if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    log_error "用户名不合法: $username"
    log_error "要求: 小写字母或下划线开头，仅含 a-z 0-9 _ -，长度 1-32"
    return 1
  fi
  # 系统保留用户名（禁止创建/删除/操作）
  local reserved="root daemon bin sys sync mail www-data news uucp proxy backup irc list gnats nobody systemd-network systemd-resolve dbus polkitd postfix sshd nginx apache mysql postgres redis"
  if [[ " $reserved " == *" $username "* ]]; then
    log_error "用户名 $username 是系统保留用户名，不允许使用"
    return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# 函数: detect_sudo_group
# 功能: 检测当前系统可用的提权组名称（sudo 或 wheel）
# 参数: 无
# 返回值: 通过 stdout 输出 sudo/wheel 之一；均不存在时输出空字符串
# ------------------------------------------------------------------------------
detect_sudo_group() {
  if getent group sudo >/dev/null 2>&1; then
    printf "sudo"
  elif getent group wheel >/dev/null 2>&1; then
    printf "wheel"
  else
    printf ""
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_list
# 功能: 列出 /etc/passwd 中所有使用可登录 shell 的用户
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
do_list() {
  printf "\n可登录用户:\n"
  while IFS=':' read -r name _ uid _ _ home shell; do
    if [[ "$shell" =~ /(bash|sh|zsh|fish|dash)$ ]]; then
      printf "  %-16s uid=%s shell=%s home=%s\n" "$name" "$uid" "$shell" "$home"
    fi
  done < /etc/passwd
}

# ------------------------------------------------------------------------------
# 函数: ensure_backup_dir
# 功能: 确保 BACKUP_ROOT 目录存在且权限为 700
# 参数: 无
# 返回值: 始终 0（mkdir 失败时静默跳过）
# ------------------------------------------------------------------------------
ensure_backup_dir() {
  mkdir -p "$BACKUP_ROOT" 2>/dev/null || true
  chmod 700 "$BACKUP_ROOT" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 函数: backup_sshd_config
# 功能: 将 sshd_config 及 sshd_config.d 下的配置备份到带时间戳的子目录
# 参数: 无
# 返回值: 始终 0，通过 stdout 输出备份目录路径
# ------------------------------------------------------------------------------
backup_sshd_config() {
  ensure_backup_dir
  local ts=""
  ts="$(date +%Y%m%d-%H%M%S)"
  local dir="${BACKUP_ROOT}/${ts}"
  mkdir -p "$dir"
  [[ -f "$SSHD_CONFIG" ]] && cp -a "$SSHD_CONFIG" "$dir/" 2>/dev/null || true
  if [[ -d "$SSHD_DROPIN_DIR" ]]; then
    mkdir -p "$dir/sshd_config.d"
    cp -a "$SSHD_DROPIN_DIR"/*.conf "$dir/sshd_config.d/" 2>/dev/null || true
  fi
  printf "%s" "$dir"
}

# ------------------------------------------------------------------------------
# 函数: do_add
# 功能: 创建新用户并设置密码，可选加入 sudo/wheel 组
# 参数: $1 - 用户名；$2 - 是否加入 sudo 组（1=是，0=否）
# 返回值: 0 表示成功或用户取消；非 0 表示校验失败或缺少依赖
# ------------------------------------------------------------------------------
do_add() {
  require_root
  local name="$1"
  local use_sudo="$2"

  validate_username "$name" || exit 1

  if id "$name" >/dev/null 2>&1; then
    die "用户已存在: $name"
  fi

  printf "\n创建用户计划:\n"
  printf "  用户名: %s\n" "$name"
  printf "  创建家目录: 是\n"
  [[ "$use_sudo" == "1" ]] && printf "  加入 sudo 组: %s\n" "$(detect_sudo_group)"
  if (( DRY_RUN )); then
    log_info "预览模式，不会创建用户。"
    return 0
  fi

  if ! confirm "确认创建用户 ${name}?"; then
    log_info "已取消。"
    return 0
  fi

  if command_exists useradd; then
    useradd -m -s /bin/bash "$name"
  elif command_exists adduser; then
    # BusyBox/Alpine adduser
    adduser -D -s /bin/bash "$name"
  else
    die "未找到 useradd 或 adduser。"
  fi

  # 设置密码（使用 read_secret 隐藏输入，避免明文回显到终端）
  local password=""
  read_secret "请为 ${name} 设置密码（输入内容不会回显）: " password || die "未输入密码。"
  if [[ -n "$password" ]]; then
    chpasswd <<<"${name}:${password}"
  fi

  if [[ "$use_sudo" == "1" ]]; then
    local sudo_group=""
    sudo_group="$(detect_sudo_group)"
    if [[ -n "$sudo_group" ]]; then
      usermod -aG "$sudo_group" "$name" 2>/dev/null || gpasswd -a "$name" "$sudo_group" 2>/dev/null || true
      log_success "已加入 ${sudo_group} 组。"
    else
      log_warn "未发现 sudo 或 wheel 组，跳过提权。"
    fi
  fi

  log_success "用户 ${name} 已创建。"
}

# ------------------------------------------------------------------------------
# 函数: do_del
# 功能: 删除指定用户，可选择是否同时删除家目录
# 参数: $1 - 用户名；$2 - 是否删除家目录（1=是，0=否）
# 返回值: 0 表示成功或用户取消；非 0 表示校验失败或确认不匹配
# ------------------------------------------------------------------------------
do_del() {
  require_root
  local name="$1"
  local remove_home="$2"

  validate_username "$name" || exit 1
  id "$name" >/dev/null 2>&1 || die "用户不存在: $name"

  # 明确拒绝删除 root（防御性二次校验，validate_username 已包含但此处显式拒绝）
  if [[ "$name" == "root" ]]; then
    die "拒绝删除 root 用户。"
  fi

  # 显示即将删除的用户详细信息
  local home_dir=""
  local user_shell=""
  home_dir="$(getent passwd "$name" | cut -d: -f6)"
  user_shell="$(getent passwd "$name" | cut -d: -f7)"
  log_warn "即将删除用户: $name"
  [[ -n "$home_dir" ]] && log_warn "用户家目录: $home_dir"
  [[ -n "$user_shell" ]] && log_warn "用户 shell: $user_shell"

  printf "\n删除用户计划:\n"
  printf "  用户名: %s\n" "$name"
  printf "  家目录: %s\n" "${home_dir:-未知}"
  printf "  Shell: %s\n" "${user_shell:-未知}"
  printf "  删除家目录: %s\n" "$([[ "$remove_home" == "1" ]] && printf 是 || printf 否)"
  if (( DRY_RUN )); then
    log_info "预览模式，不会删除用户。"
    return 0
  fi

  # 二次确认: 交互模式要求输入完整用户名作为确认
  if (( YES )); then
    log_warn "非交互模式，跳过二次确认（已通过 -y 授权）"
    # 记录到审计日志（若 logger 可用则写入 syslog）
    if command_exists logger; then
      logger -t "$SCRIPT_NAME" "审计: 非交互模式删除用户 ${name}（remove_home=${remove_home}）" 2>/dev/null || true
    fi
  else
    local confirm_input=""
    read_prompt "请输入完整用户名以确认删除 ${name}: " confirm_input || return 1
    if [[ "$confirm_input" != "$name" ]]; then
      log_error "确认用户名不匹配，已取消删除"
      return 1
    fi
  fi

  if [[ "$remove_home" == "1" ]]; then
    userdel -r "$name" 2>/dev/null || deluser --remove-home "$name" 2>/dev/null || true
  else
    userdel "$name" 2>/dev/null || deluser "$name" 2>/dev/null || true
  fi

  log_success "用户 ${name} 已删除。"
}

# ------------------------------------------------------------------------------
# 函数: do_key
# 功能: 为指定用户追加 SSH 公钥到 authorized_keys，自动修正属主和权限
# 参数: $1 - 用户名；$2 - SSH 公钥字符串或公钥文件路径
# 返回值: 0 表示成功或用户取消；非 0 表示校验失败或用户不存在
# ------------------------------------------------------------------------------
do_key() {
  require_root
  local name="$1"
  local key_input="$2"

  validate_username "$name" || exit 1
  id "$name" >/dev/null 2>&1 || die "用户不存在: $name"

  local key_content=""
  if [[ -f "$key_input" ]]; then
    key_content="$(cat "$key_input")"
  else
    key_content="$key_input"
  fi

  # 简单校验: SSH 公钥通常以 ssh- 开头或 ecdsa-/sk-ecdsa-/ssh-ed25519
  if [[ ! "$key_content" =~ ^ssh-(rsa|ed25519|dsa)|^ecdsa-|^sk-(ssh|ecdsa) ]]; then
    die "公钥格式不合法，应以 ssh-rsa/ssh-ed25519/ecdsa- 等开头。"
  fi

  local home=""
  home="$(getent passwd "$name" | awk -F: '{print $6}')"
  [[ -n "$home" && -d "$home" ]] || die "无法定位用户家目录: $name"

  local ssh_dir="${home}/.ssh"
  local auth_keys="${ssh_dir}/authorized_keys"

  printf "\n添加 SSH 公钥计划:\n"
  printf "  用户: %s\n" "$name"
  printf "  家目录: %s\n" "$home"
  printf "  写入: %s\n" "$auth_keys"
  printf "  公钥前缀: %s...\n" "${key_content:0:40}"
  if (( DRY_RUN )); then
    log_info "预览模式，不会写入公钥。"
    return 0
  fi

  if ! confirm "确认写入公钥?"; then
    log_info "已取消。"
    return 0
  fi

  mkdir -p "$ssh_dir"
  touch "$auth_keys"
  # 去重: 若已存在相同公钥则不再追加
  if grep -qF "$key_content" "$auth_keys" 2>/dev/null; then
    log_info "公钥已存在，未重复写入。"
  else
    printf "%s\n" "$key_content" >>"$auth_keys"
  fi

  # 属主和权限
  local uid_num=""
  local gid_num=""
  uid_num="$(id -u "$name")"
  gid_num="$(id -g "$name")"
  chown -R "$uid_num:$gid_num" "$ssh_dir" 2>/dev/null || true
  chmod 700 "$ssh_dir"
  chmod 600 "$auth_keys"

  log_success "公钥已写入 ${auth_keys}。"
}

# ------------------------------------------------------------------------------
# 函数: detect_managed_file
# 功能: 检测本工具应管理的目标文件（drop-in 或主配置），取决于 sshd_config 是否
#       Include 了 sshd_config.d
# 参数: 无
# 返回值: 通过 stdout 输出 MANAGED_DROPIN_FILE 或 SSHD_CONFIG
# ------------------------------------------------------------------------------
detect_managed_file() {
  if [[ -d "$SSHD_DROPIN_DIR" ]] && grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$SSHD_CONFIG" 2>/dev/null; then
    printf "%s" "$MANAGED_DROPIN_FILE"
  else
    printf "%s" "$SSHD_CONFIG"
  fi
}

# ------------------------------------------------------------------------------
# 函数: do_status
# 功能: 查看 SSH 登录相关配置，包括管理文件路径、drop-in 状态与生效的
#       PasswordAuthentication 值
# 参数: 无
# 返回值: 始终 0
# ------------------------------------------------------------------------------
do_status() {
  printf "\nSSH 登录相关配置:\n"
  local managed=""
  managed="$(detect_managed_file)"
  printf "  管理文件: %s\n" "$managed"

  if [[ -f "$MANAGED_DROPIN_FILE" ]]; then
    printf "  本工具 drop-in: %s（存在）\n" "$MANAGED_DROPIN_FILE"
    grep -E '^[[:space:]]*PasswordAuthentication' "$MANAGED_DROPIN_FILE" 2>/dev/null | sed 's/^/    /' || true
  else
    printf "  本工具 drop-in: %s（不存在）\n" "$MANAGED_DROPIN_FILE"
  fi

  if command_exists sshd; then
    local pa=""
    pa="$(sshd -T 2>/dev/null | awk '/^passwordauthentication/ {print $2}' | head -n1)"
    printf "  生效 PasswordAuthentication: %s\n" "${pa:-未知}"
  fi
}

# ------------------------------------------------------------------------------
# 函数: set_password_auth
# 功能: 启用或禁用 SSH 密码登录，通过 drop-in 或直接修改主配置实现
# 参数: $1 - 1=启用密码登录，0=禁用密码登录
# 返回值: 0 表示成功或用户取消；非 0 表示 sshd 配置校验失败
# 副作用: 修改 MANAGED_DROPIN_FILE 或 SSHD_CONFIG，并备份原配置
# ------------------------------------------------------------------------------
set_password_auth() {
  require_root
  local enable="$1"  # 1=enable, 0=disable
  local managed=""
  managed="$(detect_managed_file)"

  local label=""
  if [[ "$enable" == "1" ]]; then
    label="启用"
  else
    label="禁用"
  fi

  printf "\n%s SSH 密码登录计划:\n" "$label"
  printf "  目标文件: %s\n" "$managed"
  printf "  PasswordAuthentication %s\n" "$([[ "$enable" == "1" ]] && printf yes || printf no)"
  if (( DRY_RUN )); then
    log_info "预览模式，不会修改配置。"
    return 0
  fi

  if ! confirm "确认${label} SSH 密码登录?"; then
    log_info "已取消。"
    return 0
  fi

  local backup_dir=""
  backup_dir="$(backup_sshd_config)"
  log_info "原配置已备份到: ${backup_dir}"

  if [[ "$managed" == "$MANAGED_DROPIN_FILE" ]]; then
    mkdir -p "$SSHD_DROPIN_DIR"
    if [[ "$enable" == "1" ]]; then
      # 删除本工具 drop-in，恢复默认（默认 yes）
      if [[ -f "$MANAGED_DROPIN_FILE" ]]; then
        rm -f "$MANAGED_DROPIN_FILE"
        log_success "已删除 ${MANAGED_DROPIN_FILE}，恢复默认密码登录。"
      else
        log_info "drop-in 不存在，无需操作。"
      fi
    else
      cat >"$MANAGED_DROPIN_FILE" <<'EOF'
# 由 netool懒人工具箱 user 工具写入，禁用密码登录
PasswordAuthentication no
EOF
      log_success "已写入 ${MANAGED_DROPIN_FILE}。"
    fi
  else
    # 直接改主配置: 先移除已有 PasswordAuthentication 行，再追加
    if [[ -f "$managed" ]]; then
      cp -a "$managed" "${managed}.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    sed -i '/^[[:space:]]*PasswordAuthentication[[:space:]]/d' "$managed" 2>/dev/null || true
    if [[ "$enable" == "1" ]]; then
      printf "PasswordAuthentication yes\n" >>"$managed"
    else
      printf "PasswordAuthentication no\n" >>"$managed"
    fi
    log_success "已修改 ${managed}。"
  fi

  # 校验并重载
  if command_exists sshd; then
    if ! sshd -t 2>/dev/null; then
      log_error "sshd 配置语法校验失败，请检查或从 ${backup_dir} 恢复。"
      return 1
    fi
  fi

  if command_exists systemctl; then
    if systemctl cat sshd >/dev/null 2>&1; then
      systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || log_warn "sshd reload 失败，请手动重启。"
    elif systemctl cat ssh >/dev/null 2>&1; then
      systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || log_warn "ssh reload 失败，请手动重启。"
    fi
  fi

  log_success "SSH 配置已重载。"
  do_status
}

# ------------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口: 加载公共函数库、获取互斥锁、解析命令行参数并分发到对应操作
# 参数: $@ - 命令行参数（操作名与选项）
# 返回值: 0 表示正常结束；非 0 表示获取锁失败或参数错误
# ------------------------------------------------------------------------------
main() {
  netool_acquire_lock "user-tools" "另一个 user 实例正在运行，请等待其完成后再试。" || return 1

  local action="list"
  local name=""
  local use_sudo=0
  local key_input=""

  while (($# > 0)); do
    case "$1" in
      list|ls) action="list" ;;
      add|create) action="add" ;;
      del|delete|remove) action="del" ;;
      del-full|delete-full|remove-full) action="del-full" ;;
      key|add-key|ssh-key) action="key" ;;
      disable-password|disable-passwd) action="disable-password" ;;
      enable-password|enable-passwd) action="enable-password" ;;
      status) action="status" ;;
      --name)
        [[ $# -gt 1 ]] || die "--name 需要指定用户名。"
        name="$2"
        shift
        ;;
      --sudo) use_sudo=1 ;;
      --key)
        [[ $# -gt 1 ]] || die "--key 需要指定公钥或文件路径。"
        key_input="$2"
        shift
        ;;
      --plan|--dry-run) DRY_RUN=1 ;;
      -y|--yes) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      *) die "未知参数: $1" ;;
    esac
    shift
  done

  print_banner

  case "$action" in
    list) do_list ;;
    add)
      [[ -n "$name" ]] || die "请用 --name 指定用户名。"
      do_add "$name" "$use_sudo"
      ;;
    del)
      [[ -n "$name" ]] || die "请用 --name 指定用户名。"
      do_del "$name" 0
      ;;
    del-full)
      [[ -n "$name" ]] || die "请用 --name 指定用户名。"
      do_del "$name" 1
      ;;
    key)
      [[ -n "$name" ]] || die "请用 --name 指定用户名。"
      [[ -n "$key_input" ]] || die "请用 --key 指定公钥或文件路径。"
      do_key "$name" "$key_input"
      ;;
    disable-password) set_password_auth 0 ;;
    enable-password) set_password_auth 1 ;;
    status) do_status ;;
  esac
}

main "$@" || exit $?
