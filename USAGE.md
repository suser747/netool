# netool 懒人工具箱 — 完整使用说明

本文档涵盖 **curl 远程一键运行** 与 **本地部署运行** 两种方式的完整用法。当前主版本：**v2.1**。

---

## 目录

- [1. 快速选择运行方式](#1-快速选择运行方式)
- [2. curl 远程运行（无需上传）](#2-curl-远程运行无需上传)
- [3. 本地部署运行](#3-本地部署运行)
- [4. 入口参数与全局选项](#4-入口参数与全局选项)
- [5. 交互式菜单对照表](#5-交互式菜单对照表)
- [6. 全部工具命令参考](#6-全部工具命令参考)
- [7. 环境变量](#7-环境变量)
- [8. 安全机制与破坏性操作](#8-安全机制与破坏性操作)
- [9. 配置、日志与备份](#9-配置日志与备份)
- [10. 故障排查](#10-故障排查)
- [11. 相关文档](#11-相关文档)

---

## 1. 快速选择运行方式

| 方式 | 适用场景 | 是否需要上传 | 是否依赖 Gitee 网络 |
|------|----------|--------------|---------------------|
| **curl 远程** | 临时使用、快速运维、新机器开箱 | 否 | 是（每次按需下载脚本） |
| **本地部署** | 生产环境、离线/内网、频繁使用 | 是（克隆/FTP/scp） | 否（脚本在本地） |

**在线入口（固定地址）：**

```
https://gitee.com/suser747/netool/raw/master/main.sh
```

下文用 `$ENTRY` 代指上述地址。本地部署时用 `./main.sh` 代替 `bash <(curl -fsSL $ENTRY)`。

---

## 2. curl 远程运行（无需上传）

### 2.1 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux（Debian/Ubuntu、RHEL/CentOS、Arch、Alpine 及国产发行版等） |
| Shell | Bash 3.2+ |
| 必需命令 | `curl`、`bash` |
| 网络 | 能访问 `gitee.com` |
| 权限 | 查看类功能普通用户即可；改系统配置需 root / sudo |

### 2.2 推荐写法

**交互式菜单（首次使用）：**

```bash
# 推荐：进程替换，stdin 可用于菜单输入
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)

# 也可用管道（部分环境下菜单输入可能无响应）
curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh | bash
```

**参数式调用（日常推荐，不进入菜单）：**

```bash
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"

bash <(curl -fsSL "$ENTRY") check          # 功能检查
bash <(curl -fsSL "$ENTRY") status         # 状态面板
bash <(curl -fsSL "$ENTRY") versions       # 组件版本
bash <(curl -fsSL "$ENTRY") system info    # 系统信息
bash <(curl -fsSL "$ENTRY") mirror --plan  # 换源预览
bash <(curl -fsSL "$ENTRY") init           # 初始化向导
bash <(curl -fsSL "$ENTRY") --list         # 工具列表
bash <(curl -fsSL "$ENTRY") --help         # 帮助
```

**静默模式（只输出错误，适合脚本/CI）：**

```bash
bash <(curl -fsSL "$ENTRY") -q check
```

**设置快捷别名（可选，写入 `~/.bashrc`）：**

```bash
alias netool='bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)'
# 使用：netool status
```

### 2.3 远程模式工作原理

```
curl 下载 main.sh
       ↓
main.sh 启动
       ├─ 检测到本地 tools/ 目录 → 直接运行本地子脚本（见第 3 节）
       └─ 纯远程模式（仅有 main.sh）
              ├─ bootstrap 下载 tools/common.sh
              ├─ 按工具名下载对应子脚本（保留 tools/ 目录结构）
              ├─ bash -n 语法校验
              └─ 执行后清理临时目录
```

**内置功能（不下载子脚本）：** `check`、`status`、`versions`、`update`、`uninstall`

**按需下载子脚本：** `mirror`、`disk`、`ssh`、`system` 等其余工具

**disk 二次下载：** 验盘、SMART、盘位映射等由 `disk.sh` 再按需拉取

每次运行从 Gitee `master` 分支拉取最新代码，远程用户**无需手动更新**。

### 2.4 curl 方式完整命令示例

以下每条命令均可直接复制运行（将 `$ENTRY` 替换为实际 URL 或使用 alias）：

```bash
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"
R() { bash <(curl -fsSL "$ENTRY") "$@"; }

# ── 内置 ──
R check
R status
R versions
R update
R uninstall

# ── 系统 ──
R system info
R system update          # 仅打印更新命令，不自动执行
R system clean           # 仅打印清理命令
R system time-users
R system services
R host status
R swap status
R basic --plan
R basic -y
R logclean
R ntp status

# ── 网络 ──
R network ip
R network ports
R network ping 8.8.8.8
R network dns example.com
R bbr status
R bbr enable -y
R bench
R ssh --help
R ssl-check example.com

# ── 安全 ──
R firewall status
R security status
R user list
R cron list

# ── Docker ──
R docker status
R docker ps
R docker install --plan
R docker install -y

# ── 磁盘（! 破坏性操作见第 8 节）──
R disk status
R disk-test --plan
R disk slot-map
R smart-long
R du-analyze /var

# ── 软件源 ──
R mirror --plan
R mirror -y
R lmirrors --help
R homebrew

# ── 向导 ──
R init
```

---

## 3. 本地部署运行

### 3.1 获取项目

**方式 A：Git 克隆（推荐）**

```bash
git clone https://gitee.com/suser747/netool.git
cd netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

**方式 B：scp 上传**

```bash
scp -r /本地路径/netool/* user@服务器IP:/opt/netool/
ssh user@服务器IP "chmod +x /opt/netool/main.sh && find /opt/netool/tools -name '*.sh' -exec chmod +x {} \;"
```

**方式 C：SFTP / FileZilla**

详见 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md)。

**推荐安装目录：**

- `/opt/netool/` — 全局共用（推荐）
- `~/netool/` — 个人用户

### 3.2 本地运行方式

```bash
cd /opt/netool    # 进入项目目录

./main.sh                    # 交互式菜单
./main.sh check              # 功能检查
./main.sh status             # 状态面板
./main.sh system info        # 系统信息
./main.sh mirror --plan      # 换源预览
./main.sh init               # 初始化向导
./main.sh --list             # 工具列表
./main.sh --help             # 帮助
./main.sh --version          # 主版本号
./main.sh versions           # 全部组件版本
```

**设置全局命令（可选）：**

```bash
ln -sf /opt/netool/main.sh /usr/local/bin/netool
chmod +x /usr/local/bin/netool

netool status
netool system info
```

### 3.3 本地模式优势

- 所有脚本在磁盘上，**不依赖 Gitee** 即可运行子工具
- 执行速度更快（无下载等待）
- 适合内网、离线环境（改配置类操作本身可能仍需联网下载软件包）
- 可用 `git pull --ff-only origin master` 更新

### 3.4 更新本地副本

```bash
cd /opt/netool
git pull --ff-only origin master
# 或使用内置说明
./main.sh update
```

无 Git 环境时，重新上传/覆盖整个目录即可。

---

## 4. 入口参数与全局选项

### 4.1 调用形式

```bash
# 远程
bash <(curl -fsSL $ENTRY) [全局选项] [工具名] [工具参数...]

# 本地
./main.sh [全局选项] [工具名] [工具参数...]
```

- **不带工具名**：进入交互式分类菜单
- **带工具名**：直接调用对应子工具，后续参数原样转发

### 4.2 全局选项

| 选项 | 说明 |
|------|------|
| `-h`, `--help` | 显示帮助 |
| `--version` | 显示主版本号（如 `2.1`） |
| `--list` | 显示分类菜单项列表 |
| `-q`, `--quiet` | 静默模式，仅输出错误 |
| `--license` | 显示用户许可协议 URL |

### 4.3 内置动作（非子工具）

| 命令 | 说明 |
|------|------|
| `check` | 检查各功能依赖命令是否可用 |
| `status` | 只读状态面板（系统/网络/安全/Docker） |
| `versions` | 显示主版本与各组件版本矩阵 |
| `update` | 本地 Git 拉取或远程更新说明 |
| `uninstall` | 删除工具箱配置与审计日志 |
| `init` | 新服务器初始化向导 |

---

## 5. 交互式菜单对照表

进入菜单后，可输入**编号**或**工具别名**：

| 编号 | 功能 | 等价命令 |
|------|------|----------|
| **01** | 功能检查 | `check` |
| **02** | 状态面板 | `status` |
| **03** | 组件版本 | `versions` |
| **00** | 更新脚本 | `update` |
| **0** | 退出 | — |
| 1 | 系统信息 | `system info` |
| 2 | 系统更新* | `system update` |
| 3 | 系统清理* | `system clean` |
| 4 | SSH 管理 | `ssh` |
| 5 | 容器状态 | `docker status` |
| 6 | 网络端口 | `network ports` |
| 7 | 磁盘管理 | `disk` |
| 8 | 验盘检测! | `disk-test` |
| 9 | 盘位映射 | `disk slot-map` |
| 10 | SMART 长测 | `smart-long` |
| 11 | 时间/用户 | `system time-users` |
| 12 | 运行服务 | `system services` |
| 13 | DNS 测试 | `network dns` |
| 14 | Ping 测试 | `network ping` |
| 15 | 轻量换源 | `mirror` |
| 16 | 镜像/卷/网络 | `docker images` |
| 17 | 基础工具 | `basic` |
| 18 | BBR 优化 | `bbr` |
| 19 | 性能测试 | `bench` |
| 20 | Swap 管理 | `swap` |
| 21 | 防火墙 | `firewall` |
| 22 | 安装 Docker | `docker install` |
| 23 | 主机/时区 | `host` |
| 24 | Fail2ban | `security` |
| 25 | 进程/服务 | `service` |
| 26 | Homebrew | `homebrew` |
| 27 | 全能换源 | `lmirrors` |
| 28 | 初始化向导 | `init` |
| 29 | 卸载工具箱 | `uninstall` |
| 30 | 日志清理 | `logclean` |
| 31 | 用户管理 | `user` |
| 32 | 定时任务 | `cron` |
| 33 | 时间同步 | `ntp` |
| 34 | 证书检查 | `ssl-check` |
| 35 | 磁盘占用 | `du-analyze` |

> `*` 仅提示命令，不自动执行。`!` 为破坏性操作，请先 `--plan` 预览。

---

## 6. 全部工具命令参考

以下示例同时给出 **本地** 与 **curl 远程** 写法。

### 6.1 系统查看与维护

| 工具 | 说明 | 本地示例 | curl 示例 |
|------|------|----------|-----------|
| `system` | 系统信息 | `./main.sh system info` | `bash <(curl -fsSL $ENTRY) system info` |
| `system update` | 打印系统更新命令 | `./main.sh system update` | 同上替换前缀 |
| `system clean` | 打印清理命令 | `./main.sh system clean` | 同上 |
| `system time-users` | 时间与时区、登录用户 | `./main.sh system time-users` | 同上 |
| `system services` | 运行中的 systemd 服务 | `./main.sh system services` | 同上 |
| `host` | 主机名/时区管理 | `./main.sh host status` | 同上 |
| `swap` | Swap 查看/创建/删除 | `./main.sh swap status` | 同上 |
| `basic` | 基础工具批量安装 | `./main.sh basic --plan` | 同上 |
| `logclean` | 日志与缓存清理 | `./main.sh logclean` | 同上 |
| `ntp` | 时间同步（chrony 等） | `./main.sh ntp status` | 同上 |
| `du-analyze` | 磁盘占用分析 | `./main.sh du-analyze /var` | 同上 |

### 6.2 网络

| 工具 | 说明 | 常用示例 |
|------|------|----------|
| `network` | IP/路由/端口/连通性 | `network ip` / `network ports` / `network ping 1.1.1.1` / `network dns google.com` |
| `bbr` | BBR 拥塞控制 | `bbr status` / `bbr enable -y` / `bbr disable -y` |
| `bench` | 轻量性能测试 | `bench` |
| `ssh` | SSH 端口安全切换 | `ssh --port 2222 --mode staged -y` |
| `ssl-check` | HTTPS 证书到期 | `ssl-check example.com` |

### 6.3 安全与用户

| 工具 | 说明 | 常用示例 |
|------|------|----------|
| `firewall` | 防火墙端口管理 | `firewall status` |
| `security` | Fail2ban SSH 防护 | `security status` |
| `user` | 用户与 SSH 密钥 | `user list` |
| `cron` | 定时任务管理 | `cron list` |

### 6.4 Docker

| 工具 | 说明 | 常用示例 |
|------|------|----------|
| `docker` | 容器/镜像/安装 | `docker status` / `docker ps` / `docker images` / `docker install --plan` / `docker install -y` |

### 6.5 磁盘与硬件

| 工具 | 说明 | 常用示例 | 风险 |
|------|------|----------|------|
| `disk` | 磁盘管理菜单 | `disk` / `disk status` / `disk partition` | 分区/格式化会清数据 |
| `disk-test` | 全盘读写验盘 | `disk-test --plan` | **破坏性**，清空被测盘 |
| `slot-map` | 硬盘盘位映射 | `disk slot-map` | 低 |
| `smart-long` | SMART 长测 | `smart-long` | 低 |
| `disk wipe` | 整盘擦除 | `disk wipe --plan --devices /dev/sdX` | **破坏性** |

### 6.6 软件源与软件

| 工具 | 说明 | 区别 |
|------|------|------|
| `mirror` | 轻量换源 | 主流发行版、自动备份、一键恢复，适合大多数场景 |
| `lmirrors` | 全能换源 | 更多发行版、Docker 源、海外/教育网模式 |
| `homebrew` | Homebrew 管理 | macOS / Linux，国内镜像安装 |

**换源常用示例：**

```bash
./main.sh mirror --plan              # 预览
./main.sh mirror -y                  # 执行换源
./main.sh mirror --restore           # 恢复最近一次备份
./main.sh lmirrors --help            # 全能换源帮助
```

### 6.7 快捷工具

| 工具 | 说明 |
|------|------|
| `init` | 新服务器逐步初始化向导（系统检查→换源→BBR→SSH→Docker 等） |
| `uninstall` | 删除 `~/.config/netool/` 与 `/var/log/netool/`（不卸载已装软件） |

---

## 7. 环境变量

| 变量 | 说明 |
|------|------|
| `NETOOL_SKIP_LICENSE=1` | 跳过首次许可协议提示（自动化/CI） |
| `NETOOL_SKIP_LOCALE_TIP=1` | 跳过中文 locale 修复提示 |
| `NETOOL=1` | 由 main.sh 自动设置，表示子工具被主入口调用 |
| `NETOOL_REMOTE=1` | 远程模式标记（自动设置） |
| `YES=1` / `-y` | 子工具非交互模式（视具体工具支持） |

**自动化示例：**

```bash
export NETOOL_SKIP_LICENSE=1
export NETOOL_SKIP_LOCALE_TIP=1
bash <(curl -fsSL $ENTRY) -q check
```

---

## 8. 安全机制与破坏性操作

### 8.1 通用安全设计

1. **预览模式**：多数改配置工具支持 `--plan` / `--dry-run`，只显示计划不写入
2. **确认机制**：`-y` / `--yes` 跳过交互；破坏性操作另有确认短语
3. **自动备份**：SSH、BBR、换源、防火墙等修改前会备份到 `/var/backups/`
4. **远程校验**：curl 模式下载的脚本执行前 `bash -n` 语法检查
5. **审计日志**：root 下关键操作记录到 `/var/log/netool/audit.log`

### 8.2 破坏性操作清单

| 操作 | 预览命令 | 真正执行要求 |
|------|----------|--------------|
| 硬盘验盘 | `disk-test --plan` | `--yes` + 确认短语 `DESTROY-DISK-TEST` |
| 整盘擦除 | `disk wipe --plan --devices /dev/sdX` | 显式 `--devices` + 确认短语 `WIPE-CONFIRM` |
| 磁盘分区/格式化 | `disk partition`（交互确认） | 逐步确认 |

**验盘预览（远程/本地通用）：**

```bash
bash <(curl -fsSL $ENTRY) disk-test --plan
# 或本地
./main.sh disk-test --plan
```

---

## 9. 配置、日志与备份

| 路径 | 说明 |
|------|------|
| `~/.config/netool/` | 用户配置（许可确认等） |
| `~/.config/ayu-toolbox/` | 旧版路径（仍兼容读取） |
| `/var/log/netool/audit.log` | 审计日志（仅 root，权限 600） |
| `/var/backups/netool-*` | 各工具配置备份目录 |

**查看版本：**

```bash
./main.sh --version     # 主版本 2.1
./main.sh versions        # 全部组件版本列表
```

版本定义文件：`VERSION`（主版本）、`tools/versions.env`（组件版本）。

---

## 10. 故障排查

### 菜单无法输入（curl 管道模式）

```bash
# 不要用 curl | bash，改用：
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)
```

### curl 下载失败

```bash
curl -I https://gitee.com          # 测试连通
# 重试
for i in 1 2 3; do curl -fsSL $ENTRY | bash && break; sleep 2; done
```

### 提示「下载脚本失败」

1. 确认分支为 `master`（不是 `main`）
2. 确认已安装 `curl`
3. 改用 [本地部署](#3-本地部署运行)

### 中文乱码

```bash
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
export NETOOL_SKIP_LOCALE_TIP=1   # 跳过提示
```

### Permission denied（本地）

```bash
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

---

## 11. 相关文档

| 文档 | 内容 |
|------|------|
| [README.md](./README.md) | 项目概览与快速开始 |
| [REMOTE_USAGE.md](./REMOTE_USAGE.md) | curl 远程专题（故障排查、维护者说明） |
| [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md) | SFTP/scp 上传部署专题 |
| [USER_AGREEMENT.md](./USER_AGREEMENT.md) | 用户许可协议 |
| [CHANGELOG.md](./CHANGELOG.md) | 版本变更记录 |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | 开发与贡献规范 |
