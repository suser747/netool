# 贡献指南

感谢参与 netool 懒人工具箱的开发。

## 开发环境

- Bash 3.2+（须兼容 macOS 自带 Bash 与 CentOS 7 等旧环境）
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

- 禁用 Bash 4+ 专有语法（如 `${var,,}`）
- 破坏性操作：必须支持 `--plan`，执行前 `confirm_phrase` 或 `-y` + 明确参数
- 复用 `tools/common.sh` 中的 `require_root`、`confirm_*`、`log_*`，勿重复定义
- 改系统前 `backup_with_timestamp` 或工具内等价备份

## 提交

- 一个 PR 聚焦一类改动（功能 / 修复 / 文档）
- commit message 说明「为什么」而不只是「改了什么」

## 文档

- 用户文档以 `README.md` 为准
- 新功能设计见 `docs/ROADMAP.md`
