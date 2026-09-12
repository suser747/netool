#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 磁盘管理主入口
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: disk.sh
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   磁盘管理统一入口，支持分区/格式化/挂载、状态查看、盘位映射、
#   SMART 长测、全盘读写校验、整盘擦除等子操作。
#   各子操作通过调用同目录下专用脚本完成；本地缺失时自动从 Gitee
#   raw 在线下载并做语法校验后执行，避免下载内容被篡改。
#   涉及数据破坏的操作必须显式确认或子脚本 --yes，擦盘必须显式
#   传 --devices，默认只预览，不自动选择全部非系统盘。
#
# 使用方式:
#   $0                          进入交互菜单
#   $0 partition                分区、格式化、挂载新磁盘
#   $0 status                   查看磁盘和挂载状态
#   $0 slot-map [参数...]       显示硬盘盘位映射
#   $0 smart-long               对硬盘启动 SMART Long Test
#   $0 disk-test [参数...]      硬盘好坏检测/验盘 (破坏性)
#   $0 wipe --devices /dev/sdX  擦除明确指定的整盘 (破坏性)
#   $0 -h|--help                显示帮助
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="disk-manager"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh disk
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk
#   直接：bash tools/disk/disk.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------

REPO_URL="https://gitee.com/suser747/netool"
SCRIPT_URL="https://gitee.com/suser747/netool/raw/master/tools/disk/disk.sh"
RAW_BASE_URL="https://gitee.com/suser747/netool/raw/master"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-${0:-}}"
if [[ -n "$SCRIPT_SOURCE" && "$SCRIPT_SOURCE" != "bash" && "$SCRIPT_SOURCE" != "-bash" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  SCRIPT_DIR="$(pwd)"
fi

TARGET_DISK=""
TARGET_PART=""
MOUNT_POINT=""
FS_TYPE="ext4"
NON_INTERACTIVE=0
DRY_RUN=0
ACTION=""
PASSTHROUGH_ARGS=()

# -----------------------------------------------------------------------------
# 函数: print_divider
# 功能: 打印一条横线分隔符
# 参数: 无
# 返回值: 始终返回 0
# -----------------------------------------------------------------------------
print_divider() { printf "%s\n" "------------------------------------------------------------"; }

# -----------------------------------------------------------------------------
# 函数: print_banner
# 功能: 打印脚本横幅 (被工具箱调用时跳过)
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then return 0; fi
  print_divider
  printf "netool懒人工具箱 | 磁盘管理 v%s\n" "$SCRIPT_VERSION"
  printf "分区 / 挂载 / 盘位映射 / SMART / 全盘测试 / 擦盘\n"
  print_divider
}




# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 显示脚本使用说明
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
usage() {
  cat <<EOF
netool懒人工具箱 | 磁盘管理 v${SCRIPT_VERSION}
分区、挂载、盘位映射、SMART 长测、全盘读写校验和擦盘辅助。

用法：
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk <操作> [参数...]

操作：
  partition              分区、格式化、挂载新磁盘
  status                 查看磁盘和挂载状态
  slot-map [参数...]     显示硬盘盘位映射，参数透传给 disk_slot_map.sh
  smart-long             对硬盘启动 SMART Long Test
  disk-test [参数...]    硬盘好坏检测/验盘，全盘写入+读回校验，破坏性
  wipe --plan --devices /dev/sdX[,/dev/sdY]
                         预览擦盘目标，不写入数据
  wipe --devices /dev/sdX[,/dev/sdY] [fast|discard|zero]
                         擦除明确指定的整盘，破坏性

选项：
  --dry-run          只打印计划，不执行
  -y, --yes          非交互模式
  -h, --help         显示帮助
  --version          显示版本

说明：
  交互模式下会引导选择磁盘、分区、格式化和挂载。
  涉及数据破坏的操作需要明确确认或子脚本 --yes。
  擦盘必须显式传 --devices，默认只预览，不自动选择全部非系统盘。
  子脚本在线运行时会从 Gitee raw 自动下载。
EOF
}

# -----------------------------------------------------------------------------
# 函数: passthrough_has_help
# 功能: 判断透传参数中是否包含 -h 或 --help
# 参数: 无 (读取全局数组 PASSTHROUGH_ARGS)
# 返回值: 0 - 包含 help 参数；1 - 不包含
# 说明: 用于在调用子脚本前判断是否直接透传帮助请求而不需 root 校验。
# -----------------------------------------------------------------------------
passthrough_has_help() {
  local arg
  for arg in ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}; do
    case "$arg" in
      -h|--help) return 0 ;;
    esac
  done

  return 1
}

