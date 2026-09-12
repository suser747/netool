#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 磁盘盘位映射与定位灯控制
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: disk_slot_map.sh
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   列出系统中每块磁盘对应的盘位 (enclosure/slot) 信息，包括
#   盘位号、enclosure、状态、定位灯、故障灯、HCTL、容量、型号、
#   序列号、WWN、by-path 链接和 sysfs 设备路径。
#   支持通过 --locate 选项点亮或关闭指定硬盘的定位灯
#   (要求机器支持 enclosure locate)。
#
# 使用方式:
#   $0                                       列出所有磁盘盘位信息
#   $0 --out /root/disk-slot-map.txt         结果同时写入指定文件
#   $0 --locate /dev/sdX on|off [-y|--yes]   点亮/关闭定位灯
#   $0 -h|--help                             显示帮助信息
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="disk-slot-map"
SCRIPT_VERSION="1.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh disk_slot_map
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk_slot_map
#   直接：bash tools/disk/disk_slot_map.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


OUT=""
MODE="list"
LOCATE_DEV=""
LOCATE_STATE=""
ASSUME_YES=0

# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 显示脚本使用说明
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
usage() {
cat <<USAGE
用法:
  $0
  $0 --out /root/disk-slot-map.txt
  $0 --locate /dev/sdX on|off

说明:
  默认列出每个磁盘对应的盘位信息。
  如果系统没有暴露 /sys/class/enclosure，SLOT 会显示 UNKNOWN。
  --locate 用于尝试点亮/关闭硬盘定位灯，前提是机器支持 enclosure locate。
USAGE
}

