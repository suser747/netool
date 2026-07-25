# netool懒人工具箱

命令行懒人向 Linux 运维脚本。

记住一个入口，选功能、传参数、走自动化，都行。入口已经改成分类工具箱风格，首次交互运行会提示阅读用户许可协议。

> 💡 **离线部署**：如果需要通过 FTP 上传到服务器直接使用，请参考 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md)。

## 入口

```bash
curl -fsSL https://gitee.com/suser747/netool/raw/m/i|bash
```

## 核心特性

- **双模式部署**：支持本地运行和 `curl|bash` 远程一键执行
- **破坏性操作三重防护**：`--plan` 预览 + `--yes` 显式确认 + 确认短语
- **系统配置自动备份恢复**：SSH、BBR、换源、防火墙等均有完整回滚机制
- **跨发行版兼容**：覆盖 Debian/Red Hat/Arch/Alpine 及国产系统 30+ 发行版
- **审计日志**：root 下系统修改操作自动记录到 `/var/log/ayu-toolbox/audit.log`

## 内置工具

| 工具 | 说明 | 安全特性 |
|------|------|----------|
| `check` | 检查当前服务器依赖，判断各类功能是否可用 | 只读 |
| `system` | 系统信息与基础维护，低风险查看和命令提示 | 只读 |
| `network` | 网络信息、端口和连通性检查 | 只读 |
| `docker` | Docker 状态、容器、镜像、数据卷和网络查看 | 只读/带确认 |
| `basic` | 基础工具安装，支持先预览安装命令 | `--plan` |
| `host` | 主机名、时区和时间信息管理 | `--plan` + 备份 |
| `swap` | Swap 管理，支持查看、创建和删除 swapfile | `--plan` + fstab 备份 |
| `firewall` | 防火墙端口管理，支持状态查看和常用端口放行 | `--plan` + 白名单 |
| `security` | Fail2ban SSH 防护，支持状态查看、安装预览和保守配置 | `--plan` + `.bak` |
| `service` | 进程与 systemd 服务管理，支持查看、日志和确认后重启 | `--plan` |
| `bbr` | BBR 状态查看和内核自带 BBR 启用/禁用 | `--plan` + sysctl 备份恢复 |
| `bench` | 轻量系统、磁盘、网络测试 | `--plan` |
| `mirror` | 轻量换源（带备份恢复），支持镜像站选择、自动备份、恢复与预演 | `--plan` + 时间戳备份 + 白名单恢复 |
| `ssh` | SSH 端口管理，支持先测试再切换、备份与失败回滚 | `--plan` + staged 模式 + 自动回滚 |
| `disk` | 磁盘管理总菜单，支持分区挂载、状态查看等 | `--plan` + fstab 备份 |
| `disk-test` | 硬盘好坏检测/验盘，全盘写入+读回校验，破坏性 | 必须 `--yes` + 内核日志严格归属 |
| `slot-map` | 硬盘盘位映射 | 只读 |
| `smart-long` | 启动 SMART 长测 | 中风险 |
| `homebrew` | Homebrew 管理（安装/卸载/CLT安装），支持 macOS 和 Linux | 交互式 + 语法校验 + commit 审计 |
| `lmirrors` | 全能换源 + Docker 安装，支持更多发行版 | `.bak` 备份 + `--print-diff` |
| `init` | 服务器初始化向导，新服务器一键配置常用项 | 每步询问 + 审计日志 |
| `uninstall` | 一键卸载工具箱（仅删除自身配置和日志） | 不删系统配置 |
| `update` | 脚本更新说明/本地仓库拉取 | - |
| `logclean` | 日志清理，回收 journald/`/var/log`/包缓存/旧内核占用 | `--plan` + 保留当前内核 |
| `user` | 用户与 SSH 密钥管理，增删用户、上传公钥、禁用密码登录 | `--plan` + sshd 备份 + 权限修正 |
| `cron` | 定时任务管理，crontab 备份/恢复、systemd timer 一览 | `--plan` + 权限 600 |
| `ssl-check` | HTTPS 证书到期检查，多域名批量扫描并告警 | 只读 + 并发锁 |
| `ntp` | 时间同步管理，配置 chrony/时区，立即同步 | `--plan` + chrony.conf 备份 |
| `du-analyze` | 磁盘占用分析，快速找出大目录和大文件 | 只读 |

