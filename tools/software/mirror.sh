#!/usr/bin/env bash
# =============================================================================
# netool懒人工具箱 - 软件源一键换源/恢复脚本
# =============================================================================
# 项目名称: netool懒人工具箱 (netool)
# 脚本名称: mirror.sh
# 脚本版本: 1.0
# 项目地址: https://gitee.com/suser747/netool
#
# 功能说明:
#   面向主流 Linux 发行版的安全换源与回滚脚本，支持自动识别系统与包管理器，
#   覆盖 APT / YUM / DNF / Pacman / APK / Zypper 多种包管理生态。
#   换源前会在 /var/backups/<脚本名>/<时间戳>/ 目录下完整备份原始源配置，
#   并写入 .backup-info 元信息；提供 --restore / --restore-from 一键回滚。
# 使用方式:
#   curl -fsSL <SCRIPT_URL> | bash
#   bash <(curl -fsSL <SCRIPT_URL>) [选项]
# 选项（详见 usage）:
#   --mirror <name>      指定镜像站
#   --lang <zh|en>       输出语言
#   --dry-run            预演模式
#   --skip-refresh       跳过包索引刷新
#   --skip-backup        跳过备份
#   --restore            从最近一次备份恢复
#   --restore-from <dir> 从指定备份目录恢复
#   --list-backups       列出当前可用备份目录
#   -y, --yes            非交互模式
#
# 退出码:
#   0 - 成功
#   1 - 一般错误（参数错误、权限不足、换源/恢复失败等）
# =============================================================================

set -Eeuo pipefail

SCRIPT_NAME="linux-mirror-switcher"
SCRIPT_VERSION="1.0"
DEFAULT_MIRROR="tencent"
REPO_URL="https://gitee.com/suser747/netool"
SCRIPT_URL="https://gitee.com/suser747/netool/raw/master/tools/software/mirror.sh"
# 备份根目录：每次换源在此目录下创建 <YYYYMMDD-HHMMSS> 时间戳子目录
BACKUP_ROOT="/var/backups/${SCRIPT_NAME}"
# 备份目录内的元信息文件名，记录脚本名、版本、镜像站、包管理器等关键信息
BACKUP_METADATA_NAME=".backup-info"

MIRROR=""
ACTION="switch"
RESTORE_SOURCE=""
NON_INTERACTIVE=0
DRY_RUN=0
SKIP_REFRESH=0
SKIP_BACKUP=0
BACKUP_DIR=""
BACKUP_METADATA_WRITTEN=0
OUTPUT_LANG="zh"

OS_ID=""
OS_PRETTY=""
PACKAGE_MANAGER=""
CURRENT_MIRROR_ID=""
AFFECTED_FILES=0
SKIPPED_RESTORE_FILES=0
REFRESH_RAN=0
CURRENT_STEP=0
TOTAL_STEPS=0

# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR

# 函数: is_lang_en
# 功能: 判断当前输出语言是否为英文
# 参数: 无
# 返回值: 0 - 当前为英文, 1 - 当前为中文
is_lang_en() {
  [[ "$OUTPUT_LANG" == "en" ]]
}

# 函数: text
# 功能: 多语言文本取值，根据当前语言（zh/en）返回对应文案；未命中的 key 原样返回
# 参数: $1 - 文本 key（如 tag_info、banner_subtitle、error_need_root 等）
# 返回值: 始终 0（结果通过 stdout 输出）
text() {
  local key="$1"

  if is_lang_en; then
    case "$key" in
      tag_info) printf "INFO" ;;
      tag_success) printf " OK " ;;
      tag_warn) printf "WARN" ;;
      tag_error) printf "ERR " ;;
      tag_dry) printf "DRY " ;;
      banner_subtitle) printf "netool | Mirror Switcher" ;;
      section_runtime_summary) printf "Runtime Summary" ;;
      section_summary) printf "Summary" ;;
      section_inspecting_system) printf "Inspecting System" ;;
      section_preparing_restore) printf "Preparing Restore" ;;
      section_restoring_files) printf "Restoring Files" ;;
      section_refreshing_pkg_meta) printf "Refreshing Package Metadata" ;;
      section_preparing_switch) printf "Preparing Switch" ;;
      section_switching_repo_config) printf "Switching Repository Configuration" ;;
      label_action) printf "Action" ;;
      label_mode) printf "Mode" ;;
      label_mirror) printf "Mirror" ;;
      label_system) printf "System" ;;
      label_package_manager) printf "Package mgr" ;;
      label_backup_root) printf "Backup root" ;;
      label_script_url) printf "Script URL" ;;
      label_restore_from) printf "Restore from" ;;
      label_result) printf "Result" ;;
      label_affected) printf "Affected" ;;
      label_refresh) printf "Refresh" ;;
      label_backup) printf "Backup" ;;
      label_skipped) printf "Skipped" ;;
      label_created_at) printf "created_at" ;;
      label_meta_mirror) printf "mirror" ;;
      label_meta_manager) printf "manager" ;;
      label_unknown) printf "unknown" ;;
      mode_live) printf "live" ;;
      mode_dry_run) printf "dry-run" ;;
      action_switch) printf "switch" ;;
      action_restore) printf "restore" ;;
      result_success) printf "success" ;;
      refresh_completed) printf "completed" ;;
      refresh_skipped) printf "skipped" ;;
      backup_not_created) printf "not created" ;;
      backup_not_applicable) printf "not applicable" ;;
      backup_disabled) printf "disabled" ;;
      latest_backup) printf "latest backup" ;;
      error_script_failed) printf "Script failed near line %s with exit code %s" ;;
      error_need_root) printf "Root privileges are required. Run as root or prepend sudo yourself." ;;
      error_unsupported_mirror_mapping) printf "Unsupported mirror mapping: %s:%s" ;;
      error_no_backup_dirs) printf "No backup directories found at %s" ;;
      info_would_write_backup_metadata) printf "Would write backup metadata to %s" ;;
      error_backup_dir_missing) printf "Backup directory does not exist: %s" ;;
      error_backup_root_missing) printf "No backup root found at %s" ;;
      error_no_backup_for_restore) printf "No backup directories are available for restore" ;;
      warn_skip_restore_target) printf "Skipping unsupported restore target: %s" ;;
      error_no_files_in_backup) printf "No files were found in backup directory %s" ;;
      success_restored_files) printf "Restored %s file(s)" ;;
      warn_skipped_restore_targets) printf "Skipped %s unsupported restore target(s)" ;;
      error_os_release_missing) printf "Unable to detect the system: /etc/os-release was not found" ;;
      error_unsupported_package_manager) printf "Unsupported package manager" ;;
      error_no_apt_sources) printf "No APT source files were found under /etc/apt" ;;
      error_no_known_apt_entries) printf "No supported APT repository entries were detected in the current source files" ;;
      success_apt_switched) printf "APT sources switched to %s (%s file(s))" ;;
      error_no_rpm_sources) printf "No YUM/DNF repository files were found under /etc/yum.repos.d" ;;
      error_no_known_rpm_entries) printf "No supported YUM/DNF repository entries were detected in the current repo files" ;;
      success_rpm_switched) printf "YUM/DNF repositories switched to %s (%s file(s))" ;;
      error_file_not_found) printf "File not found: %s" ;;
      info_would_prepend_arch) printf "Would prepend Arch mirror %s\\$repo/os/\\$arch" ;;
      success_pacman_updated) printf "Pacman mirrorlist updated" ;;
      success_apk_switched) printf "APK repositories switched to %s" ;;
      error_no_zypper_sources) printf "No zypper repository files were found under /etc/zypp/repos.d" ;;
      success_zypper_switched) printf "Zypper repositories switched to %s (%s file(s))" ;;
      error_refresh_not_supported) printf "Refresh is not supported for package manager %s" ;;
      error_refresh_failed) printf "Package index refresh failed for %s" ;;
      success_refresh_completed) printf "Package index refresh completed" ;;
      error_mirror_requires_value) printf "--mirror requires a value" ;;
      error_restore_from_requires_dir) printf "--restore-from requires a directory" ;;
      error_unknown_argument) printf "Unknown argument: %s" ;;
      error_unsupported_mirror) printf "Unsupported mirror: %s" ;;
      error_mirror_missing_coverage) printf "Mirror %s does not cover the repository types required by the current system: %s" ;;
      info_mirror_recommendation) printf "Choose a wider-coverage mirror such as tencent, huawei, or nju, or run --list-mirrors for details" ;;
      error_switch_not_supported) printf "Package manager %s is not supported for switching" ;;
      info_restore_source) printf "Restore source: %s" ;;
      prompt_restore_confirm) printf "Restore package source configuration from backup?" ;;
      warn_refresh_skipped) printf "Package index refresh was skipped" ;;
      success_restore_completed) printf "Package source restore completed" ;;
      info_target_mirror) printf "Target mirror: %s" ;;
      warn_backup_disabled) printf "Backup is disabled for this run; restore will not be available for these changes" ;;
      prompt_switch_confirm) printf "Proceed to back up the current repository configuration and switch to the selected mirror?" ;;
      success_backup_saved) printf "Backup saved to %s" ;;
      success_switch_completed) printf "Mirror switch completed" ;;
      error_invalid_lang) printf "Unsupported language: %s (supported: zh, en)" ;;
      error_lang_requires_value) printf "--lang requires a value" ;;
      error_cancelled) printf "Cancelled" ;;
      label_yes_no) printf "[y/N]: " ;;
      *)
        printf "%s" "$key"
        ;;
    esac
  else
    case "$key" in
      tag_info) printf "信息" ;;
      tag_success) printf "完成" ;;
      tag_warn) printf "警告" ;;
      tag_error) printf "错误" ;;
      tag_dry) printf "预演" ;;
      banner_subtitle) printf "面向主流 Linux 发行版的安全换源与回滚脚本" ;;
      section_runtime_summary) printf "运行摘要" ;;
      section_summary) printf "执行结果" ;;
      section_inspecting_system) printf "系统检测" ;;
      section_preparing_restore) printf "准备恢复" ;;
      section_restoring_files) printf "恢复源配置文件" ;;
      section_refreshing_pkg_meta) printf "刷新软件包元数据" ;;
      section_preparing_switch) printf "准备换源" ;;
      section_switching_repo_config) printf "切换软件源配置" ;;
      label_action) printf "操作" ;;
      label_mode) printf "模式" ;;
      label_mirror) printf "镜像站" ;;
      label_system) printf "系统" ;;
      label_package_manager) printf "包管理器" ;;
      label_backup_root) printf "备份目录" ;;
      label_script_url) printf "脚本入口" ;;
      label_restore_from) printf "恢复来源" ;;
      label_result) printf "结果" ;;
      label_affected) printf "影响文件" ;;
      label_refresh) printf "索引刷新" ;;
      label_backup) printf "备份" ;;
      label_skipped) printf "跳过项目" ;;
      label_created_at) printf "创建时间" ;;
      label_meta_mirror) printf "镜像" ;;
      label_meta_manager) printf "包管理器" ;;
      label_unknown) printf "未知" ;;
      mode_live) printf "正式执行" ;;
      mode_dry_run) printf "预演" ;;
      action_switch) printf "换源" ;;
      action_restore) printf "恢复" ;;
      result_success) printf "成功" ;;
      refresh_completed) printf "已完成" ;;
      refresh_skipped) printf "已跳过" ;;
      backup_not_created) printf "未创建" ;;
      backup_not_applicable) printf "不适用" ;;
      backup_disabled) printf "已禁用" ;;
      latest_backup) printf "最近一次备份" ;;
      error_script_failed) printf "脚本在第 %s 行附近执行失败，退出码：%s" ;;
      error_need_root) printf "需要 root 权限运行；如果当前不是 root，请自行在前面加 sudo。" ;;
      error_unsupported_mirror_mapping) printf "不支持的镜像映射：%s:%s" ;;
      error_no_backup_dirs) printf "在 %s 下没有找到备份目录" ;;
      info_would_write_backup_metadata) printf "将写入备份元信息：%s" ;;
      error_backup_dir_missing) printf "备份目录不存在：%s" ;;
      error_backup_root_missing) printf "未找到备份根目录：%s" ;;
      error_no_backup_for_restore) printf "当前没有可用于恢复的备份目录" ;;
      warn_skip_restore_target) printf "跳过未受支持的恢复目标：%s" ;;
      error_no_files_in_backup) printf "备份目录 %s 中没有可恢复的文件" ;;
      success_restored_files) printf "已恢复 %s 个文件" ;;
      warn_skipped_restore_targets) printf "已跳过 %s 个未受支持的恢复目标" ;;
      error_os_release_missing) printf "无法识别当前系统：未找到 /etc/os-release" ;;
      error_unsupported_package_manager) printf "暂不支持当前包管理器" ;;
      error_no_apt_sources) printf "在 /etc/apt 下没有找到可处理的软件源文件" ;;
      error_no_known_apt_entries) printf "当前源配置中没有识别到受支持的 APT 仓库条目" ;;
      success_apt_switched) printf "APT 软件源已切换到 %s（共 %s 个文件）" ;;
      error_no_rpm_sources) printf "在 /etc/yum.repos.d 下没有找到可处理的仓库文件" ;;
      error_no_known_rpm_entries) printf "当前仓库配置中没有识别到受支持的 YUM/DNF 条目" ;;
      success_rpm_switched) printf "YUM/DNF 仓库地址已切换到 %s（共 %s 个文件）" ;;
      error_file_not_found) printf "文件不存在：%s" ;;
      info_would_prepend_arch) printf "将把 Arch 镜像 %s\\$repo/os/\\$arch 插入到镜像列表前部" ;;
      success_pacman_updated) printf "Pacman 镜像列表已更新" ;;
      success_apk_switched) printf "APK 仓库地址已切换到 %s" ;;
      error_no_zypper_sources) printf "在 /etc/zypp/repos.d 下没有找到可处理的仓库文件" ;;
      success_zypper_switched) printf "Zypper 仓库地址已切换到 %s（共 %s 个文件）" ;;
      error_refresh_not_supported) printf "当前包管理器 %s 不支持刷新索引" ;;
      error_refresh_failed) printf "包管理器 %s 刷新索引失败" ;;
      success_refresh_completed) printf "包索引刷新完成" ;;
      error_mirror_requires_value) printf "--mirror 需要指定一个值" ;;
      error_restore_from_requires_dir) printf "--restore-from 需要指定一个目录" ;;
      error_unknown_argument) printf "未知参数：%s" ;;
      error_unsupported_mirror) printf "不支持的镜像站：%s" ;;
      error_mirror_missing_coverage) printf "镜像站 %s 不覆盖当前系统所需的仓库类型：%s" ;;
      info_mirror_recommendation) printf "建议改用覆盖更完整的镜像站，例如 tencent、huawei、nju，或先执行 --list-mirrors 查看说明" ;;
      error_switch_not_supported) printf "当前包管理器 %s 暂不支持自动换源" ;;
      info_restore_source) printf "恢复来源：%s" ;;
      prompt_restore_confirm) printf "确认从备份恢复软件源配置吗？" ;;
      warn_refresh_skipped) printf "已跳过包索引刷新" ;;
      success_restore_completed) printf "软件源恢复完成" ;;
      info_target_mirror) printf "目标镜像站：%s" ;;
      warn_backup_disabled) printf "本次运行已禁用备份；此次改动将无法通过脚本自动回滚" ;;
      prompt_switch_confirm) printf "确认开始备份并切换到所选镜像站吗？" ;;
      success_backup_saved) printf "原始配置已备份到：%s" ;;
      success_switch_completed) printf "换源完成。" ;;
      error_invalid_lang) printf "不支持的语言：%s（支持：zh、en）" ;;
      error_lang_requires_value) printf "--lang 需要指定一个值" ;;
      error_cancelled) printf "已取消" ;;
      label_yes_no) printf "[y/N]: " ;;
      *)
        printf "%s" "$key"
        ;;
    esac
  fi
}