# -----------------------------------------------------------------------------
# 函数: list_disks
# 功能: 列出系统磁盘概览 (磁盘/容量/类型/文件系统/挂载点/状态)
# 参数: 无
# 返回值: 0 - 始终成功
# 说明: 通过 lsblk 获取信息，跳过 sr/fd/loop 等非物理磁盘，并根据
#       只读属性与挂载情况标注状态 (只读/已挂载/空闲/分区)。
# -----------------------------------------------------------------------------
list_disks() {
  local mount_col
  mount_col="$(netool_lsblk_mount_col)"
  printf "\n磁盘概览：\n\n"
  printf "  %-10s %-8s %-8s %-10s %-14s %-6s\n" "磁盘" "容量" "类型" "文件系统" "挂载点" "状态"
  printf "  %s\n" "----------------------------------------------------------------"

  while IFS= read -r line; do
    local name size dtype fstype mount
    name="$(awk '{print $1}' <<< "$line")"
    size="$(awk '{print $2}' <<< "$line")"
    dtype="$(awk '{print $3}' <<< "$line")"
    fstype="$(awk '{print $4}' <<< "$line")"
    mount="$(awk '{for(i=5;i<=NF-1;i++) printf $i" "; print ""}' <<< "$line" | sed 's/ *$//')"
    local ro
    ro="$(awk '{print $NF}' <<< "$line")"

    [[ "$name" =~ ^(sr|fd|loop) ]] && continue
    name="$(sed 's/^[├└─│` ]*//' <<< "$name")"

    local status=""
    if [[ "$ro" == "1" ]]; then
      status="只读"
    elif [[ -n "$mount" && "$mount" != "-" ]]; then
      status="已挂载"
    elif [[ "$dtype" == "disk" ]]; then
      status="空闲"
    else
      status="分区"
    fi

    [[ -z "$mount" || "$mount" == " " ]] && mount="-"
    [[ -z "$fstype" || "$fstype" == "0" ]] && fstype="-"

    printf "  %-10s %-8s %-8s %-10s %-14s %-6s\n" "$name" "$size" "$dtype" "$fstype" "$mount" "$status"
  done < <(lsblk -o "NAME,SIZE,TYPE,FSTYPE,${mount_col},RO" 2>/dev/null | tail -n +2)

  printf "\n"
}

# -----------------------------------------------------------------------------
# 函数: get_free_disks
# 功能: 收集未分区且未挂载的空闲整盘到全局数组 FREE_DISKS
# 参数: 无
# 返回值: 0 - 始终成功；副作用是设置全局数组 FREE_DISKS
# 说明: 通过 lsblk 检测，跳过 sr/fd/loop，仅保留既无挂载点也无分区的整盘。
# -----------------------------------------------------------------------------
get_free_disks() {
  local mount_col
  mount_col="$(netool_lsblk_mount_col)"
  FREE_DISKS=()
  while IFS= read -r line; do
    local name size
    name="$(awk '{print $1}' <<< "$line")"
    size="$(awk '{print $2}' <<< "$line")"
    local has_mount
    has_mount="$(lsblk -n -o "$mount_col" "/dev/${name}" 2>/dev/null | grep -v '^$' | head -1 || true)"
    local has_parts
    has_parts="$(lsblk -n -o NAME "/dev/${name}" 2>/dev/null | grep -v "^${name}$" | head -1 || true)"

    if [[ -z "$has_mount" && -z "$has_parts" ]]; then
      FREE_DISKS+=("${name} ${size}")
    fi
  done < <(lsblk -d -n -o NAME,SIZE 2>/dev/null | grep -v -E '^(sr|fd|loop)')
}

