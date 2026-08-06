#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 硬盘全盘读写校验测试 (破坏性)
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: disk_full_rw_test.sh
# 脚本版本: 2.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   对指定硬盘执行全盘写入 + 读回校验 (fio verify)，用于验盘/坏盘筛查。
#   默认会跳过系统盘、已挂载盘、只读盘和 --exclude 指定的盘；未指定
#   --devices 时自动选择所有未挂载的非系统盘。
#   测试期间会同时采集 smartctl 与内核日志，按"当前盘严格匹配"规则
#   归属错误，避免误判。最终生成 Markdown 报告汇总每块盘的判定结果
#   (PASS/FAIL/RETEST/WARN)。
#
# 使用方式:
#   $0 --plan --devices /dev/sdb,/dev/sdc        预览目标盘，不写入
#   $0 --yes --devices /dev/sdb,/dev/sdc         执行破坏性测试
#   $0 --yes --exclude /dev/sda --concurrency 2  自动选盘并排除 sda
#   $0 --yes --devices /dev/sdb --no-trim        测完不执行 TRIM/DISCARD
#   $0 -h|--help                                 显示帮助
#
# 退出码:
#   0 - 成功
#   1 - 一般错误
#   2 - 用法错误
#   3 - 权限错误
#   4 - 依赖缺失
# =============================================================================
set -Eeuo pipefail

SCRIPT_NAME="disk-full-rw-test"
SCRIPT_VERSION="2.0"

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
# -----------------------------------------------------------------------------
# 运行方式
#   本地：cd /opt/netool && ./main.sh disk_full_rw_test
#   远程：bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) disk_full_rw_test
#   直接：bash tools/disk/disk_full_rw_test.sh [参数...]  （需在 tools 目录结构完整时）
# -----------------------------------------------------------------------------


YES=0
PLAN_ONLY=0
DISK_CONCURRENCY=2
JOBS_PER_DISK=1
BS="1M"
IODEPTH=32
DEVICES=""
EXCLUDE_DEVICES=""
DO_TRIM=1
OUT_BASE="${HOME:-/root}/disk-test-report-$(date +%Y%m%d-%H%M%S)"

# -----------------------------------------------------------------------------
# 函数: usage
# 功能: 显示脚本使用说明
# 参数: 无
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
usage() {
cat <<USAGE
用法:
  $0 --yes [选项]

危险:
  这是全盘写入 + 读回校验测试，会清空被测试硬盘上的所有数据。

选项:
  --yes                         确认执行破坏性测试，必须加
  --plan                        只预览将被测试的硬盘，不写入数据
  --devices /dev/sdb,/dev/sdc   指定测试硬盘；不指定则自动选择未挂载的非系统盘
  --exclude /dev/sdh,/dev/sdy   排除指定硬盘
  --concurrency N               同时测试几块盘，默认 2
  --jobs-per-disk N             每块盘 fio 线程数，默认 1
                                注意：全盘 verify 模式不建议大于 1，脚本会自动降级为 1
  --bs SIZE                     fio 块大小，默认 1M
  --iodepth N                   fio 队列深度，默认 32
  --out DIR                     报告输出目录
  --no-trim                     测完后不执行 blkdiscard/TRIM

结果:
  PASS    fio 写入+读回校验通过，且当前盘没有明确严重内核磁盘错误
  FAIL    当前盘内核日志有严重 I/O/介质/超时/离线/abort 错误，或 fio 出现校验/数据不一致错误
  RETEST  fio 返回错误，但当前盘内核日志没有明确严重错误；不直接判坏，建议单盘重测
  WARN    fio 通过，但 TRIM/DISCARD 失败，或者当前盘只有 reset/block/unblock 软事件

示例:
  $0 --yes --concurrency 2 --jobs-per-disk 1 --iodepth 32
  $0 --yes --exclude /dev/sdh,/dev/sdy --concurrency 2 --jobs-per-disk 1
  $0 --yes --devices /dev/sdb,/dev/sdc --concurrency 2 --jobs-per-disk 1
  $0 --yes --concurrency 24 --bs 10M
USAGE
}

# -----------------------------------------------------------------------------
# 函数: log
# 功能: 输出带时间戳的日志到 stderr (供后台任务统一写入)
# 参数: $* - 待打印的消息内容
# 返回值: 始终返回 0
# -----------------------------------------------------------------------------
log() {
    echo "[$(date '+%F %T')] $*" >&2
}

# -----------------------------------------------------------------------------
# 函数: need_cmd
# 功能: 检查依赖命令是否存在，缺失则打印安装提示并退出
# 参数: $1 - 待检查的命令名
# 返回值: 0 - 命令存在；不返回 - 命令缺失时脚本以退出码 1 退出
# -----------------------------------------------------------------------------
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "缺少命令: $1"
        echo "请先安装依赖:"
        echo "  apt update && apt install -y fio smartmontools util-linux coreutils grep sed gawk"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 函数: is_positive_int
# 功能: 判断字符串是否为正整数
# 参数: $1 - 待判断的字符串
# 返回值: 0 - 是正整数；1 - 不是正整数
# -----------------------------------------------------------------------------
is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 ]]
}

