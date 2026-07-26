#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 整盘擦除工具 (保护系统盘)
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: wipe_except_sda_v2.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   对显式指定的整盘设备执行安全擦除，支持三种模式:
#     fast     - 清空分区表、文件系统签名、LVM/RAID 签名
#     discard  - fast 基础上执行 blkdiscard
#     zero     - fast 基础上全盘写 0
#   默认保护当前根分区所在整盘，并支持 --exclude 二次排除。
#   真实执行必须显式传 --devices 并输入 WIPE-CONFIRM 确认短语，
#   日志文件权限限制为 600 防止擦盘记录被其他用户读取。
#
# 使用方式:
#   $0 --plan --devices /dev/sdX[,/dev/sdY]            仅预览目标盘
#   $0 --devices /dev/sdX[,/dev/sdY] [fast|discard|zero]  执行擦除
#   $0 --devices /dev/sdX --exclude /dev/sdY -y          非交互模式
#   $0 -h|--help                                          显示帮助
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="wipe-except-sda"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh wipe_except_sda_v2
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) wipe_except_sda_v2
#   直接：bash tools/disk/wipe_except_sda_v2.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 显示脚本使用说明
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
usage() {
    cat <<USAGE
用法:
  $0 --plan --devices /dev/sdX[,/dev/sdY]
  $0 --devices /dev/sdX[,/dev/sdY] [fast|discard|zero]

模式:
  fast    清空分区表、文件系统签名、LVM/RAID 签名
  discard fast 基础上执行 blkdiscard
  zero    fast 基础上全盘写 0

选项:
  --plan                        只预览目标盘，不写入数据
  --devices /dev/sdX,/dev/sdY   必填，指定要擦除的整盘
  --exclude /dev/sdY            从目标中排除指定整盘
  --mode fast|discard|zero      指定擦盘模式
  -y, --yes                     非交互模式，跳过确认短语

说明:
  默认保护当前根分区所在整盘。
  真实执行必须显式传 --devices；未指定目标盘时只允许预览。
  交互执行前必须输入 WIPE-CONFIRM 确认。
USAGE
}

MODE="fast"
PLAN_ONLY=0
YES=0
DEVICES=""
EXCLUDE_DEVICES=""

# 参数解析: 支持 fast/discard/zero 位置参数，以及 --plan/--devices/--mode/
# --exclude/-y/--yes/-h/--help 选项；未知参数报错退出
while [ "$#" -gt 0 ]; do
    case "$1" in
        fast|discard|zero)
            MODE="$1"
            ;;
        --plan)
            PLAN_ONLY=1
            ;;
        --devices)
            shift
            [ "$#" -gt 0 ] || { echo "--devices 需要指定设备列表"; exit 1; }
            DEVICES="$1"
            ;;
        --mode)
            shift
            [ "$#" -gt 0 ] || { echo "--mode 需要指定 fast、discard 或 zero"; exit 1; }
            MODE="$1"
            case "$MODE" in
                fast|discard|zero) ;;
                *) echo "未知模式: $MODE"; exit 1 ;;
            esac
            ;;
        --exclude)
            shift
            [ "$#" -gt 0 ] || { echo "--exclude 需要指定设备列表"; exit 1; }
            EXCLUDE_DEVICES="$1"
            ;;
        -y|--yes)
            YES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# 加载公共函数库并获取 wipe 全局锁，避免多实例并发擦盘
# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
netool_acquire_lock "wipe" "另一个 wipe 实例正在运行，请等待其完成后再试。" || exit 1

# 非预览模式必须以 root 执行
if [ "$EUID" -ne 0 ] && [ "$PLAN_ONLY" -ne 1 ]; then
    echo "请用 root 执行"
    exit 1
fi

# -----------------------------------------------------------------------------
# 函数: need_command
# 功能: 检查依赖命令是否存在，缺失则退出
# 参数: $1 - 待检查的命令名
# 返回值: 0 - 命令存在；1 - 命令缺失 (脚本直接 exit 1)
# -----------------------------------------------------------------------------
need_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少必要命令: $1"
        exit 1
    }
}

need_command lsblk

if [ "$PLAN_ONLY" -ne 1 ]; then
    need_command findmnt
    need_command readlink
    need_command wipefs
    need_command dd
fi