# 函数: fmt
# 功能: 多语言格式化输出，根据 key 取出格式串后用 printf 替换占位符；未命中的 key 原样返回
# 参数: $1 - 格式 key; $2..$N - 占位符对应的实参
# 返回值: 始终 0（结果通过 stdout 输出）
fmt() {
  local key="$1"
  shift
  local format=""

  if is_lang_en; then
    case "$key" in
      error_script_failed) format='Script failed near line %s with exit code %s' ;;
      error_unsupported_mirror_mapping) format='Unsupported mirror mapping: %s:%s' ;;
      error_no_backup_dirs) format='No backup directories found at %s' ;;
      info_would_write_backup_metadata) format='Would write backup metadata to %s' ;;
      error_backup_dir_missing) format='Backup directory does not exist: %s' ;;
      error_backup_root_missing) format='No backup root found at %s' ;;
      warn_skip_restore_target) format='Skipping unsupported restore target: %s' ;;
      error_no_files_in_backup) format='No files were found in backup directory %s' ;;
      success_restored_files) format='Restored %s file(s)' ;;
      warn_skipped_restore_targets) format='Skipped %s unsupported restore target(s)' ;;
      success_apt_switched) format='APT sources switched to %s (%s file(s))' ;;
      success_rpm_switched) format='YUM/DNF repositories switched to %s (%s file(s))' ;;
      error_file_not_found) format='File not found: %s' ;;
      info_would_prepend_arch) format='Would prepend Arch mirror %s\$repo/os/\$arch' ;;
      success_apk_switched) format='APK repositories switched to %s' ;;
      success_zypper_switched) format='Zypper repositories switched to %s (%s file(s))' ;;
      error_refresh_not_supported) format='Refresh is not supported for package manager %s' ;;
      error_refresh_failed) format='Package index refresh failed for %s' ;;
      error_unknown_argument) format='Unknown argument: %s' ;;
      error_unsupported_mirror) format='Unsupported mirror: %s' ;;
      error_mirror_missing_coverage) format='Mirror %s does not cover the repository types required by the current system: %s' ;;
      error_switch_not_supported) format='Package manager %s is not supported for switching' ;;
      info_restore_source) format='Restore source: %s' ;;
      info_target_mirror) format='Target mirror: %s' ;;
      success_backup_saved) format='Backup saved to %s' ;;
      error_invalid_lang) format='Unsupported language: %s (supported: zh, en)' ;;
      info_restore_hint) format='Restore the latest backup with: bash <(curl -fsSL %s) --restore -y' ;;
      info_restore_from_hint) format='Restore from this backup with: bash <(curl -fsSL %s) --restore-from %s -y' ;;
      info_list_backups_hint) format='List backups with: bash <(curl -fsSL %s) --list-backups' ;;
      *)
        printf "%s" "$key"
        return 0
        ;;
    esac
  else
    case "$key" in
      error_script_failed) format='脚本在第 %s 行附近执行失败，退出码：%s' ;;
      error_unsupported_mirror_mapping) format='不支持的镜像映射：%s:%s' ;;
      error_no_backup_dirs) format='在 %s 下没有找到备份目录' ;;
      info_would_write_backup_metadata) format='将写入备份元信息：%s' ;;
      error_backup_dir_missing) format='备份目录不存在：%s' ;;
      error_backup_root_missing) format='未找到备份根目录：%s' ;;
      warn_skip_restore_target) format='跳过未受支持的恢复目标：%s' ;;
      error_no_files_in_backup) format='备份目录 %s 中没有可恢复的文件' ;;
      success_restored_files) format='已恢复 %s 个文件' ;;
      warn_skipped_restore_targets) format='已跳过 %s 个未受支持的恢复目标' ;;
      success_apt_switched) format='APT 软件源已切换到 %s（共 %s 个文件）' ;;
      success_rpm_switched) format='YUM/DNF 仓库地址已切换到 %s（共 %s 个文件）' ;;
      error_file_not_found) format='文件不存在：%s' ;;
      info_would_prepend_arch) format='将把 Arch 镜像 %s\$repo/os/\$arch 插入到镜像列表前部' ;;
      success_apk_switched) format='APK 仓库地址已切换到 %s' ;;
      success_zypper_switched) format='Zypper 仓库地址已切换到 %s（共 %s 个文件）' ;;
      error_refresh_not_supported) format='当前包管理器 %s 不支持刷新索引' ;;
      error_refresh_failed) format='包管理器 %s 刷新索引失败' ;;
      error_unknown_argument) format='未知参数：%s' ;;
      error_unsupported_mirror) format='不支持的镜像站：%s' ;;
      error_mirror_missing_coverage) format='镜像站 %s 不覆盖当前系统所需的仓库类型：%s' ;;
      error_switch_not_supported) format='当前包管理器 %s 暂不支持自动换源' ;;
      info_restore_source) format='恢复来源：%s' ;;
      info_target_mirror) format='目标镜像站：%s' ;;
      success_backup_saved) format='原始配置已备份到：%s' ;;
      error_invalid_lang) format='不支持的语言：%s（支持：zh、en）' ;;
      info_restore_hint) format='如需恢复最近一次备份，可执行：bash <(curl -fsSL %s) --restore -y' ;;
      info_restore_from_hint) format='如需恢复这次备份，可执行：bash <(curl -fsSL %s) --restore-from %s -y' ;;
      info_list_backups_hint) format='如需查看备份列表，可执行：bash <(curl -fsSL %s) --list-backups' ;;
      *)
        printf "%s" "$key"
        return 0
        ;;
    esac
  fi

  printf "$format" "$@"
}

# 函数: count_label
# 功能: 按当前语言返回文件计数描述（如 "3 个文件" / "3 file(s)"）
# 参数: $1 - 文件数量
# 返回值: 始终 0（结果通过 stdout 输出）
count_label() {
  local count="$1"

  if is_lang_en; then
    printf "%s file(s)" "$count"
  else
    printf "%s 个文件" "$count"
  fi
}

# 函数: log_info
# 功能: 输出信息级日志（青色 [信息] 前缀）
# 参数: $1..$N - 日志内容
# 返回值: 始终 0
log_info() {
  printf "%s%s[%s]%s %s\n" "$COLOR_BOLD" "$COLOR_CYAN" "$(text tag_info)" "$COLOR_RESET" "$*"
}

# 函数: log_success
# 功能: 输出成功级日志（绿色 [完成] 前缀）
# 参数: $1..$N - 日志内容
# 返回值: 始终 0
log_success() {
  printf "%s%s[%s]%s %s\n" "$COLOR_BOLD" "$COLOR_GREEN" "$(text tag_success)" "$COLOR_RESET" "$*"
}

# 函数: log_warn
# 功能: 输出警告级日志（黄色 [警告] 前缀）
# 参数: $1..$N - 日志内容
# 返回值: 始终 0
log_warn() {
  printf "%s%s[%s]%s %s\n" "$COLOR_BOLD" "$COLOR_YELLOW" "$(text tag_warn)" "$COLOR_RESET" "$*"
}

# 函数: log_error
# 功能: 输出错误级日志（红色 [错误] 前缀），输出到 stderr
# 参数: $1..$N - 日志内容
# 返回值: 始终 0
log_error() {
  printf "%s%s[%s]%s %s\n" "$COLOR_BOLD" "$COLOR_RED" "$(text tag_error)" "$COLOR_RESET" "$*" >&2
}

# 函数: print_divider
# 功能: 打印一条分隔线（60 个连字符）
# 参数: 无
# 返回值: 始终 0
print_divider() {
  printf "%s\n" "------------------------------------------------------------"
}

# 函数: print_kv
# 功能: 以 "  key    value" 的固定宽度格式打印一行键值对
# 参数: $1 - 键; $2 - 值
# 返回值: 始终 0
print_kv() {
  printf "  %-16s %s\n" "$1" "$2"
}

# 函数: print_banner
# 功能: 打印脚本启动横幅（被 netool 主入口调用时跳过）
# 参数: 无
# 返回值: 始终 0
print_banner() {
  if [[ -n "${NETOOL:-}" ]]; then
    return 0
  fi

  print_divider
  printf "netool懒人工具箱 | 一键换源 v%s\n" "$SCRIPT_VERSION"
  printf "%s\n" "$(text banner_subtitle)"
  print_divider
}

# 函数: start_section
# 功能: 打印一级章节标题（蓝色 ==> 前缀）
# 参数: $1 - 章节标题文本
# 返回值: 始终 0
start_section() {
  printf "\n%s==>%s %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$1"
}

# 函数: reset_steps
# 功能: 重置步骤计数器，并根据是否跳过索引刷新计算总步骤数（3 或 4）
# 参数: 无
# 返回值: 始终 0（设置全局 CURRENT_STEP / TOTAL_STEPS）
reset_steps() {
  CURRENT_STEP=0
  if (( SKIP_REFRESH )); then
    TOTAL_STEPS=3
  else
    TOTAL_STEPS=4
  fi
}

# 函数: start_step
# 功能: 推进并打印当前步骤标题（蓝色 ==> [当前/总数] 标题）
# 参数: $1 - 步骤标题文本
# 返回值: 始终 0（自增全局 CURRENT_STEP）
start_step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf "\n%s==>%s [%s/%s] %s\n" "$COLOR_BLUE" "$COLOR_RESET" "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

# 函数: mode_label
# 功能: 返回当前运行模式文案（预演 / 正式执行）
# 参数: 无
# 返回值: 始终 0（结果通过 stdout 输出）
mode_label() {
  if (( DRY_RUN )); then
    printf "%s\n" "$(text mode_dry_run)"
  else
    printf "%s\n" "$(text mode_live)"
  fi
}

# 函数: action_label
# 功能: 返回当前操作类型文案（换源 / 恢复）
# 参数: 无
# 返回值: 始终 0（结果通过 stdout 输出）
action_label() {
  case "$ACTION" in
    switch)
      printf "%s\n" "$(text action_switch)"
      ;;
    restore)
      printf "%s\n" "$(text action_restore)"
      ;;
    *)
      printf "%s\n" "$ACTION"
      ;;
  esac
}

# 函数: selected_mirror_label
# 功能: 返回当前选中镜像站的展示文案；换源但未选镜像时返回"待选择"
# 参数: 无（依赖全局 ACTION / MIRROR）
# 返回值: 始终 0（结果通过 stdout 输出）
selected_mirror_label() {
  if [[ "$ACTION" == "switch" && -z "$MIRROR" ]]; then
    if is_lang_en; then
      printf "choose in script\n"
    else
      printf "待选择\n"
    fi
    return 0
  fi

  printf "%s\n" "$(mirror_display_name "$MIRROR")"
}