## 一级菜单

```text
 _____   _  _     _____
  ___   _   _   ___    ___   _ __  |___  | | || |   |___  |
 / __| | | | | / __|  / _ \ | '__|    / /  | || |_     / /
 \__ \ | |_| | \__ \ |  __/ | |      / /   |__   _|   / /
 |___/  \__,_| |___/  \___| |_|     /_/       |_|    /_/
netool懒人工具箱 v2.0
命令行懒人向 Linux 运维脚本
------------------------------------------------------------
首次使用脚本，请先阅读并同意用户许可协议。
用户许可协议: https://gitee.com/suser747/netool/blob/main/USER_AGREEMENT.md
----------------------
是否同意以上条款？(y/n):

系统查看  1系统信息  11时间用户  12运行服务  23主机时区  25进程服务  35磁盘占用
系统维护  2系统更新  3系统清理  17基础工具  20Swap  30日志清理  33时间同步
网络工具  6网络端口  13DNS测试  14Ping测试  19性能测试
网络配置  4SSH管理  18BBR优化  21防火墙  34证书检查
Docker    5Docker状态  16Docker资源  22Docker安装
磁盘硬件  7磁盘管理  8验盘检测  9盘位映射  10SMART长测
用户安全  24Fail2ban  31用户管理  32定时任务
软件源    15轻量换源  26Homebrew  27全能换源
快捷工具  28初始化向导  29卸载工具箱
其他      01功能检查  00更新  0退出

提示  不确定选01; 高风险操作会再次确认; 15轻量换源带备份; 27全能换源支持更多发行版+Docker。
```

## 支持系统

| 系列 | 发行版 | 支持版本（lmirrors 全能换源） |
|------|--------|----------|
| Debian 系 | Ubuntu | 16.04、18.04、20.04、22.04、24.04 |
| Debian 系 | Debian | 8、9 (Stretch)、10 (Buster)、11 (Bullseye)、12 (Bookworm)、13 (Trixie) |
| Debian 系 | Linux Mint | 19.x、20.x、21.x、22.x |
| Debian 系 | Kali | Rolling |
| Debian 系 | Zorin OS | 16+、17+ |
| Debian 系 | Raspberry Pi OS | 基于 Debian 的版本 |
| Debian 系 | Deepin | 20.x、23.x |
| Debian 系 | openKylin | 所有版本 |
| Red Hat 系 | CentOS | 7、8、Stream 8/9/10 |
| Red Hat 系 | CentOS Stream | 8、9、10 |
| Red Hat 系 | Rocky Linux | 8.x、9.x |
| Red Hat 系 | AlmaLinux | 8.x、9.x |
| Red Hat 系 | RHEL | 7、8、9、10 |
| Red Hat 系 | Fedora | 37、38、39、40、41+ |
| Red Hat 系 | Oracle Linux | 7、8、9 |
| 国产系统 | openEuler | 20.03、22.03、24.03 |
| 国产系统 | Anolis OS | 8.x、23.x |
| 国产系统 | OpenCloudOS | 8、9、Stream |
| 国产系统 | TencentOS | Server 3、4 |
| 国产系统 | Kylin Server | V10 SP1/SP2/SP3 |
| 国产系统 | Kylin Desktop | 所有版本 |
| Arch 系 | Arch Linux | Rolling |
| Arch 系 | Manjaro | Rolling |
| Arch 系 | EndeavourOS | Rolling |
| 其他 | Alpine Linux | 3.16+、Edge |
| 其他 | openSUSE | Leap 15.4+、Tumbleweed |
| 其他 | Gentoo | Rolling |
| 其他 | Void Linux | Rolling |
| 其他 | NixOS | 22.05+ |

说明：
- 上表为 lmirrors 全能换源工具实际支持的发行版清单
- mirror 轻量换源按包管理器（apt/yum/dnf/pacman/apk/zypper）泛化识别，覆盖范围更广
- 未识别的系统在 lmirrors 中会明确报错退出，不会自动兜底；可改用 mirror 工具尝试