# 日志路径: root 用户写入 HOME，普通用户写入 TMPDIR；预览模式无所谓权限
if [ "$EUID" -eq 0 ]; then
    LOG_DIR="${HOME:-/root}"
    [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] || LOG_DIR="${TMPDIR:-/tmp}"
    LOG="$LOG_DIR/wipe_except_sda_v2_$(date +%Y%m%d_%H%M%S).log"
else
    LOG="${TMPDIR:-/tmp}/wipe_except_sda_v2_$(date +%Y%m%d_%H%M%S).log"
fi

# 预先创建日志文件并限制权限为 600，避免擦盘记录被其他用户读取
touch "$LOG" 2>/dev/null || true
chmod 600 "$LOG" 2>/dev/null || true

# 将后续所有标准输出与错误输出通过 tee 同时写入屏幕与日志文件
exec > >(tee -a "$LOG") 2>&1

echo "日志文件: $LOG"
echo

echo "模式: $MODE"
echo

echo "当前磁盘:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL
echo

# 不再硬编码 /dev/sda，改为动态检测根分区所在整盘加入保护列表
PROTECT_DISKS=()

ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [ -n "$ROOT_SRC" ]; then
    # 反向追溯根分区来源的整盘设备，加入保护列表
    while read -r dev type; do
        [ -n "$dev" ] || continue
        if [ "$type" = "disk" ]; then
            PROTECT_DISKS+=("$dev")
        fi
    done < <(lsblk -spnr -o NAME,TYPE "$ROOT_SRC" 2>/dev/null || true)
fi

# -----------------------------------------------------------------------------
# 函数: uniq_list
# 功能: 对传入的列表去重并排序
# 参数: $@ - 待去重的多个元素
# 返回值: 0 - 始终成功；标准输出去重排序后的结果 (每行一个)
# -----------------------------------------------------------------------------
uniq_list() {
    printf '%s\n' "$@" | grep -v '^$' | sort -u
}

mapfile -t PROTECT_DISKS < <(uniq_list "${PROTECT_DISKS[@]}")

echo "保护盘:"
printf '  %s\n' "${PROTECT_DISKS[@]}"
echo