# 函数: current_source_label_title
# 功能: 返回"当前源"标题文案（按当前语言）
# 参数: 无
# 返回值: 始终 0（结果通过 stdout 输出）
current_source_label_title() {
  if is_lang_en; then
    printf "Current source"
  else
    printf "当前源"
  fi
}

# 函数: current_source_label
# 功能: 返回当前系统源识别结果文案（未识别 / 官方源 / 具体镜像名）
# 参数: 无（依赖全局 CURRENT_MIRROR_ID）
# 返回值: 始终 0（结果通过 stdout 输出）
current_source_label() {
  case "$CURRENT_MIRROR_ID" in
    "")
      if is_lang_en; then
        printf "not recognized"
      else
        printf "未识别"
      fi
      ;;
    official)
      if is_lang_en; then
        printf "official upstream"
      else
        printf "官方源"
      fi
      ;;
    *)
      printf "%s\n" "$(mirror_display_name "$CURRENT_MIRROR_ID")"
      ;;
  esac
}

# 函数: print_runtime_summary
# 功能: 打印运行前摘要，包括操作、模式、镜像站、当前源、系统、包管理器、备份目录、脚本入口等
# 参数: 无（依赖全局 ACTION / MIRROR / OS_PRETTY / PACKAGE_MANAGER 等）
# 返回值: 始终 0
print_runtime_summary() {
  start_section "$(text section_runtime_summary)"
  print_kv "$(text label_action)" "$(action_label)"
  print_kv "$(text label_mode)" "$(mode_label)"
  print_kv "$(text label_mirror)" "$(selected_mirror_label)"
  if [[ "$ACTION" == "switch" ]]; then
    print_kv "$(current_source_label_title)" "$(current_source_label)"
  fi
  print_kv "$(text label_system)" "$OS_PRETTY"
  print_kv "$(text label_package_manager)" "$PACKAGE_MANAGER"
  print_kv "$(text label_backup_root)" "$BACKUP_ROOT"
  print_kv "$(text label_script_url)" "$SCRIPT_URL"

  if [[ "$ACTION" == "restore" ]]; then
    print_kv "$(text label_restore_from)" "${RESTORE_SOURCE:-$(text latest_backup)}"
  fi
}

# 函数: print_completion_summary
# 功能: 打印执行结果摘要，包括结果、系统、镜像站、影响文件数、索引刷新状态、备份状态等
# 参数: $1 - 结果标签文案（如"成功"）
# 返回值: 始终 0（依赖全局 REFRESH_RAN / BACKUP_DIR / SKIP_BACKUP / AFFECTED_FILES 等）
print_completion_summary() {
  local result_label="$1"
  local refresh_status=""
  local backup_status=""

  if (( REFRESH_RAN )); then
    refresh_status="$(text refresh_completed)"
  else
    refresh_status="$(text refresh_skipped)"
  fi

  if [[ -n "$BACKUP_DIR" && $SKIP_BACKUP -eq 0 ]]; then
    backup_status="$BACKUP_DIR"
  elif [[ "$ACTION" == "restore" ]]; then
    backup_status="$(text backup_not_applicable)"
  elif (( SKIP_BACKUP )); then
    backup_status="$(text backup_disabled)"
  else
    backup_status="$(text backup_not_created)"
  fi

  start_section "$(text section_summary)"
  print_kv "$(text label_result)" "$result_label"
  print_kv "$(text label_system)" "$OS_PRETTY"
  print_kv "$(text label_package_manager)" "$PACKAGE_MANAGER"
  print_kv "$(text label_mirror)" "$(mirror_display_name "$MIRROR")"
  print_kv "$(text label_affected)" "$(count_label "$AFFECTED_FILES")"
  print_kv "$(text label_refresh)" "$refresh_status"
  print_kv "$(text label_backup)" "$backup_status"

  if [[ "$ACTION" == "restore" && $SKIPPED_RESTORE_FILES -gt 0 ]]; then
    print_kv "$(text label_skipped)" "$(count_label "$SKIPPED_RESTORE_FILES")"
  fi
}

# 函数: print_follow_up
# 功能: 打印后续操作提示，包括查看备份列表、恢复最近备份、恢复指定备份的命令
# 参数: 无（依赖全局 ACTION / BACKUP_DIR）
# 返回值: 始终 0
print_follow_up() {
  if is_lang_en; then
    start_section "Next Steps"
  else
    start_section "后续操作"
  fi

  log_info "$(fmt info_list_backups_hint "$SCRIPT_URL")"

  if [[ "$ACTION" == "switch" ]]; then
    log_info "$(fmt info_restore_hint "$SCRIPT_URL")"
    if [[ -n "$BACKUP_DIR" ]]; then
      log_info "$(fmt info_restore_from_hint "$SCRIPT_URL" "$BACKUP_DIR")"
    fi
  fi
}

# 函数: die
# 功能: 输出错误日志并立即退出脚本（退出码 1）
# 参数: $1..$N - 错误信息
# 返回值: 无（脚本退出码 1）
die() {
  log_error "$*"
  exit 1
}

# 函数: on_error
# 功能: ERR 信号陷阱函数，捕获命令执行失败时的行号与退出码
# 参数: 无（通过 $BASH_LINENO 与 $? 获取上下文）
# 返回值: 无（以原退出码退出）
on_error() {
  local exit_code=$?
  if [[ -n "${NETOOL:-}" ]]; then
    log_error "执行失败，退出码：${exit_code}"
  else
    log_error "脚本在第 ${BASH_LINENO[0]:-unknown} 行附近执行失败，退出码：${exit_code}"
  fi
  exit "$exit_code"
}

trap on_error ERR

# 函数: usage
# 功能: 打印脚本帮助信息（按当前语言输出中/英文用法、选项说明、示例）
# 参数: 无
# 返回值: 始终 0
usage() {
  if is_lang_en; then
    cat <<EOF
netool懒人工具箱 | 一键换源 v${SCRIPT_VERSION}
Switch package mirrors on common Linux distributions.
Automatically detects the system and package manager, supports both switching and restoring from backup.

Usage:
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL ${SCRIPT_URL}) [options]
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) mirror [options]

Options:
  --mirror <name>      Select a mirror. Chinese names are recommended; legacy aliases still work
  --lang <zh|en>       Select output language, default: zh
  --dry-run            Print actions without changing the system
  --skip-refresh       Skip package index refresh after switching or restoring
  --skip-backup        Skip backup when switching mirrors
  --restore            Restore from the latest backup
  --restore-from <dir> Restore from a specific backup directory
  --list-backups       List available backup directories
  -y, --yes            Run without interactive confirmation
  -h, --help           Show help
  --list-mirrors       Show supported mirrors
  --version            Show script version

Execution:
  Run as root. If your current shell is not root, prepend sudo yourself.
  Backups are stored in ${BACKUP_ROOT}

Supported:
  Ubuntu / Debian / most apt-based distributions
  CentOS / Rocky / AlmaLinux / Fedora / openEuler / most yum/dnf-based distributions
  Arch Linux
  Alpine Linux
  openSUSE Leap / Tumbleweed

Examples:
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL ${SCRIPT_URL}) --mirror 腾讯云 -y
  bash <(curl -fsSL ${SCRIPT_URL}) --dry-run
  bash <(curl -fsSL ${SCRIPT_URL}) --restore -y
EOF
  else
    cat <<EOF
netool懒人工具箱 | 一键换源 v${SCRIPT_VERSION}
面向主流 Linux 发行版的安全换源与回滚脚本。
自动识别系统与包管理器，支持换源、备份、恢复与预演模式。

用法：
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL ${SCRIPT_URL}) [选项]
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) mirror [选项]

选项：
  --mirror <name>      指定镜像站，优先使用中文镜像名；旧的英文别名仍然兼容
  --lang <zh|en>       指定输出语言，默认：zh
  --dry-run            只打印即将执行的动作，不修改系统
  --skip-refresh       换源或恢复后跳过包索引刷新
  --skip-backup        换源时跳过原始配置备份
  --restore            从最近一次备份恢复
  --restore-from <dir> 从指定备份目录恢复
  --list-backups       列出当前可用备份目录
  -y, --yes            非交互模式，直接执行
  -h, --help           显示帮助
  --list-mirrors       显示支持的镜像站
  --version            显示脚本版本

执行说明：
  请以 root 身份运行；如果当前不是 root，请自行在前面加 sudo。
  默认备份目录：${BACKUP_ROOT}

支持范围：
  Ubuntu / Debian / 大多数 apt 系发行版
  CentOS / Rocky / AlmaLinux / Fedora / openEuler / 大多数 yum/dnf 系发行版
  Arch Linux
  Alpine Linux
  openSUSE Leap / Tumbleweed

示例：
  curl -fsSL ${SCRIPT_URL} | bash
  bash <(curl -fsSL ${SCRIPT_URL}) --mirror 腾讯云 -y
  bash <(curl -fsSL ${SCRIPT_URL}) --dry-run
  bash <(curl -fsSL ${SCRIPT_URL}) --restore -y
EOF
  fi
}

# 函数: list_mirrors
# 功能: 打印所有支持的镜像站列表及其覆盖范围说明（按当前语言输出）
# 参数: 无
# 返回值: 始终 0
list_mirrors() {
  if is_lang_en; then
    cat <<'EOF'
Supported mirrors:
  清华大学       - wide coverage (legacy alias: tuna)
  中国科学技术大学 - wide coverage (legacy alias: ustc)
  阿里云         - wide coverage (legacy alias: aliyun)
  腾讯云         - full coverage (legacy alias: tencent)
  华为云         - full coverage (legacy alias: huawei)
  北京外国语大学 - common distros (legacy alias: bfsu)
  南京大学       - full coverage (legacy alias: nju)
  网易           - selected distros (legacy alias: 163)
  上海交通大学   - selected distros (legacy alias: sjtug)

Coverage differs by distribution.
The script validates the repository types required by the current system before changing files.
EOF
  else
    cat <<'EOF'
支持的镜像站：
  清华大学       - 覆盖较广（兼容旧别名：tuna）
  中国科学技术大学 - 覆盖较广（兼容旧别名：ustc）
  阿里云         - 覆盖较广（兼容旧别名：aliyun）
  腾讯云         - 覆盖完整（兼容旧别名：tencent）
  华为云         - 覆盖完整（兼容旧别名：huawei）
  北京外国语大学 - 常见发行版（兼容旧别名：bfsu）
  南京大学       - 覆盖完整（兼容旧别名：nju）
  网易           - 部分发行版（兼容旧别名：163）
  上海交通大学   - 部分发行版（兼容旧别名：sjtug）

不同镜像站的发行版覆盖范围不同。
脚本会在修改前按当前系统与现有仓库配置校验所需目录是否受支持。
EOF
  fi
}

# 函数: known_mirror_hosts_regex
# 功能: 输出所有已知镜像站主机名的正则表达式（| 分隔），用于 sed/grep 匹配
# 参数: 无
# 返回值: 始终 0（结果通过 stdout 输出）
known_mirror_hosts_regex() {
  printf '%s\n' 'mirrors\.tuna\.tsinghua\.edu\.cn|mirrors\.ustc\.edu\.cn|mirrors\.aliyun\.com|mirrors\.huaweicloud\.com|mirrors\.cloud\.tencent\.com|mirrors\.bfsu\.edu\.cn|mirrors\.163\.com|mirror\.sjtu\.edu\.cn|mirror\.nju\.edu\.cn'
}

# 函数: canonical_mirror_id
# 功能: 将用户输入的镜像站别名/中文名统一转换为标准镜像 id（如"清华"→"tuna"）
# 参数: $1 - 用户输入的镜像站名称或别名（不区分大小写）
# 返回值: 0 - 识别成功（stdout 输出标准 id）; 1 - 未识别
canonical_mirror_id() {
  local input
  input="$(tolower "$1")"

  case "$input" in
    tuna|清华|清华大学|tsinghua)
      printf "tuna\n"
      ;;
    ustc|中科大|中国科学技术大学)
      printf "ustc\n"
      ;;
    aliyun|阿里|阿里云)
      printf "aliyun\n"
      ;;
    tencent|腾讯|腾讯云)
      printf "tencent\n"
      ;;
    huawei|华为|华为云)
      printf "huawei\n"
      ;;
    bfsu|北外|北京外国语大学)
      printf "bfsu\n"
      ;;
    nju|南大|南京大学)
      printf "nju\n"
      ;;
    163|netease|网易)
      printf "163\n"
      ;;
    sjtug|上交|上交大|上海交通大学)
      printf "sjtug\n"
      ;;
    *)
      return 1
      ;;
  esac
}