# -----------------------------------------------------------------------------
# 函数: prompt_disk
# 功能: 交互式让用户从空闲磁盘列表中选择目标磁盘
# 参数: 无
# 返回值: 0 - 选择成功 (设置 TARGET_DISK)；1 - 用户取消或无可用磁盘
# 说明: 调用 get_free_disks 填充候选列表，输入 b/B/back/返回 可取消。
# -----------------------------------------------------------------------------
prompt_disk() {
  get_free_disks

  if (( ${#FREE_DISKS[@]} == 0 )); then
    log_warn "未检测到可用的空闲磁盘（未分区、未挂载）。"
    log_info "当前磁盘状态："
    list_disks
    return 1
  fi

  printf "\n可用空闲磁盘：\n"
  local idx=1
  local entry
  for entry in "${FREE_DISKS[@]}"; do
    local name size
    name="$(awk '{print $1}' <<< "$entry")"
    size="$(awk '{print $2}' <<< "$entry")"
    local model
    model="$(lsblk -d -n -o MODEL "/dev/${name}" 2>/dev/null | xargs || true)"
    printf "  %s. /dev/%-6s %s  %s\n" "$idx" "$name" "$size" "${model:+($model)}"
    idx=$((idx + 1))
  done

  local input=""
  printf "\n  b. 返回\n"
  read_prompt "选择磁盘（输入编号）： " input || return 1

  case "$input" in
    b|B|back|返回) return 1 ;;
  esac

  if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#FREE_DISKS[@]} )); then
    TARGET_DISK="/dev/$(awk '{print $1}' <<< "${FREE_DISKS[$((input - 1))]}")"
    log_info "已选择：${TARGET_DISK}"
    return 0
  fi

  log_warn "无效输入。"
  return 1
}

# -----------------------------------------------------------------------------
# 函数: partition_path_for
# 功能: 根据整盘设备名生成分区设备路径 (处理 nvme/mmcblk 等以数字结尾的情况)
# 参数: $1 - 整盘设备路径 (如 /dev/sda 或 /dev/nvme0n1)
#       $2 - 分区号
# 返回值: 0 - 始终成功；标准输出分区设备路径
# 说明: 设备名以数字结尾时插入 p 前缀 (如 /dev/nvme0n1p1)，否则直接拼接。
# -----------------------------------------------------------------------------
partition_path_for() {
  local disk="$1"
  local number="$2"

  if [[ "$disk" =~ [0-9]$ ]]; then
    printf "%sp%s\n" "$disk" "$number"
  else
    printf "%s%s\n" "$disk" "$number"
  fi
}

# -----------------------------------------------------------------------------
# 函数: prompt_partition_scheme
# 功能: 交互式让用户选择分区方案 (目前只支持整盘单分区)
# 参数: $1 - 目标磁盘路径
# 返回值: 0 - 选择成功 (设置 TARGET_PART)；1 - 用户取消或无效选择
# -----------------------------------------------------------------------------
prompt_partition_scheme() {
  local disk="$1"
  local size_sector
  size_sector="$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)"
  local size_gb
  size_gb=$(( size_sector / 1073741824 ))

  printf "\n磁盘 %s 总容量 %sG\n" "$disk" "$size_gb"
  printf "\n选择分区方案：\n"
  printf "  1. 整盘单分区（推荐，全部空间分一个区）\n"
  printf "  b. 返回\n"

  local input=""
  read_prompt "输入编号，默认 1： " input || return 1

  case "${input:-1}" in
    1)
      TARGET_PART="$(partition_path_for "$disk" 1)"
      return 0
      ;;
    b|B|back|返回)
      return 1
      ;;
    *)
      log_warn "无效选择。"
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# 函数: prompt_fs_type
# 功能: 交互式让用户选择文件系统类型
# 参数: 无
# 返回值: 0 - 选择成功 (设置 FS_TYPE)；1 - 用户取消或无效选择
# 说明: 可选 ext4 (推荐)、xfs (大文件)、btrfs (快照)。
# -----------------------------------------------------------------------------
prompt_fs_type() {
  printf "\n选择文件系统：\n"
  printf "  1. ext4（推荐，兼容性最好）\n"
  printf "  2. xfs（适合大文件）\n"
  printf "  3. btrfs（支持快照）\n"
  printf "  b. 返回\n"

  local input=""
  read_prompt "输入编号，默认 1： " input || return 1

  case "${input:-1}" in
    1) FS_TYPE="ext4"; return 0 ;;
    2) FS_TYPE="xfs"; return 0 ;;
    3) FS_TYPE="btrfs"; return 0 ;;
    b|B|back|返回) return 1 ;;
    *) log_warn "无效选择。"; return 1 ;;
  esac
}

