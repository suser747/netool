# 本地部署指南（Git / SFTP / scp）

> 完整双模式说明（本地 + curl）请参阅 **[USAGE.md](./USAGE.md)**。本文专注本地上传与离线运行。

---

## 目录

- [一、准备工作](#一准备工作)
- [二、获取与上传](#二获取与上传)
- [三、本地运行](#三本地运行)
- [四、全部命令参考](#四全部命令参考)
- [五、更新与维护](#五更新与维护)
- [六、常见问题](#六常见问题)

---

## 一、准备工作

### 1.1 项目目录结构

```
netool/
├── main.sh              # 统一入口
├── VERSION              # 主版本号
├── USAGE.md             # 完整使用说明
├── README.md
├── REMOTE_USAGE.md
├── USER_AGREEMENT.md
├── tools/
│   ├── common.sh        # 公共函数库
│   ├── load_common.sh   # 公共库加载器
│   ├── versions.env     # 组件版本清单
│   ├── version.sh       # 版本展示函数
│   ├── system/          # 系统维护
│   ├── network/         # 网络工具
│   ├── security/        # 安全与用户
│   ├── disk/            # 磁盘硬件
│   ├── docker/          # Docker
│   ├── software/        # 换源与软件
│   └── utility/         # 初始化向导
└── scripts/
    └── validate.sh      # 本地验证
```

### 1.2 推荐安装路径

| 路径 | 适用 |
|------|------|
| `/opt/netool/` | 全局共用（推荐） |
| `~/netool/` | 个人用户 |

### 1.3 服务器信息（上传时需要）

- 服务器 IP、SSH/SFTP 端口（默认 22）
- 登录用户名、密码或密钥

---

## 二、获取与上传

### 方式 A：Git 克隆（推荐）

```bash
# 在服务器上直接克隆
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 B：scp 一键上传

```bash
# 本地执行：上传到服务器
scp -r -P 22 /本地路径/netool/* user@服务器IP:/opt/netool/

# 赋权
ssh -p 22 user@服务器IP \
  "chmod +x /opt/netool/main.sh && find /opt/netool/tools -name '*.sh' -exec chmod +x {} \;"
```

### 方式 C：SFTP 命令行

```bash
sftp -P 22 user@服务器IP
cd /opt
mkdir netool
cd netool
put -r /本地路径/netool/* .
bye
```

登录服务器赋权：

```bash
ssh user@服务器IP
cd /opt/netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 D：FileZilla 图形界面

1. 新建 SFTP 站点，连接服务器
2. 右侧进入 `/opt/netool/`，左侧选择本地 `netool/` 目录
3. 拖拽上传全部文件
4. SSH 登录执行上述赋权命令

> 请确保本地与服务器终端均使用 UTF-8 编码。

---

## 三、本地运行

### 3.1 基本用法

```bash
cd /opt/netool

./main.sh                    # 交互式分类菜单
./main.sh check              # 功能依赖检查
./main.sh status             # 一键状态面板
./main.sh versions           # 组件版本矩阵
./main.sh system info        # 系统信息
./main.sh network ports      # 网络端口
./main.sh mirror --plan      # 换源预览
./main.sh init               # 初始化向导
./main.sh --list             # 菜单项列表
./main.sh --help             # 帮助
./main.sh --version          # 主版本号
```

### 3.2 全局快捷命令（可选）

```bash
ln -sf /opt/netool/main.sh /usr/local/bin/netool
chmod +x /usr/local/bin/netool

# 任意目录可用
netool
netool status
netool system info
netool mirror --plan
```

### 3.3 本地模式特点

- 所有子脚本在磁盘上，**无需 curl 下载**，执行更快
- 适合内网、频繁使用、生产环境
- 脚本本身可离线运行（安装软件包/换源等操作可能仍需外网）
- 与 curl 远程使用**相同的命令语法**，仅前缀不同：

| 远程 | 本地 |
|------|------|
| `bash <(curl -fsSL $ENTRY) check` | `./main.sh check` |
| `bash <(curl -fsSL $ENTRY) status` | `./main.sh status` |
| `bash <(curl -fsSL $ENTRY) mirror -y` | `./main.sh mirror -y` |

### 3.4 交互式菜单

运行 `./main.sh` 不带参数进入分类菜单。编号与命令对照见 [USAGE.md §5](./USAGE.md#5-交互式菜单对照表)。

常用编号：

| 编号 | 功能 |
|------|------|
| 01 | 功能检查 |
| 02 | 状态面板 |
| 03 | 组件版本 |
| 28 | 初始化向导 |
| 0 | 退出 |

---

## 四、全部命令参考

### 内置命令

```bash
./main.sh check
./main.sh status
./main.sh versions
./main.sh update
./main.sh uninstall
./main.sh init
```

### 系统

```bash
./main.sh system info
./main.sh system update       # 仅打印命令
./main.sh system clean
./main.sh system time-users
./main.sh system services
./main.sh host status
./main.sh swap status
./main.sh basic --plan
./main.sh basic -y
./main.sh logclean
./main.sh ntp status
./main.sh du-analyze /var
```

### 网络

```bash
./main.sh network ip
./main.sh network ports
./main.sh network ping 8.8.8.8
./main.sh network dns example.com
./main.sh bbr status
./main.sh bbr enable -y
./main.sh bench
./main.sh ssh --help
./main.sh ssl-check example.com
```

### 安全

```bash
./main.sh firewall status
./main.sh security status
./main.sh user list
./main.sh cron list
```

### Docker

```bash
./main.sh docker status
./main.sh docker ps
./main.sh docker images
./main.sh docker install --plan
./main.sh docker install -y
```

### 磁盘

```bash
./main.sh disk status
./main.sh disk-test --plan          # 验盘预览（破坏性，见 USAGE.md）
./main.sh disk slot-map
./main.sh smart-long
```

### 软件源

```bash
./main.sh mirror --plan
./main.sh mirror -y
./main.sh mirror --restore
./main.sh lmirrors --help
./main.sh homebrew
```

完整说明与 curl 对照见 **[USAGE.md](./USAGE.md)**。

---

## 五、更新与维护

### Git 更新

```bash
cd /opt/netool
git pull --ff-only origin master
```

### 查看更新说明

```bash
./main.sh update
```

### 本地验证

```bash
bash scripts/validate.sh
```

### 卸载工具箱配置

```bash
./main.sh uninstall
# 仅删除 ~/.config/netool/ 和 /var/log/netool/，不卸载 Docker 等已装软件
```

---

## 六、常见问题

### Q1：Permission denied

```bash
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### Q2：中文乱码

```bash
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
export NETOOL_SKIP_LOCALE_TIP=1
```

### Q3：能否离线使用？

脚本可离线运行。但 Docker 安装、换源、Homebrew 等操作本身需要联网下载。

### Q4：没有 Git 怎么更新？

重新 scp/FTP 上传覆盖整个目录，或改用 curl 远程模式（见 [REMOTE_USAGE.md](./REMOTE_USAGE.md)）。

### Q5：本地和 curl 有什么区别？

命令完全相同，本地无需下载子脚本、速度更快、可离线。详见 [USAGE.md §1](./USAGE.md#1-快速选择运行方式)。

---

## 相关文档

- **[USAGE.md](./USAGE.md)** — 完整使用说明
- [REMOTE_USAGE.md](./REMOTE_USAGE.md) — curl 远程运行
- [README.md](./README.md) — 项目概览
