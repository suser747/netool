# FTP 上传与服务器直接使用指南

本指南说明如何通过 FTP/SFTP 将 netool 懒人工具箱上传到 Linux 服务器，并在服务器上直接使用。

## 目录

- [一、准备工作](#一准备工作)
- [二、上传到服务器](#二上传到服务器)
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
├── REMOTE_USAGE.md
├── USER_AGREEMENT.md
├── CHANGELOG.md
├── FTP_DEPLOYMENT.md
├── LICENSE
└── tools/
    ├── common.sh
    ├── load_common.sh
    └── ...（各分类子工具）
```

### 1.2 服务器信息准备

- 服务器 IP 地址
- SSH/SFTP 端口（默认 22）
- 登录用户名
- 登录密码或密钥文件

---

## 二、上传到服务器

### 方式 1：SFTP 命令行上传

```bash
# 连接服务器
sftp -P 22 username@服务器IP

# 进入服务器目标目录
cd /opt

# 创建工具箱目录
mkdir netool
cd netool

# 上传整个项目（在 sftp 交互模式下执行）
put -r /本地路径/netool/* .

bye
```

**上传完成后，登录服务器并赋予执行权限：**

```bash
ssh username@服务器IP
cd /opt/netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 2：FileZilla 图形界面上传

1. 打开 FileZilla，新建 SFTP 站点并连接
2. 右侧进入 `/opt/netool/`
3. 左侧选择本地 `netool/` 目录，拖拽上传
4. 上传完成后在服务器执行：

```bash
cd /opt/netool
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### 方式 3：scp 一键上传

```bash
scp -r -P 22 /本地路径/netool/* username@服务器IP:/opt/netool/

ssh -p 22 username@服务器IP \
  "chmod +x /opt/netool/main.sh && find /opt/netool/tools -name '*.sh' -exec chmod +x {} \;"
```

> **提示：** 若包含中文文件名，请确保本地与服务器终端均使用 UTF-8 编码。

---

## 三、服务器上直接使用

### 3.1 进入工具箱目录

```bash
cd /opt/netool
```

### 3.2 交互式菜单（推荐）

```bash
./main.sh
```

### 3.3 命令行直接调用

```bash
./main.sh system info      # 系统信息
./main.sh check            # 功能检查
./main.sh mirror           # 一键换源
./main.sh init             # 初始化向导
./main.sh --list           # 工具列表
./main.sh --help           # 帮助
```

完整远程 curl 用法见 [REMOTE_USAGE.md](REMOTE_USAGE.md)。

### 3.4 设置全局快捷方式（可选）

```bash
ln -s /opt/netool/main.sh /usr/local/bin/netool
chmod +x /usr/local/bin/netool
```

之后任意目录可直接运行：

```bash
netool
netool system info
```

---

## 四、常用命令速查

| 功能 | 命令 |
|------|------|
| 进入菜单 | `./main.sh` |
| 系统信息 | `./main.sh system info` |
| 功能检查 | `./main.sh check` |
| 一键换源 | `./main.sh mirror` |
| 初始化向导 | `./main.sh init` |
| 脚本更新 | `./main.sh update` |
| 工具列表 | `./main.sh --list` |
| 帮助 | `./main.sh --help` |

---

## 五、常见问题

### Q1：上传后提示 Permission denied？

```bash
chmod +x main.sh
find tools -name "*.sh" -exec chmod +x {} \;
```

### Q2：中文显示乱码？

```bash
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
```

或在运行前设置 `NETOOL_SKIP_LOCALE_TIP=1` 跳过 locale 提示。

### Q3：可以离线使用吗？

可以。上传后脚本在本地运行；但 Docker 安装、换源、Homebrew 等操作本身仍需联网。

### Q4：如何更新？

有 Git 环境时：

```bash
git pull --ff-only origin master
```

无 Git 时重新上传覆盖即可。

### Q5：推荐安装目录？

- `/opt/netool/` — 全局统一存放（推荐）
- `~/netool/` — 个人用户使用