## 常用命令

```bash
# 菜单选择
curl -fsSL https://gitee.com/suser747/netool/raw/m/i|bash

# 系统信息
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) system

# 检查当前服务器功能依赖
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) check

# 基础工具安装预览
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) basic --plan

# 主机名和时区
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) host status
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) host set-timezone Asia/Shanghai

# Swap 状态
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) swap status

# 防火墙状态
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) firewall status

# Fail2ban SSH 防护
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) security status
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) security install --plan
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) security enable-ssh

# 进程与服务
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) service top
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) service logs nginx

# Docker 安装预览
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) docker install --plan

# BBR 状态
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) bbr status

# 启用 BBR（跳过确认）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) bbr enable -y

# 轻量性能测试
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) bench

# 网络端口
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) network ports

# Docker 容器
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) docker ps

# 直接换源
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) mirror

# 直接管理 SSH 端口
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ssh

# 磁盘管理菜单
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk

# 查看磁盘和挂载状态
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk status

# 先预览哪些硬盘会被验盘测试（不写入数据）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk-test --plan

# 硬盘好坏检测/验盘（破坏性，全盘写入，会清空被测盘）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk-test --yes --devices /dev/sdX

# 擦盘预览和执行（破坏性，必须明确指定整盘）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk wipe --plan --devices /dev/sdX
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) disk wipe --devices /dev/sdX fast

# 硬盘盘位映射
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) slot-map

# 启动 SMART 长测
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) smart-long

# Homebrew 管理（安装/卸载/CLT安装）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) homebrew
# 进入主菜单后可选择：
#   1 - 安装/配置 Homebrew（含国内镜像源配置）
#   2 - 卸载 Homebrew（含残留清理和配置备份）
#   3 - 安装 Command Line Tools (Git)（仅 macOS）

# LinuxMirrors 系统软件源切换
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) lmirrors

# 传参数给子脚本
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) mirror --mirror 腾讯云 -y
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ssh --port 2222 --mode staged -y

# 服务器初始化向导
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) init

# 日志占用情况
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) logclean status

# 清理日志预览（不执行）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) logclean clean --plan

# 清理日志并附带旧内核（保留当前内核）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) logclean clean --old-kernels -y

# 列出可登录用户
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) user list

# 创建用户并加入 sudo 组
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) user add --name deploy --sudo

# 为用户追加 SSH 公钥
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) user key --name deploy --key "ssh-ed25519 AAAA..."

# 禁用 SSH 密码登录（仅允许密钥）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) user disable-password -y

# 列出当前用户的 crontab
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) cron list

# 备份当前用户 crontab
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) cron backup

# 列出所有用户的 crontab（需 root）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) cron list-all

# 列出 systemd timer
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) cron timers

# 从备份恢复 crontab
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) cron restore --file /var/backups/ayu-cron-tools/deploy-20260725.cron -y

# HTTPS 证书到期检查
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ssl-check example.com www.example.com

# 自定义端口和告警阈值
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ssl-check example.com:8443 --warn-days 14

# 从文件批量扫描
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ssl-check --file /path/to/domains.txt

# 时间同步状态
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ntp status

# 配置 chrony + 时区（默认 Asia/Shanghai）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ntp setup -y

# 自定义 NTP 服务器和时区
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ntp setup --servers "ntp.aliyun.com cn.pool.ntp.org" --timezone Asia/Shanghai -y

# 立即同步一次时间
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) ntp sync -y

# 磁盘占用分析（默认扫描 /）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) du-analyze

# 分析指定目录，显示前 30 个大目录/文件
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) du-analyze --top 30 /var

# 自定义深度和最小大小
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) du-analyze --depth 4 --min 100M /home

# 一键卸载工具箱
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) uninstall

# 更新工具箱（本地仓库时执行 git pull）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) update

# 静默模式（只输出错误）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) -q check

# 查看可用工具
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) --list
```

## 仓库结构

