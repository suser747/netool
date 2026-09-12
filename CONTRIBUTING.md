# 贡献指南

感谢参与 netool 懒人工具箱的开发。

## 开发环境

- Bash 3.2+（须兼容 macOS 自带 Bash 与 CentOS 7 等旧环境）
- **最低建议：** CentOS 7 / Debian 9 / Ubuntu 16.04 同类环境（util-linux 2.23、systemd 219、GNU sed 4.2、Bash 4.2）；全能换源 lmirrors 需 Bash 4+
- 推荐安装 [shellcheck](https://www.shellcheck.net/)

## 本地验证

```bash
bash scripts/validate.sh          # 语法 + 冒烟 + 远程模拟
bash scripts/check-versions.sh    # 版本号与 versions.env 一致性
```

## 新增工具

1. 在 `tools/<分类>/` 下新增脚本
2. 头部引入 `load_common.sh` 并 `trap on_error ERR`
3. 在 `main.sh` 的 `tool_rel_path` / `resolve_selection` / `tool_display_name` 注册
4. 更新 `tools/versions.env` 与 `CHANGELOG.md`
5. 子菜单使用 `print_menu_nav_hint`；返回键统一为 `b`

## 编码规范

- 须兼容 **Bash 3.2 + `set -u`**（macOS 自带 Bash / 旧环境）
- **禁用** Bash 4+：`declare -A`、`local -n`、`mapfile`/`readarray`、`${var,,}`（用 `tolower`）
- 空数组展开必须用安全写法：`${arr[@]+"${arr[@]}"}`；禁止直接 `"${arr[@]}"`（空数组会 `unbound variable`）
- 读入多行到数组：用 `netool_mapfile`（见 `tools/common.sh`），勿用 `mapfile`
- 限时执行：用 `netool_run_timeout`，勿依赖 GNU `timeout`
- 旧 Linux 兼容：优先用 `tools/common.sh` 中的 `netool_*` 辅助函数，勿直接假设新特性可用
  - `netool_lsblk_mount_col` — `MOUNTPOINTS` vs `MOUNTPOINT`（util-linux ≥2.27）
  - `netool_lsblk_disk_paths` / `netool_lsblk_root_disk` — 无 `lsblk -p`/`-s`（util-linux 2.23）
  - `netool_lsblk_supports_p` / `netool_lsblk_dev_type` / `netool_lsblk_tree_*` — 擦盘等设备树枚举
  - `netool_systemctl_enable_now` — 无 `systemctl --now`（systemd 219）
  - `netool_listening_tcp_local_addrs` — 无 `ss -H` 时跳过表头，并回退 netstat
  - `netool_sed_ere_opt` — GNU sed `-r` vs BSD/GNU `-E`
  - `netool_sort_version` — 无 `sort -V` 时回退 plain `sort`
- 勿写死：`MOUNTPOINTS`、`ss -H`、`systemctl enable --now`、`sed -E`、`lsblk -p`（CentOS 7 可能不支持）
- 最低建议验证环境：CentOS 7；全能换源（lmirrors）另需 Bash 4+
- 破坏性操作：必须支持 `--plan`，执行前 `confirm_phrase` 或 `-y` + 明确参数
- 复用 `tools/common.sh` 中的 `require_root`、`confirm_*`、`log_*`，勿重复定义
- 改系统前 `backup_with_timestamp` 或工具内等价备份
- Linux 专用工具（磁盘擦除/SMART 等）须在业务逻辑前做平台判断；`--help` 可放行

## 提交

- 一个 PR 聚焦一类改动（功能 / 修复 / 文档）
- commit message 说明「为什么」而不只是「改了什么」

## 文档

- 用户文档以 `README.md` 为准
- 新功能设计见 `docs/ROADMAP.md`
