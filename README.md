# netool 懒人工具箱

命令行懒人向 Linux 运维脚本。**一个入口、菜单或参数调用**，覆盖系统维护、网络、安全、磁盘、Docker、换源等场景。当前版本：**v2.1**。

**在线入口（固定）：**

```
https://gitee.com/suser747/netool/raw/master/main.sh
```

下文 `$ENTRY` 代指上述地址；本地部署时用 `./main.sh` 代替 `bash <(curl -fsSL "$ENTRY")`。

---

## 目录

- [一、项目简介](#一项目简介)
- [二、如何选择运行方式](#二如何选择运行方式)
- [三、curl 远程运行](#三curl-远程运行)
- [四、本地部署（Git / 上传）](#四本地部署git--上传)
- [五、分系统详细教程](#五分系统详细教程)
  - [5.1 Debian / Ubuntu](#51-debian--ubuntu)
  - [5.2 CentOS / RHEL / Rocky / AlmaLinux](#52-centos--rhel--rocky--almalinux)
  - [5.3 Fedora](#53-fedora)
  - [5.4 Arch Linux / Manjaro](#54-arch-linux--manjaro)
  - [5.5 Alpine Linux](#55-alpine-linux)
  - [5.6 openSUSE](#56-opensuse)
  - [5.7 国产 Linux（openEuler / Anolis 等）](#57-国产-linuxopeneuler--anolis-等)
  - [5.8 macOS（管理远程 Linux）](#58-macos管理远程-linux)
  - [5.9 Windows WSL2](#59-windows-wsl2)
- [六、命令与菜单参考](#六命令与菜单参考)
- [七、环境变量与安全](#七环境变量与安全)
- [八、用户许可协议](#八用户许可协议)
- [九、配置、日志与故障排查](#九配置日志与故障排查)
- [十、开发与贡献](#十开发与贡献)
- [十一、License 与变更记录](#十一license-与变更记录)

---

## 一、项目简介

### 核心特性

| 特性 | 说明 |
|------|------|
| 双模式 | curl 远程一键执行 + 本地/Git/FTP 部署 |
| 状态面板 | `status` 只读汇总系统/网络/安全/Docker |
| 版本管理 | `versions` 查看全部组件版本 |
| 安全机制 | `--plan` 预览、`-y` 确认、破坏性操作确认短语 |
| 配置备份 | SSH、BBR、换源、防火墙等可回滚 |
| 跨发行版 | Debian/RHEL/Arch/Alpine 及主流国产系统 |
| 审计日志 | root 操作记录至 `/var/log/netool/audit.log` |

### 项目结构

```
netool/
├── main.sh              # 统一入口
├── VERSION              # 主版本号
├── tools/
│   ├── common.sh        # 公共函数库
│   ├── load_common.sh   # 公共库加载器
│   ├── versions.env     # 组件版本清单
│   ├── system/          # 系统维护
│   ├── network/         # 网络工具
│   ├── security/        # 安全与用户
│   ├── disk/            # 磁盘硬件
│   ├── docker/          # Docker
│   ├── software/        # 换源与软件
│   └── utility/         # 初始化向导
└── scripts/validate.sh  # 本地验证
```

### 30 秒快速体验

```bash
# 远程：功能检查 + 状态面板
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status

# 本地（已克隆到 /opt/netool 时）
cd /opt/netool && ./main.sh check && ./main.sh status
```

---

## 二、如何选择运行方式

| 方式 | 适用场景 | 需上传 | 需访问 Gitee |
|------|----------|--------|--------------|
| **curl 远程** | 临时运维、新机器开箱、快速验证 | 否 | 是 |
| **本地部署** | 生产环境、内网、频繁使用 | 是 | 否（脚本本地） |

| | curl 远程 | 本地部署 |
|---|-----------|----------|
| 安装成本 | 零 | 克隆或上传一次 |
| 执行速度 | 有下载延迟 | 更快 |
| 离线 | 需联网拉脚本 | 脚本可离线 |
| 更新 | 自动最新 | `git pull` 或重新上传 |

**推荐安装目录（本地）：** `/opt/netool/`（全局）或 `~/netool/`（个人）

---

## 三、curl 远程运行

### 3.1 通用要求

| 项目 | 要求 |
|------|------|
| 系统 | Linux（见第五节分系统教程） |
| Shell | Bash 3.2+ |
| 必需命令 | `curl`、`bash` |
| 网络 | 能访问 `gitee.com` |
| 权限 | 查看类普通用户即可；改配置需 root/sudo |

### 3.2 安装 curl（各系统命令见第五节）

若已安装可跳过。未安装时无法使用远程模式。

### 3.3 推荐调用方式

**① 交互菜单（首次使用）**

```bash
# ✅ 推荐：进程替换，菜单可正常输入
bash <(curl -fsSL "$ENTRY")

# ⚠️ 管道模式：部分环境菜单无法输入
curl -fsSL "$ENTRY" | bash
```

**② 参数调用（日常推荐）**

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

**③ 静默模式（脚本/CI）**

```bash
bash <(curl -fsSL "$ENTRY") -q check
```

**④ 全局别名（写入 `~/.bashrc`）**

```bash
alias netool='bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)'
# 使用：netool status
```

### 3.4 远程工作原理

```
curl 下载 main.sh
    ↓
main.sh 启动
    ├─ 本地存在 tools/ → 直接运行本地子脚本
    └─ 纯远程模式
           ├─ bootstrap 下载 tools/common.sh
           ├─ 按需下载子脚本 + bash -n 校验
           └─ 执行后清理临时目录
```

- **内置（不下载子脚本）：** `check`、`status`、`versions`、`update`、`uninstall`
- **按需下载：** `mirror`、`disk`、`ssh`、`system` 等
- **disk 二次下载：** 验盘、SMART、盘位映射等

每次运行拉取 Gitee `master` 最新代码，**远程用户无需手动更新**。

### 3.5 远程故障排查

| 现象 | 处理 |
|------|------|
| 菜单无法输入 | 改用 `bash <(curl -fsSL "$ENTRY")`，勿用 `curl \| bash` |
| 下载失败 | `curl -I https://gitee.com` 测连通；重试或改本地部署 |
| 缺少 curl | 见第五节对应系统安装命令 |
| 中文乱码 | `export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8` |
| 下载脚本失败 | 确认分支为 `master`；确认 main.sh 为 v2.1+ |

```bash
# 下载重试
for i in 1 2 3; do curl -fsSL "$ENTRY" | bash && break; sleep 2; done
```

---

## 四、本地部署（Git / 上传）

### 4.1 Git 克隆（推荐）

```bash
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 4.2 scp 上传

```bash
# 本地执行
scp -r -P 22 /本地路径/netool/* user@服务器IP:/opt/netool/

# 服务器赋权
ssh -p 22 user@服务器IP \
  "chmod +x /opt/netool/main.sh && find /opt/netool/tools -name '*.sh' -exec chmod +x {} \;"
```

### 4.3 SFTP 命令行

```bash
sftp -P 22 user@服务器IP
cd /opt
mkdir netool
cd netool
put -r /本地路径/netool/* .
bye

# 登录服务器
ssh user@服务器IP
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
```

### 4.4 FileZilla 图形界面

1. 新建 SFTP 站点，连接服务器  
2. 右侧进入 `/opt/netool/`，左侧选择本地 `netool/` 目录  
3. 拖拽上传全部文件  
4. SSH 登录执行赋权命令（同 4.1）

### 4.5 本地运行

```bash
cd /opt/netool

./main.sh                    # 交互菜单
./main.sh check              # 功能检查
./main.sh status             # 状态面板
./main.sh versions           # 组件版本
./main.sh system info        # 系统信息
./main.sh mirror --plan      # 换源预览
./main.sh init               # 初始化向导
./main.sh --version          # 主版本
./main.sh --list             # 菜单列表
```

**全局快捷命令：**

```bash
ln -sf /opt/netool/main.sh /usr/local/bin/netool
netool status
```

### 4.6 更新本地副本

```bash
cd /opt/netool
git pull --ff-only origin master   # 有 Git 时
./main.sh update                   # 查看更新说明
```

无 Git 时重新 scp/FTP 覆盖即可。

---

## 五、分系统详细教程

以下每节包含：**安装依赖 → curl 远程 → 本地部署 → 常用示例 → 注意事项**。

统一变量（远程教程请先执行）：

```bash
export ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"
```

---

### 5.1 Debian / Ubuntu

**适用：** Debian 10+、Ubuntu 18.04+、Linux Mint、Deepin 等

**① 安装依赖**

```bash
sudo apt update
sudo apt install -y curl bash git ca-certificates
# 可选：中文 locale
sudo apt install -y locales
sudo locale-gen zh_CN.UTF-8
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
```

**② curl 远程**

```bash
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
bash <(curl -fsSL "$ENTRY") system info
sudo bash <(curl -fsSL "$ENTRY") mirror --plan
sudo bash <(curl -fsSL "$ENTRY") bbr status
```

**③ 本地部署**

```bash
sudo apt install -y git
sudo git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
./main.sh check
```

**④ 典型场景**

```bash
# 新服务器初始化
sudo bash <(curl -fsSL "$ENTRY") init

# Docker 安装预览
sudo bash <(curl -fsSL "$ENTRY") docker install --plan

# SSH 端口 staged 模式
sudo bash <(curl -fsSL "$ENTRY") ssh --port 2222 --mode staged -y
```

**注意：** 改源、BBR、防火墙、Docker 安装等需 `sudo` 或 root。

---

### 5.2 CentOS / RHEL / Rocky / AlmaLinux

**适用：** CentOS 7/8/Stream、RHEL 7/8/9、Rocky、AlmaLinux、Oracle Linux

**① 安装依赖**

```bash
# CentOS 7 / RHEL 7
sudo yum install -y curl bash git ca-certificates

# CentOS 8+ / Rocky / Alma / RHEL 8+
sudo dnf install -y curl bash git ca-certificates
```

**② curl 远程**

```bash
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
sudo bash <(curl -fsSL "$ENTRY") mirror --plan
sudo bash <(curl -fsSL "$ENTRY") firewall status
```

**③ 本地部署**

```bash
sudo dnf install -y git || sudo yum install -y git
sudo git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
sudo ./main.sh check
```

**④ 典型场景**

```bash
# 启用 BBR
sudo bash <(curl -fsSL "$ENTRY") bbr enable -y

# Fail2ban 状态
sudo bash <(curl -fsSL "$ENTRY") security status

# 时间同步
sudo bash <(curl -fsSL "$ENTRY") ntp status
```

**注意：** CentOS 7 默认 Bash 较旧但 ≥3.2 可用；firewalld 与 SELinux 改 SSH 端口前请阅读 `ssh` 工具提示。

---

### 5.3 Fedora

**① 安装依赖**

```bash
sudo dnf install -y curl bash git
```

**② curl 远程 / ③ 本地部署**

同 5.2，包管理器统一为 `dnf`。

```bash
bash <(curl -fsSL "$ENTRY") check
sudo git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
```

---

### 5.4 Arch Linux / Manjaro

**① 安装依赖**

```bash
sudo pacman -Sy --noconfirm curl bash git
```

**② curl 远程**

```bash
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
sudo bash <(curl -fsSL "$ENTRY") mirror --plan
```

**③ 本地部署**

```bash
sudo pacman -S --noconfirm git
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
./main.sh check
```

**注意：** 换源工具会识别 pacman；建议换源前 `--plan` 预览。

---

### 5.5 Alpine Linux

**① 安装依赖**

```bash
apk add curl bash git
# Alpine 默认 sh 为 ash，请显式使用 bash
```

**② curl 远程**

```bash
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
```

**③ 本地部署**

```bash
apk add git
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
./main.sh check
```

**注意：** 部分工具依赖 `systemd`/`ufw` 等在 Alpine 上不可用，先用 `check` 查看可用性。

---

### 5.6 openSUSE

**① 安装依赖**

```bash
# Leap / Tumbleweed
sudo zypper install -y curl bash git
```

**② curl 远程 / ③ 本地**

```bash
bash <(curl -fsSL "$ENTRY") check
sudo zypper install -y git
sudo git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
```

---

### 5.7 国产 Linux（openEuler / Anolis 等）

**适用：** openEuler、Anolis OS、银河麒麟、UOS 服务器版等（多为 RHEL 系或 Debian 系）

**识别包管理器：**

```bash
command -v apt  && echo Debian系
command -v dnf  && echo RHEL系(dnf)
command -v yum  && echo RHEL系(yum)
```

**安装依赖：** 按对应系执行 5.1 或 5.2 的安装命令。

**curl 远程（通用）：**

```bash
bash <(curl -fsSL "$ENTRY") check      # 先检查本机可用功能
bash <(curl -fsSL "$ENTRY") status
sudo bash <(curl -fsSL "$ENTRY") mirror --plan
sudo bash <(curl -fsSL "$ENTRY") lmirrors --help   # 全能换源，支持更多发行版
```

**本地部署：**

```bash
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool && chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;
```

---

### 5.8 macOS（管理远程 Linux）

netool 面向 **Linux 服务器**；macOS 通常作为运维终端，通过 SSH 连到 Linux 后执行。

**① 安装本地工具**

```bash
# 需已安装 bash 4+ 与 curl（macOS 自带 curl）
/bin/bash --version
curl --version
```

**② 远程 curl（在 Mac 终端执行，作用于当前机器时需 Linux 环境）**

```bash
# 一般用法：SSH 到 Linux 后在远端执行
ssh user@linux-server
export ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"
bash <(curl -fsSL "$ENTRY") check
```

**③ 本地克隆（用于阅读代码或打包上传）**

```bash
git clone https://gitee.com/suser747/netool.git ~/netool
# 上传到 Linux 服务器
scp -r ~/netool/* user@server:/opt/netool/
```

**④ Homebrew 工具**

`homebrew` 子工具支持 macOS 本机安装 Homebrew（在 Linux 服务器上请用对应 Linux 教程）。

```bash
bash <(curl -fsSL "$ENTRY") homebrew
```

---

### 5.9 Windows WSL2

在 WSL2 的 **Linux 发行版** 内按对应教程操作（Ubuntu 最常见）。

**① 启用 WSL 并安装 Ubuntu**（Windows 侧，管理员 PowerShell）：

```powershell
wsl --install
```

**② 进入 WSL Ubuntu 后：**

```bash
sudo apt update && sudo apt install -y curl bash git
export ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
```

**③ 本地克隆到 WSL：**

```bash
git clone https://gitee.com/suser747/netool.git ~/netool
cd ~/netool && chmod +x main.sh && ./main.sh check
```

**注意：** WSL 与真实服务器环境有差异，磁盘/验盘等硬件工具请在物理机或云服务器上运行。

---

## 六、命令与菜单参考

### 6.1 调用形式

```bash
# 远程
bash <(curl -fsSL "$ENTRY") [全局选项] [工具名] [参数...]

# 本地
./main.sh [全局选项] [工具名] [参数...]
```

| 全局选项 | 说明 |
|----------|------|
| `-h`, `--help` | 帮助 |
| `--version` | 主版本号 |
| `--list` | 菜单项列表 |
| `-q`, `--quiet` | 静默，仅输出错误 |
| `--license` | 许可协议 URL |

### 6.2 内置命令

| 命令 | 说明 |
|------|------|
| `check` | 依赖与功能可用性检查 |
| `status` | 只读状态面板 |
| `versions` | 组件版本矩阵 |
| `update` | 更新说明 / git pull |
| `uninstall` | 删除配置与日志 |
| `init` | 新服务器初始化向导 |

### 6.3 交互菜单对照

| 编号 | 功能 | 命令 |
|------|------|------|
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
| 8 | 验盘! | `disk-test` |
| 9 | 盘位映射 | `disk slot-map` |
| 10 | SMART 长测 | `smart-long` |
| 11 | 时间/用户 | `system time-users` |
| 12 | 运行服务 | `system services` |
| 13 | DNS 测试 | `network dns` |
| 14 | Ping 测试 | `network ping` |
| 15 | 轻量换源 | `mirror` |
| 16 | Docker 资源 | `docker images` |
| 17 | 基础工具 | `basic` |
| 18 | BBR | `bbr` |
| 19 | 性能测试 | `bench` |
| 20 | Swap | `swap` |
| 21 | 防火墙 | `firewall` |
| 22 | 安装 Docker | `docker install` |
| 23 | 主机/时区 | `host` |
| 24 | Fail2ban | `security` |
| 25 | 进程/服务 | `service` |
| 26 | Homebrew | `homebrew` |
| 27 | 全能换源 | `lmirrors` |
| 28 | 初始化向导 | `init` |
| 29 | 卸载 | `uninstall` |
| 30 | 日志清理 | `logclean` |
| 31 | 用户管理 | `user` |
| 32 | 定时任务 | `cron` |
| 33 | 时间同步 | `ntp` |
| 34 | 证书检查 | `ssl-check` |
| 35 | 磁盘占用 | `du-analyze` |

> `*` 仅打印命令不执行。`!` 破坏性，先 `--plan`。

### 6.4 工具速查

| 分类 | 工具 | 常用示例 |
|------|------|----------|
| 系统 | system / host / swap / basic / logclean / ntp / du-analyze | `system info`、`host status`、`basic --plan` |
| 网络 | network / bbr / bench / ssh / ssl-check | `network ports`、`bbr status`、`ssh --help` |
| 安全 | firewall / security / user / cron | `firewall status`、`user list` |
| Docker | docker | `docker status`、`docker install --plan` |
| 磁盘 | disk / disk-test / slot-map / smart-long | `disk status`、`disk-test --plan` |
| 软件源 | mirror / lmirrors / homebrew | `mirror --plan`、`mirror -y`、`lmirrors` |

**换源：**

```bash
./main.sh mirror --plan       # 轻量换源预览（推荐先试）
./main.sh mirror -y           # 执行换源
./main.sh mirror --restore    # 恢复备份
./main.sh lmirrors --help     # 全能换源（更多发行版 + Docker 源）
```

**远程/本地命令对照：**

| 功能 | 远程 | 本地 |
|------|------|------|
| 功能检查 | `bash <(curl -fsSL "$ENTRY") check` | `./main.sh check` |
| 状态面板 | `bash <(curl -fsSL "$ENTRY") status` | `./main.sh status` |
| 换源预览 | `bash <(curl -fsSL "$ENTRY") mirror --plan` | `./main.sh mirror --plan` |
| 初始化 | `bash <(curl -fsSL "$ENTRY") init` | `./main.sh init` |

---

## 七、环境变量与安全

### 7.1 环境变量

| 变量 | 说明 |
|------|------|
| `NETOOL_SKIP_LICENSE=1` | 跳过首次许可提示（CI/自动化） |
| `NETOOL_SKIP_LOCALE_TIP=1` | 跳过中文 locale 提示 |
| `NETOOL=1` | 主入口调用子工具时自动设置 |
| `-y` / `YES=1` | 非交互（视子工具支持） |

```bash
export NETOOL_SKIP_LICENSE=1 NETOOL_SKIP_LOCALE_TIP=1
bash <(curl -fsSL "$ENTRY") -q check
```

### 7.2 安全设计

1. **预览：** `--plan` / `--dry-run` 只显示计划  
2. **备份：** SSH、BBR、换源等自动备份至 `/var/backups/`  
3. **校验：** 远程脚本执行前 `bash -n`  
4. **审计：** root 操作写入 `/var/log/netool/audit.log`  

### 7.3 破坏性操作

| 操作 | 预览 | 执行要求 |
|------|------|----------|
| 硬盘验盘 | `disk-test --plan` | `--yes` + 短语 `DESTROY-DISK-TEST` |
| 整盘擦除 | `disk wipe --plan --devices /dev/sdX` | 显式 `--devices` + `WIPE-CONFIRM` |
| 分区格式化 | `disk partition` | 交互逐步确认 |

---

## 八、用户许可协议

使用 netool 懒人工具箱前，请确认已理解以下事项。

### 1. 脚本用途

用于辅助 Linux 系统信息查看、网络排查、Docker 状态、软件源切换、SSH 端口管理、磁盘管理与硬盘检测等。

### 2. 风险提示

- 部分功能会修改系统配置（软件源、SSH、分区、挂载等）。
- `disk-test` 会对目标盘**全盘写入并读回校验**，清空被测盘全部数据。
- `disk wipe` 擦盘会破坏数据，执行须显式指定 `--devices`。
- 在生产环境或含业务数据的服务器上执行高风险功能前，请完成备份并确认救援方式。

### 3. 用户责任

你须确认有权限管理目标服务器，并对设备路径、端口、镜像源等参数负责。

验盘前建议：

```bash
bash <(curl -fsSL "$ENTRY") disk-test --plan
```

擦盘前建议：

```bash
bash <(curl -fsSL "$ENTRY") disk wipe --plan --devices /dev/sdX
```

### 4. 隐私与数据安全

- 工具在本地运行，**不向第三方上传数据**。
- 审计日志仅记录操作类型与时间，**不记录密码、密钥等敏感信息**。
- 日志权限 600，目录 700，仅 root 可读。
- 可通过 `uninstall` 删除配置与日志。

### 5. 免责声明

本工具按现状提供，不承诺适用所有环境。因误操作、系统差异、网络异常或数据丢失造成的损失，由执行者自行承担。

**如不同意以上条款，请不要运行本工具。**

首次交互式运行会提示确认；带工具名参数调用时跳过提示。许可记录：`~/.config/netool/license-v1.accepted`。

---

## 九、配置、日志与故障排查

### 9.1 路径

| 路径 | 说明 |
|------|------|
| `~/.config/netool/` | 用户配置、许可确认 |
| `~/.config/ayu-toolbox/` | 旧版路径（兼容） |
| `/var/log/netool/audit.log` | 审计日志 |
| `/var/backups/netool-*` | 各工具配置备份 |

### 9.2 版本

```bash
./main.sh --version    # 主版本（VERSION 文件）
./main.sh versions     # 全部组件（tools/versions.env）
```

### 9.3 常见问题

| 问题 | 解决 |
|------|------|
| Permission denied | `chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;` |
| 菜单无输入 | 用 `bash <(curl -fsSL "$ENTRY")` 不用管道 |
| curl 失败 | 装 curl、测 Gitee 连通、改本地部署 |
| 中文乱码 | `export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8` |
| 远程脚本失败 | 确认 Gitee 分支 `master`、main.sh v2.1+ |

---

## 十、开发与贡献

### 10.1 开发环境

- Bash 4.0+（目标环境）；开发机 **Bash 3.2 也需兼容**（禁用 `${var,,}` 等 Bash4 语法）
- 推荐 [shellcheck](https://www.shellcheck.net/)

### 10.2 新增工具规范

1. 脚本放在 `tools/<分类>/`  
2. 声明 `SCRIPT_NAME`、`SCRIPT_VERSION`，并在 `tools/versions.env` 登记  
3. `set -Eeuo pipefail`  
4. 引入公共库：

```bash
# shellcheck source=../load_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../load_common.sh"
trap on_error ERR
```

5. 支持 `--help`、`--version`、`-y`、`--plan`  
6. 改配置须备份并可恢复  
7. 在 `main.sh` 注册路由与菜单  
8. 更新 `CHANGELOG.md`  

### 10.3 本地验证

```bash
bash scripts/validate.sh

# 或手动
find . -name '*.sh' -exec bash -n {} \;
NETOOL_SKIP_LICENSE=1 NETOOL_SKIP_LOCALE_TIP=1 bash main.sh check
NETOOL_SKIP_LICENSE=1 bash main.sh mirror --version
bash scripts/test-remote.sh    # 远程模式模拟
```

### 10.4 提交规范

`feat:` 新功能 · `fix:` 修复 · `refactor:` 重构 · `docs:` 文档 · `ci:` CI

### 10.5 维护者：发布远程可用版本

远程用户依赖 Gitee `master` 分支：

```bash
git push origin master
bash scripts/test-remote.sh
```

---

## 十一、License 与变更记录

- 许可证：[Apache License 2.0](./LICENSE)  
- 版本变更：[CHANGELOG.md](./CHANGELOG.md)  
- 仓库：<https://gitee.com/suser747/netool>