```text
main.sh                # 统一入口
tools/common.sh        # 公共函数库（join_by、metadata_value、ayu_acquire_lock 等）

# 系统维护工具
tools/system/system.sh     # 系统信息与基础维护
tools/system/host.sh       # 主机名/时区管理
tools/system/swap.sh       # Swap 管理
tools/system/service.sh    # 进程与服务管理
tools/system/logclean.sh   # 日志/缓存/旧内核清理
tools/system/ntp.sh        # 时间同步管理（chrony/时区）

# 网络工具
tools/network/network.sh   # 网络工具
tools/network/bbr.sh       # BBR 状态和启用
tools/network/bench.sh     # 轻量性能测试
tools/network/ssh-port.sh  # SSH 端口管理
tools/network/ssl-check.sh # HTTPS 证书到期检查

# 安全工具
tools/security/firewall.sh # 防火墙端口管理
tools/security/security.sh # Fail2ban SSH 防护
tools/security/user.sh     # 用户与 SSH 密钥管理
tools/security/cron.sh     # 定时任务管理（crontab/systemd timer）

# 磁盘工具
tools/disk/disk.sh           # 磁盘管理总入口
tools/disk/du-analyze.sh     # 磁盘占用分析
tools/disk/disk_full_rw_test.sh # 硬盘验盘
tools/disk/disk_slot_map.sh     # 盘位映射
tools/disk/smart.sh             # SMART 长测
tools/disk/wipe_except_sda_v2.sh # 擦盘

# Docker 工具
tools/docker/docker.sh       # Docker 查看工具

# 软件源工具
tools/software/basic.sh      # 基础工具安装
tools/software/mirror.sh     # 一键换源
tools/software/lmirrors.sh   # Linux 软件源切换 + Docker 安装换源
tools/software/homebrew.sh   # Homebrew 国内镜像源安装

# 实用工具
tools/utility/init.sh       # 服务器初始化向导
```

## Homebrew 工具详解

`homebrew` 工具是 Homebrew 包管理器的一体化管理方案，支持 macOS 和 Linux 双平台，提供安装、卸载、Command Line Tools 安装三大功能。解决国内用户访问 GitHub 速度慢的问题，内置多个国内镜像源可选。

### 系统要求

**macOS**：

| 要求 | 说明 |
|------|------|
| 操作系统 | macOS 10.15 (Catalina) 或更高版本 |
| 处理器 | Intel Core 或 Apple Silicon (M1/M2/M3) |
| 工具 | Command Line Tools for Xcode 或 Xcode |

**Linux**：

| 要求 | 说明 |
|------|------|
| 发行版 | Ubuntu, Debian, CentOS, Fedora 等 |
| 工具 | Git, curl, sudo |

### 功能特性

- **自动化安装**：一键完成 Homebrew 安装和国内源配置
- **多镜像源支持**：清华、中科大、阿里、腾讯、上交 5 个国内镜像源
- **跨平台支持**：支持 macOS 和 Linux 系统
- **架构自动识别**：自动识别 Intel 和 Apple Silicon 芯片
- **安全卸载**：卸载前自动备份配置文件到桌面
- **错误自动修复**：安装失败时自动尝试修复
- **commit 审计**：记录官方 install.sh 的 commit hash 便于追溯
- **语法校验**：执行前 `bash -n` 校验，防止 sed 替换出错或内容被篡改

### 三大功能模块

#### 1. 安装/配置 Homebrew

安装 brew 并配置国内镜像源，进入后可选三种操作：

- **安装并配置国内源（推荐）**：完整安装 Homebrew 并配置镜像源
- **仅配置国内源**：跳过安装，仅配置已安装 brew 的镜像源
- **仅更换 brew 仓库地址**：只修改已安装 brew 的远程仓库地址

安装流程：
1. 网络检测（≥2 站点可访问才判定正常）
2. macOS 版本检查（≥10.15）
3. Git 依赖检查（缺失时自动安装）
4. 选择镜像源（5 选 1）
5. 询问是否删除旧版（可选备份到桌面）
6. 克隆官方 install.git 仓库
7. 记录 commit hash 用于审计
8. sed 替换 GitHub 地址为国内镜像
9. `bash -n` 语法校验
10. 执行修改后的 install.sh
11. 写入环境变量到 shell 配置文件
12. 验证安装并执行首次更新

#### 2. 卸载 Homebrew

完整卸载 Homebrew 并清理残留文件：

