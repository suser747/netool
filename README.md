# netool 懒人工具箱

命令行 Linux 运维脚本集合。**一个入口**：菜单交互或命令行参数，覆盖系统、网络、安全、磁盘、Docker、换源等。当前版本 **v2.1**。

在线入口：

```
https://gitee.com/suser747/netool/raw/master/main.sh
```

---

## 项目截图

> 将截图放入 `docs/images/` 后，取消下方注释即可在文档中显示。

<!-- 交互菜单 -->
<!-- ![交互式菜单](docs/images/menu.png) -->
*（预留：menu.png — 运行 `./main.sh` 或 `bash <(curl -fsSL $ENTRY)` 的菜单界面）*

<!-- 状态面板 -->
<!-- ![状态面板](docs/images/status.png) -->
*（预留：status.png — `./main.sh status` 输出示例）*

<!-- curl 远程 -->
<!-- ![curl 远程运行](docs/images/curl-demo.png) -->
*（预留：curl-demo.png — 远程一键检查/换源等终端截图）*

---

## 两种使用方式

| | **curl 远程运行** | **本地直接使用** |
|---|-------------------|------------------|
| **是什么** | 只下载 `main.sh`，子脚本按需从 Gitee 拉取 | 整个仓库在服务器上（克隆/FTP/scp） |
| **要不要上传** | 否 | 是 |
| **要不要联网** | 是（访问 gitee.com） | 脚本可离线；装软件/换源仍可能要网 |
| **适合** | 临时运维、新机器快速检查 | 生产、内网、频繁使用 |
| **更新** | 每次自动最新 | `git pull` 或重新上传 |

下文 `$ENTRY` = `https://gitee.com/suser747/netool/raw/master/main.sh`

---

## 一、curl 远程运行

**说明：** 服务器只需 `curl` + `bash`，无需把整个项目上传到机器。`main.sh` 会先 bootstrap 下载 `common.sh`，再按你输入的工具名下载对应子脚本，执行前做 `bash -n` 校验。

**要求：** Linux · Bash 3.2+ · 能访问 Gitee · 改配置需 `sudo`

### 1.1 交互菜单

```bash
# ✅ 推荐（菜单可正常输入）
bash <(curl -fsSL "$ENTRY")

# ⚠️ 管道模式：部分环境菜单无法输入
curl -fsSL "$ENTRY" | bash
```

### 1.2 参数调用（推荐日常）

```bash
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"

bash <(curl -fsSL "$ENTRY") check          # 功能检查
bash <(curl -fsSL "$ENTRY") status         # 状态面板
bash <(curl -fsSL "$ENTRY") versions       # 组件版本
bash <(curl -fsSL "$ENTRY") system info    # 系统信息
bash <(curl -fsSL "$ENTRY") mirror --plan  # 换源预览（不改系统）
bash <(curl -fsSL "$ENTRY") init           # 初始化向导
bash <(curl -fsSL "$ENTRY") -q check       # 静默，仅错误
```

### 1.3 别名（可选）

```bash
# 写入 ~/.bashrc
alias netool='bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)'
netool status
```

### 1.4 内置 vs 需下载

| 类型 | 命令 | 是否下载子脚本 |
|------|------|----------------|
| 内置 | `check` `status` `versions` `update` `uninstall` | 否 |
| 子工具 | `mirror` `disk` `ssh` `system` … | 是 |

### 1.5 curl 常见问题

| 问题 | 处理 |
|------|------|
| 菜单不能输入 | 改用 `bash <(curl -fsSL "$ENTRY")`，勿用 `\| bash` |
| 下载失败 | 检查 Gitee 连通；安装 `curl`；或改本地部署 |
| 中文乱码 | `export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8` |

---

## 二、本地直接使用

**说明：** 把完整项目放到服务器（如 `/opt/netool`），`main.sh` 检测到本地 `tools/` 目录后**直接执行磁盘上的子脚本**，不经过 curl 下载，速度更快，适合离线/内网。

### 2.1 获取项目