# 函数: mirror_display_name
# 功能: 将标准镜像 id 转换为展示名称（如"tuna"→"清华大学"）；无法识别时原样返回
# 参数: $1 - 镜像 id 或用户输入
# 返回值: 始终 0（结果通过 stdout 输出）
mirror_display_name() {
  local mirror_id=""

  if ! mirror_id="$(canonical_mirror_id "$1" 2>/dev/null)"; then
    printf '%s' "$1"
    return 0
  fi

  case "$mirror_id" in
    tuna) printf '清华大学' ;;
    ustc) printf '中国科学技术大学' ;;
    aliyun) printf '阿里云' ;;
    tencent) printf '腾讯云' ;;
    huawei) printf '华为云' ;;
    bfsu) printf '北京外国语大学' ;;
    nju) printf '南京大学' ;;
    163) printf '网易' ;;
    sjtug) printf '上海交通大学' ;;
  esac
}

# 函数: mirror_id_from_url
# 功能: 从镜像 URL 中识别所属镜像站 id（包括官方源标识 official）
# 参数: $1 - 镜像 URL
# 返回值: 0 - 识别成功（stdout 输出 id）; 1 - 未识别
mirror_id_from_url() {
  local url="$1"

  case "$url" in
    *mirrors.tuna.tsinghua.edu.cn*) printf "tuna\n" ;;
    *mirrors.ustc.edu.cn*) printf "ustc\n" ;;
    *mirrors.aliyun.com*) printf "aliyun\n" ;;
    *mirrors.cloud.tencent.com*) printf "tencent\n" ;;
    *mirrors.huaweicloud.com*) printf "huawei\n" ;;
    *mirrors.bfsu.edu.cn*) printf "bfsu\n" ;;
    *mirror.nju.edu.cn*) printf "nju\n" ;;
    *mirrors.163.com*) printf "163\n" ;;
    *mirror.sjtu.edu.cn*) printf "sjtug\n" ;;
    *archive.ubuntu.com*|*security.ubuntu.com*|*ports.ubuntu.com*|*deb.debian.org*|*ftp.debian.org*|*security.debian.org*|*mirror.centos.org*|*mirror.stream.centos.org*|*vault.centos.org*|*dl.rockylinux.org*|*download.rockylinux.org*|*repo.almalinux.org*|*download.fedoraproject.org*|*dl.fedoraproject.org*|*repo.openeuler.org*|*dl-cdn.alpinelinux.org*|*dl-*.alpinelinux.org*|*download.opensuse.org*)
      printf "official\n"
      ;;
    *)
      return 1
      ;;
  esac
}

# 函数: mirror_choice_notes
# 功能: 生成镜像站选择的备注信息（默认推荐/兼容旧别名/当前使用）
# 参数: $1 - 镜像 id
# 返回值: 始终 0（结果通过 stdout 输出，逗号分隔）
mirror_choice_notes() {
  local mirror_id="$1"
  local notes=()

  if is_lang_en; then
    [[ "$mirror_id" == "$DEFAULT_MIRROR" ]] && notes+=("default recommended")
    notes+=("alias: $mirror_id")
    [[ "$CURRENT_MIRROR_ID" == "$mirror_id" ]] && notes+=("current")
    join_by ", " "${notes[@]}"
  else
    [[ "$mirror_id" == "$DEFAULT_MIRROR" ]] && notes+=("默认推荐")
    notes+=("兼容旧别名：$mirror_id")
    [[ "$CURRENT_MIRROR_ID" == "$mirror_id" ]] && notes+=("当前使用")
    join_by "，" "${notes[@]}"
  fi
}

# 函数: print_mirror_choice
# 功能: 打印一行镜像站菜单选项（编号. 名称（备注））
# 参数: $1 - 菜单编号; $2 - 镜像 id
# 返回值: 始终 0
print_mirror_choice() {
  local number="$1"
  local mirror_id="$2"

  if is_lang_en; then
    printf "  %s. %s (%s)\n" "$number" "$(mirror_display_name "$mirror_id")" "$(mirror_choice_notes "$mirror_id")"
  else
    printf "  %s. %s（%s）\n" "$number" "$(mirror_display_name "$mirror_id")" "$(mirror_choice_notes "$mirror_id")"
  fi
}

# 函数: select_mirror_interactively
# 功能: 交互式镜像站选择菜单，循环展示选项直到用户输入有效编号或镜像名称
# 参数: 无（设置全局 MIRROR）
# 返回值: 0 - 选择成功; 1 - 用户选择返回
select_mirror_interactively() {
  local answer=""

  while :; do
    if is_lang_en; then
      printf "\nChoose the target mirror:\n"
      print_mirror_choice 1 tuna
      print_mirror_choice 2 ustc
      print_mirror_choice 3 aliyun
      print_mirror_choice 4 tencent
      print_mirror_choice 5 huawei
      print_mirror_choice 6 bfsu
      print_mirror_choice 7 nju
      print_mirror_choice 8 163
      print_mirror_choice 9 sjtug
      printf "  b. Back\n"
      read -r -p "Enter a number or mirror name, default 4: " answer
    else
      printf "\n请选择目标镜像站：\n"
      print_mirror_choice 1 tuna
      print_mirror_choice 2 ustc
      print_mirror_choice 3 aliyun
      print_mirror_choice 4 tencent
      print_mirror_choice 5 huawei
      print_mirror_choice 6 bfsu
      print_mirror_choice 7 nju
      print_mirror_choice 8 163
      print_mirror_choice 9 sjtug
      printf "  b. 返回\n"
      read -r -p "请输入编号或镜像站名称，默认 4： " answer
    fi

    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"

    case "$answer" in
      b|B|back|返回)
        return 1
        ;;
      ""|4)
        MIRROR="$DEFAULT_MIRROR"
        return 0
        ;;
      1)
        MIRROR="tuna"
        return 0
        ;;
      2)
        MIRROR="ustc"
        return 0
        ;;
      3)
        MIRROR="aliyun"
        return 0
        ;;
      5)
        MIRROR="huawei"
        return 0
        ;;
      6)
        MIRROR="bfsu"
        return 0
        ;;
      7)
        MIRROR="nju"
        return 0
        ;;
      8)
        MIRROR="163"
        return 0
        ;;
      9)
        MIRROR="sjtug"
        return 0
        ;;
    esac

    if MIRROR="$(canonical_mirror_id "$answer" 2>/dev/null)"; then
      return 0
    fi

    if is_lang_en; then
      log_warn "Invalid selection. Enter 1-9 or a supported mirror name."
    else
      log_warn "输入无效，请输入 1-9 或支持的镜像站名称。"
    fi
  done
}

# 函数: resolve_switch_mirror
# 功能: 确定换源目标镜像站：已指定则直接使用；非交互模式用默认值；交互模式弹出选择菜单
# 参数: 无（依赖全局 MIRROR / NON_INTERACTIVE）
# 返回值: 0 - 已确定镜像站; 1 - 用户取消
resolve_switch_mirror() {
  [[ -n "$MIRROR" ]] && return 0

  if (( NON_INTERACTIVE )); then
    MIRROR="$DEFAULT_MIRROR"
    if is_lang_en; then
      log_info "No mirror was specified in non-interactive mode. Using default mirror: $(mirror_display_name "$MIRROR")"
    else
      log_info "未指定镜像站，非交互模式下将使用默认镜像站：$(mirror_display_name "$MIRROR")"
    fi
    return 0
  fi

  if ! select_mirror_interactively; then
    return 1
  fi
}

# 函数: confirm_same_mirror_if_needed
# 功能: 当当前系统已使用与目标相同的镜像站时，提示用户确认是否继续重写配置
# 参数: 无（依赖全局 CURRENT_MIRROR_ID / MIRROR）
# 返回值: 0 - 继续; 1 - 用户取消
confirm_same_mirror_if_needed() {
  [[ -n "$CURRENT_MIRROR_ID" ]] || return 0
  [[ "$CURRENT_MIRROR_ID" != "official" ]] || return 0
  [[ "$CURRENT_MIRROR_ID" == "$MIRROR" ]] || return 0

  if is_lang_en; then
    log_warn "The system already appears to use $(mirror_display_name "$MIRROR")."
    if ! confirm "Continue anyway and rewrite sources plus refresh metadata?"; then
      log_info "No changes were made."
      return 1
    fi
  else
    log_warn "当前检测到系统已经在使用 $(mirror_display_name "$MIRROR")。"
    if ! confirm "当前已是所选镜像站，是否仍继续重写配置并刷新索引？"; then
      log_info "当前已保留原配置，本次未做修改。"
      return 1
    fi
  fi
}

# 函数: is_supported_mirror
# 功能: 判断给定镜像站是否在受支持列表中
# 参数: $1 - 镜像站名称或别名
# 返回值: 0 - 受支持; 1 - 不受支持
is_supported_mirror() {
  case "$(canonical_mirror_id "$1" 2>/dev/null || true)" in
    tuna|ustc|aliyun|tencent|huawei|bfsu|nju|163|sjtug)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 函数: mirror_supports_key
# 功能: 判断指定镜像站是否覆盖给定的仓库类型（如 ubuntu/debian/centos 等）
# 参数: $1 - 镜像 id; $2 - 仓库类型 key
# 返回值: 0 - 覆盖; 1 - 不覆盖
mirror_supports_key() {
  local mirror="$1"
  local key="$2"

  case "${mirror}:${key}" in
    tuna:ubuntu|tuna:ubuntu_ports|tuna:debian|tuna:debian_security|tuna:centos|tuna:centos_stream|tuna:centos_vault|tuna:fedora|tuna:epel|tuna:openeuler|tuna:archlinux|tuna:alpine|tuna:opensuse)
      return 0
      ;;
    ustc:ubuntu|ustc:ubuntu_ports|ustc:debian|ustc:debian_security|ustc:centos_stream|ustc:centos_vault|ustc:rocky|ustc:fedora|ustc:epel|ustc:openeuler|ustc:archlinux|ustc:alpine|ustc:opensuse)
      return 0
      ;;
    aliyun:ubuntu|aliyun:ubuntu_ports|aliyun:debian|aliyun:debian_security|aliyun:centos|aliyun:centos_stream|aliyun:centos_vault|aliyun:almalinux|aliyun:fedora|aliyun:epel|aliyun:openeuler|aliyun:archlinux|aliyun:alpine|aliyun:opensuse)
      return 0
      ;;
    tencent:ubuntu|tencent:ubuntu_ports|tencent:debian|tencent:debian_security|tencent:centos|tencent:centos_stream|tencent:centos_vault|tencent:rocky|tencent:almalinux|tencent:fedora|tencent:epel|tencent:openeuler|tencent:archlinux|tencent:alpine|tencent:opensuse)
      return 0
      ;;
    huawei:ubuntu|huawei:ubuntu_ports|huawei:debian|huawei:debian_security|huawei:centos|huawei:centos_stream|huawei:centos_vault|huawei:rocky|huawei:almalinux|huawei:fedora|huawei:epel|huawei:openeuler|huawei:archlinux|huawei:alpine|huawei:opensuse)
      return 0
      ;;
    bfsu:ubuntu|bfsu:ubuntu_ports|bfsu:debian|bfsu:debian_security|bfsu:centos|bfsu:centos_stream|bfsu:centos_vault|bfsu:fedora|bfsu:epel|bfsu:archlinux|bfsu:alpine|bfsu:opensuse)
      return 0
      ;;
    nju:ubuntu|nju:ubuntu_ports|nju:debian|nju:debian_security|nju:centos|nju:centos_stream|nju:centos_vault|nju:rocky|nju:almalinux|nju:fedora|nju:epel|nju:openeuler|nju:archlinux|nju:alpine|nju:opensuse)
      return 0
      ;;
    163:ubuntu|163:ubuntu_ports|163:debian|163:debian_security|163:centos|163:centos_vault|163:rocky|163:fedora|163:openeuler|163:archlinux)
      return 0
      ;;
    sjtug:ubuntu_ports|sjtug:debian|sjtug:debian_security|sjtug:centos|sjtug:rocky|sjtug:almalinux|sjtug:fedora|sjtug:openeuler|sjtug:archlinux|sjtug:alpine|sjtug:opensuse)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 函数: repo_type_label
# 功能: 将仓库类型 key 转换为展示标签（如 ubuntu_ports→ubuntu-ports）
# 参数: $1 - 仓库类型 key
# 返回值: 始终 0（结果通过 stdout 输出）
repo_type_label() {
  case "$1" in
    ubuntu_ports) printf 'ubuntu-ports' ;;
    debian_security) printf 'debian-security' ;;
    centos_stream) printf 'centos-stream' ;;
    centos_vault) printf 'centos-vault' ;;
    *) printf '%s' "$1" ;;
  esac
}

# 函数: ensure_mirror_supports_keys
# 功能: 批量校验镜像站是否覆盖当前系统所需的全部仓库类型；缺失时报错并返回 1
# 参数: $1 - 镜像 id; $2..$N - 所需的仓库类型 key 列表
# 返回值: 0 - 全部覆盖; 1 - 存在缺失
ensure_mirror_supports_keys() {
  local mirror="$1"
  shift
  local key=""
  local missing=()

  for key in "$@"; do
    [[ -n "$key" ]] || continue
    if ! mirror_supports_key "$mirror" "$key"; then
      missing+=("$(repo_type_label "$key")")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    log_error "$(fmt error_mirror_missing_coverage "$mirror" "$(join_by ', ' "${missing[@]}")")"
    log_info "$(text info_mirror_recommendation)"
    return 1
  fi

  return 0
}

