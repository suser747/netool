# netool 懒人工具箱

命令行懒人向 Linux 运维脚本。一个入口，菜单或参数调用，覆盖系统维护、网络、安全、磁盘、Docker、换源等场景。

> **完整使用说明（本地 + curl 远程）：[USAGE.md](./USAGE.md)**

## 快速开始

### curl 远程（无需上传）

```bash
# 在线入口
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"

# 交互菜单（推荐进程替换写法）
bash <(curl -fsSL "$ENTRY")

# 参数调用（日常推荐）
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
bash <(curl -fsSL "$ENTRY") system info
bash <(curl -fsSL "$ENTRY") mirror --plan
```

### 本地部署

```bash
git clone https://gitee.com/suser747/netool.git
cd netool
chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;

./main.sh                  # 菜单
./main.sh check            # 功能检查
./main.sh status           # 状态面板
./main.sh system info      # 系统信息
```

上传/FTP 部署见 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md)。

## 核心特性

- **双模式**：`curl|bash` 远程一键执行 + 本地/FTP 部署
- **状态面板**：`status` 只读汇总系统/网络/安全/Docker
- **版本管理**：`versions` 查看全部组件版本
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

完整命令与菜单对照见 **[USAGE.md](./USAGE.md)**，或运行 `bash main.sh --list` / `bash main.sh --help`。

## 文档索引

| 文档 | 说明 |
|------|------|
| **[USAGE.md](./USAGE.md)** | **完整使用说明（本地 + curl，推荐阅读）** |
| [REMOTE_USAGE.md](./REMOTE_USAGE.md) | curl 远程专题与故障排查 |
| [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md) | SFTP/scp 本地上传部署 |
| [USER_AGREEMENT.md](./USER_AGREEMENT.md) | 用户许可协议 |
| [CHANGELOG.md](./CHANGELOG.md) | 版本变更 |

## 项目结构

```
main.sh                 # 统一入口
VERSION                 # 主版本号
USAGE.md                # 完整使用说明
tools/common.sh         # 公共函数库
tools/versions.env      # 各组件版本号
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

## 开发

```bash
bash scripts/validate.sh    # 语法检查 + 冒烟测试
```

详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## License

[Apache License 2.0](./LICENSE)