# -----------------------------------------------------------------------------
# 函数: is_protected_disk
# 功能: 判断设备是否在保护盘列表中
# 参数: $1 - 设备路径
# 返回值: 0 - 在保护列表中 (受保护，禁止擦除)；1 - 不在保护列表中
# -----------------------------------------------------------------------------
is_protected_disk() {
    local dev="$1"
    local p

    for p in "${PROTECT_DISKS[@]}"; do
        if [ "$dev" = "$p" ]; then
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# 函数: normalize_dev
# 功能: 规范化设备路径 (去首尾空白并解析符号链接)
# 参数: $1 - 待规范化的设备路径
# 返回值: 0 - 成功，标准输出规范化后的绝对路径；1 - 输入为空
# -----------------------------------------------------------------------------
normalize_dev() {
    local dev="$1"
    dev="$(echo "$dev" | sed 's/^ *//; s/ *$//')"
    [ -n "$dev" ] || return 1
    readlink -f "$dev" 2>/dev/null || echo "$dev"
}

# -----------------------------------------------------------------------------
# 函数: is_excluded_disk
# 功能: 判断设备是否在 --exclude 排除列表中
# 参数: $1 - 设备路径
# 返回值: 0 - 在排除列表中 (跳过擦除)；1 - 不在排除列表中或未指定 --exclude
# 说明: 同时比对原始路径与 readlink 解析后的真实路径，避免符号链接漏判
# -----------------------------------------------------------------------------
is_excluded_disk() {
    local dev="$1"
    local item=""
    local normalized_dev=""
    local normalized_item=""

    [ -n "$EXCLUDE_DEVICES" ] || return 1

    normalized_dev="$(normalize_dev "$dev" 2>/dev/null || echo "$dev")"
    IFS=',' read -r -a exclude_arr <<< "$EXCLUDE_DEVICES"

    for item in "${exclude_arr[@]}"; do
        item="$(echo "$item" | sed 's/^ *//; s/ *$//')"
        [ -n "$item" ] || continue
        normalized_item="$(normalize_dev "$item" 2>/dev/null || echo "$item")"
        if [ "$dev" = "$item" ] || [ "$normalized_dev" = "$normalized_item" ]; then
            return 0
        fi
    done

    return 1
}

TARGET_DISKS=()

# 未指定 --devices 时: 预览模式列出可用整盘供选择；非预览模式拒绝执行
if [ -z "$DEVICES" ]; then
    if [ "$PLAN_ONLY" -eq 1 ]; then
        echo "未指定 --devices。可用整盘如下，请复制明确目标后再预览或执行:"
        lsblk -dnpr -o NAME,SIZE,TYPE,MODEL,SERIAL | awk '$3=="disk"{print "  "$0}'
        echo
        echo "示例:"
        echo "  $0 --plan --devices /dev/sdX"
        echo "  $0 --devices /dev/sdX fast"
        exit 0
    fi

    echo "拒绝执行：必须显式指定 --devices /dev/sdX[,/dev/sdY]"
    echo "先运行 --plan --devices /dev/sdX 预览目标。"
    exit 1
fi

# 解析 --devices 逗号分隔列表，逐个校验: 必须是存在的整盘且非保护盘/排除盘
IFS=',' read -r -a input_devices <<< "$DEVICES"
for dev in "${input_devices[@]}"; do
    dev="$(normalize_dev "$dev" 2>/dev/null || true)"
    [ -n "$dev" ] || continue

    if [ ! -b "$dev" ]; then
        echo "跳过不存在或不是块设备: $dev"
        continue
    fi

    type="$(lsblk -dnpr -o TYPE "$dev" 2>/dev/null | head -n1)"
    if [ "$type" != "disk" ]; then
        echo "跳过非整盘设备: $dev"
        continue
    fi

    if is_protected_disk "$dev"; then
        echo "跳过保护盘: $dev"
        continue
    fi

    if is_excluded_disk "$dev"; then
        echo "跳过排除盘: $dev"
        continue
    fi

    TARGET_DISKS+=("$dev")
done

mapfile -t TARGET_DISKS < <(uniq_list "${TARGET_DISKS[@]}")

if [ "${#TARGET_DISKS[@]}" -eq 0 ]; then
    echo "没有需要清空的目标盘"
    exit 0
fi

echo
echo "即将清空以下整盘:"
printf '  %s\n' "${TARGET_DISKS[@]}"
echo

echo "严重警告：除了保护盘以外，以上硬盘数据会被破坏。"

# 预览模式只展示目标，不写入数据
if [ "$PLAN_ONLY" -eq 1 ]; then
    echo
    echo "预览模式，不会写入数据。确认目标无误后去掉 --plan 再执行。"
    exit 0
fi

# 交互模式必须输入确认短语 WIPE-CONFIRM；-y/--yes 可跳过
if [ "$YES" -ne 1 ]; then
    echo "确认请输入: WIPE-CONFIRM"
    read -r CONFIRM

    if [ "$CONFIRM" != "WIPE-CONFIRM" ]; then
        echo "确认字符串不匹配，取消。"
        exit 1
    fi
fi

echo
echo "开始处理..."
echo

TARGET_STACK=()
MD_STACK=()

# -----------------------------------------------------------------------------
# 函数: collect_stack
# 功能: 收集目标盘及其所有子设备的设备树，并记录 md 阵列
# 参数: $1 - 目标整盘设备路径
# 返回值: 0 - 始终成功；副作用是向 TARGET_STACK 追加所有子设备，
#         向 MD_STACK 追加类型为 raid*/md 的设备
# -----------------------------------------------------------------------------
collect_stack() {
    local disk="$1"

    while read -r dev type; do
        [ -b "$dev" ] || continue

        TARGET_STACK+=("$dev")

        case "$type" in
            raid*|md)
                MD_STACK+=("$dev")
                ;;
        esac
    done < <(lsblk -nrpo NAME,TYPE "$disk" 2>/dev/null || true)
}

# 遍历所有目标盘收集设备树
for disk in "${TARGET_DISKS[@]}"; do
    collect_stack "$disk"
done

mapfile -t TARGET_STACK < <(uniq_list "${TARGET_STACK[@]}")
mapfile -t MD_STACK < <(uniq_list "${MD_STACK[@]}")

echo "目标设备树:"
printf '  %s\n' "${TARGET_STACK[@]}"
echo

if [ "${#MD_STACK[@]}" -gt 0 ]; then
    echo "发现目标盘关联 mdadm 阵列:"
    printf '  %s\n' "${MD_STACK[@]}"
else
    echo "未从 lsblk 发现目标盘关联 mdadm 阵列"
fi

echo