```bash
# Git（推荐）
git clone https://gitee.com/suser747/netool.git /opt/netool
cd /opt/netool
chmod +x main.sh && find tools -name "*.sh" -exec chmod +x {} \;

# 或 scp 上传后同样赋权
```

### 2.2 运行

```bash
cd /opt/netool

./main.sh                    # 菜单
./main.sh check
./main.sh status
./main.sh system info
./main.sh mirror --plan
./main.sh init
./main.sh --version
./main.sh versions
./main.sh --list
```

### 2.3 全局命令

```bash
ln -sf /opt/netool/main.sh /usr/local/bin/netool
netool status
```

### 2.4 更新

```bash
cd /opt/netool && git pull --ff-only origin master
```

### 2.5 与 curl 命令对照

| 功能 | curl 远程 | 本地 |
|------|-----------|------|
| 功能检查 | `bash <(curl -fsSL "$ENTRY") check` | `./main.sh check` |
| 状态面板 | `bash <(curl -fsSL "$ENTRY") status` | `./main.sh status` |
| 换源预览 | `bash <(curl -fsSL "$ENTRY") mirror --plan` | `./main.sh mirror --plan` |
| 初始化 | `bash <(curl -fsSL "$ENTRY") init` | `./main.sh init` |

改系统配置类命令请加 `sudo`：`sudo ./main.sh mirror -y`

---

## 三、常用命令

| 命令 | 说明 |
|------|------|
| `check` | 依赖与功能检查 |
| `status` | 系统/网络/安全/Docker 摘要 |
| `versions` | 主版本 + 组件版本 |
| `system info` | 系统信息 |
| `mirror --plan` | 轻量换源预览 |
| `lmirrors` | 全能换源（更多发行版） |
| `bbr status` / `bbr enable -y` | BBR |
| `ssh` | SSH 端口管理 |
| `docker status` / `docker install --plan` | Docker |
| `disk status` / `disk-test --plan` | 磁盘 / 验盘预览 |
| `init` | 新服务器向导 |
| `uninstall` | 删除工具箱配置与日志 |

完整列表：`./main.sh --list` 或 `./main.sh --help`

### 菜单编号速查

| 编号 | 功能 | 编号 | 功能 |
|------|------|------|------|
| 01 | 功能检查 | 15 | 轻量换源 |
| 02 | 状态面板 | 22 | 安装 Docker |
| 03 | 组件版本 | 28 | 初始化向导 |
| 1 | 系统信息 | 8 | 验盘（!） |
| 4 | SSH | 0 | 退出 |

> `!` 验盘/擦盘为破坏性操作，须先 `--plan`。

---

## 四、环境与安全

```bash
export NETOOL_SKIP_LICENSE=1      # 跳过首次许可提示（自动化）
export NETOOL_SKIP_LOCALE_TIP=1   # 跳过 locale 提示
```

- 改配置前可用 `--plan` / `--dry-run` 预览  
- 验盘需确认短语 `DESTROY-DISK-TEST`；擦盘需 `WIPE-CONFIRM`  
- 配置备份：`/var/backups/netool-*` · 审计：`/var/log/netool/`

### 用户许可（摘要）

使用即表示理解：部分功能会修改系统；验盘/擦盘会 destroy 数据；工具按现状提供，误操作风险自负。完整条款见运行时的许可提示。不同意请勿使用。

---

## 五、开发与贡献

```bash
bash scripts/validate.sh   # 语法 + 冒烟测试
```

- 新工具放 `tools/<分类>/`，引入 `load_common.sh`，在 `main.sh` 注册路由  
- 更新 `tools/versions.env` 与 `CHANGELOG.md`  
- Bash 3.2 兼容（禁用 `${var,,}`）· 推荐 shellcheck  

---

## 六、其他

| 路径 | 说明 |
|------|------|
| `~/.config/netool/` | 用户配置 |
| `VERSION` / `tools/versions.env` | 版本定义 |
| [CHANGELOG.md](./CHANGELOG.md) | 变更记录 |
| [LICENSE](./LICENSE) | Apache 2.0 |

仓库：https://gitee.com/suser747/netool
