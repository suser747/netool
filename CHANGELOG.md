# Changelog

## [2.1.0] - 2026-07-25

### 修复

- 修正 13 个子脚本 `common.sh` 引用路径，新增 `tools/load_common.sh` 统一加载
- **修复 curl 远程模式**：main.sh 可在线 bootstrap common.sh；子脚本按目录结构下载；兼容 Gitee 旧版脚本
- `run_init_wizard` 远程模式下改为通过 `run_tool init` 下载执行
- `disk.sh` 磁盘子脚本远程下载时同步拉取 common.sh
- 统一远程 raw URL 为 `master` 分支
- 修复 `set -u` 下空数组未绑定变量；Bash 3.2 兼容 `tolower()`

### 新增

- 完整使用说明已整合至 [README.md](./README.md)（含 curl 远程、本地部署、分系统教程、许可协议、贡献指南）
- `scripts/test-remote.sh` 远程模式自动化测试

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