# -----------------------------------------------------------------------------
# 函数: prompt_mount_point
# 功能: 交互式让用户输入挂载目录，并校验合法性
# 参数: 无
# 返回值: 0 - 输入成功 (设置 MOUNT_POINT)；1 - 用户取消或校验失败
# 说明: 校验项包括非空、绝对路径、不含空格、未被占用挂载。
# -----------------------------------------------------------------------------
prompt_mount_point() {
  printf "\n输入挂载目录（绝对路径）：\n"
  printf "  示例：/data\n"

  local input=""
  read_prompt "挂载目录： " input || return 1

  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"

  if [[ -z "$input" ]]; then
    log_warn "未输入挂载目录。"
    return 1
  fi

  if [[ "$input" != /* ]]; then
    log_warn "请输入绝对路径（以 / 开头）。"
    return 1
  fi

  if [[ "$input" =~ [[:space:]] ]]; then
    log_warn "挂载目录暂不支持空格，请换成不含空格的路径。"
    return 1
  fi

  if mountpoint -q "$input" 2>/dev/null; then
    log_warn "目录 ${input} 已有挂载。"
    return 1
  fi

  MOUNT_POINT="$input"
  return 0
}

# -----------------------------------------------------------------------------
# 函数: wait_for_partition
# 功能: 等待分区设备节点出现 (最多 10 秒)
# 参数: $1 - 期望出现的分区设备路径
# 返回值: 0 - 分区节点已出现；1 - 超时仍未出现
# 说明: 每次循环调用 partprobe 与 udevadm settle 加速内核重新识别分区表。
# -----------------------------------------------------------------------------
wait_for_partition() {
  local part="$1"
  local attempt=0

  while (( attempt < 10 )); do
    if [[ -b "$part" ]]; then
      return 0
    fi

    partprobe "$TARGET_DISK" 2>/dev/null || true
    command_exists udevadm && udevadm settle 2>/dev/null || true
    sleep 1
    attempt=$((attempt + 1))
  done

  return 1
}

# -----------------------------------------------------------------------------
# 函数: findmnt_supports_tab_file
# 功能: 检测当前 findmnt 是否支持 --tab-file 选项
# 参数: 无
# 返回值: 0 - 支持；1 - 不支持或 findmnt 缺失
# 说明: 用于决定写入 fstab 前是否能用 findmnt --verify 做语法校验。
# -----------------------------------------------------------------------------
findmnt_supports_tab_file() {
  command_exists findmnt || return 1
  findmnt --help 2>/dev/null | grep -q -- '--tab-file'
}

# -----------------------------------------------------------------------------
# 函数: append_fstab_entry
# 功能: 安全地向 /etc/fstab 追加一条挂载条目
# 参数: $1 - 待追加的 fstab 行
#       $2 - 用于去重检查的匹配字符串 (一般是 UUID 或设备路径)
# 返回值: 0 - 写入成功或已存在；1 - 校验失败或写入失败
# 说明: 写入前先备份原 fstab；若 findmnt 支持 --tab-file 则做语法校验；
#       通过临时文件 + mv -f 实现原子写入，避免中断导致 fstab 损坏。
# -----------------------------------------------------------------------------
append_fstab_entry() {
  local entry="$1"
  local match="$2"
  local backup=""
  local temp_file=""

  if grep -qF "$match" /etc/fstab 2>/dev/null; then
    log_info "fstab 中已存在此条目。"
    return 0
  fi

  backup="/etc/fstab.${SCRIPT_NAME}.$(date +%Y%m%d-%H%M%S).bak"
  temp_file="$(mktemp)"

  cp -a /etc/fstab "$backup"
  cat /etc/fstab >"$temp_file"
  printf "%s\n" "$entry" >>"$temp_file"

  if findmnt_supports_tab_file; then
    if ! findmnt --verify --tab-file "$temp_file" >/dev/null 2>&1; then
      rm -f "$temp_file"
      log_error "新的 fstab 未通过校验，已保留原文件：/etc/fstab"
      log_info "fstab 备份已保存：${backup}"
      return 1
    fi
  elif command_exists findmnt; then
    log_warn "当前 findmnt 不支持 --tab-file，已跳过写入前校验。"
  fi

  # 原子写入 /etc/fstab：先写到临时文件，再用 mv -f 替换，
  # 避免写入过程中断导致 fstab 被截断或损坏
  local tmp_fstab
  tmp_fstab="$(mktemp)"
  cat "$temp_file" >"$tmp_fstab"
  mv -f "$tmp_fstab" /etc/fstab
  rm -f "$temp_file"

  log_success "已写入 fstab：${entry}"
  log_info "fstab 备份已保存：${backup}"
}

# -----------------------------------------------------------------------------
# 函数: do_partition
# 功能: 执行分区/格式化/挂载流程 (交互式引导 + 实际操作)
# 参数: 无 (通过全局变量 TARGET_DISK/TARGET_PART/FS_TYPE/MOUNT_POINT 传递)
# 返回值: 0 - 成功或用户取消；1 - 关键步骤失败
# 说明: 涉及破坏性操作，需用户 confirm_default_no 确认；DRY_RUN 模式只打印。
# -----------------------------------------------------------------------------
do_partition() {
  require_root

  if ! prompt_disk; then return 0; fi
  if ! prompt_partition_scheme "$TARGET_DISK"; then return 0; fi
  if ! prompt_fs_type; then return 0; fi
  if ! prompt_mount_point; then return 0; fi

  printf "\n"
  print_divider
  printf "  磁盘：    %s\n" "$TARGET_DISK"
  printf "  分区：    %s\n" "$TARGET_PART"
  printf "  文件系统：%s\n" "$FS_TYPE"
  printf "  挂载到：  %s\n" "$MOUNT_POINT"
  print_divider

  log_warn "此操作将清除 ${TARGET_DISK} 上的所有数据！"
  if ! confirm_default_no "确认执行分区和格式化？"; then
    log_info "已取消。"
    return 0
  fi

  if (( DRY_RUN )); then
    log_info "预演：将分区 ${TARGET_DISK}、格式化 ${TARGET_PART} 为 ${FS_TYPE}、挂载到 ${MOUNT_POINT}"
    return 0
  fi

  log_info "正在分区 ${TARGET_DISK}..."
  parted -s "$TARGET_DISK" mklabel gpt
  parted -s "$TARGET_DISK" mkpart primary "${FS_TYPE}" 1MiB 100%
  partprobe "$TARGET_DISK" 2>/dev/null || true

  if ! wait_for_partition "$TARGET_PART"; then
    log_error "分区已创建，但系统未检测到 ${TARGET_PART}。请稍后手动检查后重试。"
    return 1
  fi

  log_info "正在格式化 ${TARGET_PART} 为 ${FS_TYPE}..."
  # 不同文件系统的强制格式化参数不同：ext4 用 -F，xfs/btrfs 用 -f
  local mkfs_force_opt="-f"
  case "$FS_TYPE" in
    ext2|ext3|ext4) mkfs_force_opt="-F" ;;
  esac
  mkfs."$FS_TYPE" "$mkfs_force_opt" "$TARGET_PART" 2>/dev/null || mkfs."$FS_TYPE" "$TARGET_PART"

  log_info "正在创建挂载目录 ${MOUNT_POINT}..."
  mkdir -p "$MOUNT_POINT"

  local uuid
  uuid="$(blkid -s UUID -o value "$TARGET_PART" 2>/dev/null || true)"

  log_info "正在挂载..."
  if [[ -n "$uuid" ]]; then
    mount -U "$uuid" "$MOUNT_POINT"
  else
    mount "$TARGET_PART" "$MOUNT_POINT"
  fi

  if mountpoint -q "$MOUNT_POINT"; then
    log_success "挂载成功：${TARGET_PART} → ${MOUNT_POINT}"
  else
    log_error "挂载失败，可手动执行：mount $TARGET_PART $MOUNT_POINT"
    return 1
  fi

  log_info "正在写入 /etc/fstab 实现开机自动挂载..."
  if [[ -n "$uuid" ]]; then
    local fstab_entry
    fstab_entry="UUID=${uuid} ${MOUNT_POINT} ${FS_TYPE} defaults 0 2"
    append_fstab_entry "$fstab_entry" "$uuid"
  else
    local fstab_entry
    fstab_entry="${TARGET_PART} ${MOUNT_POINT} ${FS_TYPE} defaults 0 2"
    append_fstab_entry "$fstab_entry" "$TARGET_PART"
  fi

  printf "\n"
  print_divider
  log_success "磁盘管理完成！"
  printf "  分区：    %s\n" "$TARGET_PART"
  printf "  文件系统：%s\n" "$FS_TYPE"
  printf "  挂载点：  %s\n" "$MOUNT_POINT"
  printf "  开机挂载：已配置 (/etc/fstab)\n"
  print_divider
}

# -----------------------------------------------------------------------------
# 函数: do_status
# 功能: 显示磁盘概览与挂载详情
# 参数: 无
# 返回值: 0 - 始终成功
# 说明: 优先使用 findmnt 获取挂载详情，回退到 df 命令。
# -----------------------------------------------------------------------------
do_status() {
  list_disks

  printf "挂载详情：\n\n"
  printf "  %-14s %-16s %-8s %-8s %-8s\n" "挂载点" "设备" "文件系统" "容量" "可用"
  printf "  %s\n" "------------------------------------------------------------"

  local findmnt_ok=0
  while IFS= read -r line; do
    local target source fstype size avail
    read -r target source fstype size avail <<< "$line"
    printf "  %-14s %-16s %-8s %-8s %-8s\n" "$target" "$source" "$fstype" "$size" "$avail"
    findmnt_ok=1
  done < <(findmnt -t ext2,ext3,ext4,xfs,btrfs,zfs -n -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL 2>/dev/null)

  if (( ! findmnt_ok )); then
    while IFS= read -r line; do
      local source size used avail mount
      read -r source size used avail _ mount <<< "$line" || true
      [[ -n "${source:-}" && -n "${mount:-}" ]] || continue
      printf "  %-14s %-16s %-8s %-8s %-8s\n" "$mount" "$source" "-" "$size" "$avail"
    done < <(df -h -t ext2 -t ext3 -t ext4 -t xfs -t btrfs 2>/dev/null | tail -n +2)
  fi

  printf "\n"
}

# -----------------------------------------------------------------------------
# 函数: run_disk_subtool
# 功能: 运行磁盘子脚本，优先用本地文件，缺失时从 Gitee raw 下载
# 参数: $1 - 子脚本文件名 (如 smart.sh)
#       $@ - 透传给子脚本的参数
# 返回值: 子脚本的退出码；下载/语法校验失败时 die 退出
# 说明: 下载后会执行 bash -n 语法校验，避免被篡改或截断的脚本被执行。
# -----------------------------------------------------------------------------
run_disk_subtool() {
  local script="$1"
  shift || true

  local local_path="${SCRIPT_DIR}/${script}"
  local common_path=""
  local status=0

  if [[ -f "$local_path" ]]; then
    bash "$local_path" "$@"
    return $?
  fi

  command_exists curl || die "缺少必要命令：curl"

  mkdir -p "$SCRIPT_DIR"
  if ! curl -fsSL "${RAW_BASE_URL}/tools/disk/${script}" -o "$local_path"; then
    die "下载磁盘子脚本失败：${RAW_BASE_URL}/tools/disk/${script}"
  fi
  chmod 700 "$local_path"

  if ! bash -n "$local_path" 2>/dev/null; then
    rm -f "$local_path"
    die "下载的子脚本语法校验失败：tools/disk/${script}"
  fi

  common_path="$(dirname "$SCRIPT_DIR")/common.sh"
  local loader_path="$(dirname "$SCRIPT_DIR")/load_common.sh"
  if [[ ! -f "$common_path" ]]; then
    mkdir -p "$(dirname "$common_path")"
    if ! curl -fsSL "${RAW_BASE_URL}/tools/common.sh" -o "$common_path"; then
      die "下载 common.sh 失败"
    fi
    if ! bash -n "$common_path" 2>/dev/null; then
      rm -f "$common_path"
      die "common.sh 语法校验失败"
    fi
    chmod 600 "$common_path"
  fi
  if [[ ! -f "$loader_path" ]]; then
    if ! curl -fsSL "${RAW_BASE_URL}/tools/load_common.sh" -o "$loader_path"; then
      die "下载 load_common.sh 失败"
    fi
    chmod 700 "$loader_path"
  fi
  export NETOOL_COMMON_FILE="$common_path"

  bash "$local_path" "$@" || status=$?
  return "$status"
}

# -----------------------------------------------------------------------------
# 函数: confirm_phrase
# 功能: 要求用户输入指定确认短语才继续 (强校验，比 y/N 更严格)
# 参数: $1 - 提示文本
#       $2 - 期望的确认短语
# 返回值: 0 - 输入匹配；1 - 输入不匹配或读取失败
# 说明: 非交互模式直接返回 0。
# -----------------------------------------------------------------------------
confirm_phrase() {
  local prompt="$1"
  local phrase="$2"
  local input=""

  if (( NON_INTERACTIVE )); then
    return 0
  fi

  printf "%s\n" "$prompt"
  read_prompt "请输入 ${phrase} 确认： " input || return 1
  [[ "$input" == "$phrase" ]]
}

# -----------------------------------------------------------------------------
# 函数: do_slot_map
# 功能: 调用 disk_slot_map.sh 显示盘位映射
# 参数: 无 (透传 PASSTHROUGH_ARGS)
# 返回值: 透传子脚本退出码
# -----------------------------------------------------------------------------
do_slot_map() {
  run_disk_subtool "disk_slot_map.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}
}

# -----------------------------------------------------------------------------
# 函数: do_smart_long
# 功能: 调用 smart.sh 对非保护盘启动 SMART Long Test
# 参数: 无 (透传 PASSTHROUGH_ARGS)
# 返回值: 0 - 用户取消或子脚本成功；透传子脚本退出码
# 说明: 帮助参数直接透传；否则需 root 并交互确认后才执行。
# -----------------------------------------------------------------------------
do_smart_long() {
  if passthrough_has_help; then
    run_disk_subtool "smart.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}
    return $?
  fi

  require_root

  log_warn "SMART Long Test 会在后台长时间占用硬盘自检资源。"
  if ! confirm_default_no "确认对非保护盘启动 SMART Long Test？"; then
    log_info "已取消。"
    return 0
  fi

  run_disk_subtool "smart.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}
}

# -----------------------------------------------------------------------------
# 函数: do_full_rw_test
# 功能: 调用 disk_full_rw_test.sh 执行全盘读写校验 (破坏性)
# 参数: 无 (透传 PASSTHROUGH_ARGS)
# 返回值: 0 - 用户取消或子脚本成功；1 - 拒绝执行；透传子脚本退出码
# 说明: 无参数时先 --plan 预览，要求输入 DESTROY-DISK-TEST 短语确认后才
#       执行 --yes；显式 --plan/--yes 也分别处理。
# -----------------------------------------------------------------------------
do_full_rw_test() {
  if passthrough_has_help; then
    run_disk_subtool "disk_full_rw_test.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"} || return $?
    return $?
  fi

  if (( ${#PASSTHROUGH_ARGS[@]} == 0 )); then
    require_root

    log_warn "硬盘好坏检测会对目标盘执行全盘写入 + 读回校验。"
    log_warn "被测硬盘上的所有数据都会被覆盖，无法恢复。"
    printf "\n将先预览默认会测试哪些未挂载的非系统盘：\n"
    run_disk_subtool "disk_full_rw_test.sh" --plan || return $?
    printf "\n"
    if ! confirm_phrase "确认这些硬盘都可以被清空后，才允许继续执行写入测试。" "DESTROY-DISK-TEST"; then
      log_info "已取消。"
      return 0
    fi
    run_disk_subtool "disk_full_rw_test.sh" --yes
    return $?
  fi

  if [[ " ${PASSTHROUGH_ARGS[*]+"${PASSTHROUGH_ARGS[*]}"} " != *" --yes "* && " ${PASSTHROUGH_ARGS[*]+"${PASSTHROUGH_ARGS[*]}"} " != *" --plan "* ]]; then
    log_warn "硬盘好坏检测是破坏性全盘写入测试，必须先显式传 --plan 或 --yes。"
    log_info "建议先执行：disk full-rw-test --plan --devices /dev/sdX"
    return 1
  fi

  if [[ " ${PASSTHROUGH_ARGS[*]+"${PASSTHROUGH_ARGS[*]}"} " == *" --plan "* ]]; then
    run_disk_subtool "disk_full_rw_test.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"} || return $?
    return $?
  fi

  require_root

  if [[ " ${PASSTHROUGH_ARGS[*]+"${PASSTHROUGH_ARGS[*]}"} " == *" --yes "* ]]; then
    log_warn "即将执行破坏性验盘：被测硬盘数据会被清空。"
    local plan_args=()
    local arg
    for arg in ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}; do
      [[ "$arg" == "--yes" ]] && continue
      plan_args+=("$arg")
    done
    printf "\n先预览本次会被写入测试的硬盘：\n"
    run_disk_subtool "disk_full_rw_test.sh" --plan ${plan_args[@]+"${plan_args[@]}"} || return $?
    printf "\n"
    if ! confirm_phrase "请确认已经核对 --devices/--exclude 和目标盘清单。" "DESTROY-DISK-TEST"; then
      log_info "已取消。"
      return 0
    fi
  fi

  run_disk_subtool "disk_full_rw_test.sh" ${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"}
}

# -----------------------------------------------------------------------------
# 函数: do_wipe_except_system
# 功能: 调用 wipe_except_sda_v2.sh 执行擦盘 (破坏性)
# 参数: 无 (透传 PASSTHROUGH_ARGS)
# 返回值: 0 - 用户取消或子脚本成功；1 - 拒绝执行；透传子脚本退出码
# 说明: 无 --devices 时只预览；非交互模式自动追加 --yes；--plan 不需 root。
# -----------------------------------------------------------------------------
do_wipe_except_system() {
  local args=()
  args=(${PASSTHROUGH_ARGS[@]+"${PASSTHROUGH_ARGS[@]}"})
  local has_devices=0
  local has_plan=0
  local has_yes=0
  local arg=""

  if passthrough_has_help; then
    run_disk_subtool "wipe_except_sda_v2.sh" ${args[@]+"${args[@]}"}
    return $?
  fi

  for arg in ${args[@]+"${args[@]}"}; do
    case "$arg" in
      --devices) has_devices=1 ;;
      --plan) has_plan=1 ;;
      -y|--yes) has_yes=1 ;;
    esac
  done

  if (( ${#args[@]} == 0 )); then
    log_warn "擦盘是破坏性操作，默认只显示使用方式，不自动选择硬盘。"
    run_disk_subtool "wipe_except_sda_v2.sh" --plan
    log_info "真正执行前请先预览：disk wipe --plan --devices /dev/sdX"
    log_info "确认无误后再执行：disk wipe --devices /dev/sdX fast"
    return 0
  fi

  if (( ! has_devices )); then
    log_warn "拒绝执行：擦盘必须显式指定 --devices /dev/sdX[,/dev/sdY]。"
    log_info "先预览：disk wipe --plan --devices /dev/sdX"
    return 1
  fi

  if (( NON_INTERACTIVE && ! has_yes )); then
    args+=(--yes)
  fi

  if (( ! has_plan )); then
    require_root
  fi

  log_warn "擦盘会清除 --devices 指定整盘上的分区表、文件系统签名和数据。"
  run_disk_subtool "wipe_except_sda_v2.sh" ${args[@]+"${args[@]}"}
}

# -----------------------------------------------------------------------------
# 函数: run_action
# 功能: 根据全局 ACTION 派发到对应的 do_* 子操作
# 参数: 无 (读取全局变量 ACTION)
# 返回值: 透传子操作的退出码；未知 ACTION 时 die 退出
# -----------------------------------------------------------------------------
run_action() {
  case "$ACTION" in
    partition) do_partition ;;
    status) do_status ;;
    slot-map) do_slot_map ;;
    smart-long) do_smart_long ;;
    full-rw-test) do_full_rw_test ;;
    wipe) do_wipe_except_system ;;
    *) die "未知操作：${ACTION}" ;;
  esac
}

# -----------------------------------------------------------------------------
# 函数: parse_args
# 功能: 解析命令行参数，设置 ACTION 与 PASSTHROUGH_ARGS
# 参数: $@ - 命令行参数
# 返回值: 0 - 始终成功 (未知参数会通过 die 退出)
# 说明: 第一个非选项参数作为操作名，其后所有参数透传给子脚本。
# -----------------------------------------------------------------------------
parse_args() {
  while (($# > 0)); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      -y|--yes) NON_INTERACTIVE=1 ;;
      -h|--help) usage; exit 0 ;;
      --version) printf "%s\n" "$SCRIPT_VERSION"; exit 0 ;;
      partition|part|mount)
        ACTION="partition"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      status|list)
        ACTION="status"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      slot-map|slot|map)
        ACTION="slot-map"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      smart-long|smart)
        ACTION="smart-long"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      disk-test|verify-disk|check-disk|full-rw-test|rw-test|test|验盘|硬盘检测)
        ACTION="full-rw-test"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      wipe|wipe-except-system|wipe-except-sda)
        ACTION="wipe"
        shift
        PASSTHROUGH_ARGS=("$@")
        return 0
        ;;
      *) die "未知参数或操作：$1" ;;
    esac
    shift
  done
}

# -----------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口，加载公共函数库、获取锁、解析参数并派发操作
# 参数: $@ - 命令行参数
# 返回值: 0 - 成功；1 - 一般错误或锁获取失败
# 说明: 未指定 ACTION 时进入交互式菜单循环，直到用户选择返回。
# -----------------------------------------------------------------------------
main() {
  netool_acquire_lock "disk" "另一个 disk 实例正在运行，请等待其完成后再试。" || return 1
  parse_args "$@"
  print_banner

  if [[ -n "$ACTION" ]]; then
    run_action || return $?
    return $?
  fi

  local answer=""
  local status=0
  while true; do
    printf "\n请选择操作：\n"
    printf "  1. 分区并挂载新磁盘\n"
    printf "  2. 查看磁盘和挂载状态\n"
    printf "  3. 硬盘盘位映射\n"
    printf "  4. 启动 SMART 长测\n"
    printf "  5. 硬盘好坏检测/验盘（全盘写入，会清空被测盘）\n"
    printf "  6. 擦盘预览（真正执行需命令行指定 --devices）\n"
    printf "  b. 返回\n"
    print_menu_nav_hint
    if ! read_prompt "输入编号： " answer; then
      log_error "无法读取输入。请改用：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk <操作>"
      return 1
    fi

    case "$answer" in
      "")
        log_warn "未读取到输入，请重新输入。"
        continue
        ;;
      1)
        status=0
        do_partition || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      2)
        status=0
        do_status || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      3)
        status=0
        PASSTHROUGH_ARGS=()
        do_slot_map || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      4)
        status=0
        PASSTHROUGH_ARGS=()
        do_smart_long || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      5)
        status=0
        PASSTHROUGH_ARGS=()
        do_full_rw_test || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      6)
        status=0
        PASSTHROUGH_ARGS=(--plan)
        do_wipe_except_system || status=$?
        if (( status != 0 )); then
          log_warn "操作未完成（退出码：${status}），返回菜单。"
        fi
        ;;
      b|B|back|返回)
        log_info "已返回。"
        return 0
        ;;
      *) log_warn "无效输入，请输入 1-6 或 b 返回。" ;;
    esac
  done
}

main "$@" || exit $?