1. 检测 Homebrew 安装状态
2. 备份配置文件到桌面（`.zprofile`、`.bash_profile`、`.profile`）
3. 清理环境变量
4. 下载并执行官方卸载脚本
5. 逐个询问清理残留目录（7 个常见路径）
6. 完成提示和后续建议

#### 3. 安装 Command Line Tools（仅 macOS）

macOS 专用 Git 安装，通过 `softwareupdate` 自动安装：

1. 检测是否已安装 Command Line Tools
2. 通过 `softwareupdate -l` 查找可用版本
3. 自动安装并配置路径
4. 验证 Git 是否可用

### 镜像源列表

**软件包下载源（Bottle + pip + git 三合一）**：

| 序号 | 名称 | Bottle 地址 | pip 地址 | Git 地址 |
|------|------|-------------|----------|----------|
| 1 | 中科大 | mirrors.ustc.edu.cn/homebrew-bottles | pypi.mirrors.ustc.edu.cn/simple | mirrors.ustc.edu.cn/git/homebrew |
| 2 | 清华大学 | mirrors.tuna.tsinghua.edu.cn/homebrew-bottles | pypi.tuna.tsinghua.edu.cn/simple | mirrors.tuna.tsinghua.edu.cn/git/homebrew |
| 3 | 上海交通大学 | mirror.sjtu.edu.cn/homebrew-bottles | mirror.sjtu.edu.cn/pypi/web/simple | - |
| 4 | 腾讯 | mirrors.cloud.tencent.com/homebrew-bottles | mirrors.cloud.tencent.com/pypi/simple | - |
| 5 | 阿里巴巴 | mirrors.aliyun.com/homebrew/homebrew-bottles | mirrors.aliyun.com/pypi/simple | - |

**仅 Git 仓库地址源**（用于"仅更换仓库地址"场景）：

| 序号 | 名称 | 地址 |
|------|------|------|
| 1 | 清华大学 | mirrors.tuna.tsinghua.edu.cn/git/homebrew |
| 2 | Gitee | gitee.com/Homebrew2 |

### Homebrew 安装路径

| 平台 | 架构 | 安装路径 |
|------|------|----------|
| macOS | Apple Silicon (M1/M2/M3) | `/opt/homebrew` |
| macOS | Intel | `/usr/local` |
| Linux | 所有架构 | `/home/linuxbrew/.linuxbrew` |

### Homebrew 常用命令

```bash
brew -v              # 查看版本
brew update          # 更新 brew
brew search xxx      # 搜索软件
brew install xxx     # 安装软件
brew uninstall xxx   # 卸载软件
brew ls              # 列出已安装软件
brew info xxx        # 查看软件信息
brew outdated        # 查看可更新的软件
brew upgrade         # 更新所有软件
brew cleanup         # 清理旧版本
brew config          # 查看 brew 配置
brew doctor          # 诊断 brew 问题
```

### Homebrew 安装后注意事项

- 安装完成后**必须重启终端**或运行 `source ~/.zprofile`（zsh）或 `source ~/.bash_profile`（bash），否则国内地址无法生效
- Linux 用户需运行 `source /etc/profile` 或重启电脑
- 如果选择了删除旧版，桌面会有 `Old_Homebrew_<时间戳>` 文件夹，可手动删除
- 卸载后备份文件保存在桌面 `Homebrew_Backup_<时间戳>` 目录

## 新增工具规范

- 脚本放 `tools/<name>.sh`；功能模块化较多时可在 `tools/<group>/` 下分子目录（如 `tools/disk/`）
- 共享工具函数放 `tools/common.sh`，避免在多个脚本中重复定义
- `main.sh` 里加菜单项、别名和下载地址
- README 加功能说明，CHANGELOG 记录变化
- 脚本头部声明 `SCRIPT_NAME` 和 `SCRIPT_VERSION`，并统一 `set -Eeuo pipefail`
- 提供完整 `log_info`/`log_success`/`log_warn`/`log_error` 日志函数（需要 `COLOR_*` 变量），并设置 `trap on_error ERR`
- 支持的标准参数：`--help`（帮助）、`--version`（版本）、`-y/--yes`（非交互）、`--plan` 或 `--dry-run`（预览）
- 改系统配置必须先备份，提供恢复方式
- 交互模式用子菜单循环，执行完回到子菜单
- 用 `return 1` 处理软错误，不用 `die` 退出
- 统一使用 `AYU_TOOLBOX` 环境变量控制工具箱内调用行为（如关闭颜色输出、抑制 banner）
- 外部引入脚本（如 `homebrew.sh`、`lmirrors.sh`）保留其原生交互逻辑，仅需补齐 `SCRIPT_NAME`、`SCRIPT_VERSION` 和日志函数兼容层