# -----------------------------------------------------------------------------
# 函数: need_cmd
# 功能: 检查依赖命令是否存在，缺失则退出
# 参数: $1 - 待检查的命令名
# 返回值: 0 - 命令存在；1 - 命令缺失 (脚本直接 exit 1)
# -----------------------------------------------------------------------------
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1" >&2
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 函数: read_one_line
# 功能: 安全读取 sysfs 文件的第一行内容并去除首尾空白与 NUL
# 参数: $1 - 待读取的文件路径
# 返回值: 0 - 始终成功；标准输出文件首行内容，文件不可读时输出空串
# -----------------------------------------------------------------------------
read_one_line() {
    local f="$1"
    if [[ -r "$f" ]]; then
        head -n1 "$f" 2>/dev/null | tr -d '\000' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    else
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# 函数: real_path
# 功能: 获取文件/设备的真实绝对路径 (readlink -f 解析符号链接)
# 参数: $1 - 待解析的路径
# 返回值: 0 - 始终成功；标准输出解析后的绝对路径，失败时回退原值
# -----------------------------------------------------------------------------
real_path() {
    readlink -f "$1" 2>/dev/null || echo "$1"
}

# -----------------------------------------------------------------------------
# 函数: get_base
# 功能: 获取设备节点的 basename (如 /dev/sda1 -> sda1)
# 参数: $1 - 设备路径
# 返回值: 0 - 始终成功；标准输出 basename
# -----------------------------------------------------------------------------
get_base() {
    basename "$(real_path "$1")"
}

# -----------------------------------------------------------------------------
# 函数: get_lsblk_field
# 功能: 通过 lsblk 获取设备的指定字段值
# 参数: $1 - 设备路径 (如 /dev/sda)
#       $2 - 字段名 (如 SIZE、MODEL、SERIAL、HCTL、WWN)
# 返回值: 0 - 始终成功；标准输出字段值 (已压缩空白并 trim)，失败时输出空串
# -----------------------------------------------------------------------------
get_lsblk_field() {
    local dev="$1"
    local field="$2"
    lsblk -dnro "$field" "$dev" 2>/dev/null | head -n1 | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//'
}

# -----------------------------------------------------------------------------
# 函数: get_udev_prop
# 功能: 通过 udevadm 获取设备的指定属性值
# 参数: $1 - 设备路径
#       $2 - 属性键名 (如 ID_SERIAL_SHORT、ID_WWN)
# 返回值: 0 - 始终成功；标准输出属性值，无 udevadm 或未命中时输出空串
# -----------------------------------------------------------------------------
get_udev_prop() {
    local dev="$1"
    local key="$2"
    if command -v udevadm >/dev/null 2>&1; then
        udevadm info --query=property --name "$dev" 2>/dev/null | awk -F= -v k="$key" '$1==k{print $2; exit}'
    fi
}

# -----------------------------------------------------------------------------
# 函数: get_smart_serial
# 功能: 通过 smartctl 获取硬盘序列号 (lsblk 未取到时兜底)
# 参数: $1 - 设备路径
# 返回值: 0 - 始终成功；标准输出序列号，无 smartctl 或读取失败时输出空串
# -----------------------------------------------------------------------------
get_smart_serial() {
    local dev="$1"
    if command -v smartctl >/dev/null 2>&1; then
        smartctl -i "$dev" 2>/dev/null | awk -F: '/Serial Number/{gsub(/^[ \t]+/,"",$2); print $2; exit}'
    fi
}

# -----------------------------------------------------------------------------
# 函数: links_to_dev
# 功能: 在指定目录中查找指向目标设备的符号链接名称
# 参数: $1 - 待搜索的目录 (如 /dev/disk/by-path)
#       $2 - 目标设备路径
#       $3 - 最大返回链接数，默认 5
# 返回值: 0 - 始终成功；标准输出用 " ; " 分隔的链接名列表，无匹配时输出空串
# -----------------------------------------------------------------------------
links_to_dev() {
    local dir="$1"
    local dev="$2"
    local max="${3:-5}"
    local rdev link target count out name

    rdev="$(real_path "$dev")"
    count=0
    out=""

    [[ -d "$dir" ]] || {
        echo ""
        return 0
    }

    # 遍历目录下的符号链接，解析后与目标设备真实路径比对，命中则收集其 basename
    while IFS= read -r -d '' link; do
        target="$(real_path "$link")"
        if [[ "$target" == "$rdev" ]]; then
            name="$(basename "$link")"
            if [[ "$count" -lt "$max" ]]; then
                if [[ -z "$out" ]]; then
                    out="$name"
                else
                    out="$out ; $name"
                fi
            fi
            count=$((count + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -type l -print0 2>/dev/null | sort -z)

    echo "$out"
}

# -----------------------------------------------------------------------------
# 函数: component_info
# 功能: 读取 enclosure 组件的盘位/状态/定位/故障信息并格式化输出
# 参数: $1 - enclosure 组件的 sysfs 路径 (如 /sys/class/enclosure/0:0:0:0/1)
# 返回值: 0 - 始终成功；标准输出以 "|" 分隔的 7 字段:
#         enc|component|slot|status|locate|fault|comp_path
# -----------------------------------------------------------------------------
component_info() {
    local comp="$1"
    local enc=""
    local component=""
    local slot=""
    local status=""
    local locate=""
    local fault=""

    enc="$(basename "$(dirname "$comp")")"
    component="$(basename "$comp")"
    slot="$(read_one_line "$comp/slot")"
    status="$(read_one_line "$comp/status")"
    locate="$(read_one_line "$comp/locate")"
    fault="$(read_one_line "$comp/fault")"

    # 字段为空时填充为组件名或 UNKNOWN，保证表格输出统一
    [[ -n "$slot" ]] || slot="$component"
    [[ -n "$status" ]] || status="UNKNOWN"
    [[ -n "$locate" ]] || locate="UNKNOWN"
    [[ -n "$fault" ]] || fault="UNKNOWN"

    printf '%s|%s|%s|%s|%s|%s|%s\n' \
        "$enc" "$component" "$slot" "$status" "$locate" "$fault" "$comp"
}

# -----------------------------------------------------------------------------
# 函数: find_enclosure_component
# 功能: 在 /sys/class/enclosure 中定位磁盘对应的盘位组件
# 参数: $1 - 磁盘 basename (如 sda)
#       $2 - 磁盘的 HCTL (Host:Channel:Target:Lun)，可选
# 返回值: 0 - 找到盘位组件 (并通过 component_info 输出字段)；
#         1 - 未找到匹配的盘位组件
# 说明: 依次尝试三种匹配策略，命中即返回:
#       1) 盘位组件下直接有 device/block/<disk> (最准确)
#       2) 磁盘 device 下存在 enclosure_device:* 反向链接
#       3) 兜底遍历 enclosure 组件，比对 device/block、scsi_disk/HCTL 或 device 真实路径
# -----------------------------------------------------------------------------
find_enclosure_component() {
    local base="$1"
    local hctl="$2"
    local disk_sys=""
    local p=""
    local comp=""
    local devtarget=""

    disk_sys="$(real_path "/sys/block/$base/device")"

    shopt -s nullglob

    # 策略 1: 盘位组件下面直接有 device/block/<disk> (最准确)
    for p in /sys/class/enclosure/*/*/device/block/"$base"; do
        [[ -e "$p" ]] || continue
        comp="${p%/device/block/$base}"
        component_info "$comp"
        shopt -u nullglob
        return 0
    done

    # 策略 2: 磁盘 device 下面有 enclosure_device:* 反向链接
    for p in /sys/block/"$base"/device/enclosure_device:*; do
        [[ -e "$p" ]] || continue
        comp="$(real_path "$p")"
        component_info "$comp"
        shopt -u nullglob
        return 0
    done

    # 策略 3: 兜底 - 遍历 enclosure 组件，看 device 是否指向该磁盘 scsi device
    for comp in /sys/class/enclosure/*/*; do
        [[ -d "$comp" ]] || continue
        [[ -e "$comp/device" ]] || continue

        if [[ -e "$comp/device/block/$base" ]]; then
            component_info "$comp"
            shopt -u nullglob
            return 0
        fi

        if [[ -n "$hctl" && -e "$comp/device/scsi_disk/$hctl" ]]; then
            component_info "$comp"
            shopt -u nullglob
            return 0
        fi

        devtarget="$(real_path "$comp/device")"
        if [[ -n "$disk_sys" && "$devtarget" == "$disk_sys" ]]; then
            component_info "$comp"
            shopt -u nullglob
            return 0
        fi
    done

    shopt -u nullglob
    return 1
}

# -----------------------------------------------------------------------------
# 函数: list_disks
# 功能: 列出系统中所有类型为 disk 的块设备路径
# 参数: 无
# 返回值: 0 - 始终成功；标准输出每行一个设备路径 (按版本号排序)
# -----------------------------------------------------------------------------
list_disks() {
    lsblk -dnpo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}' | sort -V
}

# -----------------------------------------------------------------------------
# 函数: print_table
# 功能: 收集所有磁盘的盘位与属性信息并输出对齐的表格
# 参数: 无
# 返回值: 0 - 始终成功；标准输出表格内容
# 说明: 使用 mktemp 临时文件汇总，优先用 column 命令对齐；无法获取的字段填 UNKNOWN
# -----------------------------------------------------------------------------
print_table() {
    local tmp=""
    local dev=""
    local base=""
    local size=""
    local hctl=""
    local model=""
    local serial=""
    local wwn=""
    local bypath=""
    local sysdev=""
    local enc_info=""
    local enc="UNKNOWN"
    local component="UNKNOWN"
    local slot="UNKNOWN"
    local status="UNKNOWN"
    local locate="UNKNOWN"
    local fault="UNKNOWN"
    local comp_path=""

    tmp="$(mktemp)"

    # 写入表头，使用 Tab 分隔以便后续 column -t 对齐
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "DEV" "SLOT" "ENCLOSURE" "STATUS" "LOCATE" "FAULT" "HCTL" "SIZE" "MODEL" "SERIAL" "WWN" "BY_PATH" "SYSFS_DEVICE" > "$tmp"

    # 逐行遍历所有磁盘，收集属性与盘位信息
    while IFS= read -r dev; do
        [[ -b "$dev" ]] || continue

        base="$(get_base "$dev")"
        size="$(get_lsblk_field "$dev" SIZE)"
        hctl="$(get_lsblk_field "$dev" HCTL)"
        model="$(get_lsblk_field "$dev" MODEL)"
        serial="$(get_lsblk_field "$dev" SERIAL)"
        wwn="$(get_lsblk_field "$dev" WWN)"

        # 序列号/WWN 在 lsblk 未取到时，依次回退到 udevadm 与 smartctl
        [[ -n "$serial" ]] || serial="$(get_udev_prop "$dev" ID_SERIAL_SHORT)"
        [[ -n "$serial" ]] || serial="$(get_smart_serial "$dev")"
        [[ -n "$wwn" ]] || wwn="$(get_udev_prop "$dev" ID_WWN_WITH_EXTENSION)"
        [[ -n "$wwn" ]] || wwn="$(get_udev_prop "$dev" ID_WWN)"

        bypath="$(links_to_dev /dev/disk/by-path "$dev" 5)"
        sysdev="$(real_path "/sys/block/$base/device")"

        # 每个磁盘重置 enclosure 相关字段，避免上一轮数据残留
        enc="UNKNOWN"
        component="UNKNOWN"
        slot="UNKNOWN"
        status="UNKNOWN"
        locate="UNKNOWN"
        fault="UNKNOWN"
        comp_path=""

        # 查找盘位组件，命中则拆分 7 字段
        enc_info="$(find_enclosure_component "$base" "$hctl" 2>/dev/null || true)"
        if [[ -n "$enc_info" ]]; then
            IFS='|' read -r enc component slot status locate fault comp_path <<< "$enc_info"
            [[ -n "$slot" ]] || slot="$component"
        fi

        # 所有字段兜底为 UNKNOWN，保证表格完整
        [[ -n "$size" ]] || size="UNKNOWN"
        [[ -n "$model" ]] || model="UNKNOWN"
        [[ -n "$serial" ]] || serial="UNKNOWN"
        [[ -n "$wwn" ]] || wwn="UNKNOWN"
        [[ -n "$bypath" ]] || bypath="UNKNOWN"
        [[ -n "$hctl" ]] || hctl="UNKNOWN"
        [[ -n "$sysdev" ]] || sysdev="UNKNOWN"

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$dev" "$slot" "$enc" "$status" "$locate" "$fault" "$hctl" "$size" "$model" "$serial" "$wwn" "$bypath" "$sysdev" >> "$tmp"
    done < <(list_disks)

    # 优先使用 column 对齐输出，否则原样输出
    if command -v column >/dev/null 2>&1; then
        column -t -s $'\t' "$tmp"
    else
        cat "$tmp"
    fi

    rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# 函数: locate_disk
# 功能: 点亮或关闭指定硬盘的 enclosure 定位灯
# 参数: $1 - 设备路径 (如 /dev/sdb)
#       $2 - 定位状态 (on/yes/true/1 点亮；off/no/false/0 关闭)
# 返回值: 0 - 成功写入 locate 文件；
#         1 - 设备不是块设备，或状态参数非法；
#         2 - 未找到该磁盘的 enclosure/slot 信息；
#         3 - locate 文件不可写
# 说明: 通过 find_enclosure_component 定位盘位组件后，向其 locate sysfs
#       文件写入 1/0 实现灯的开关。需要 root 权限。
# -----------------------------------------------------------------------------
locate_disk() {
    local dev="$1"
    local state="$2"
    local value=""
    local base=""
    local hctl=""
    local enc_info=""
    local enc=""
    local component=""
    local slot=""
    local status=""
    local locate=""
    local fault=""
    local comp_path=""
    local locate_file=""

    # 校验设备是否为块设备
    [[ -b "$dev" ]] || {
        echo "不是块设备: $dev" >&2
        return 1
    }

    # 将多种状态写法归一化为 1/0
    case "$state" in
        on|ON|1|yes|true) value=1 ;;
        off|OFF|0|no|false) value=0 ;;
        *)
            echo "locate 状态只能是 on 或 off" >&2
            return 1
            ;;
    esac

    base="$(get_base "$dev")"
    hctl="$(get_lsblk_field "$dev" HCTL)"
    enc_info="$(find_enclosure_component "$base" "$hctl" 2>/dev/null || true)"

    # 没有盘位信息则无法控制定位灯
    if [[ -z "$enc_info" ]]; then
        echo "$dev 没有找到 enclosure/slot 信息，无法控制定位灯。" >&2
        return 2
    fi

    # 拆分盘位字段并定位 locate sysfs 文件
    IFS='|' read -r enc component slot status locate fault comp_path <<< "$enc_info"
    locate_file="$comp_path/locate"

    # 检查 locate 文件可写性，避免写入失败
    if [[ ! -w "$locate_file" ]]; then
        echo "$dev 找到盘位，但 locate 文件不可写: $locate_file" >&2
        echo "盘位信息: $enc_info" >&2
        return 3
    fi

    # 写入 1/0 控制定位灯开关
    echo "$value" > "$locate_file"
    echo "$dev locate=$state"
    echo "盘位: ${slot:-$component}  enclosure=$enc component=$component status=$status fault=$fault"
}

# 参数解析: 支持 --out、--locate、-y/--yes、-h/--help
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            OUT="${2:-}"
            shift 2
            ;;
        --locate)
            MODE="locate"
            LOCATE_DEV="${2:-}"
            LOCATE_STATE="${3:-}"
            shift 3
            ;;
        -y|--yes)
            ASSUME_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            usage
            exit 1
            ;;
    esac
done

need_cmd lsblk
need_cmd readlink
need_cmd awk
need_cmd sed
need_cmd find
need_cmd sort
need_cmd head

if [[ "$MODE" == "locate" ]]; then
    # locate 操作会改变硬件定位灯状态，执行前需用户确认 (除非已传 -y/--yes)
    if [[ "$ASSUME_YES" -ne 1 ]]; then
        echo "即将对 $LOCATE_DEV 执行 locate=$LOCATE_STATE 操作 (点亮/关闭定位灯)。"
        echo "请确认目标设备无误，输入 y 或 yes 继续，其他任意输入取消:"
        read -r CONFIRM
        case "$CONFIRM" in
            y|Y|yes|YES) ;;
            *)
                echo "已取消 locate 操作。"
                exit 0
                ;;
        esac
    fi
    locate_disk "$LOCATE_DEV" "$LOCATE_STATE"
    exit $?
fi

if [[ -n "$OUT" ]]; then
    mkdir -p "$(dirname "$OUT")"
    print_table | tee "$OUT"
else
    print_table
fi