# 参数解析: --yes/--plan/--devices/--exclude/--concurrency/--jobs-per-disk/
# --bs/--iodepth/--out/--no-trim/-h/--help；未知参数报错退出
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            YES=1
            shift
            ;;
        --plan)
            PLAN_ONLY=1
            shift
            ;;
        --devices)
            DEVICES="${2:-}"
            shift 2
            ;;
        --exclude)
            EXCLUDE_DEVICES="${2:-}"
            shift 2
            ;;
        --concurrency)
            DISK_CONCURRENCY="${2:-2}"
            shift 2
            ;;
        --jobs-per-disk)
            JOBS_PER_DISK="${2:-1}"
            shift 2
            ;;
        --bs)
            BS="${2:-1M}"
            shift 2
            ;;
        --iodepth)
            IODEPTH="${2:-32}"
            shift 2
            ;;
        --out)
            OUT_BASE="${2:-$OUT_BASE}"
            shift 2
            ;;
        --no-trim)
            DO_TRIM=0
            shift
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
done

if [[ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]]; then
    log_error "此磁盘工具仅支持 Linux（当前：$(uname -s)）。"
    exit 1
fi

if ! is_positive_int "$DISK_CONCURRENCY"; then
    echo "--concurrency 必须是正整数"
    exit 1
fi

if ! is_positive_int "$JOBS_PER_DISK"; then
    echo "--jobs-per-disk 必须是正整数"
    exit 1
fi

if ! is_positive_int "$IODEPTH"; then
    echo "--iodepth 必须是正整数"
    exit 1
fi

# 重要：fio verify + 裸块设备 + 多 writer 可能互相覆盖，导致误判。
# 单盘提速建议调大 bs / iodepth，或者提高多盘并发，不建议单盘 numjobs > 1。
if [[ "$JOBS_PER_DISK" -gt 1 ]]; then
    echo "警告：当前是全盘 verify 测试，--jobs-per-disk=$JOBS_PER_DISK 可能导致多 writer 覆盖误判。"
    echo "脚本已自动将 JOBS_PER_DISK 降级为 1。"
    JOBS_PER_DISK=1
fi

need_cmd lsblk
need_cmd blockdev
need_cmd awk
need_cmd grep
need_cmd sed
need_cmd tail
need_cmd date
need_cmd hostname
need_cmd uname
need_cmd readlink

if [[ "$PLAN_ONLY" != "1" ]]; then
    need_cmd fio
    need_cmd smartctl
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "请使用 root 执行。"
    exit 1
fi

if [[ "$YES" != "1" && "$PLAN_ONLY" != "1" ]]; then
    echo "未加 --yes，拒绝执行。"
    echo "这是破坏性全盘写入测试，会清空硬盘数据。"
    echo "建议先执行 --plan 预览会被测试的硬盘。"
    exit 1
fi

if [[ "$PLAN_ONLY" != "1" ]]; then
    mkdir -p -m 700 "$OUT_BASE"
fi

# -----------------------------------------------------------------------------
# 函数: real_dev
# 功能: 获取设备的真实绝对路径 (readlink -f 解析符号链接)
# 参数: $1 - 待解析的设备路径
# 返回值: 0 - 始终成功；标准输出解析后的绝对路径，失败时回退原值
# -----------------------------------------------------------------------------
real_dev() {
    readlink -f "$1" 2>/dev/null || echo "$1"
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
    [[ -n "$dev" ]] || return 1
    readlink -f "$dev" 2>/dev/null || echo "$dev"
}

# -----------------------------------------------------------------------------
# 函数: device_is_excluded
# 功能: 判断设备是否在 --exclude 排除列表中
# 参数: $1 - 设备路径
# 返回值: 0 - 在排除列表中 (跳过测试)；1 - 不在排除列表中或未指定 --exclude
# 说明: 同时比对原始路径与 readlink 解析后的真实路径，避免符号链接漏判。
# -----------------------------------------------------------------------------
device_is_excluded() {
    local dev="$1"
    local ndev item nitem

    [[ -n "$EXCLUDE_DEVICES" ]] || return 1

    ndev="$(normalize_dev "$dev" 2>/dev/null || echo "$dev")"
    IFS=',' read -r -a exclude_arr <<< "$EXCLUDE_DEVICES"

    for item in ${exclude_arr[@]+"${exclude_arr[@]}"}; do
        item="$(echo "$item" | sed 's/^ *//; s/ *$//')"
        [[ -n "$item" ]] || continue

        nitem="$(normalize_dev "$item" 2>/dev/null || echo "$item")"

        if [[ "$ndev" == "$nitem" || "$dev" == "$item" ]]; then
            return 0
        fi
    done

    return 1
}

# -----------------------------------------------------------------------------
# 函数: disk_has_mountpoint
# 功能: 判断整盘是否含有任意挂载点 (用于排除系统盘/已挂载盘)
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 有挂载点；1 - 无挂载点
# -----------------------------------------------------------------------------
disk_has_mountpoint() {
    local dev="$1"
    if lsblk -nrpo MOUNTPOINT "$dev" >/dev/null 2>&1; then
        lsblk -nrpo MOUNTPOINT "$dev" 2>/dev/null | grep -q '[^[:space:]]'
    else
        lsblk -nro MOUNTPOINT "$dev" 2>/dev/null | grep -q '[^[:space:]]'
    fi
}

# -----------------------------------------------------------------------------
# 函数: disk_is_readonly
# 功能: 判断整盘是否为只读 (通过 lsblk RO 字段)
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 只读；1 - 可写
# -----------------------------------------------------------------------------
disk_is_readonly() {
    local dev="$1"
    local ro
    ro="$(lsblk -dnro RO "$dev" 2>/dev/null | head -n1)"
    [[ "$ro" == "1" ]]
}

# -----------------------------------------------------------------------------
# 函数: disk_size_bytes
# 功能: 获取整盘字节数容量
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功；标准输出字节数，失败时输出 0
# -----------------------------------------------------------------------------
disk_size_bytes() {
    blockdev --getsize64 "$1" 2>/dev/null || echo 0
}

