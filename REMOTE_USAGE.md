# 远程使用指南（curl 一键运行）

本文说明如何**不克隆仓库、不上传 FTP**，直接在 Linux 服务器上通过 `curl` 拉取脚本并使用 netool 懒人工具箱。

## 在线入口

```bash
# 固定地址（Gitee master 分支）
https://gitee.com/suser747/netool/raw/master/main.sh
```

> 请始终使用 `https://`，不要省略协议头。

---

## 两种推荐用法

### 1. 交互式菜单（适合首次使用）

```bash
curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh | bash
```

**注意**：管道模式下 stdin 被占用，菜单输入可能无响应。若无法输入，请改用下方「进程替换」写法：

```bash
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)
```

### 2. 参数式调用（推荐日常使用）

直接指定工具名和参数，**不进入菜单**，参数传递更清晰：

```bash
# 功能检查
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) check
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) status
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) versions

# 系统信息
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) system

# 换源预览（不修改系统）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) mirror --plan

# SSH 端口 staged 模式
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) ssh --port 2222 --mode staged -y

# 静默模式（只输出错误）
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh) -q check
```

---

## 工作原理

```
curl 下载 main.sh
       ↓
main.sh 启动
       ├─ 本地有 tools/ 目录 → 直接运行本地子脚本（FTP/克隆部署）
       └─ 远程模式（仅 main.sh）
              ├─ 下载 tools/common.sh（启动引导）
              ├─ 按工具名下载对应子脚本（保留 tools/ 目录结构）
              ├─ bash -n 语法校验
              └─ 执行后自动清理临时目录
```

远程模式下：

- `check`、`status`、`versions`、`update`、`uninstall` 等内置功能**不下载**子脚本
- `mirror`、`disk`、`ssh` 等工具会**按需下载**对应脚本
- `disk` 的磁盘子脚本（验盘、SMART 等）由 `disk.sh` **二次按需下载**
- 每次运行拉取 Gitee 上最新代码，**无需手动更新**

---

## 常用命令速查

| 场景 | 命令 |
|------|------|
| 进入菜单 | `curl -fsSL .../main.sh \| bash` |
| 功能检查 | `bash <(curl -fsSL .../main.sh) check` |
| 系统信息 | `bash <(curl -fsSL .../main.sh) system` |
| 轻量换源 | `bash <(curl -fsSL .../main.sh) mirror` |
| 全能换源 | `bash <(curl -fsSL .../main.sh) lmirrors` |
| 磁盘管理 | `bash <(curl -fsSL .../main.sh) disk status` |
| 验盘预览 | `bash <(curl -fsSL .../main.sh) disk-test --plan` |
| 初始化向导 | `bash <(curl -fsSL .../main.sh) init` |
| 查看工具列表 | `bash <(curl -fsSL .../main.sh) --list` |
| 查看帮助 | `bash <(curl -fsSL .../main.sh) --help` |

将 `.../main.sh` 替换为：

`https://gitee.com/suser747/netool/raw/master/main.sh`

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux（各发行版，见 README） |
| Shell | Bash 3.2+ |
| 必需命令 | `curl`、`bash` |
| 网络 | 能访问 `gitee.com` |
| 权限 | 查看类功能普通用户即可；改配置需 root / sudo |

---

## 首次使用与许可协议

首次**交互式**运行会提示阅读 [用户许可协议](./USER_AGREEMENT.md)。

- 确认状态保存在 `~/.config/netool/license-v1.accepted`
- 兼容旧路径 `~/.config/ayu-toolbox/`
- 带工具名参数调用时跳过许可提示（视为明确意图）

跳过许可（自动化场景）：

```bash
export NETOOL_SKIP_LICENSE=1
bash <(curl -fsSL .../main.sh) check
```

---

## 安全说明

1. **预览再执行**：改配置类操作支持 `--plan` / `--dry-run` 先预览
2. **破坏性操作**：验盘、擦盘等需 `--yes` + 确认短语
3. **语法校验**：远程下载的脚本执行前会 `bash -n` 校验
4. **配置备份**：SSH、BBR、换源等会自动备份，支持回滚
5. **供应链**：建议从官方 Gitee 地址拉取；生产环境可考虑克隆仓库本地部署

---

## 故障排查

### curl 下载失败 / 超时

```bash
# 重试 3 次
for i in 1 2 3; do curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh | bash && break; done
```

或使用代理 / 换网络。仍失败时可 [FTP/本地部署](./FTP_DEPLOYMENT.md)。

### 菜单无法输入

管道 `curl | bash` 会占用 stdin。**改用**：

```bash
bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)
```

### 提示「下载脚本失败」

1. 确认能访问 Gitee：`curl -I https://gitee.com`
2. 确认分支为 `master`（不是 `main`）
3. 检查服务器是否安装 `curl`

### 提示「缺少 curl」

```bash
# Debian/Ubuntu
sudo apt install -y curl

# CentOS/RHEL
sudo yum install -y curl
```

### 子脚本 common.sh 报错

请确保使用的是**最新版** `main.sh`（v2.1+）。旧版远程模式存在 common 路径问题，已修复。

### 中文乱码

```bash
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
# 或安装中文字体后重连 SSH
```

---

## 远程 vs 本地部署

| 方式 | 优点 | 缺点 |
|------|------|------|
| **curl 远程** | 零安装、始终最新、一条命令 | 依赖网络、每次下载脚本 |
| **克隆/FTP 本地** | 离线可用、更快、可改代码 | 需上传、手动 git pull 更新 |

本地部署详见 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md)。

---

## 维护者：发布远程可用版本

远程用户依赖 Gitee 上的 `master` 分支文件。修改代码后需推送：

```bash
git add -A
git commit -m "your message"
git push origin master
```

推送后，远程 `curl` 用户下次运行即自动获得更新。

本地验证远程模式：

```bash
bash scripts/test-remote.sh
```

---

## 相关文档

- [README.md](./README.md) — 项目概览
- [USER_AGREEMENT.md](./USER_AGREEMENT.md) — 用户许可协议
- [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md) — 本地/FTP 部署
- [CHANGELOG.md](./CHANGELOG.md) — 版本变更