## 配置与日志文件

工具箱使用的配置和日志文件路径如下：

| 类型 | 路径 | 说明 |
|------|------|------|
| 用户配置目录 | `~/.config/ayu-toolbox/` | 存储用户许可协议确认状态 |
| 许可确认文件 | `~/.config/ayu-toolbox/license-v1.accepted` | 首次同意后生成 |
| 审计日志目录 | `/var/log/ayu-toolbox/` | 仅 root 用户，权限 700 |
| 审计日志文件 | `/var/log/ayu-toolbox/audit.log` | 记录系统修改操作，权限 600 |
| SMART 长测日志 | `/var/log/smart-long-test/` | SMART 长测的详细日志 |
| 验盘报告目录 | `~/disk-test-report-<时间戳>/` | disk-test 生成的报告、fio/TRIM 日志 |
| 擦盘日志 | `~/wipe_except_sda_v2_<时间戳>.log` 或 `$TMPDIR` 下 | wipe 操作的完整执行日志 |
| SSH 配置备份 | `/var/backups/ayu-user-tools/<时间戳>/` | user 工具修改 sshd 前的备份 |
| crontab 备份 | `/var/backups/ayu-cron-tools/<用户>-<时间戳>.cron` | cron 工具的 crontab 备份，权限 600 |

> **隐私说明**：本工具仅在本地运行，不会向任何第三方服务器上传数据。审计日志只记录操作类型和时间，**不会记录任何密码、密钥、令牌或其他敏感数据**；审计日志文件权限为 600，目录权限为 700，仅 root 用户可访问。你可以随时通过 `uninstall` 命令删除工具箱的所有配置和日志。

## 故障排查

### 中文显示乱码 / 菱形方块
- **症状**：菜单和提示中的中文字符显示为菱形或乱码
- **原因**：系统缺少中文字体，或终端 locale 设置不正确
- **解决**：
  1. 安装中文字体：
     - Debian / Ubuntu：`sudo apt install -y fonts-wqy-zenhei fonts-wqy-microhei`
     - CentOS / RHEL：`sudo yum install -y wqy-zenhei-fonts wqy-microhei-fonts`
  2. 安装后重新连接 SSH 终端即可正常显示
  3. 如果仍有问题，检查 locale 设置：`export LANG=en_US.UTF-8` 或 `export LANG=zh_CN.UTF-8`

### 菜单无法输入选择
- **症状**：通过 `curl ...|bash` 进入菜单后，键盘输入没反应
- **原因**：管道模式下标准输入被占用
- **解决**：改用 `bash <(curl -fsSL 入口地址)` 或本地部署后直接运行

### curl 下载失败 / 连接超时
- **症状**：`curl: (28) Operation timed out` 或下载中断
- **原因**：网络到 Gitee 不稳定
- **解决**：
  1. 本地下载项目后通过 FTP 上传到服务器（参考 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md)）
  2. 使用国内镜像或代理
  3. 多次重试：`for i in 1 2 3; do curl -fsSL 地址|bash && break; done`

### 提示 "缺少必要命令"
- **症状**：运行工具时报错缺少某个命令
- **原因**：对应依赖未安装
- **解决**：
  1. 先运行 `check` 功能查看依赖情况
  2. 使用系统包管理器安装缺少的包（如 `apt install`、`yum install`）
  3. 查看类功能一般缺部分命令也能降级显示，不影响其他工具

### 权限不足 / Permission denied
- **症状**：报 `Permission denied` 或提示需要 root
- **原因**：修改系统配置需要 root 权限
- **解决**：
  1. 使用 root 用户运行
  2. 或加 `sudo`：`sudo bash main.sh`
  3. 查看类功能一般不需要 root

