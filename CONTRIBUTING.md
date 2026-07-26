# 贡献指南

## 开发环境

- Bash 4.0+（目标运行环境）；开发机 Bash 3.2 也需兼容（勿使用 `${var,,}` 等 Bash 4 专有语法）
- 推荐安装 [shellcheck](https://www.shellcheck.net/)

## 新增工具规范

1. 脚本放在 `tools/<分类>/` 下
2. 头部声明 `SCRIPT_NAME`、`SCRIPT_VERSION`，并在 `tools/versions.env` 登记对应 `tool_id=version`
3. 使用 `set -Eeuo pipefail`
4. 引入公共库：

```bash
# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
```

4. 支持标准参数：`--help`、`--version`、`-y/--yes`、`--plan`/`--dry-run`
5. 修改系统配置必须备份并提供恢复方式
6. 在 `main.sh` 注册菜单项与路由
7. 更新 `CHANGELOG.md`

## 本地验证

```bash
# 语法检查
find . -name '*.sh' -exec bash -n {} \;

# shellcheck
shellcheck -x main.sh tools/common.sh tools/**/*.sh

# 冒烟测试
NETOOL_SKIP_LICENSE=1 bash main.sh check
NETOOL_SKIP_LICENSE=1 bash main.sh mirror --version
```

## 提交规范

- feat: 新功能
- fix: 修复
- refactor: 重构
- docs: 文档
- ci: CI 配置