# 函数: list_backups
# 功能: 列出 BACKUP_ROOT 下所有时间戳备份目录，并打印其元信息
# 参数: 无
# 返回值: 始终 0；备份根目录不存在时打印警告并返回 0
list_backups() {
  local backup_dir=""

  if [[ ! -d "$BACKUP_ROOT" ]]; then
    log_warn "$(fmt error_no_backup_dirs "$BACKUP_ROOT")"
    return 0
  fi

  while IFS= read -r backup_dir; do
    [[ -d "$backup_dir" ]] || continue
    print_backup_entry "$backup_dir"
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
}

# 函数: backup_metadata_path
# 功能: 拼接指定备份目录下元信息文件的完整路径
# 参数: $1 - 备份目录
# 返回值: 始终 0（结果通过 stdout 输出元信息文件路径）
backup_metadata_path() {
  local backup_dir="$1"
  printf "%s/%s\n" "$backup_dir" "$BACKUP_METADATA_NAME"
}

# 函数: print_backup_entry
# 功能: 打印单个备份目录的基本信息与元信息（创建时间、镜像站、包管理器）
# 参数: $1 - 备份目录绝对路径
# 返回值: 始终 0
print_backup_entry() {
  local backup_dir="$1"
  local metadata_file=""
  local created_at=""
  local mirror_name=""
  local manager_name=""

  metadata_file="$(backup_metadata_path "$backup_dir")"
  printf "%s\n" "$backup_dir"

  [[ -f "$metadata_file" ]] || return 0

  created_at="$(metadata_value "$metadata_file" CREATED_AT)"
  mirror_name="$(metadata_value "$metadata_file" MIRROR)"
  manager_name="$(metadata_value "$metadata_file" PACKAGE_MANAGER)"
  [[ -n "$mirror_name" ]] && mirror_name="$(mirror_display_name "$mirror_name")"

  if [[ -n "$created_at" || -n "$mirror_name" || -n "$manager_name" ]]; then
    printf "  %s=%s %s=%s %s=%s\n" \
      "$(text label_created_at)" \
      "${created_at:-$(text label_unknown)}" \
      "$(text label_meta_mirror)" \
      "${mirror_name:-$(text label_unknown)}" \
      "$(text label_meta_manager)" \
      "${manager_name:-$(text label_unknown)}"
  fi
}

# 函数: run_cmd
# 功能: 命令执行封装，DRY_RUN 模式下仅打印命令不执行；否则原样执行
# 参数: $1..$N - 要执行的命令及其参数
# 返回值: 透传被执行命令的退出码（DRY_RUN 模式下始终 0）
run_cmd() {
  if (( DRY_RUN )); then
    printf "%s[%s]%s" "$COLOR_YELLOW" "$(text tag_dry)" "$COLOR_RESET"
    printf " %q" "$@"
    printf "\n"
    return 0
  fi

  "$@"
}

# 函数: require_root
# 功能: 检查当前是否以 root 身份运行，否则 die
# 参数: 无
# 返回值: 无（非 root 时 die 退出码 1）
require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "$(text error_need_root)"
  fi
}

# 函数: confirm
# 功能: 向用户展示 Y/N 确认提示；NON_INTERACTIVE 模式下自动通过
# 参数: $1 - 提示文本
# 返回值: 0 - 用户确认; 1 - 用户取消
confirm() {
  local prompt="$1"
  local answer=""

  if (( NON_INTERACTIVE )); then
    return 0
  fi

  read -r -p "${prompt} $(text label_yes_no)" answer
  [[ "$answer" =~ ^([yY]|[yY][eE][sS]|是|确认)$ ]]
}

# 函数: mirror_url_for
# 功能: 根据镜像 id 与仓库类型 key 返回对应的镜像 URL；未命中返回 1
# 参数: $1 - 仓库类型 key（如 ubuntu/debian/centos 等）
# 返回值: 0 - 命中（stdout 输出 URL）; 1 - 未命中
mirror_url_for() {
  local key="$1"

  case "${MIRROR}:${key}" in
    tuna:ubuntu) echo "https://mirrors.tuna.tsinghua.edu.cn/ubuntu/" ;;
    tuna:ubuntu_ports) echo "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/" ;;
    tuna:debian) echo "https://mirrors.tuna.tsinghua.edu.cn/debian/" ;;
    tuna:debian_security) echo "https://mirrors.tuna.tsinghua.edu.cn/debian-security/" ;;
    tuna:centos) echo "https://mirrors.tuna.tsinghua.edu.cn" ;;
    tuna:centos_stream) echo "https://mirrors.tuna.tsinghua.edu.cn/centos-stream" ;;
    tuna:centos_vault) echo "https://mirrors.tuna.tsinghua.edu.cn/centos-vault" ;;
    tuna:fedora) echo "https://mirrors.tuna.tsinghua.edu.cn/fedora" ;;
    tuna:epel) echo "https://mirrors.tuna.tsinghua.edu.cn/epel" ;;
    tuna:openeuler) echo "https://mirrors.tuna.tsinghua.edu.cn" ;;
    tuna:archlinux) echo "https://mirrors.tuna.tsinghua.edu.cn/archlinux/" ;;
    tuna:alpine) echo "https://mirrors.tuna.tsinghua.edu.cn/alpine" ;;
    tuna:opensuse) echo "https://mirrors.tuna.tsinghua.edu.cn/opensuse" ;;

    ustc:ubuntu) echo "https://mirrors.ustc.edu.cn/ubuntu/" ;;
    ustc:ubuntu_ports) echo "https://mirrors.ustc.edu.cn/ubuntu-ports/" ;;
    ustc:debian) echo "https://mirrors.ustc.edu.cn/debian/" ;;
    ustc:debian_security) echo "https://mirrors.ustc.edu.cn/debian-security/" ;;
    ustc:centos_stream) echo "https://mirrors.ustc.edu.cn/centos-stream" ;;
    ustc:centos_vault) echo "https://mirrors.ustc.edu.cn/centos-vault" ;;
    ustc:rocky) echo "https://mirrors.ustc.edu.cn" ;;
    ustc:fedora) echo "https://mirrors.ustc.edu.cn/fedora" ;;
    ustc:epel) echo "https://mirrors.ustc.edu.cn/epel" ;;
    ustc:openeuler) echo "https://mirrors.ustc.edu.cn" ;;
    ustc:archlinux) echo "https://mirrors.ustc.edu.cn/archlinux/" ;;
    ustc:alpine) echo "https://mirrors.ustc.edu.cn/alpine" ;;
    ustc:opensuse) echo "https://mirrors.ustc.edu.cn/opensuse" ;;

    aliyun:ubuntu) echo "https://mirrors.aliyun.com/ubuntu/" ;;
    aliyun:ubuntu_ports) echo "https://mirrors.aliyun.com/ubuntu-ports/" ;;
    aliyun:debian) echo "https://mirrors.aliyun.com/debian/" ;;
    aliyun:debian_security) echo "https://mirrors.aliyun.com/debian-security/" ;;
    aliyun:centos) echo "https://mirrors.aliyun.com" ;;
    aliyun:centos_stream) echo "https://mirrors.aliyun.com/centos-stream" ;;
    aliyun:centos_vault) echo "https://mirrors.aliyun.com/centos-vault" ;;
    aliyun:almalinux) echo "https://mirrors.aliyun.com" ;;
    aliyun:fedora) echo "https://mirrors.aliyun.com/fedora" ;;
    aliyun:epel) echo "https://mirrors.aliyun.com/epel" ;;
    aliyun:openeuler) echo "https://mirrors.aliyun.com" ;;
    aliyun:archlinux) echo "https://mirrors.aliyun.com/archlinux/" ;;
    aliyun:alpine) echo "https://mirrors.aliyun.com/alpine" ;;
    aliyun:opensuse) echo "https://mirrors.aliyun.com/opensuse" ;;

    tencent:ubuntu) echo "https://mirrors.cloud.tencent.com/ubuntu/" ;;
    tencent:ubuntu_ports) echo "https://mirrors.cloud.tencent.com/ubuntu-ports/" ;;
    tencent:debian) echo "https://mirrors.cloud.tencent.com/debian/" ;;
    tencent:debian_security) echo "https://mirrors.cloud.tencent.com/debian-security/" ;;
    tencent:centos) echo "https://mirrors.cloud.tencent.com" ;;
    tencent:centos_stream) echo "https://mirrors.cloud.tencent.com/centos-stream" ;;
    tencent:centos_vault) echo "https://mirrors.cloud.tencent.com/centos-vault" ;;
    tencent:rocky) echo "https://mirrors.cloud.tencent.com" ;;
    tencent:almalinux) echo "https://mirrors.cloud.tencent.com" ;;
    tencent:fedora) echo "https://mirrors.cloud.tencent.com/fedora" ;;
    tencent:epel) echo "https://mirrors.cloud.tencent.com/epel" ;;
    tencent:openeuler) echo "https://mirrors.cloud.tencent.com" ;;
    tencent:archlinux) echo "https://mirrors.cloud.tencent.com/archlinux/" ;;
    tencent:alpine) echo "https://mirrors.cloud.tencent.com/alpine" ;;
    tencent:opensuse) echo "https://mirrors.cloud.tencent.com/opensuse" ;;

    huawei:ubuntu) echo "https://mirrors.huaweicloud.com/ubuntu/" ;;
    huawei:ubuntu_ports) echo "https://mirrors.huaweicloud.com/ubuntu-ports/" ;;
    huawei:debian) echo "https://mirrors.huaweicloud.com/debian/" ;;
    huawei:debian_security) echo "https://mirrors.huaweicloud.com/debian-security/" ;;
    huawei:centos) echo "https://mirrors.huaweicloud.com" ;;
    huawei:centos_stream) echo "https://mirrors.huaweicloud.com/centos-stream" ;;
    huawei:centos_vault) echo "https://mirrors.huaweicloud.com/centos-vault" ;;
    huawei:rocky) echo "https://mirrors.huaweicloud.com" ;;
    huawei:almalinux) echo "https://mirrors.huaweicloud.com" ;;
    huawei:fedora) echo "https://mirrors.huaweicloud.com/fedora" ;;
    huawei:epel) echo "https://mirrors.huaweicloud.com/epel" ;;
    huawei:openeuler) echo "https://mirrors.huaweicloud.com" ;;
    huawei:archlinux) echo "https://mirrors.huaweicloud.com/archlinux/" ;;
    huawei:alpine) echo "https://mirrors.huaweicloud.com/alpine" ;;
    huawei:opensuse) echo "https://mirrors.huaweicloud.com/opensuse" ;;

    bfsu:ubuntu) echo "https://mirrors.bfsu.edu.cn/ubuntu/" ;;
    bfsu:ubuntu_ports) echo "https://mirrors.bfsu.edu.cn/ubuntu-ports/" ;;
    bfsu:debian) echo "https://mirrors.bfsu.edu.cn/debian/" ;;
    bfsu:debian_security) echo "https://mirrors.bfsu.edu.cn/debian-security/" ;;
    bfsu:centos) echo "https://mirrors.bfsu.edu.cn" ;;
    bfsu:centos_stream) echo "https://mirrors.bfsu.edu.cn/centos-stream" ;;
    bfsu:centos_vault) echo "https://mirrors.bfsu.edu.cn/centos-vault" ;;
    bfsu:fedora) echo "https://mirrors.bfsu.edu.cn/fedora" ;;
    bfsu:epel) echo "https://mirrors.bfsu.edu.cn/epel" ;;
    bfsu:archlinux) echo "https://mirrors.bfsu.edu.cn/archlinux/" ;;
    bfsu:alpine) echo "https://mirrors.bfsu.edu.cn/alpine" ;;
    bfsu:opensuse) echo "https://mirrors.bfsu.edu.cn/opensuse" ;;

    nju:ubuntu) echo "https://mirror.nju.edu.cn/ubuntu/" ;;
    nju:ubuntu_ports) echo "https://mirror.nju.edu.cn/ubuntu-ports/" ;;
    nju:debian) echo "https://mirror.nju.edu.cn/debian/" ;;
    nju:debian_security) echo "https://mirror.nju.edu.cn/debian-security/" ;;
    nju:centos) echo "https://mirror.nju.edu.cn" ;;
    nju:centos_stream) echo "https://mirror.nju.edu.cn/centos-stream" ;;
    nju:centos_vault) echo "https://mirror.nju.edu.cn/centos-vault" ;;
    nju:rocky) echo "https://mirror.nju.edu.cn" ;;
    nju:almalinux) echo "https://mirror.nju.edu.cn" ;;
    nju:fedora) echo "https://mirror.nju.edu.cn/fedora" ;;
    nju:epel) echo "https://mirror.nju.edu.cn/epel" ;;
    nju:openeuler) echo "https://mirror.nju.edu.cn" ;;
    nju:archlinux) echo "https://mirror.nju.edu.cn/archlinux/" ;;
    nju:alpine) echo "https://mirror.nju.edu.cn/alpine" ;;
    nju:opensuse) echo "https://mirror.nju.edu.cn/opensuse" ;;

    163:ubuntu) echo "https://mirrors.163.com/ubuntu/" ;;
    163:ubuntu_ports) echo "https://mirrors.163.com/ubuntu-ports/" ;;
    163:debian) echo "https://mirrors.163.com/debian/" ;;
    163:debian_security) echo "https://mirrors.163.com/debian-security/" ;;
    163:centos) echo "https://mirrors.163.com" ;;
    163:centos_vault) echo "https://mirrors.163.com/centos-vault" ;;
    163:rocky) echo "https://mirrors.163.com" ;;
    163:fedora) echo "https://mirrors.163.com/fedora" ;;
    163:openeuler) echo "https://mirrors.163.com" ;;
    163:archlinux) echo "https://mirrors.163.com/archlinux/" ;;

    sjtug:ubuntu_ports) echo "https://mirror.sjtu.edu.cn/ubuntu-ports/" ;;
    sjtug:debian) echo "https://mirror.sjtu.edu.cn/debian/" ;;
    sjtug:debian_security) echo "https://mirror.sjtu.edu.cn/debian-security/" ;;
    sjtug:centos) echo "https://mirror.sjtu.edu.cn" ;;
    sjtug:rocky) echo "https://mirror.sjtu.edu.cn" ;;
    sjtug:almalinux) echo "https://mirror.sjtu.edu.cn" ;;
    sjtug:fedora) echo "https://mirror.sjtu.edu.cn/fedora" ;;
    sjtug:openeuler) echo "https://mirror.sjtu.edu.cn" ;;
    sjtug:archlinux) echo "https://mirror.sjtu.edu.cn/archlinux/" ;;
    sjtug:alpine) echo "https://mirror.sjtu.edu.cn/alpine" ;;
    sjtug:opensuse) echo "https://mirror.sjtu.edu.cn/opensuse" ;;

    *)
      die "$(fmt error_unsupported_mirror_mapping "$MIRROR" "$key")"
      ;;
  esac
}