### 换源后无法安装软件
- **症状**：换源后 `apt update` 或 `yum update` 报错
- **原因**：镜像站同步延迟或选错了发行版版本
- **解决**：
  1. 使用 `mirror` 工具的恢复功能：`mirror --restore` 或 `mirror --restore-from <dir>`
  2. 备份目录位于 `/var/backups/linux-mirror-switcher/`，按时间戳子目录存放
  3. 尝试切换其他镜像站

### SSH 端口修改后连不上
- **症状**：改了 SSH 端口后远程连接断开
- **原因**：新端口没放行防火墙，或 sshd 重启失败
- **解决**：
  1. `ssh` 工具支持先测试再切换，建议使用 staged 模式
  2. 如果已断开，通过 VNC/控制台登录恢复原配置
  3. 原配置备份位于 `/var/backups/ssh-port-manager/`，按时间戳子目录存放，可用 `ssh --restore` 恢复

### Docker 安装失败
- **症状**：Docker 安装过程报错或启动失败
- **原因**：系统版本不兼容或网络问题
- **解决**：
  1. 先运行 `check` 确认依赖情况
  2. 检查网络是否能访问 Docker 软件源
  3. 参考 Docker 官方文档手动安装

### Homebrew 安装后提示 `command not found: brew`
- **症状**：终端运行 brew 命令提示找不到
- **原因**：PATH 环境变量未生效
- **解决**：
  1. 检查 brew 是否存在：
     ```bash
     # Intel 芯片
     /usr/local/Homebrew/bin/brew -v
     # Apple Silicon (M1/M2)
     /opt/homebrew/bin/brew -v
     # Linux
     /home/linuxbrew/.linuxbrew/bin/brew -v
     ```
  2. 如果上面命令有输出版本号，说明是 PATH 配置问题，重启终端后检查：
     ```bash
     echo $PATH
     ```
  3. 或手动加载配置文件：
     ```bash
     source ~/.zprofile      # zsh 用户
     source ~/.bash_profile  # bash 用户
     source /etc/profile     # Linux 用户
     ```