# -----------------------------------------------------------------------------
# 函数: is_in_target_stack
# 功能: 判断设备是否在已收集的目标设备树中
# 参数: $1 - 待判断的设备路径
# 返回值: 0 - 在目标设备树中；1 - 不在目标设备树中
# 说明: 通过 readlink -f 解析真实路径后逐一比对，避免符号链接漏判
# -----------------------------------------------------------------------------
is_in_target_stack() {
    local dev="$1"
    local real
    local t
    local treal

    real="$(readlink -f "$dev" 2>/dev/null || echo "$dev")"

    for t in "${TARGET_STACK[@]}"; do
        treal="$(readlink -f "$t" 2>/dev/null || echo "$t")"

        if [ "$real" = "$treal" ]; then
            return 0
        fi
    done

    return 1
}

echo "[1] 停用目标盘上的 swap..."

# 遍历 /proc/swaps，停用所有位于目标设备树中的 swap 分区
while read -r swapdev rest; do
    [ "$swapdev" = "Filename" ] && continue
    [ -b "$swapdev" ] || continue

    if is_in_target_stack "$swapdev"; then
        echo "swapoff $swapdev"
        swapoff "$swapdev" || true
    fi
done < /proc/swaps

echo

echo "[2] 卸载目标设备挂载点..."

# 卸载目标设备树中每个设备的所有挂载点，失败则强制懒卸载
for dev in "${TARGET_STACK[@]}"; do
    [ -b "$dev" ] || continue

    while read -r mnt; do
        [ -n "$mnt" ] || continue
        echo "umount $mnt"
        umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done < <(findmnt -rn -S "$dev" -o TARGET 2>/dev/null || true)
done

echo


echo "[3] 查找并停用目标盘相关 LVM VG..."

VG_LIST=()

# 通过 pvs 查找位于目标设备树中的 PV 所属 VG
if command -v pvs >/dev/null 2>&1; then
    while IFS='|' read -r pv vg; do
        pv="$(echo "$pv" | xargs)"
        vg="$(echo "$vg" | xargs)"

        [ -n "$pv" ] || continue
        [ -n "$vg" ] || continue

        if is_in_target_stack "$pv"; then
            VG_LIST+=("$vg")
        fi
    done < <(pvs --noheadings --separator '|' -o pv_name,vg_name 2>/dev/null || true)

    if [ "${#VG_LIST[@]}" -gt 0 ]; then
        mapfile -t VG_LIST < <(uniq_list "${VG_LIST[@]}")
    fi
fi

# 发现目标 VG 时先卸载其所有 LV 挂载点，再 vgchange -an 停用
if [ "${#VG_LIST[@]}" -gt 0 ]; then
    echo "发现目标 VG:"
    printf '  %s\n' "${VG_LIST[@]}"

    if command -v lvs >/dev/null 2>&1; then
        for vg in "${VG_LIST[@]}"; do
            while read -r lvpath; do
                lvpath="$(echo "$lvpath" | xargs)"
                [ -b "$lvpath" ] || continue

                while read -r mnt; do
                    [ -n "$mnt" ] || continue
                    echo "umount $mnt"
                    umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
                done < <(findmnt -rn -S "$lvpath" -o TARGET 2>/dev/null || true)
            done < <(lvs --noheadings -o lv_path "$vg" 2>/dev/null || true)
        done
    fi

    for vg in "${VG_LIST[@]}"; do
        [ -n "$vg" ] || continue
        echo "vgchange -an $vg"
        vgchange -an "$vg" || true
    done
else
    echo "未发现目标盘相关 LVM VG"
fi

echo

echo "[4] 停止目标盘相关 mdadm 阵列..."

# 停止目标设备树中的 md 阵列，先卸载其挂载点再 mdadm --stop
if [ "${#MD_STACK[@]}" -gt 0 ] && command -v mdadm >/dev/null 2>&1; then
    for md in "${MD_STACK[@]}"; do
        [ -b "$md" ] || continue

        while read -r mnt; do
            [ -n "$mnt" ] || continue
            echo "umount $mnt"
            umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
        done < <(findmnt -rn -S "$md" -o TARGET 2>/dev/null || true)

        echo "mdadm --stop $md"
        mdadm --stop "$md" || true
    done
else
    echo "没有 mdadm 阵列需要停止，或者未安装 mdadm"
fi

echo


echo "[5] 停止所有非保护盘参与的 mdadm 残留阵列..."