# 函数: ensure_backup_dir
# 功能: 确保本次备份目录已创建并写入元信息；SKIP_BACKUP 或已创建时跳过（幂等）
# 参数: 无（依赖全局 BACKUP_DIR / SKIP_BACKUP，设置 BACKUP_DIR）
# 返回值: 始终 0
# 副作用: 在 BACKUP_ROOT 下创建 <时间戳>/ 子目录
ensure_backup_dir() {
  if (( SKIP_BACKUP )); then
    return 0
  fi

  if [[ -n "$BACKUP_DIR" ]]; then
    return 0
  fi

  BACKUP_DIR="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  run_cmd mkdir -p "$BACKUP_DIR"
  write_backup_metadata
}

# 函数: write_backup_metadata
# 功能: 写入备份元信息文件（.backup-info），记录脚本名、版本、镜像站、包管理器等
# 参数: 无（依赖全局 BACKUP_DIR）
# 返回值: 始终 0；DRY_RUN 模式下只打印计划不写文件
# 副作用: 在备份目录内创建 .backup-info；标记 BACKUP_METADATA_WRITTEN 防止重复写入
write_backup_metadata() {
  local metadata_file=""

  (( BACKUP_METADATA_WRITTEN )) && return 0
  [[ -n "$BACKUP_DIR" ]] || return 0

  metadata_file="$(backup_metadata_path "$BACKUP_DIR")"

  if (( DRY_RUN )); then
    log_info "$(fmt info_would_write_backup_metadata "$metadata_file")"
    BACKUP_METADATA_WRITTEN=1
    return 0
  fi

  if [[ -f "$metadata_file" ]]; then
    BACKUP_METADATA_WRITTEN=1
    return 0
  fi

  cat >"$metadata_file" <<EOF
SCRIPT_NAME=${SCRIPT_NAME}
SCRIPT_VERSION=${SCRIPT_VERSION}
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ACTION=${ACTION}
MIRROR=${MIRROR}
OS_ID=${OS_ID:-unknown}
PACKAGE_MANAGER=${PACKAGE_MANAGER:-unknown}
EOF

  BACKUP_METADATA_WRITTEN=1
}

# 函数: backup_file
# 功能: 将单个源文件按其绝对路径结构复制到本次备份目录中
# 参数: $1 - 待备份的源文件绝对路径
# 返回值: 0 - 成功或源文件不存在或 SKIP_BACKUP 时静默返回 0
# 副作用: 必要时创建备份目录及父目录层级
backup_file() {
  local source_file="$1"
  local target_file=""

  [[ -f "$source_file" ]] || return 0
  (( SKIP_BACKUP )) && return 0

  ensure_backup_dir

  # 通过 ${source_file#/} 去掉前导 / 后拼接到 BACKUP_DIR 下，保留原目录层级
  target_file="${BACKUP_DIR}/${source_file#/}"
  run_cmd mkdir -p "$(dirname "$target_file")"
  run_cmd cp -a "$source_file" "$target_file"
}

# 函数: resolve_restore_source
# 功能: 解析恢复来源：优先使用 --restore-from 指定目录，否则取 BACKUP_ROOT 下最新时间戳目录
# 参数: 无（依赖全局 RESTORE_SOURCE）
# 返回值: 通过 stdout 输出恢复目录绝对路径；失败时 die
resolve_restore_source() {
  local latest_backup=""

  if [[ -n "$RESTORE_SOURCE" ]]; then
    [[ -d "$RESTORE_SOURCE" ]] || die "$(fmt error_backup_dir_missing "$RESTORE_SOURCE")"
    printf "%s\n" "$RESTORE_SOURCE"
    return 0
  fi

  [[ -d "$BACKUP_ROOT" ]] || die "$(fmt error_backup_root_missing "$BACKUP_ROOT")"
  # 备份目录以 YYYYMMDD-HHMMSS 命名，按字典序排序即按时间序排序
  latest_backup="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
  [[ -n "$latest_backup" ]] || die "$(text error_no_backup_for_restore)"
  printf "%s\n" "$latest_backup"
}

