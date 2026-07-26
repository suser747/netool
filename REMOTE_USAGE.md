# 远程使用指南（curl 一键运行）

> 完整双模式说明（本地 + curl）请参阅 **[USAGE.md](./USAGE.md)**。本文专注 curl 远程场景。

## 在线入口

```
https://gitee.com/suser747/netool/raw/master/main.sh
```

下文 `$ENTRY` 即上述地址。

---

## 快速上手

```bash
ENTRY="https://gitee.com/suser747/netool/raw/master/main.sh"

# 1. 交互菜单（必须用进程替换，否则菜单可能无法输入）
bash <(curl -fsSL "$ENTRY")

# 2. 参数调用（日常推荐）
bash <(curl -fsSL "$ENTRY") check
bash <(curl -fsSL "$ENTRY") status
bash <(curl -fsSL "$ENTRY") versions
bash <(curl -fsSL "$ENTRY") system info
bash <(curl -fsSL "$ENTRY") mirror --plan
bash <(curl -fsSL "$ENTRY") init

# 3. 静默模式
bash <(curl -fsSL "$ENTRY") -q check

# 4. 快捷别名（写入 ~/.bashrc）
alias netool='bash <(curl -fsSL https://gitee.com/suser747/netool/raw/master/main.sh)'
```

---

## 工作原理

```
curl 下载 main.sh → main.sh 启动
  ├─ 本地有 tools/ → 直接运行本地子脚本
  └─ 纯远程模式
        ├─ bootstrap 下载 tools/common.sh
        ├─ 按需下载子脚本 + bash -n 校验
        └─ 执行后清理临时目录
```

| 类型 | 命令示例 | 是否下载子脚本 |
|------|----------|----------------|
| 内置 | `check` `status` `versions` `update` `uninstall` | 否 |
| 子工具 | `mirror` `disk` `ssh` `system` … | 是 |
| disk 子功能 | `disk-test` `smart-long` `slot-map` | disk.sh 二次下载 |

每次运行拉取 Gitee `master` 最新代码，**无需手动更新**。

---

## 常用命令速查

| 场景 | 命令 |
|------|------|
| 进入菜单 | `bash <(curl -fsSL $ENTRY)` |
| 功能检查 | `bash <(curl -fsSL $ENTRY) check` |
| 状态面板 | `bash <(curl -fsSL $ENTRY) status` |
| 组件版本 | `bash <(curl -fsSL $ENTRY) versions` |
| 系统信息 | `bash <(curl -fsSL $ENTRY) system info` |
| 轻量换源预览 | `bash <(curl -fsSL $ENTRY) mirror --plan` |
| 全能换源 | `bash <(curl -fsSL $ENTRY) lmirrors` |
| SSH 改端口 | `bash <(curl -fsSL $ENTRY) ssh --port 2222 --mode staged -y` |
| BBR 状态 | `bash <(curl -fsSL $ENTRY) bbr status` |
| Docker 状态 | `bash <(curl -fsSL $ENTRY) docker status` |
| 磁盘状态 | `bash <(curl -fsSL $ENTRY) disk status` |
| 验盘预览 | `bash <(curl -fsSL $ENTRY) disk-test --plan` |
| 初始化向导 | `bash <(curl -fsSL $ENTRY) init` |
| 工具列表 | `bash <(curl -fsSL $ENTRY) --list` |
| 帮助 | `bash <(curl -fsSL $ENTRY) --help` |

更多工具与菜单编号对照见 [USAGE.md §6](./USAGE.md#6-全部工具命令参考)。

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux |
| Shell | Bash 3.2+ |
| 必需命令 | `curl`、`bash` |
| 网络 | 能访问 `gitee.com` |
| 权限 | 查看类普通用户；改配置需 root/sudo |

---

## 首次使用与许可

- 首次**无参数**交互运行会提示 [用户许可协议](./USER_AGREEMENT.md)
- 确认保存在 `~/.config/netool/license-v1.accepted`
- **带工具名**调用时跳过许可提示

自动化跳过：

```bash
export NETOOL_SKIP_LICENSE=1
bash <(curl -fsSL $ENTRY) check
```

---

## 环境变量

| 变量 | 说明 |
|------|------|
| `NETOOL_SKIP_LICENSE=1` | 跳过许可提示 |
| `NETOOL_SKIP_LOCALE_TIP=1` | 跳过中文 locale 提示 |

---

## 安全说明

1. 改配置类支持 `--plan` / `--dry-run` 先预览
2. 验盘/擦盘等破坏性操作需 `--yes` + 确认短语
3. 远程脚本执行前 `bash -n` 校验
4. SSH/BBR/换源等自动备份，可回滚
5. 生产环境建议克隆仓库 [本地部署](./FTP_DEPLOYMENT.md)

---

## 故障排查

### 菜单无法输入

```bash
# 错误：curl | bash 占用 stdin
# 正确：
bash <(curl -fsSL $ENTRY)
```

### curl 下载失败

```bash
curl -I https://gitee.com
for i in 1 2 3; do curl -fsSL $ENTRY | bash && break; sleep 2; done
```

仍失败 → 改用 [本地/FTP 部署](./FTP_DEPLOYMENT.md)。

### 提示「下载脚本失败」

1. 确认分支为 `master`（非 `main`）
2. 确认已安装 `curl`：`apt install -y curl` / `yum install -y curl`
3. 确认 main.sh 为 v2.1+

### 中文乱码

```bash
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
export NETOOL_SKIP_LOCALE_TIP=1
```

---

## 远程 vs 本地

| | curl 远程 | 本地部署 |
|---|-----------|----------|
| 安装 | 零安装 | 需克隆/上传 |
| 网络 | 必须 | 脚本可离线 |
| 更新 | 自动最新 | `git pull` |
| 速度 | 有下载延迟 | 更快 |

本地部署详见 [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md) 与 [USAGE.md §3](./USAGE.md#3-本地部署运行)。

---

## 维护者说明

远程用户依赖 Gitee `master` 分支，修改后需推送：

```bash
git push origin master
```

本地验证远程模式：

```bash
bash scripts/test-remote.sh
```

---

## 相关文档

- [USAGE.md](./USAGE.md) — 完整使用说明
- [README.md](./README.md) — 项目概览
- [FTP_DEPLOYMENT.md](./FTP_DEPLOYMENT.md) — 本地部署
- [USER_AGREEMENT.md](./USER_AGREEMENT.md) — 许可协议
