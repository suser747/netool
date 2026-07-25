# FTP 上传与服务器直接使用指南

本指南说明如何通过 FTP/SFTP 将 netool 懒人工具箱上传到 Linux 服务器，并在服务器上直接使用。

## 目录

- [一、准备工作](#一准备工作)
- [二、上传到服务器](#二上传到服务器)
  - [方式 1：SFTP 命令行上传](#方式-1sftp-命令行上传)
  - [方式 2：FileZilla 图形界面上传](#方式-2filezilla-图形界面上传)
  - [方式 3：scp 一键上传](#方式-3scp-一键上传)
- [三、服务器上直接使用](#三服务器上直接使用)
- [四、常用命令速查](#四常用命令速查)
- [五、常见问题](#五常见问题)

---

## 一、准备工作

### 1.1 本地文件准备

确保本地已下载或克隆完整的 netool 懒人工具箱项目：

```
netool/
├── main.sh
├── README.md
├── USER_AGREEMENT.md
├── CHANGELOG.md
├── FTP_DEPLOYMENT.md
├── LICENSE
└── tools/
    ├── common.sh
    ├── system/
    │   ├── system.sh
    │   ├── host.sh
    │   ├── swap.sh
    │   ├── service.sh
    │   ├── logclean.sh
    │   └── ntp.sh
    ├── network/
    │   ├── network.sh
    │   ├── bbr.sh
    │   ├── bench.sh
    │   ├── ssh-port.sh
    │   └── ssl-check.sh
    ├── security/
    │   ├── firewall.sh
    │   ├── security.sh
    │   ├── user.sh
    │   └── cron.sh
    ├── disk/
    │   ├── disk.sh
    │   ├── du-analyze.sh
    │   ├── disk_full_rw_test.sh
    │   ├── disk_slot_map.sh
    │   ├── smart.sh
    │   └── wipe_except_sda_v2.sh
    ├── docker/
    │   └── docker.sh
    ├── software/
    │   ├── basic.sh
    │   ├── mirror.sh
    │   ├── lmirrors.sh
    │   └── homebrew.sh
    └── utility/
        └── init.sh
```

### 1.2 服务器信息准备

- 服务器 IP 地址
- SSH/SFTP 端口（默认 22）
- 登录用户名
- 登录密码或密钥文件

---

## 二、上传到服务器

### 方式 1：SFTP 命令行上传

在本地终端（Windows PowerShell / macOS 终端 / Linux 终端）中执行：

```bash
# 连接服务器
sftp -P 22 username@服务器IP

# 进入服务器目标目录（例如 /opt
cd /opt

# 创建工具箱目录
mkdir ayu-toolbox
cd ayu-toolbox

# 上传整个项目（在 sftp 交互模式下执行）
put -r /本地路径/lt-main/* .

# 退出 sftp
bye
```

**上传完成后，登录服务器并赋予执行权限：

```bash
ssh username@服务器IP
cd /opt/ayu-toolbox
chmod +x main.sh check.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 2：FileZilla 图形界面上传

1. 打开 FileZilla，点击「站点管理器」
2. 新建站点：
   - 协议：`SFTP - SSH File Transfer Protocol
   - 主机：服务器 IP
   - 端口：22（或你的 SSH 端口）
   - 登录类型：正常 / 密钥文件
   - 用户：用户名
   - 密码：密码（或选择密钥文件）
3. 连接后，右侧找到服务器目标目录（如 `/opt/netool/`）
4. 左侧找到本地项目文件夹 `lt-main/`
5. 全选本地文件，拖拽到右侧服务器目录
6. 等待上传完成

上传完成后，在服务器终端执行：

```bash
cd /opt/ayu-toolbox
chmod +x main.sh check.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 3：scp 一键上传

最快捷的方式，直接一条命令上传整个目录：

```bash
# 上传整个项目到服务器
scp -r -P 22 /本地路径/lt-main/* username@服务器IP:/opt/netool/

# 然后登录服务器赋权
ssh -p 22 username@服务器IP "mkdir -p /opt/ayu-toolbox && chmod +x /opt/netool/main.sh /opt/netool/check.sh && find /opt/netool/tools -name "*.sh" -exec chmod +x {} \;"
```

> **提示：** 如果项目中包含中文文件名，请确保服务器终端和本地终端编码一致（推荐 UTF-8）。

---

## 三、服务器上直接使用

### 3.1 进入工具箱目录

```bash
cd /opt/ayu-toolbox
```

### 3.2 交互式菜单方式（推荐）

```bash
./main.sh
```

进入分类菜单，按数字选择工具即可。

### 3.3 命令行直接调用

```bash
# 查看系统信息
./main.sh system

# 检查功能可用性
./main.sh check

# 查看网络端口
./main.sh network ports

# Docker 状态
./main.sh docker status

# 一键换源
./main.sh mirror

# SSH 端口管理
./main.sh ssh

# Swap 状态
./main.sh swap status

# 防火墙状态
./main.sh firewall status

# BBR 状态
./main.sh bbr status

# 启用 BBR（跳过确认）
./main.sh bbr enable -y

# 基础工具安装预览
./main.sh basic --plan

# 主机名/时区
./main.sh host status

# Fail2ban 状态
./main.sh security status

# 进程 TOP
./main.sh service top

# 轻量性能测试
./main.sh bench

# 磁盘状态
./main.sh disk status

# 验盘预览
./main.sh disk-test --plan

# Homebrew 国内安装
./main.sh homebrew

# Linux 软件源切换
./main.sh lmirrors

# 服务器初始化向导
./main.sh init

# 一键卸载工具箱
./main.sh uninstall

# 静默模式（只输出错误）
./main.sh -q check

# 查看所有可用工具
./main.sh --list

# 查看帮助
./main.sh --help

# 查看版本
./main.sh --version
```

### 3.4 设置全局快捷方式（可选）

如果想在任何目录都能直接调用，添加软链接：

```bash
ln -s /opt/netool/main.sh /usr/local/bin/ayu
chmod +x /usr/local/bin/ayu
```

之后任意目录直接输入：

```bash
ayu
ayu system
ayu check
```

---

## 四、常用命令速查

| 功能 | 命令 |
|------|------|
| 进入菜单 | `./main.sh` |
| 系统信息 | `./main.sh system` |
| 功能检查 | `./main.sh check` |
| 网络端口 | `./main.sh network ports` |
| Docker 状态 | `./main.sh docker status` |
| 一键换源 | `./main.sh mirror` |
| SSH 端口 | `./main.sh ssh` |
| Swap 管理 | `./main.sh swap status` |
| 防火墙 | `./main.sh firewall status` |
| BBR 优化 | `./main.sh bbr status` |
| 基础工具 | `./main.sh basic --plan` |
| 主机名/时区 | `./main.sh host status` |
| 进程服务 | `./main.sh service top` |
| 性能测试 | `./main.sh bench` |
| 磁盘管理 | `./main.sh disk` |
| 验盘预览 | `./main.sh disk-test --plan` |
| 盘位映射 | `./main.sh slot-map` |
| SMART 长测 | `./main.sh smart-long` |
| Homebrew 安装 | `./main.sh homebrew` |
| LinuxMirrors 换源 | `./main.sh lmirrors` |
| 服务器初始化向导 | `./main.sh init` |
| 卸载工具箱 | `./main.sh uninstall` |
| 静默模式 | `./main.sh -q check` |
| 脚本更新 | `./main.sh update` |
| 工具列表 | `./main.sh --list` |
| 帮助 | `./main.sh --help` |
| 版本 | `./main.sh --version` |

---

## 五、常见问题

### Q1：上传后执行提示「Permission denied」怎么办？

给脚本添加执行权限：

```bash
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### Q2：FTP 上传后中文显示乱码？

确保本地和服务器都使用 UTF-8 编码。服务器端执行：

```bash
export LANG=en_US.UTF-8
```

### Q3：可以离线使用吗？

可以。上传到服务器后，所有工具脚本都在本地，不需要联网。
但部分功能本身需要联网，如：
- Docker 安装/卸载需要联网下载包
- Homebrew 安装需要联网下载
- 系统更新/换源需要联网

### Q4：如何更新本地工具箱？

如果服务器有 Git 环境，直接在项目目录执行：

```bash
git pull --ff-only origin master
```

没有 Git 的话，重新上传覆盖即可。

### Q5：安装到哪个目录比较好？

推荐：
- `/opt/netool/` — 全局工具统一存放
- `~/ayu-toolbox/` — 当前用户使用

根据实际情况选择即可。