# 函数: is_restore_target_allowed
# 功能: 判断恢复目标路径是否在允许的包管理相关目录范围内
# 参数: $1 - 目标文件绝对路径
# 返回值: 0 - 允许; 1 - 不允许
is_restore_target_allowed() {
  local target_file="$1"

  case "$target_file" in
    /etc/apt/*|/etc/yum.repos.d/*|/etc/pacman.d/*|/etc/apk/*|/etc/zypp/repos.d/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 函数: restore_backup_tree
# 功能: 从指定备份目录将所有文件按原绝对路径恢复到系统中
# 参数: $1 - 备份目录
# 返回值: 0 - 至少恢复一个文件; 非 0 - 无文件可恢复
# 副作用: 设置全局 AFFECTED_FILES / SKIPPED_RESTORE_FILES
restore_backup_tree() {
  local restore_dir="$1"
  local backup_file=""
  local target_file=""
  local restored_count=0
  local skipped_count=0

  [[ -d "$restore_dir" ]] || die "$(fmt error_backup_dir_missing "$restore_dir")"

  while IFS= read -r backup_file; do
    [[ -f "$backup_file" ]] || continue
    # 通过 ${backup_file#${restore_dir}/} 去掉备份目录前缀，再补回 / 还原绝对路径
    target_file="/${backup_file#${restore_dir}/}"

    # 仅允许恢复到包管理相关目录，避免误覆盖其他系统文件
    if ! is_restore_target_allowed "$target_file"; then
      skipped_count=$((skipped_count + 1))
      log_warn "$(fmt warn_skip_restore_target "$target_file")"
      continue
    fi

    run_cmd mkdir -p "$(dirname "$target_file")"
    run_cmd cp -a "$backup_file" "$target_file"
    restored_count=$((restored_count + 1))
  done < <(find "$restore_dir" -type f | sort)

  (( restored_count > 0 )) || { log_error "$(fmt error_no_files_in_backup "$restore_dir")"; return 1; }
  AFFECTED_FILES=$restored_count
  SKIPPED_RESTORE_FILES=$skipped_count
  log_success "$(fmt success_restored_files "$restored_count")"

  if (( skipped_count > 0 )); then
    log_warn "$(fmt warn_skipped_restore_targets "$skipped_count")"
  fi
}

# 函数: detect_system
# 功能: 检测当前系统：读取 /etc/os-release 并判定包管理器类型
# 参数: 无
# 返回值: 0 - 成功; 无 /etc/os-release 或包管理器不识别时 die
# 副作用: 设置全局 OS_ID / OS_PRETTY / PACKAGE_MANAGER
detect_system() {
  [[ -r /etc/os-release ]] || die "$(text error_os_release_missing)"

  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-unknown}"
  OS_PRETTY="${PRETTY_NAME:-$OS_ID}"

  # 按优先级探测可用的包管理器，确定后续的换源分支
  if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
  elif command -v pacman >/dev/null 2>&1; then
    PACKAGE_MANAGER="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
  elif command -v zypper >/dev/null 2>&1; then
    PACKAGE_MANAGER="zypper"
  else
    die "$(text error_unsupported_package_manager)"
  fi
}

# 函数: detect_current_mirror
# 功能: 扫描当前源配置文件，判定当前使用的镜像站或是否为官方源
# 参数: 无（依赖全局 PACKAGE_MANAGER）
# 返回值: 始终 0；结果写入全局 CURRENT_MIRROR_ID（可能为空、official、或具体镜像 id）
# 说明: 仅识别已知镜像站 URL；非主流 URL 会留空
detect_current_mirror() {
  local url=""
  local urls=""
  local mirror_id=""
  local official_seen=0

  CURRENT_MIRROR_ID=""

  case "$PACKAGE_MANAGER" in
    apt)
      urls="$(find /etc/apt -maxdepth 2 -type f \( -name "*.list" -o -name "*.sources" \) 2>/dev/null | xargs grep -hEo 'https?://[^[:space:]]+' 2>/dev/null || true)"
      ;;
    yum|dnf)
      urls="$(find /etc/yum.repos.d -maxdepth 1 -type f -name "*.repo" 2>/dev/null | xargs grep -hEo 'https?://[^[:space:]]+' 2>/dev/null || true)"
      ;;
    pacman)
      if [[ -f /etc/pacman.d/mirrorlist ]]; then
        urls="$(grep -hE '^[[:space:]]*Server[[:space:]]*=' /etc/pacman.d/mirrorlist 2>/dev/null | grep -Eo 'https?://[^[:space:]]+' || true)"
      fi
      ;;
    apk)
      if [[ -f /etc/apk/repositories ]]; then
        urls="$(grep -hEo 'https?://[^[:space:]]+' /etc/apk/repositories 2>/dev/null || true)"
      fi
      ;;
    zypper)
      urls="$(find /etc/zypp/repos.d -maxdepth 1 -type f -name "*.repo" 2>/dev/null | xargs grep -hEo 'https?://[^[:space:]]+' 2>/dev/null || true)"
      ;;
  esac

  [[ -n "$urls" ]] || return 0

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if mirror_id="$(mirror_id_from_url "$url" 2>/dev/null)"; then
      if [[ "$mirror_id" == "official" ]]; then
        official_seen=1
        continue
      fi

      CURRENT_MIRROR_ID="$mirror_id"
      return 0
    fi
  done <<<"$urls"

  (( official_seen )) && CURRENT_MIRROR_ID="official"
}

# 函数: switch_apt_sources
# 功能: 切换 APT 软件源（Debian/Ubuntu）到目标镜像站，先用 sed 替换 archive/security/已知镜像 URL
# 参数: 无（依赖全局 MIRROR / BACKUP_DIR）
# 返回值: 0 - 成功; 无可处理文件或不支持镜像时 die
# 副作用: 修改 /etc/apt 下的 .list/.sources 文件；修改前调用 backup_file 备份
switch_apt_sources() {
  local file=""
  local debian_mirror=""
  local debian_security_mirror=""
  local ubuntu_mirror=""
  local ubuntu_ports_mirror=""
  local file_count=0
  local need_debian=0
  local need_debian_security=0
  local need_ubuntu=0
  local need_ubuntu_ports=0
  local mirror_hosts_regex=""
  local apt_files=()
  local sed_args=()
  local required_keys=()

  mirror_hosts_regex="$(known_mirror_hosts_regex)"

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    apt_files+=("$file")

    if grep -Eq "https?://((([[:alnum:]-]+\\.)?archive\\.ubuntu\\.com)|security\\.ubuntu\\.com|(${mirror_hosts_regex}))/ubuntu/?" "$file"; then
      need_ubuntu=1
    fi

    if grep -Eq "https?://(ports\\.ubuntu\\.com|(${mirror_hosts_regex}))/ubuntu-ports/?" "$file"; then
      need_ubuntu_ports=1
    fi

    if grep -Eq "https?://(deb\\.debian\\.org|ftp\\.debian\\.org|(${mirror_hosts_regex}))/debian/?" "$file"; then
      need_debian=1
    fi

    if grep -Eq 'security\\.debian\\.org|debian-security' "$file"; then
      need_debian_security=1
    fi
  done < <(find /etc/apt -maxdepth 2 -type f \( -name "*.list" -o -name "*.sources" \) 2>/dev/null)

  file_count=${#apt_files[@]}
  (( file_count > 0 )) || die "$(text error_no_apt_sources)"

  (( need_debian )) && required_keys+=(debian)
  (( need_debian_security )) && required_keys+=(debian_security)
  (( need_ubuntu )) && required_keys+=(ubuntu)
  (( need_ubuntu_ports )) && required_keys+=(ubuntu_ports)
  (( ${#required_keys[@]} > 0 )) || die "$(text error_no_known_apt_entries)"

  if ! ensure_mirror_supports_keys "$MIRROR" "${required_keys[@]}"; then
    exit 1
  fi

  (( need_debian )) && debian_mirror="$(mirror_url_for debian)"
  (( need_debian_security )) && debian_security_mirror="$(mirror_url_for debian_security)"
  (( need_ubuntu )) && ubuntu_mirror="$(mirror_url_for ubuntu)"
  (( need_ubuntu_ports )) && ubuntu_ports_mirror="$(mirror_url_for ubuntu_ports)"

  sed_args=(-E -i)

  if [[ -n "$ubuntu_mirror" ]]; then
    sed_args+=(
      -e "s|https?://([[:alnum:]-]+\\.)?archive\\.ubuntu\\.com/ubuntu/?|${ubuntu_mirror}|g"
      -e "s|https?://security\\.ubuntu\\.com/ubuntu/?|${ubuntu_mirror}|g"
      -e "s#https?://(${mirror_hosts_regex})/ubuntu/?#${ubuntu_mirror}#g"
    )
  fi

  if [[ -n "$ubuntu_ports_mirror" ]]; then
    sed_args+=(
      -e "s|https?://ports\\.ubuntu\\.com/ubuntu-ports/?|${ubuntu_ports_mirror}|g"
      -e "s#https?://(${mirror_hosts_regex})/ubuntu-ports/?#${ubuntu_ports_mirror}#g"
    )
  fi

  if [[ -n "$debian_mirror" ]]; then
    sed_args+=(
      -e "s|https?://deb\\.debian\\.org/debian/?|${debian_mirror}|g"
      -e "s|https?://ftp\\.debian\\.org/debian/?|${debian_mirror}|g"
      -e "s#https?://(${mirror_hosts_regex})/debian/?#${debian_mirror}#g"
    )
  fi

  if [[ -n "$debian_security_mirror" ]]; then
    sed_args+=(
      -e "s|https?://security\\.debian\\.org/debian-security/?|${debian_security_mirror}|g"
      -e "s|https?://security\\.debian\\.org/?|${debian_security_mirror}|g"
      -e "s|https?://deb\\.debian\\.org/debian-security/?|${debian_security_mirror}|g"
      -e "s#https?://(${mirror_hosts_regex})/debian-security/?#${debian_security_mirror}#g"
    )
  fi

  for file in "${apt_files[@]}"; do
    backup_file "$file"
    run_cmd sed "${sed_args[@]}" "$file"
  done

  AFFECTED_FILES=$file_count
  log_success "$(fmt success_apt_switched "$(mirror_display_name "$MIRROR")" "$file_count")"
}

# 函数: switch_rpm_sources
# 功能: 切换 YUM/DNF 仓库源（RHEL/CentOS/Fedora/Rocky/AlmaLinux/openEuler）到目标镜像站
# 参数: 无（依赖全局 MIRROR / BACKUP_DIR）
# 返回值: 0 - 成功; 无可处理文件或不支持镜像时 die
# 副作用: 修改 /etc/yum.repos.d 下的 .repo 文件；修改前调用 backup_file 备份
switch_rpm_sources() {
  local file=""
  local file_count=0
  local need_centos=0
  local need_centos_stream=0
  local need_centos_vault=0
  local need_rocky=0
  local need_almalinux=0
  local need_fedora=0
  local need_epel=0
  local need_openeuler=0
  local centos_root=""
  local centos_stream_root=""
  local centos_vault_root=""
  local rocky_root=""
  local almalinux_root=""
  local fedora_root=""
  local epel_root=""
  local openeuler_root=""
  local mirror_hosts_regex=""
  local repo_files=()
  local sed_args=()
  local required_keys=()

  mirror_hosts_regex="$(known_mirror_hosts_regex)"

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    repo_files+=("$file")

    if grep -Eq "mirror\\.centos\\.org/centos|(${mirror_hosts_regex})/centos/" "$file"; then
      need_centos=1
    fi

    if grep -Eq "mirror\\.stream\\.centos\\.org|(${mirror_hosts_regex})/centos-stream/" "$file"; then
      need_centos_stream=1
    fi

    if grep -Eq "vault\\.centos\\.org/centos|(${mirror_hosts_regex})/centos-vault/" "$file"; then
      need_centos_vault=1
    fi

    if grep -Eq "(dl|download)\\.rockylinux\\.org|(${mirror_hosts_regex})/rocky/" "$file"; then
      need_rocky=1
    fi

    if grep -Eq "repo\\.almalinux\\.org|(${mirror_hosts_regex})/almalinux/" "$file"; then
      need_almalinux=1
    fi

    if grep -Eq "(download|dl)\\.fedoraproject\\.org/pub/fedora/linux|(${mirror_hosts_regex})/fedora/" "$file"; then
      need_fedora=1
    fi

    if grep -Eq "(download|dl)\\.fedoraproject\\.org/pub/epel|(${mirror_hosts_regex})/epel/" "$file"; then
      need_epel=1
    fi

    if grep -Eq "repo\\.openeuler\\.org|(${mirror_hosts_regex})/openeuler/" "$file"; then
      need_openeuler=1
    fi
  done < <(find /etc/yum.repos.d -maxdepth 1 -type f -name "*.repo" 2>/dev/null)

  file_count=${#repo_files[@]}
  (( file_count > 0 )) || die "$(text error_no_rpm_sources)"

  (( need_centos )) && required_keys+=(centos)
  (( need_centos_stream )) && required_keys+=(centos_stream)
  (( need_centos_vault )) && required_keys+=(centos_vault)
  (( need_rocky )) && required_keys+=(rocky)
  (( need_almalinux )) && required_keys+=(almalinux)
  (( need_fedora )) && required_keys+=(fedora)
  (( need_epel )) && required_keys+=(epel)
  (( need_openeuler )) && required_keys+=(openeuler)
  (( ${#required_keys[@]} > 0 )) || die "$(text error_no_known_rpm_entries)"

  if ! ensure_mirror_supports_keys "$MIRROR" "${required_keys[@]}"; then
    exit 1
  fi

  (( need_centos )) && centos_root="$(mirror_url_for centos)"
  (( need_centos_stream )) && centos_stream_root="$(mirror_url_for centos_stream)"
  (( need_centos_vault )) && centos_vault_root="$(mirror_url_for centos_vault)"
  (( need_rocky )) && rocky_root="$(mirror_url_for rocky)"
  (( need_almalinux )) && almalinux_root="$(mirror_url_for almalinux)"
  (( need_fedora )) && fedora_root="$(mirror_url_for fedora)"
  (( need_epel )) && epel_root="$(mirror_url_for epel)"
  (( need_openeuler )) && openeuler_root="$(mirror_url_for openeuler)"

  sed_args=(-E -i
    -e 's|^[[:space:]]*metalink=|# metalink=|g'
    -e 's|^[[:space:]]*mirrorlist=|# mirrorlist=|g'
    -e 's|^[[:space:]]*#([[:space:]]*baseurl=)|\1|g'
  )

  if [[ -n "$centos_root" ]]; then
    sed_args+=(
      -e "s|https?://mirror\\.centos\\.org/centos/?|${centos_root}/centos/|g"
      -e "s#https?://(${mirror_hosts_regex})/centos/?#${centos_root}/centos/#g"
    )
  fi

  if [[ -n "$centos_stream_root" ]]; then
    sed_args+=(
      -e "s|https?://mirror\\.stream\\.centos\\.org/?|${centos_stream_root}/|g"
      -e "s#https?://(${mirror_hosts_regex})/centos-stream/?#${centos_stream_root}/#g"
    )
  fi

  if [[ -n "$centos_vault_root" ]]; then
    sed_args+=(
      -e "s|https?://vault\\.centos\\.org/centos/?|${centos_vault_root}/centos/|g"
      -e "s#https?://(${mirror_hosts_regex})/centos-vault/centos/?#${centos_vault_root}/centos/#g"
    )
  fi

  if [[ -n "$rocky_root" ]]; then
    sed_args+=(
      -e "s|https?://dl\\.rockylinux\\.org/rocky/?|${rocky_root}/rocky/|g"
      -e "s|https?://download\\.rockylinux\\.org/rocky/?|${rocky_root}/rocky/|g"
      -e "s#https?://(${mirror_hosts_regex})/rocky/?#${rocky_root}/rocky/#g"
    )
  fi

  if [[ -n "$almalinux_root" ]]; then
    sed_args+=(
      -e "s|https?://repo\\.almalinux\\.org/almalinux/?|${almalinux_root}/almalinux/|g"
      -e "s#https?://(${mirror_hosts_regex})/almalinux/?#${almalinux_root}/almalinux/#g"
    )
  fi

  if [[ -n "$fedora_root" ]]; then
    sed_args+=(
      -e "s|https?://download\\.fedoraproject\\.org/pub/fedora/linux/?|${fedora_root}/|g"
      -e "s|https?://dl\\.fedoraproject\\.org/pub/fedora/linux/?|${fedora_root}/|g"
      -e "s#https?://(${mirror_hosts_regex})/fedora/?#${fedora_root}/#g"
    )
  fi

  if [[ -n "$epel_root" ]]; then
    sed_args+=(
      -e "s|https?://download\\.fedoraproject\\.org/pub/epel/?|${epel_root}/|g"
      -e "s|https?://dl\\.fedoraproject\\.org/pub/epel/?|${epel_root}/|g"
      -e "s#https?://(${mirror_hosts_regex})/epel/?#${epel_root}/#g"
    )
  fi

  if [[ -n "$openeuler_root" ]]; then
    sed_args+=(
      -e "s|https?://repo\\.openeuler\\.org|${openeuler_root}|g"
    )
  fi

  for file in "${repo_files[@]}"; do
    backup_file "$file"
    run_cmd sed "${sed_args[@]}" "$file"
  done

  AFFECTED_FILES=$file_count
  log_success "$(fmt success_rpm_switched "$(mirror_display_name "$MIRROR")" "$file_count")"
}

switch_pacman_sources() {
  local file="/etc/pacman.d/mirrorlist"
  local temp_file=""
  local mirror_root=""

  [[ -f "$file" ]] || die "$(fmt error_file_not_found "$file")"

  if ! ensure_mirror_supports_keys "$MIRROR" archlinux; then
    exit 1
  fi

  mirror_root="$(mirror_url_for archlinux)"
  backup_file "$file"

  if (( DRY_RUN )); then
    log_info "$(fmt info_would_prepend_arch "$mirror_root")"
    return 0
  fi

  temp_file="$(mktemp)"
  sed '/^## linux-mirror-switcher begin$/,/^## linux-mirror-switcher end$/d' "$file" >"$temp_file"
  {
    printf "## linux-mirror-switcher begin\n"
    printf "Server = %s\$repo/os/\$arch\n" "$mirror_root"
    printf "## linux-mirror-switcher end\n\n"
    cat "$temp_file"
  } >"${temp_file}.new"
  install -m 644 "${temp_file}.new" "$file"
  rm -f "$temp_file" "${temp_file}.new"

  AFFECTED_FILES=1
  log_success "$(text success_pacman_updated)"
}

switch_apk_sources() {
  local file="/etc/apk/repositories"
  local alpine_root=""
  local mirror_hosts_regex=""

  [[ -f "$file" ]] || die "$(fmt error_file_not_found "$file")"

  mirror_hosts_regex="$(known_mirror_hosts_regex)"
  if ! ensure_mirror_supports_keys "$MIRROR" alpine; then
    exit 1
  fi

  alpine_root="$(mirror_url_for alpine)"
  backup_file "$file"
  run_cmd sed -E -i \
    -e "s|https?://dl-cdn\\.alpinelinux\\.org/alpine|${alpine_root}|g" \
    -e "s|https?://dl-[0-9]+\\.alpinelinux\\.org/alpine|${alpine_root}|g" \
    -e "s#https?://(${mirror_hosts_regex})/alpine#${alpine_root}#g" \
    "$file"

  AFFECTED_FILES=1
  log_success "$(fmt success_apk_switched "$(mirror_display_name "$MIRROR")")"
}

# 函数: switch_zypper_sources
# 功能: 切换 Zypper 仓库地址（openSUSE）到目标镜像站，用 sed 替换 /etc/zypp/repos.d 下的 .repo 文件
# 参数: 无（依赖全局 MIRROR / BACKUP_DIR）
# 返回值: 0 - 成功; 无可处理文件时 die
# 副作用: 修改 /etc/zypp/repos.d 下的 .repo 文件；修改前调用 backup_file 备份
switch_zypper_sources() {
  local file=""
  local opensuse_root=""
  local file_count=0
  local mirror_hosts_regex=""

  mirror_hosts_regex="$(known_mirror_hosts_regex)"
  if ! ensure_mirror_supports_keys "$MIRROR" opensuse; then
    exit 1
  fi

  opensuse_root="$(mirror_url_for opensuse)"

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    file_count=$((file_count + 1))
    backup_file "$file"
    run_cmd sed -E -i \
      -e 's|^[[:space:]]*metalink=|# metalink=|g' \
      -e 's|^[[:space:]]*mirrorlist=|# mirrorlist=|g' \
      -e 's|^[[:space:]]*#([[:space:]]*baseurl=)|\1|g' \
      -e "s|https?://download\\.opensuse\\.org|${opensuse_root}|g" \
      -e "s#https?://(${mirror_hosts_regex})/opensuse#${opensuse_root}#g" \
      "$file"
  done < <(find /etc/zypp/repos.d -maxdepth 1 -type f -name "*.repo" 2>/dev/null)

  (( file_count > 0 )) || die "$(text error_no_zypper_sources)"
  AFFECTED_FILES=$file_count
  log_success "$(fmt success_zypper_switched "$(mirror_display_name "$MIRROR")" "$file_count")"
}

# 函数: refresh_package_index
# 功能: 换源或恢复后根据包管理器类型刷新软件包索引（apt-get update / dnf makecache / pacman -Syy 等）
# 参数: 无（依赖全局 PACKAGE_MANAGER / SKIP_REFRESH / BACKUP_DIR）
# 返回值: 0 - 成功; 刷新失败返回 1 并提示可执行的恢复命令（SKIP_REFRESH 时直接返回 0）
# 副作用: 成功后设置全局 REFRESH_RAN=1
refresh_package_index() {
  (( SKIP_REFRESH )) && return 0

  local refresh_ok=0

  case "$PACKAGE_MANAGER" in
    apt)
      if run_cmd apt-get update; then
        refresh_ok=1
      fi
      ;;
    dnf)
      if run_cmd dnf makecache; then
        refresh_ok=1
      fi
      ;;
    yum)
      if run_cmd yum makecache; then
        refresh_ok=1
      fi
      ;;
    pacman)
      if run_cmd pacman -Syy; then
        refresh_ok=1
      fi
      ;;
    apk)
      if run_cmd apk update; then
        refresh_ok=1
      fi
      ;;
    zypper)
      if run_cmd zypper refresh; then
        refresh_ok=1
      fi
      ;;
    *)
      die "$(fmt error_refresh_not_supported "$PACKAGE_MANAGER")"
      ;;
  esac

  if (( ! refresh_ok )); then
    log_error "$(fmt error_refresh_failed "$PACKAGE_MANAGER")"
    if [[ -n "$BACKUP_DIR" ]]; then
      if is_lang_en; then
        log_warn "The mirror config has been changed but the package index refresh failed."
        log_warn "You can restore the previous config with: bash <(curl -fsSL ${SCRIPT_URL}) --restore-from ${BACKUP_DIR} -y"
      else
        log_warn "镜像源配置已修改，但包索引刷新失败。"
        log_warn "可执行恢复命令：bash <(curl -fsSL ${SCRIPT_URL}) --restore-from ${BACKUP_DIR} -y"
      fi
    fi
    return 1
  fi

  REFRESH_RAN=1
  log_success "$(text success_refresh_completed)"
}

# 函数: parse_args
# 功能: 解析命令行参数，设置全局开关与操作模式
# 参数: $1..$N - 命令行参数
# 返回值: 0 - 继续执行; 遇到 --list-backups / --list-mirrors / --version / -h 时直接 exit
# 副作用: 设置 MIRROR / ACTION / RESTORE_SOURCE / DRY_RUN / SKIP_REFRESH / SKIP_BACKUP / OUTPUT_LANG 等
parse_args() {
  while (($# > 0)); do
    case "$1" in
      --mirror)
        shift
        [[ $# -gt 0 ]] || die "$(text error_mirror_requires_value)"
        MIRROR="$1"
        ;;
      --lang)
        shift
        [[ $# -gt 0 ]] || die "$(text error_lang_requires_value)"
        OUTPUT_LANG="$1"
        ;;
      --dry-run|--plan)
        DRY_RUN=1
        ;;
      --skip-refresh)
        SKIP_REFRESH=1
        ;;
      --skip-backup)
        SKIP_BACKUP=1
        ;;
      --restore)
        ACTION="restore"
        ;;
      --restore-from)
        shift
        [[ $# -gt 0 ]] || die "$(text error_restore_from_requires_dir)"
        ACTION="restore"
        RESTORE_SOURCE="$1"
        ;;
      --list-backups)
        list_backups
        exit 0
        ;;
      -y|--yes|--non-interactive)
        NON_INTERACTIVE=1
        ;;
      --list-mirrors|--list)
        list_mirrors
        exit 0
        ;;
      --version)
        printf "%s\n" "$SCRIPT_VERSION"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "$(fmt error_unknown_argument "$1")"
        ;;
    esac
    shift
  done

  case "$OUTPUT_LANG" in
    zh|en) ;;
    *)
      die "$(fmt error_invalid_lang "$OUTPUT_LANG")"
      ;;
  esac

  if [[ "$ACTION" == "switch" ]]; then
    if [[ -n "$MIRROR" ]]; then
      if ! is_supported_mirror "$MIRROR"; then
        die "$(fmt error_unsupported_mirror "$MIRROR")"
      fi
      MIRROR="$(canonical_mirror_id "$MIRROR")"
    elif (( NON_INTERACTIVE )); then
      MIRROR="$DEFAULT_MIRROR"
    fi
  fi
}

# 函数: perform_switch
# 功能: 根据检测到的包管理器分发到对应的换源实现
# 参数: 无（依赖全局 PACKAGE_MANAGER / MIRROR / BACKUP_DIR）
# 返回值: 0 - 成功; 不支持的包管理器 die
# 说明: 各分支会在修改前调用 backup_file 备份原始源文件
perform_switch() {
  case "$PACKAGE_MANAGER" in
    apt)
      switch_apt_sources
      ;;
    dnf|yum)
      switch_rpm_sources
      ;;
    pacman)
      switch_pacman_sources
      ;;
    apk)
      switch_apk_sources
      ;;
    zypper)
      switch_zypper_sources
      ;;
    *)
      die "$(fmt error_switch_not_supported "$PACKAGE_MANAGER")"
      ;;
  esac
}

# 函数: main
# 功能: 主流程：参数解析 → 系统检测 → 备份与换源/恢复 → 索引刷新 → 结果汇总
# 参数: $1..$N - 命令行参数
# 返回值: 0 - 成功; 非 0 - 刷新失败或用户取消
# 说明: 恢复路径不修改源文件结构，仅将备份文件按原绝对路径覆盖
main() {
  netool_acquire_lock "mirror" "另一个 mirror 实例正在运行，请等待其完成后再试。" || return 1
  local restore_dir=""

  parse_args "$@"
  reset_steps
  print_banner
  if (( ! DRY_RUN )); then
    require_root
  fi

  start_step "$(text section_inspecting_system)"
  detect_system
  detect_current_mirror
  print_runtime_summary

  if [[ "$ACTION" == "restore" ]]; then
    start_step "$(text section_preparing_restore)"
    restore_dir="$(resolve_restore_source)"
    log_info "$(fmt info_restore_source "$restore_dir")"

    if ! confirm "$(text prompt_restore_confirm)"; then
      log_info "$(text error_cancelled)"
      return 0
    fi

    start_step "$(text section_restoring_files)"
    restore_backup_tree "$restore_dir"
    if (( SKIP_REFRESH )); then
      log_warn "$(text warn_refresh_skipped)"
    else
      start_step "$(text section_refreshing_pkg_meta)"
      if ! refresh_package_index; then
        print_completion_summary "$(text result_success)"
        print_follow_up
        return 1
      fi
    fi
    log_success "$(text success_restore_completed)"
    print_completion_summary "$(text result_success)"
    print_follow_up
    return 0
  fi

  start_step "$(text section_preparing_switch)"
  if ! resolve_switch_mirror; then
    log_info "$(text error_cancelled)"
    return 0
  fi
  if ! confirm_same_mirror_if_needed; then
    log_info "$(text error_cancelled)"
    return 0
  fi
  log_info "$(fmt info_target_mirror "$(mirror_display_name "$MIRROR")")"

  if (( SKIP_BACKUP )); then
    log_warn "$(text warn_backup_disabled)"
  fi

  if ! confirm "$(text prompt_switch_confirm)"; then
    log_info "$(text error_cancelled)"
    return 0
  fi

  start_step "$(text section_switching_repo_config)"
  perform_switch
  if (( SKIP_REFRESH )); then
    log_warn "$(text warn_refresh_skipped)"
  else
    start_step "$(text section_refreshing_pkg_meta)"
    if ! refresh_package_index; then
      print_completion_summary "$(text result_success)"
      print_follow_up
      return 1
    fi
  fi

  if [[ -n "$BACKUP_DIR" && $SKIP_BACKUP -eq 0 ]]; then
    log_success "$(fmt success_backup_saved "$BACKUP_DIR")"
  fi

  log_success "$(text success_switch_completed)"
  print_completion_summary "$(text result_success)"
  print_follow_up
}

# 函数: interactive_menu
# 功能: 交互式菜单：循环展示换源/恢复/查看备份/查看镜像站，直到用户返回
# 参数: 无
# 返回值: 始终 0（用户选择返回时）
interactive_menu() {
  local answer=""
  local status=0

  while true; do
    printf "\n请选择操作：\n"
    printf "  1. 换源\n"
    printf "  2. 从备份恢复\n"
    printf "  3. 查看备份列表\n"
    printf "  4. 查看支持的镜像站\n"
    printf "  b. 返回\n"
    read -r -p "输入编号： " answer

    case "$answer" in
      1)
        ACTION="switch"
        MIRROR=""
        status=0
        main || status=$?
        if (( status != 0 )); then
          if is_lang_en; then
            log_warn "Operation did not complete (exit code: ${status}); returning to menu."
          else
            log_warn "操作未完成（退出码：${status}），返回菜单。"
          fi
        fi
        ;;
      2)
        ACTION="restore"
        status=0
        main || status=$?
        if (( status != 0 )); then
          if is_lang_en; then
            log_warn "Operation did not complete (exit code: ${status}); returning to menu."
          else
            log_warn "操作未完成（退出码：${status}），返回菜单。"
          fi
        fi
        ;;
      3)
        list_backups
        ;;
      4)
        list_mirrors
        ;;
      b|B|back|返回)
        log_info "已返回。"
        return 0
        ;;
      *)
        log_warn "无效输入，请输入 1-4 或 b 返回。"
        ;;
    esac
  done
}

# 函数: cli_main
# 功能: 命令行主流程：参数已显式提供时的直接执行路径（非交互式）
# 参数: $1..$N - 命令行参数
# 返回值: 成功 exit 0; 失败 die
cli_main() {
  parse_args "$@"
  reset_steps
  print_banner

  start_step "$(text section_inspecting_system)"
  detect_system
  detect_current_mirror
  print_runtime_summary

  if [[ "$ACTION" == "restore" ]]; then
    if (( ! DRY_RUN )); then
      require_root
    fi
    start_step "$(text section_preparing_restore)"
    restore_dir="$(resolve_restore_source)"
    log_info "$(fmt info_restore_source "$restore_dir")"

    if ! confirm "$(text prompt_restore_confirm)"; then
      die "$(text error_cancelled)"
    fi

    start_step "$(text section_restoring_files)"
    restore_backup_tree "$restore_dir"
    if (( SKIP_REFRESH )); then
      log_warn "$(text warn_refresh_skipped)"
    else
      start_step "$(text section_refreshing_pkg_meta)"
      refresh_package_index
    fi
    log_success "$(text success_restore_completed)"
    print_completion_summary "$(text result_success)"
    print_follow_up
    exit 0
  fi

  start_step "$(text section_preparing_switch)"
  resolve_switch_mirror
  confirm_same_mirror_if_needed
  log_info "$(fmt info_target_mirror "$(mirror_display_name "$MIRROR")")"

  if (( SKIP_BACKUP )); then
    log_warn "$(text warn_backup_disabled)"
  fi

  if ! confirm "$(text prompt_switch_confirm)"; then
    die "$(text error_cancelled)"
  fi

  if (( ! DRY_RUN )); then
    require_root
  fi

  start_step "$(text section_switching_repo_config)"
  perform_switch
  if (( SKIP_REFRESH )); then
    log_warn "$(text warn_refresh_skipped)"
  else
    start_step "$(text section_refreshing_pkg_meta)"
    refresh_package_index
  fi

  if [[ -n "$BACKUP_DIR" && $SKIP_BACKUP -eq 0 ]]; then
    log_success "$(fmt success_backup_saved "$BACKUP_DIR")"
  fi

  log_success "$(text success_switch_completed)"
  print_completion_summary "$(text result_success)"
  print_follow_up
}

# 函数: entry
# 功能: 脚本统一入口：根据是否显式提供参数决定走命令行模式或交互菜单
# 参数: $1..$N - 命令行参数
# 返回值: 透传 cli_main / interactive_menu 的退出码
entry() {
  parse_args "$@"

  if [[ -n "$MIRROR" || "$ACTION" == "restore" ]] || (( NON_INTERACTIVE )); then
    cli_main
  else
    interactive_menu
  fi
}

entry "$@"