# 扫描所有 /dev/md* 设备，跳过包含保护盘的阵列，其余尝试卸载并停止
if command -v mdadm >/dev/null 2>&1; then
    for md in /dev/md* /dev/md/*; do
        [ -b "$md" ] || continue

        should_skip=0
        for prot in "${PROTECT_DISKS[@]}"; do
            if mdadm --detail "$md" 2>/dev/null | grep -qE "${prot}[0-9p]*$"; then
                should_skip=1
                break
            fi
        done
        if (( should_skip == 1 )); then
            log_info "跳过包含保护盘 ${prot} 的阵列：$md"
            continue
        fi

        if findmnt -rn -S "$md" >/dev/null 2>&1; then
            echo "阵列仍有挂载，尝试卸载: $md"
            while read -r mnt; do
                [ -n "$mnt" ] || continue
                echo "umount $mnt"
                umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
            done < <(findmnt -rn -S "$md" -o TARGET 2>/dev/null || true)
        fi

        echo "mdadm --stop $md"
        mdadm --stop "$md" || true
    done
fi

echo


echo "[6] 清除目标盘上的 RAID/LVM/文件系统签名..."

# 遍历每个目标盘的子设备，依次清除 mdadm 超级块、LVM PV、wipefs 签名
for disk in "${TARGET_DISKS[@]}"; do
    while read -r dev; do
        [ -b "$dev" ] || continue

        echo "处理签名: $dev"

        if command -v mdadm >/dev/null 2>&1; then
            mdadm --zero-superblock --force "$dev" 2>/dev/null || true
        fi

        if command -v pvremove >/dev/null 2>&1; then
            pvremove -ff -y "$dev" 2>/dev/null || true
        fi

        wipefs -af "$dev" 2>/dev/null || true
    done < <(lsblk -nrpo NAME "$disk" 2>/dev/null || true)
done

echo

echo "[7] 清空整盘分区表、头尾数据..."

# 对每个目标整盘: sgdisk zap-all、wipefs、写零前 100MiB 与末尾 100MiB
for disk in "${TARGET_DISKS[@]}"; do
    [ -b "$disk" ] || continue

    echo "清理整盘: $disk"

    if command -v sgdisk >/dev/null 2>&1; then
        sgdisk --zap-all "$disk" || true
    else
        echo "未安装 sgdisk，跳过 GPT zap-all"
    fi

    wipefs -af "$disk" || true

    # 写零前 100MiB，覆盖 MBR/GPT 头与分区表
    echo "写零前 100MiB: $disk"
    dd if=/dev/zero of="$disk" bs=1M count=100 conv=fsync status=progress || true

    # 设备容量大于 200MiB 时再写零最后 100MiB，覆盖 GPT 备份头
    size_bytes="$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)"
    if [ "$size_bytes" -gt $((200 * 1024 * 1024)) ]; then
        seek_mb=$(( size_bytes / 1024 / 1024 - 100 ))
        echo "写零最后 100MiB: $disk"
        dd if=/dev/zero of="$disk" bs=1M seek="$seek_mb" count=100 conv=fsync status=progress || true
    fi

    blockdev --rereadpt "$disk" 2>/dev/null || true
done

echo


# 根据模式执行额外操作: discard 模式 blkdiscard，zero 模式全盘写零
if [ "$MODE" = "discard" ]; then
    echo "[8] 执行 blkdiscard..."

    for disk in "${TARGET_DISKS[@]}"; do
        [ -b "$disk" ] || continue
        echo "blkdiscard -f $disk"
        blkdiscard -f "$disk" || echo "blkdiscard 失败或设备不支持: $disk"
    done

elif [ "$MODE" = "zero" ]; then
    echo "[8] 全盘写零..."

    for disk in "${TARGET_DISKS[@]}"; do
        [ -b "$disk" ] || continue
        echo "全盘写零: $disk"
        dd if=/dev/zero of="$disk" bs=16M conv=fsync status=progress || true
        sync
    done

else
    echo "[8] fast 模式，不做全盘 discard/zero"
fi

echo

echo "[9] 刷新内核分区表..."

# 通知内核重新读取所有目标盘的分区表
for disk in "${TARGET_DISKS[@]}"; do
    [ -b "$disk" ] || continue

    blockdev --rereadpt "$disk" 2>/dev/null || true
done

sync

echo
echo "完成。"
echo
echo "当前磁盘状态:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL
echo
echo "当前 mdadm 状态:"
cat /proc/mdstat 2>/dev/null || true
echo
echo "日志: $LOG"
