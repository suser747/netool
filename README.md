# netool 懒人工具箱

命令行懒人向 Linux 运维脚本。一个入口，菜单或参数调用，覆盖系统维护、网络、安全、磁盘、Docker、换源等场景。

## 快速开始

> 远程一键运行详见 **[REMOTE_USAGE.md](./REMOTE_USAGE.md)**

```bash
# 在线运行（Gitee master 分支）
curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh | bash

# 带参数调用（推荐）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) check
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) mirror --plan

# 本地运行
git clone https://gitee.com/suser747/netool.git
cd netool && bash main.sh
```

## 核心特性

- **双模式**：`curl|bash` 远程一键执行 + 本地/FTP 部署
- **安全机制**：`--plan` 预览 + `-y` 确认 + 破坏性操作确认短语
- **配置备份**：SSH、BBR、换源、防火墙等均可回滚
- **跨发行版**：Debian/RHEL/Arch/Alpine 及国产系统
- **审计日志**：root 下操作记录到 `/var/log/netool/audit.log`

## 常用命令

| 命令 | 说明 |
|------|------|
| `check` | 检查依赖与功能可用性 |
| `status` | 一键状态面板（只读摘要） |
| `versions` | 查看主版本与各组件版本 |
| `system` | 系统信息与维护 |
| `mirror` / `lmirrors` | 轻量换源 / 全能换源 |
| `ssh` | SSH 端口管理（支持 staged 模式） |
| `disk` / `disk-test` | 磁盘管理 / 验盘（破坏性） |
| `init` | 新服务器初始化向导 |
| `uninstall` | 卸载工具箱配置与日志 |

完整命令列表：`bash main.sh --list` 或 `bash main.sh --help`

## 项目结构

```
main.sh                 # 统一入口
VERSION                 # 主版本号
tools/common.sh         # 公共函数库
tools/versions.env      # 各组件版本号
tools/version.sh        # 版本展示函数
tools/system/           # 系统维护
tools/network/          # 网络工具
tools/security/         # 安全与用户
tools/disk/             # 磁盘硬件
tools/docker/           # Docker
tools/software/         # 换源与软件
tools/utility/          # 初始化向导
scripts/validate.sh     # 本地验证
```

## 配置与日志

| 路径 | 说明 |
|------|------|
| `~/.config/netool/` | 用户配置（许可确认等） |
| `/var/log/netool/` | 审计日志（root） |
| `/var/backups/netool-*` | 各工具配置备份 |

> 兼容旧版 `~/.config/ayu-toolbox/` 路径。

## 开发

```bash
bash scripts/validate.sh    # 本地语法检查 + 冒烟测试
```

详见 [CONTRIBUTING.md](./CONTRIBUTING.md)、[CHANGELOG.md](./CHANGELOG.md)。

## License

[Apache License 2.0](./LICENSE)