### Homebrew 安装软件报错 404
- **症状**：`brew install` 时返回 404 错误
- **原因**：镜像源同步延迟或网络问题
- **解决**：
  1. 切换其他镜像源重新运行 `homebrew` 工具选择"仅配置国内源"
  2. 检查网络连接
  3. 查看 [官方更新记录](https://brew.sh/blog/) 确认是否有近期更新

### Homebrew Git 相关报错
- **症状**：报错包含 `git -c xxxxxxx xxx xxx` 等语句
- **解决**：将报错中提供的解决语句（`git -C ...`）逐句运行即可

### Homebrew 网络错误 (errno 54/443)
- **症状**：报错包含 errno 54 或 443
- **原因**：国内镜像源稳定性有限
- **解决**：切换下载源通常可以解决，建议多尝试几个源

### Homebrew Ruby 版本问题
- **症状**：检测到不是最新系统，需要自动升级 Ruby 后失败
- **解决**：
  ```bash
  # 设置镜像源
  export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.ustc.edu.cn/homebrew-bottles
  # 清理缓存
  rm -rf ~/Library/Caches/Homebrew/
  # 更新
  brew update
  ```

### Running Homebrew as root
- **症状**：`Error: Running Homebrew as root is extremely dangerous and no longer supported.`
- **原因**：执行过 `su` 命令切换到了 root 权限
- **解决**：
  ```bash
  # 方法 1：关闭终端重新打开
  # 方法 2：退出 root
  exit
  # 方法 3：切换回普通用户
  su - 用户名
  ```

### bad interpreter: /bin/bash^M
- **症状**：`/usr/local/bin/brew: bad interpreter: /bin/bash^M: no such file or directory`
- **原因**：Git 配置了 `core.autocrlf true` 导致换行符被转换
- **解决**：
  ```bash
  # 检查 Git 配置
  git config --global core.autocrlf
  # 如果显示 true，运行下面命令解决
  git config --global core.autocrlf input
  # 重新运行安装脚本
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) homebrew
  ```

### M1/M2 芯片路径错误
- **症状**：`which brew` 输出 `/usr/local/Homebrew/bin/brew`（应该是 `/opt/homebrew/bin/brew`）
- **原因**：Apple Silicon 安装到了 Intel 路径
- **解决**：
  ```bash
  # 删除错误的目录
  sudo rm -rf /usr/local/Homebrew
  # 重新运行安装脚本
  bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) homebrew
  ```

### BadCPU type in executable
- **症状**：`BadCPU type in executable`
- **原因**：M 芯片电脑上存在两个 brew（Intel 版和 ARM 版）
- **解决**：
  ```bash
  # 删除 Intel 版本（M 芯片）
  sudo rm -rf /usr/local/Homebrew
  # 或删除 ARM 版本（Intel 芯片）
  sudo rm -rf /opt/homebrew
  ```
  或检查配置文件中的错误路径：
  ```bash
  open ~/.zprofile
  open ~/.bash_profile
  open ~/.profile
  # 删除包含错误路径的行
  ```

### fatal: not in a git directory
- **症状**：`fatal: not in a git directory` 或 `Error: Command failed with exit 128: git`
- **解决**：
  ```bash
  git config --global http.sslVerify false
  ```

### 如何重置 Homebrew
- **问题**：不小心修改了 brew 文件夹内容
- **解决**：
  ```bash
  brew update-reset
  ```

## 注意

- 修改系统配置需 `root`，不是 root 请加 `sudo`
- 无参数菜单入口推荐 `curl -fsSL https://gitee.com/suser747/netool/raw/m/i|bash`，比进程替换写法更短
- 带工具名或参数时继续使用 `bash <(curl -fsSL https://gitee.com/suser747/netool/raw/m/i) mirror` 这种写法，参数传递更清楚
- 推荐始终保留 `https://`，不要使用省略协议头的 raw 地址
- **破坏性操作三重防护**：
  - `--plan` / `--dry-run`：预览将要执行的操作，不修改系统
  - `-y` / `--yes`：跳过交互确认（慎用）
  - 确认短语：高破坏性操作需手动输入确认短语（如 `DESTROY-DISK-TEST`）
- **安全回滚机制**：
  - `ssh`、`bbr`、`mirror`、`swap`、`ntp`、`user` 等工具会自动备份原配置
  - 失败时自动回滚，成功后可手动恢复到任意历史备份
  - `ssh` 支持 staged 模式：先双端口测试，验证通过后再切换
- `disk-test` 会全盘写入并清空被测盘；建议先跑 `disk-test --plan`，真正执行时还需要输入 `DESTROY-DISK-TEST` 二次确认
- `disk wipe` 同样会破坏数据；菜单中只做预览，真正执行必须用命令行显式指定 `--devices`
- 首次交互运行需要同意 [USER_AGREEMENT.md](./USER_AGREEMENT.md)，确认状态保存在 `~/.config/ayu-toolbox/`
- 菜单中的 `[仅提示]` 项只打印建议命令，不会自动执行系统更新或清理
- 菜单中的 `[需 root]`、`[会改配置]`、`[毁数据]` 项执行前要先确认目标和备份
- `homebrew` 提供 Homebrew 包管理器的安装、卸载、Command Line Tools 安装三大功能，支持 macOS 和 Linux，详见 [Homebrew 工具详解](#homebrew-工具详解) 章节
- `lmirrors` 会修改系统软件源配置，支持自动备份和恢复，Docker 安装换源为可选功能

## 安全设计

本工具箱采用多层安全防护：

1. **并发锁**：通过 `ayu_acquire_lock` 防止多个实例同时修改系统配置
2. **配置备份**：所有修改系统配置的操作都会自动备份原配置
3. **白名单恢复**：恢复操作只允许写入特定路径，防止备份被污染后越权
4. **语法校验**：下载的脚本执行前会进行 `bash -n` 语法检查
5. **审计日志**：root 下所有系统修改操作记录到 `/var/log/ayu-toolbox/audit.log`（权限 600）
6. **隐私保护**：审计日志不记录密码、密钥等敏感数据

## License

[MIT](./LICENSE) Copyright (c) 2026 suser747