# -----------------------------------------------------------------------------
# 函数: disk_model
# 功能: 获取整盘型号字符串 (压缩空白)
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功；标准输出去除多余空白后的型号字符串
# -----------------------------------------------------------------------------
disk_model() {
    lsblk -dnro MODEL "$1" 2>/dev/null | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# 函数: disk_serial
# 功能: 获取整盘序列号字符串 (压缩空白)
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功；标准输出去除多余空白后的序列号字符串
# -----------------------------------------------------------------------------
disk_serial() {
    lsblk -dnro SERIAL "$1" 2>/dev/null | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# 函数: disk_tran
# 功能: 获取整盘传输总线类型 (sata/nvme/usb 等)
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功；标准输出去除多余空白后的总线类型字符串
# -----------------------------------------------------------------------------
disk_tran() {
    lsblk -dnro TRAN "$1" 2>/dev/null | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# 函数: disk_hctl
# 功能: 获取整盘的 HCTL (Host:Channel:Target:Lun) 标识
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功；标准输出去除多余空白后的 HCTL 字符串
# 说明: 用于内核日志中按 "sd HCTL:" 模式精确匹配当前盘的错误归属。
# -----------------------------------------------------------------------------
disk_hctl() {
    lsblk -dnro HCTL "$1" 2>/dev/null | head -n1 | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

# -----------------------------------------------------------------------------
# 函数: regex_escape
# 功能: 对字符串进行正则转义 (在 ERE 元字符前加反斜杠)
# 参数: $1 - 待转义的字符串
# 返回值: 0 - 始终成功；标准输出转义后的字符串
# -----------------------------------------------------------------------------
regex_escape() {
    sed 's/[][(){}.^$*+?|\\]/\\&/g' <<< "$1"
}

# -----------------------------------------------------------------------------
# 函数: human_size
# 功能: 将字节数转换为人类可读的大小字符串
# 参数: $1 - 字节数
# 返回值: 0 - 始终成功；标准输出格式化后的大小字符串
# 说明: 优先使用 numfmt (GNU coreutils)；缺失时回退到 "N bytes"。
# -----------------------------------------------------------------------------
human_size() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1"
    else
        echo "$1 bytes"
    fi
}

# -----------------------------------------------------------------------------
# 函数: disk_supports_discard
# 功能: 判断整盘是否支持 TRIM/DISCARD 操作
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 支持 DISCARD；1 - 不支持
# 说明: 优先读 sysfs 的 discard_max_bytes，其次回退到 lsblk DISC-MAX 字段。
# -----------------------------------------------------------------------------
disk_supports_discard() {
    local dev="$1"
    local rdev base sysfile max

    rdev="$(real_dev "$dev")"
    base="$(basename "$rdev")"
    sysfile="/sys/block/$base/queue/discard_max_bytes"

    if [[ -r "$sysfile" ]]; then
        max="$(cat "$sysfile" 2>/dev/null | tr -dc '0-9')"
        if [[ "$max" =~ ^[0-9]+$ ]] && [[ "$max" -gt 0 ]]; then
            return 0
        fi
    fi

    local disc_max
    disc_max="$(lsblk -dnbo DISC-MAX "$dev" 2>/dev/null | head -n1 | tr -dc '0-9')"

    if [[ "$disc_max" =~ ^[0-9]+$ ]] && [[ "$disc_max" -gt 0 ]]; then
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# 函数: smart_dump
# 功能: 将 smartctl 详细信息写入指定文件
# 参数: $1 - 整盘设备路径
#       $2 - 输出文件路径
# 返回值: 0 - 始终成功 (smartctl 失败也不退出，便于部分采集)
# 说明: 优先用 smartctl -x 获取全量信息，失败时回退到 smartctl -a。
# -----------------------------------------------------------------------------
smart_dump() {
    local dev="$1"
    local out="$2"

    smartctl -x "$dev" > "$out" 2>&1 || smartctl -a "$dev" > "$out" 2>&1 || true
}

# -----------------------------------------------------------------------------
# 函数: smart_summary_lines
# 功能: 从 smartctl 输出文件中提取关键健康项行
# 参数: $1 - smartctl 输出文件路径
# 返回值: 0 - 始终成功；标准输出关键健康项行
# 说明: 覆盖 SMART overall、磨损度、温度、重映射、CRC、坏块等关键指标。
# -----------------------------------------------------------------------------
smart_summary_lines() {
    local file="$1"

    grep -Ei \
      "SMART overall-health|SMART Health Status|Percentage Used|Available Spare|Media and Data Integrity Errors|Error Information Log Entries|Critical Warning|Power_On_Hours|Power Cycle|Power_Cycle_Count|Unsafe_Shutdown|Temperature|Reallocated|Reported_Uncorrect|SATA_CRC|CRC_Error|Bad_Block|Program_Fail|Erase_Fail|SSD_Life|Life_Left|Wear_Leveling|Media_Wearout|Lifetime_Writes|Lifetime_Reads|Total_LBAs_Written|Total_LBAs_Read|Command_Timeout|Current_Pending|Offline_Uncorrect|Non-medium|grown defect" \
      "$file" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# 函数: kernel_errors_since
# 功能: 采集测试期间的内核日志，并按当前盘严格匹配规则分类
# 参数: $1 - 起始时间字符串 (date 可解析格式)
#       $2 - 当前盘设备基名 (如 sdb)
#       $3 - 当前盘 HCTL
#       $4 - 输出文件路径 (当前盘匹配的日志)
# 返回值: 0 - 始终成功
# 说明: 同时生成 ${4}.all (全部内核日志) 与 ${4}.global-unmatched
#       (全局未归属错误日志)。只有 $4 中的内容参与当前盘判定。
# -----------------------------------------------------------------------------
kernel_errors_since() {
    local since="$1"
    local devbase="$2"
    local hctl="$3"
    local outfile="$4"

    local all_log="${outfile}.all"
    local global_error_log="${outfile}.global-unmatched"
    local dev_re hctl_re current_disk_re kernel_error_re

    dev_re="$(regex_escape "$devbase")"
    hctl_re="$(regex_escape "$hctl")"

    if command -v journalctl >/dev/null 2>&1; then
        journalctl -k --since "$since" --no-pager 2>/dev/null > "$all_log" || true
    else
        dmesg -T 2>/dev/null > "$all_log" || true
    fi

    : > "$outfile"
    : > "$global_error_log"

    # 当前盘严格匹配规则：
    #   [sdl]
    #   sdl:
    #   dev sdl
    #   sd 0:0:74:0:   其中 0:0:74:0 必须等于该盘当前 HCTL
    # 不能只因为日志里有 timeout/reset/I/O error 就归属到当前盘。
    if [[ -n "$hctl" ]]; then
        current_disk_re="(\[$dev_re\]|(^|[[:space:]])$dev_re:[[:space:]]|(^|[[:space:]])dev[[:space:]]+$dev_re([^[:alnum:]_]|$)|(^|[[:space:]])sd[[:space:]]+$hctl_re:[[:space:]])"
    else
        current_disk_re="(\[$dev_re\]|(^|[[:space:]])$dev_re:[[:space:]]|(^|[[:space:]])dev[[:space:]]+$dev_re([^[:alnum:]_]|$))"
    fi

    # 只把明确属于当前盘的日志放进 kernel-errors.txt。
    grep -Ei "$current_disk_re" "$all_log" > "$outfile" || true

    # 全局错误只保存，不参与当前盘判定。
    kernel_error_re="I/O error|Buffer I/O|blk_update_request|medium error|Medium Error|Hardware Error|uncorrect|Unrecovered|read error|write error|end_request|rejecting I/O|device offline|offline device|DID_TIME_OUT|DID_ERROR|DID_BAD_TARGET|hostbyte=|driverbyte=|sense key|failed command|attempting task abort|task abort|abort command|timed out|timeout|resetting link|hard resetting link|COMRESET failed|link is slow to respond|frozen|Power-on or device reset occurred|device_block|device_unblock|reset occurred"

    grep -Ei "$kernel_error_re" "$all_log" | grep -Eiv "$current_disk_re" > "$global_error_log" || true
}

# -----------------------------------------------------------------------------
# 函数: trim_disk_after_test
# 功能: 测试完成后对硬盘执行 TRIM/DISCARD，并记录状态
# 参数: $1 - 整盘设备路径
#       $2 - 该盘的报告输出目录
# 返回值: 0 - 始终成功 (TRIM 失败也不影响主流程，由 status 文件记录)
# 说明: 写入 trim-status.txt 取值 SKIP/OK/FAIL；SKIP 包括 --no-trim、
#       缺少 blkdiscard、硬盘不支持 DISCARD 等情况。
# -----------------------------------------------------------------------------
trim_disk_after_test() {
    local dev="$1"
    local dir="$2"
    local trim_log="$dir/trim.log"
    local trim_status="$dir/trim-status.txt"

    if [[ "$DO_TRIM" != "1" ]]; then
        echo "SKIP" > "$trim_status"
        echo "用户指定 --no-trim，跳过 TRIM / DISCARD" > "$trim_log"
        return 0
    fi

    echo "开始对 $dev 执行 TRIM / DISCARD" > "$trim_log"

    if ! command -v blkdiscard >/dev/null 2>&1; then
        echo "SKIP" > "$trim_status"
        echo "系统缺少 blkdiscard 命令，跳过" >> "$trim_log"
        return 0
    fi

    if ! disk_supports_discard "$dev"; then
        echo "SKIP" > "$trim_status"
        echo "$dev 不支持 DISCARD/TRIM，跳过" >> "$trim_log"
        return 0
    fi

    sync
    blockdev --flushbufs "$dev" >> "$trim_log" 2>&1 || true

    blkdiscard -f -v "$dev" >> "$trim_log" 2>&1
    local rc=$?

    sync
    blockdev --flushbufs "$dev" >> "$trim_log" 2>&1 || true

    if [[ "$rc" -eq 0 ]]; then
        echo "OK" > "$trim_status"
        echo "$dev TRIM / DISCARD 完成" >> "$trim_log"
    else
        echo "FAIL" > "$trim_status"
        echo "$dev TRIM / DISCARD 失败，返回码: $rc" >> "$trim_log"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# 函数: meta_set
# 功能: 向 meta.tsv 追加一行键值记录 (tab 分隔)
# 参数: $1 - meta.tsv 文件路径
#       $2 - 键
#       $@ - 值 (允许多个，会以空格拼接)
# 返回值: 0 - 始终成功
# -----------------------------------------------------------------------------
meta_set() {
    local file="$1"
    local key="$2"
    shift 2
    local value="$*"

    printf '%s\t%s\n' "$key" "$value" >> "$file"
}

# -----------------------------------------------------------------------------
# 函数: meta_get
# 功能: 从 meta.tsv 中读取指定键的值
# 参数: $1 - 报告目录 (包含 meta.tsv)
#       $2 - 键名
# 返回值: 0 - 始终成功；标准输出对应键的值 (未找到时输出空)
# -----------------------------------------------------------------------------
meta_get() {
    local dir="$1"
    local key="$2"

    awk -F '\t' -v k="$key" '
        $1 == k {
            sub(/^[^\t]*\t/, "")
            print
            exit
        }
    ' "$dir/meta.tsv" 2>/dev/null
}

# -----------------------------------------------------------------------------
# 函数: build_device_list
# 功能: 构建待测试的硬盘列表 (逐行输出设备路径)
# 参数: 无 (读取全局 DEVICES/EXCLUDE_DEVICES)
# 返回值: 0 - 始终成功；标准输出每行一个设备路径
# 说明: 指定 --devices 时校验每个设备；否则自动遍历所有整盘，跳过
#       排除盘/只读盘/已挂载盘/容量异常盘。
# -----------------------------------------------------------------------------
build_device_list() {
    local result=()

    if [[ -n "$DEVICES" ]]; then
        IFS=',' read -r -a input_devs <<< "$DEVICES"

        for dev in "${input_devs[@]}"; do
            dev="$(echo "$dev" | sed 's/^ *//; s/ *$//')"
            [[ -n "$dev" ]] || continue

            if [[ ! -b "$dev" ]]; then
                log "跳过不存在或不是块设备: $dev"
                continue
            fi

            if device_is_excluded "$dev"; then
                log "跳过排除盘: $dev"
                continue
            fi

            if disk_is_readonly "$dev"; then
                log "跳过只读盘: $dev"
                continue
            fi

            if disk_has_mountpoint "$dev"; then
                log "跳过已挂载/系统相关硬盘: $dev"
                continue
            fi

            result+=("$dev")
        done

        ((${#result[@]})) && printf '%s\n' "${result[@]}"
        return
    fi

    while read -r dev; do
        [[ -b "$dev" ]] || continue

        if device_is_excluded "$dev"; then
            log "跳过排除盘: $dev"
            continue
        fi

        if disk_is_readonly "$dev"; then
            log "跳过只读盘: $dev"
            continue
        fi

        if disk_has_mountpoint "$dev"; then
            log "跳过已挂载/系统相关硬盘: $dev"
            continue
        fi

        local size
        size="$(disk_size_bytes "$dev")"

        if [[ "$size" -le 0 ]]; then
            log "跳过容量异常硬盘: $dev"
            continue
        fi

        result+=("$dev")
    done < <(netool_lsblk_disk_paths)

    ((${#result[@]})) && printf '%s\n' "${result[@]}"
}

# -----------------------------------------------------------------------------
# 函数: run_one_disk
# 功能: 对单块硬盘执行完整的写入+读回校验测试流程
# 参数: $1 - 整盘设备路径
# 返回值: 0 - 始终成功 (测试结果通过 status.txt 与 meta.tsv 记录)
# 说明: 流程包括 SMART 前/后采集、fio 全盘 verify、TRIM、内核日志归属、
#       结果判定 (PASS/FAIL/RETEST/WARN)。该函数通常以后台方式调用。
# -----------------------------------------------------------------------------
run_one_disk() {
    local dev="$1"
    local rdev base dir meta

    rdev="$(real_dev "$dev")"
    base="$(basename "$rdev")"
    dir="$OUT_BASE/$base"
    meta="$dir/meta.tsv"

    mkdir -p -m 700 "$dir"
    : > "$meta"

    local start_time
    start_time="$(date '+%F %T')"

    local size_bytes size_human model serial tran hctl
    size_bytes="$(disk_size_bytes "$dev")"
    size_human="$(human_size "$size_bytes")"
    model="$(disk_model "$dev")"
    serial="$(disk_serial "$dev")"
    tran="$(disk_tran "$dev")"
    hctl="$(disk_hctl "$dev")"

    meta_set "$meta" "device" "$dev"
    meta_set "$meta" "real_device" "$rdev"
    meta_set "$meta" "base" "$base"
    meta_set "$meta" "hctl" "$hctl"
    meta_set "$meta" "model" "$model"
    meta_set "$meta" "serial" "$serial"
    meta_set "$meta" "transport" "$tran"
    meta_set "$meta" "size_bytes" "$size_bytes"
    meta_set "$meta" "size_human" "$size_human"
    meta_set "$meta" "start_time" "$start_time"
    meta_set "$meta" "jobs_per_disk" "$JOBS_PER_DISK"
    meta_set "$meta" "bs" "$BS"
    meta_set "$meta" "iodepth" "$IODEPTH"
    meta_set "$meta" "trim_enabled" "$DO_TRIM"

    log "开始测试 $dev HCTL=[$hctl] 型号=[$model] 序列号=[$serial] 容量=$size_human"

    smart_dump "$dev" "$dir/smart-before.txt"

    local fio_log="$dir/fio.log"
    local kernel_log="$dir/kernel-errors.txt"
    local status_file="$dir/status.txt"

    sync
    # drop_caches 失败时打印警告而不是静默忽略，避免影响读回校验准确性的判断
    if ! echo 3 > /proc/sys/vm/drop_caches 2>/dev/null; then
        log_warn "drop_caches 写入失败（非致命），可能影响读回校验准确性。"
    fi

    local fio_rc=0

    # 单盘 fio writer 数量取自 JOBS_PER_DISK (脚本上方已自动降级为 1)，
    # 避免 verify 模式多 writer 互相覆盖导致误判。
    fio \
      --name="full_rw_verify_${base}" \
      --filename="$dev" \
      --direct=1 \
      --ioengine=libaio \
      --thread=1 \
      --rw=write \
      --bs="$BS" \
      --iodepth="$IODEPTH" \
      --numjobs="${JOBS_PER_DISK}" \
      --size=100% \
      --verify=crc32c \
      --do_verify=1 \
      --verify_fatal=1 \
      --verify_dump=1 \
      --verify_state_save=0 \
      --group_reporting=1 \
      --eta=always \
      --output="$fio_log" \
      --output-format=normal || fio_rc=$?

    sync

    trim_disk_after_test "$dev" "$dir"

    smart_dump "$dev" "$dir/smart-after.txt"
    kernel_errors_since "$start_time" "$base" "$hctl" "$kernel_log"

    local end_time
    end_time="$(date '+%F %T')"

    meta_set "$meta" "end_time" "$end_time"
    meta_set "$meta" "fio_rc" "$fio_rc"

    local trim_result
    trim_result="$(cat "$dir/trim-status.txt" 2>/dev/null || echo UNKNOWN)"
    meta_set "$meta" "trim_result" "$trim_result"

    local direct_disk_error=0
    local kernel_soft_event=0
    local fio_verify_error=0
    local fio_io_error=0
    local result reason

    if grep -Eiq "verify.*failed|bad magic header|crc.*error|verify: bad|data mismatch|miscompare" "$fio_log" 2>/dev/null; then
        fio_verify_error=1
    fi

    if grep -Eiq "io_u error|Input/output error|No such device|device offline|Resource temporarily unavailable|Operation not permitted" "$fio_log" 2>/dev/null; then
        fio_io_error=1
    fi

    # kernel_log 只包含明确匹配当前盘名或当前盘 HCTL 的日志。
    # kernel-errors.txt.global-unmatched 里的全局错误不参与当前盘判定。
    if [[ -s "$kernel_log" ]]; then
        # 严重错误：只有当前盘日志里出现这些，才判 FAIL。
        if grep -Eiq \
            "I/O error|Buffer I/O|blk_update_request|medium error|Medium Error|Hardware Error|uncorrect|Unrecovered|read error|write error|end_request|rejecting I/O|device offline|offline device|DID_TIME_OUT|DID_ERROR|DID_BAD_TARGET|hostbyte=|driverbyte=|sense key|failed command|attempting task abort|task abort|abort command|timed out|timeout|COMRESET failed|link is slow to respond|frozen" \
            "$kernel_log"; then
            direct_disk_error=1
        fi

        # 软事件：不判 FAIL，只 WARN。
        if grep -Eiq \
            "Power-on or device reset occurred|device_block|device_unblock|device reset occurred|reset occurred" \
            "$kernel_log"; then
            kernel_soft_event=1
        fi
    fi

    if [[ "$direct_disk_error" -eq 1 ]]; then
        result="FAIL"
        reason="当前盘内核日志明确出现严重 I/O/介质/超时/离线/abort 错误"
    elif [[ "$fio_verify_error" -eq 1 ]]; then
        result="FAIL"
        reason="fio 日志发现数据校验失败/CRC/miscompare，属于该盘数据一致性错误"
    elif [[ "$fio_rc" -ne 0 ]]; then
        result="RETEST"
        if [[ "$fio_io_error" -eq 1 ]]; then
            reason="fio 返回错误码 $fio_rc 且出现 I/O 错误，但当前盘内核日志没有明确严重错误；不直接判坏，建议单盘重测"
        else
            reason="fio 返回错误码 $fio_rc，但当前盘内核日志没有明确严重错误；不直接判坏，建议单盘重测"
        fi
    elif [[ "$trim_result" == "FAIL" ]]; then
        result="WARN"
        reason="fio 校验通过，但 TRIM / DISCARD 执行失败"
    elif [[ "$kernel_soft_event" -eq 1 ]]; then
        result="WARN"
        reason="fio 校验通过，但当前盘出现 reset/block/unblock 软事件；不直接判坏，建议复测或检查背板/线缆/HBA"
    else
        result="PASS"
        reason="fio 全盘写入+读回校验完成，且当前盘没有明确严重内核磁盘错误"
    fi

    meta_set "$meta" "direct_disk_error" "$direct_disk_error"
    meta_set "$meta" "kernel_soft_event" "$kernel_soft_event"
    meta_set "$meta" "fio_verify_error" "$fio_verify_error"
    meta_set "$meta" "fio_io_error" "$fio_io_error"

    {
        echo "$result"
        echo "$reason"
    } > "$status_file"

    log "完成测试 $dev 结果=$result TRIM=$trim_result 原因=$reason"
}

# -----------------------------------------------------------------------------
# 函数: wait_for_slot
# 功能: 等待出现空闲的并发槽位 (后台任务数 < DISK_CONCURRENCY)
# 参数: 无
# 返回值: 0 - 始终成功 (有空闲槽位时返回)
# 说明: 通过 jobs -rp 统计当前后台任务数，每 5 秒轮询一次。
# -----------------------------------------------------------------------------
wait_for_slot() {
    while true; do
        local running
        running="$(jobs -rp | wc -l)"

        if [[ "$running" -lt "$DISK_CONCURRENCY" ]]; then
            break
        fi

        sleep 5
    done
}

# -----------------------------------------------------------------------------
# 函数: generate_report
# 功能: 汇总所有测试硬盘的元数据与状态，生成 Markdown 报告
# 参数: 无 (读取全局 OUT_BASE)
# 返回值: 0 - 始终成功；标准输出报告文件路径
# 说明: 报告包含判定规则、内核日志归属规则、总览表格和每块盘详情
#       (SMART 关键项、TRIM 日志、fio 日志尾部、内核日志归属等)。
# -----------------------------------------------------------------------------
generate_report() {
    local report="$OUT_BASE/report.md"

    {
        echo "# 硬盘全盘读写校验测试报告"
        echo
        echo "- 生成时间: $(date '+%F %T')"
        echo "- 主机名: $(hostname)"
        echo "- 内核: $(uname -a)"
        echo "- 输出目录: \`$OUT_BASE\`"
        echo "- 多盘并发数: \`$DISK_CONCURRENCY\`"
        echo "- 单盘 fio 线程数: \`$JOBS_PER_DISK\`"
        echo "- fio bs: \`$BS\`"
        echo "- fio iodepth: \`$IODEPTH\`"
        echo "- 测试后 TRIM/DISCARD: \`$DO_TRIM\`"
        echo "- 排除设备: \`${EXCLUDE_DEVICES:-无}\`"
        echo
        echo "> 注意：本测试为全盘破坏性写入测试，被测盘原数据已经被覆盖。"
        echo
        echo "## 判定规则"
        echo
        echo "- **PASS**: fio 写入+读回校验通过，且当前盘没有明确严重内核磁盘错误。"
        echo "- **FAIL**: 当前盘内核日志明确出现严重 I/O/介质/超时/离线/abort 错误，或 fio 发现校验/数据不一致错误。"
        echo "- **RETEST**: fio 返回错误，但当前盘内核日志没有明确严重错误；不直接判坏，建议单盘重测。"
        echo "- **WARN**: fio 通过，但 TRIM/DISCARD 失败，或者当前盘只有 reset/block/unblock 软事件。"
        echo
        echo "## 内核日志归属规则"
        echo
        echo "只有明确匹配当前盘的日志才参与该盘判定，例如："
        echo
        echo "- \`[sdl]\`"
        echo "- \`sdl:\`"
        echo "- \`dev sdl\`"
        echo "- \`sd 0:0:74:0:\`，其中 \`0:0:74:0\` 必须等于该盘当前 HCTL"
        echo
        echo "全局错误会保存到 \`kernel-errors.txt.global-unmatched\`，但不会影响该盘结果。"
        echo
        echo "## 总览"
        echo
        echo "| 设备 | HCTL | 结果 | TRIM | 容量 | 型号 | 序列号 | 原因 | 日志目录 |"
        echo "|---|---|---:|---:|---:|---|---|---|---|"

        local dir
        for dir in "$OUT_BASE"/*; do
            [[ -d "$dir" ]] || continue
            [[ -f "$dir/meta.tsv" ]] || continue

            local device hctl model serial size_human result reason trim_result
            device="$(meta_get "$dir" device)"
            hctl="$(meta_get "$dir" hctl)"
            model="$(meta_get "$dir" model)"
            serial="$(meta_get "$dir" serial)"
            size_human="$(meta_get "$dir" size_human)"
            trim_result="$(cat "$dir/trim-status.txt" 2>/dev/null || echo UNKNOWN)"
            result="$(sed -n '1p' "$dir/status.txt" 2>/dev/null || echo UNKNOWN)"
            reason="$(sed -n '2p' "$dir/status.txt" 2>/dev/null || echo '')"

            echo "| \`$device\` | \`${hctl:-未知}\` | **$result** | $trim_result | $size_human | ${model:-未知} | ${serial:-未知} | $reason | \`$dir\` |"
        done

        echo
        echo "## 每块盘详情"
        echo

        for dir in "$OUT_BASE"/*; do
            [[ -d "$dir" ]] || continue
            [[ -f "$dir/meta.tsv" ]] || continue

            local device real_device hctl model serial tran size_human start_time end_time fio_rc trim_result result reason
            local direct_disk_error kernel_soft_event fio_verify_error fio_io_error

            device="$(meta_get "$dir" device)"
            real_device="$(meta_get "$dir" real_device)"
            hctl="$(meta_get "$dir" hctl)"
            model="$(meta_get "$dir" model)"
            serial="$(meta_get "$dir" serial)"
            tran="$(meta_get "$dir" transport)"
            size_human="$(meta_get "$dir" size_human)"
            start_time="$(meta_get "$dir" start_time)"
            end_time="$(meta_get "$dir" end_time)"
            fio_rc="$(meta_get "$dir" fio_rc)"
            trim_result="$(cat "$dir/trim-status.txt" 2>/dev/null || echo UNKNOWN)"
            result="$(sed -n '1p' "$dir/status.txt" 2>/dev/null || echo UNKNOWN)"
            reason="$(sed -n '2p' "$dir/status.txt" 2>/dev/null || echo '')"
            direct_disk_error="$(meta_get "$dir" direct_disk_error)"
            kernel_soft_event="$(meta_get "$dir" kernel_soft_event)"
            fio_verify_error="$(meta_get "$dir" fio_verify_error)"
            fio_io_error="$(meta_get "$dir" fio_io_error)"

            echo "### $device"
            echo
            echo "- 真实设备: \`${real_device:-未知}\`"
            echo "- HCTL: \`${hctl:-未知}\`"
            echo "- 结果: **$result**"
            echo "- 原因: $reason"
            echo "- TRIM / DISCARD: $trim_result"
            echo "- 型号: ${model:-未知}"
            echo "- 序列号: ${serial:-未知}"
            echo "- 接口类型: ${tran:-未知}"
            echo "- 容量: $size_human"
            echo "- 开始时间: ${start_time:-未知}"
            echo "- 结束时间: ${end_time:-未知}"
            echo "- fio 返回码: ${fio_rc:-未知}"
            echo "- direct_disk_error: ${direct_disk_error:-未知}"
            echo "- kernel_soft_event: ${kernel_soft_event:-未知}"
            echo "- fio_verify_error: ${fio_verify_error:-未知}"
            echo "- fio_io_error: ${fio_io_error:-未知}"
            echo
            echo "#### SMART 测试前关键项"
            echo
            echo '```text'
            smart_summary_lines "$dir/smart-before.txt"
            echo '```'
            echo
            echo "#### SMART 测试后关键项"
            echo
            echo '```text'
            smart_summary_lines "$dir/smart-after.txt"
            echo '```'
            echo
            echo "#### TRIM / DISCARD 日志"
            echo
            echo '```text'
            if [[ -s "$dir/trim.log" ]]; then
                cat "$dir/trim.log"
            else
                echo "无 TRIM 日志"
            fi
            echo '```'
            echo
            echo "#### fio 日志尾部"
            echo
            echo '```text'
            tail -n 120 "$dir/fio.log" 2>/dev/null || true
            echo '```'
            echo
            echo "#### 测试期间该盘匹配到的内核日志"
            echo
            echo '```text'
            if [[ -s "$dir/kernel-errors.txt" ]]; then
                cat "$dir/kernel-errors.txt"
            else
                echo "未发现该盘直接相关内核日志"
            fi
            echo '```'
            echo
            echo "#### 测试期间全局未归属错误日志"
            echo
            echo '```text'
            if [[ -s "$dir/kernel-errors.txt.global-unmatched" ]]; then
                tail -n 120 "$dir/kernel-errors.txt.global-unmatched"
            else
                echo "未发现全局未归属错误日志"
            fi
            echo '```'
            echo
            echo "#### 原始日志文件"
            echo
            echo "- SMART 前: \`$dir/smart-before.txt\`"
            echo "- SMART 后: \`$dir/smart-after.txt\`"
            echo "- fio 日志: \`$dir/fio.log\`"
            echo "- TRIM 日志: \`$dir/trim.log\`"
            echo "- 当前盘匹配内核日志: \`$dir/kernel-errors.txt\`"
            echo "- 测试期间完整内核日志窗口: \`$dir/kernel-errors.txt.all\`"
            echo "- 全局未归属错误日志: \`$dir/kernel-errors.txt.global-unmatched\`"
            echo
        done
    } > "$report"

    echo "$report"
}

# -----------------------------------------------------------------------------
# 函数: main
# 功能: 脚本主入口，加载公共函数库、获取锁、构建测试盘列表并并发执行
# 参数: 无 (通过全局变量传递已解析的命令行参数)
# 返回值: 0 - 成功；1 - 锁获取失败或无可用测试盘
# 说明: 预览模式只列出目标盘后退出；正式模式按 DISK_CONCURRENCY 并发
#       调用 run_one_disk，全部完成后生成 Markdown 报告。
# -----------------------------------------------------------------------------
main() {
    # shellcheck source=../load_common.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
    netool_acquire_lock "disk-test" "另一个 disk-test 实例正在运行，请等待其完成后再试。" || exit 1

    if [[ "$PLAN_ONLY" != "1" ]]; then
        log "输出目录: $OUT_BASE"
    fi

    netool_mapfile TEST_DEVS < <(build_device_list)

    if [[ "${#TEST_DEVS[@]}" -eq 0 ]]; then
        echo "没有找到可测试硬盘。"
        echo "默认会跳过系统盘、已挂载盘、只读盘和 --exclude 指定的盘。"
        echo
        echo "如确认要测试指定盘，请先预览:"
        echo "  $0 --plan --devices /dev/sdb,/dev/sdc"
        exit 1
    fi

    echo
    if [[ "$PLAN_ONLY" == "1" ]]; then
        echo "预览：以下硬盘会被全盘写入测试并清空数据:"
    else
        echo "即将执行全盘破坏性读写校验，以下硬盘会被清空:"
    fi
    echo

    local dev size model serial hctl
    for dev in "${TEST_DEVS[@]}"; do
        size="$(human_size "$(disk_size_bytes "$dev")")"
        model="$(disk_model "$dev")"
        serial="$(disk_serial "$dev")"
        hctl="$(disk_hctl "$dev")"
        echo "  $dev  HCTL=[$hctl]  容量=$size  型号=[$model]  序列号=[$serial]"
    done

    echo
    echo "多盘并发: $DISK_CONCURRENCY"
    echo "单盘 fio 线程: $JOBS_PER_DISK"
    echo "块大小: $BS"
    echo "iodepth: $IODEPTH"
    echo "测完 TRIM/DISCARD: $DO_TRIM"
    echo "排除设备: ${EXCLUDE_DEVICES:-无}"
    echo
    if [[ "$PLAN_ONLY" == "1" ]]; then
        echo "当前是预览模式，没有写入任何数据。"
        echo "真正执行前请再次确认目标盘，命令需带 --yes。"
        exit 0
    fi

    echo "再次提醒：这是破坏性全盘写入测试，被测盘数据会被清空。"
    echo

    for dev in "${TEST_DEVS[@]}"; do
        wait_for_slot
        run_one_disk "$dev" &
    done

    wait

    local report
    report="$(generate_report)"

    echo
    echo "测试完成。"
    echo "报告文件: $report"
    echo "完整日志目录: $OUT_BASE"
}

main
