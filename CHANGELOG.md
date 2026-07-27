# Changelog

## [2.3.0] - 2026-07-27

### 新增

- **应用 / 中间件** 全栈模块（`tools/apps/`）：
  - `web` — Nginx/Apache/Caddy 状态与配置检查
  - `db` — MySQL/PG/Redis 状态与配置（只读，不回显密码）
  - `app-config` — Compose/.env/Supervisor 扫描与权限审计
  - `audit` — 用户/sudo/SSH/文件权限只读审计
  - `logs` — 日志占用、ERROR tail、监控 agent、logrotate 提示
  - `cron-templates` — cert-renew / disk-alert / log-truncate 模板

### 菜单

- 重组主菜单：应用运维 20–25、软件源 26–28、快捷 29–31
- `validate.sh` / `test-remote.sh` 增加新模块冒烟测试

## [2.2.0] - 2026-07-27

### 交互

- 主菜单改为**大类入口**（选编号进入子脚本二级菜单）
- 执行前反馈、完成后 Enter 返回；统一导航说明（主菜单 `0` 退出 · 子菜单 `b` 返回）
- 非 TTY stdin 警告并提示 `bash <(curl ...)`；菜单 25 / CLI `update`·`self-update` 更新工具箱

### 功能

- 实现 `-y/--yes`、`-q/--quiet` 并 export 至子工具（`NON_INTERACTIVE` / `QUIET`）
- 远程子脚本可选缓存 `~/.cache/netool/`（`NETOOL_NO_CACHE=1` 禁用）

### 工程

- 子脚本移除重复的 `require_root` / `confirm_*` / `on_error`（统一 common.sh）
- 新增 `USER_AGREEMENT.md`、`CONTRIBUTING.md`、`docs/ROADMAP.md`
- 新增 `scripts/check-versions.sh` 版本一致性校验
- 在线入口 URL 与 README 短链统一（`NETOOL_SHORT_ENTRY_URL`）

## [2.1.1] - 2026-07-27

### 修复

- **修复菜单选编号无反应**：`load_common.sh` 误判 `|| exit 0` 导致子脚本加载后立即退出
- `main.sh status` 在 macOS 上 `hostname -I` 不可用时不致整脚本中断

## [2.1.0] - 2026-07-25

### 修复

- 修正 13 个子脚本 `common.sh` 引用路径，新增 `tools/load_common.sh` 统一加载
- **修复 curl 远程模式**：main.sh 可在线 bootstrap common.sh；子脚本按目录结构下载；兼容 Gitee 旧版脚本
- `run_init_wizard` 远程模式下改为通过 `run_tool init` 下载执行
- `disk.sh` 磁盘子脚本远程下载时同步拉取 common.sh
- 统一远程 raw URL 为 `master` 分支
- 修复 `set -u` 下空数组未绑定变量；Bash 3.2 兼容 `tolower()`

### 文档

- 精简 [README.md](./README.md)：curl 远程 vs 本地直接使用分栏说明、命令对照表、项目截图占位（`docs/images/`）
- 核心库与子脚本补充运行方式注释；`main.sh` 各函数增加说明注释

### 优化

- 重构 `tools/common.sh`：统一路径常量、并发锁、语法校验、许可文件兼容
- `main.sh` 引入公共库，去除重复日志/审计/输入函数
- 远程子脚本下载后增加 `bash -n` 语法校验
- `check_display_env` 仅在 locale 异常时提示，移除无条件 3 秒等待
- 品牌路径统一为 `netool`（配置 `~/.config/netool/`，日志 `/var/log/netool/`），兼容旧 `ayu-toolbox` 路径

### 工程化

- 新增 GitHub Actions CI（shellcheck + bash -n + 冒烟测试）
- 新增 `.editorconfig`、`CONTRIBUTING.md`

## [2.0.0] - 2026-07-25

- 初次发布：分类工具箱、35+ 运维工具、破坏性操作三重防护
