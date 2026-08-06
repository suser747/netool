#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 硬盘 SMART 长测批量启动工具
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: smart.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   扫描系统中所有整盘设备，对非保护盘批量启动 SMART Long Test。
#   默认保护 /dev/sda 以及当前根分区所在整盘，避免误伤系统盘。
#   每块盘的 smartctl 信息、测试能力、健康状态等都会写入独立日志。
#   --list 模式只列出候选盘与保护盘，不启动测试。
#
# 使用方式:
#   $0                  扫描硬盘并启动 SMART Long Test (需 root)
#   $0 --list           仅列出候选整盘与保护盘
#   $0 -h|--help        显示帮助信息
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="smart-long-test"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh smart
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) smart
#   直接：bash tools/disk/smart.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


LOG_DIR="/var/log/smart-long-test"
DATE="$(date '+%Y%m%d_%H%M%S')"

# 默认保护盘列表，始终包含 /dev/sda；detect_root_disk 会追加根分区所在整盘
SKIP_DISKS=("/dev/sda")

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
  $0 --list

说明:
  扫描整盘设备并启动 SMART Long Test。
  默认跳过 /dev/sda 和当前根分区所在整盘，日志写入 ${LOG_DIR}。
  --list 只列出候选整盘和保护盘，不启动测试。

依赖:
  smartmontools / smartctl
USAGE
}

LIST_ONLY=0

# -----------------------------------------------------------------------------
# 函数: uniq_list
# 功能: 对传入的列表去重并排序
# 参数: $@ - 待去重的多个元素
# 返回值: 0 - 始终成功；标准输出去重排序后的结果 (每行一个)
# -----------------------------------------------------------------------------
uniq_list() {
    printf '%s\n' "$@" | grep -v '^$' | sort -u
}

# -----------------------------------------------------------------------------
# 函数: detect_root_disk
# 功能: 检测根分区所在的整盘并追加到 SKIP_DISKS 保护列表
# 参数: 无
# 返回值: 0 - 始终成功；副作用是更新全局数组 SKIP_DISKS
# 说明: 通过 findmnt 获取根分区 SOURCE，再用 lsblk -spnr 反向追溯其所属整盘，
#       将该整盘设备路径加入保护列表并去重。
# -----------------------------------------------------------------------------
detect_root_disk() {
    local root_disk=""
    root_disk="$(netool_lsblk_root_disk 2>/dev/null || true)"
    if [ -n "$root_disk" ]; then
        SKIP_DISKS+=("$root_disk")
    fi

    netool_mapfile SKIP_DISKS < <(uniq_list ${SKIP_DISKS[@]+"${SKIP_DISKS[@]}"})
}

# 参数解析: --list 仅预览；其他非法参数报错退出
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --list|list|status)
        LIST_ONLY=1
        ;;
    "")
        ;;
    *)
        echo "未知参数: $1"
        usage
        exit 1
        ;;
esac

if [[ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]]; then
    log_error "此磁盘工具仅支持 Linux（当前：$(uname -s)）。"
    exit 1
fi

if ! command -v lsblk >/dev/null 2>&1; then
    echo "缺少命令: lsblk"
    exit 1
fi

# 检测根分区所在整盘并加入保护列表
detect_root_disk

# 收集所有整盘设备路径
DISKS="$(netool_lsblk_disk_paths)"

if [ "$LIST_ONLY" -eq 1 ]; then
    echo "保护盘:"
    printf '  %s\n' ${SKIP_DISKS[@]+"${SKIP_DISKS[@]}"}
    echo
    echo "候选整盘:"
    if [ -n "$DISKS" ]; then
        printf '%s\n' "$DISKS" | sed 's/^/  /'
    else
        echo "  未发现硬盘"
    fi
    exit 0
fi

mkdir -p "$LOG_DIR"

if [ "$EUID" -ne 0 ]; then
    echo "请用 root 执行"
    exit 1
fi

if ! command -v smartctl >/dev/null 2>&1; then
    echo "未安装 smartmontools"
    echo "Debian/Ubuntu: apt install -y smartmontools"
    echo "CentOS/Rocky/AlmaLinux: yum install -y smartmontools"
    exit 1
fi

echo "开始扫描硬盘..."
echo "将跳过:"
printf '  %s\n' ${SKIP_DISKS[@]+"${SKIP_DISKS[@]}"}
echo

if [ -z "$DISKS" ]; then
    echo "未发现硬盘"
    exit 1
fi

# 使用 while read 逐行遍历磁盘列表，避免 for 循环在设备名含空格/特殊字符时出错
printf '%s\n' "$DISKS" | while IFS= read -r DEV; do
    [ -n "$DEV" ] || continue

    # 跳过保护盘列表中的硬盘
    for SKIP in ${SKIP_DISKS[@]+"${SKIP_DISKS[@]}"}; do
        if [ "$DEV" = "$SKIP" ]; then
            echo "跳过硬盘: $DEV"
            continue 2
        fi
    done

    # 将设备路径中的 "/" 替换为 "_"，生成安全的日志文件名
    SAFE_NAME=$(echo "$DEV" | sed 's#/#_#g')
    LOG_FILE="$LOG_DIR/${SAFE_NAME}_${DATE}.log"

    echo "========================================"
    echo "检测硬盘: $DEV"
    echo "日志文件: $LOG_FILE"

    # 依次执行: 信息查询、开启 SMART、查询能力、启动长测、健康状态，结果汇总写入日志
    {
        echo "========================================"
        echo "Device: $DEV"
        echo "Time: $(date)"
        echo "========================================"
        echo

        echo "[1] smartctl -i $DEV"
        smartctl -i "$DEV"
        echo

        echo "[2] 尝试开启 SMART"
        smartctl -s on "$DEV"
        echo

        echo "[3] 查询测试能力"
        smartctl -c "$DEV"
        echo

        echo "[4] 启动 SMART Long Test"
        smartctl -t long "$DEV"
        echo

        echo "[5] 当前健康状态"
        smartctl -H "$DEV"
        echo

    } > "$LOG_FILE" 2>&1

    # 通过日志内容判断 Long Test 是否成功启动
    if grep -qiE "Please wait|Self Test has begun|Extended self-test routine recommended polling time|long.*test" "$LOG_FILE"; then
        echo "已启动 Long Test: $DEV"
    else
        echo "可能启动失败，请查看日志: $LOG_FILE"
    fi

    echo
done

echo "========================================"
echo "处理完成"
echo
echo "查看日志:"
echo "  ls -lh $LOG_DIR"
echo
echo "查看测试结果:"
echo "  smartctl -l selftest /dev/sdX"
echo "  smartctl -a /dev/sdX"
echo "========================================"
